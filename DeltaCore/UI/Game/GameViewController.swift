//
//  GameViewController.swift
//  DeltaCore
//
//  Created by Riley Testut on 7/4/16.
//  Happy 4th of July, Everyone! 🎉
//  Copyright © 2016 Riley Testut. All rights reserved.
//

import UIKit
import AVFoundation

fileprivate extension NSLayoutConstraint
{
    class func constraints(aspectFitting view1: UIView, to view2: UIView) -> [NSLayoutConstraint]
    {
        let boundingWidthConstraint = view1.widthAnchor.constraint(lessThanOrEqualTo: view2.widthAnchor, multiplier: 1.0)
        let boundingHeightConstraint = view1.heightAnchor.constraint(lessThanOrEqualTo: view2.heightAnchor, multiplier: 1.0)
        
        let widthConstraint = view1.widthAnchor.constraint(equalTo: view2.widthAnchor)
        widthConstraint.priority = .defaultHigh
        
        let heightConstraint = view1.heightAnchor.constraint(equalTo: view2.heightAnchor)
        heightConstraint.priority = .defaultHigh
        
        return [boundingWidthConstraint, boundingHeightConstraint, widthConstraint, heightConstraint]
    }
}

public protocol GameViewControllerDelegate: AnyObject
{
    func gameViewControllerShouldPauseEmulation(_ gameViewController: GameViewController) -> Bool
    func gameViewControllerShouldResumeEmulation(_ gameViewController: GameViewController) -> Bool
    
    func gameViewController(_ gameViewController: GameViewController, handleMenuInputFrom gameController: GameController)
    
    func gameViewControllerDidUpdate(_ gameViewController: GameViewController)
    func gameViewController(_ gameViewController: GameViewController, didUpdateGameViews gameViews: [GameView])
}

public extension GameViewControllerDelegate
{
    func gameViewControllerShouldPauseEmulation(_ gameViewController: GameViewController) -> Bool { return true }
    func gameViewControllerShouldResumeEmulation(_ gameViewController: GameViewController) -> Bool { return true }
    
    func gameViewController(_ gameViewController: GameViewController, handleMenuInputFrom gameController: GameController) {}
    
    func gameViewControllerDidUpdate(_ gameViewController: GameViewController) {}
    func gameViewController(_ gameViewController: GameViewController, didUpdateGameViews gameViews: [GameView]) {}
}

private var kvoContext = 0

open class GameViewController: UIViewController, GameControllerReceiver
{
    open var game: GameProtocol?
    {
        didSet
        {
            if let game = self.game
            {
                self.emulatorCore = EmulatorCore(game: game)
            }
            else
            {
                self.emulatorCore = nil
            }
        }
    }
    
    open private(set) var emulatorCore: EmulatorCore?
    {
        didSet
        {
            oldValue?.stop()
            
            self.emulatorCore?.updateHandler = { [weak self] core in
                guard let strongSelf = self else { return }
                strongSelf.delegate?.gameViewControllerDidUpdate(strongSelf)
            }
            
            self.prepareForGame()
        }
    }
    
    open weak var delegate: GameViewControllerDelegate?
    
    public var gameView: GameView! {
        return self.gameViews.first
    }
    public private(set) var gameViews: [GameView] = []
    public var blurGameView = GameView(frame: .zero)
    
    public var blurGameViewBlurView: UIVisualEffectView!
    public var blurTintView: UIView = UIView(frame: .zero)

    private var blurScreen: ControllerSkin.Screen! = ControllerSkin.Screen(id: "gameViewController.screen.blur", placement: .app)
    
    public var blurScreenKeepAspect: Bool = true {
        didSet {
            self.updateBlurScreen()
        }
    }
    public var blurScreenEnabled: Bool = true {
        didSet {
            self.blurGameView.isHidden = !self.blurScreenEnabled
            self.blurGameViewBlurView.isHidden = !self.blurScreenEnabled
            self.blurTintView.isHidden = !self.blurScreenEnabled
        }
    }
    
    public var backgroundColor: UIColor = .black {
        didSet {
            self.view.backgroundColor = self.backgroundColor
        }
    }
    
    public var ignoreInputFrames: Bool = false {
        didSet {
            self.updateGameViews()
        }
    }
    
    private var screenSize: CGSize = CGSize()
    private var availableGameFrame: CGRect = CGRect()
        
    open private(set) var controllerView: ControllerView!
    private var splitViewInputViewHeight: CGFloat = 0
    
    private let emulatorCoreQueue = DispatchQueue(label: "com.litritt.DeltaCore.GameViewController.emulatorCoreQueue", qos: .userInitiated)
    
    private var _previousControllerSkin: ControllerSkinProtocol?
    private var _previousControllerSkinTraits: ControllerSkin.Traits?
    
    private var appPlacementLayoutGuide: UILayoutGuide!
    private var appPlacementXConstraint: NSLayoutConstraint!
    private var appPlacementYConstraint: NSLayoutConstraint!
    private var appPlacementWidthConstraint: NSLayoutConstraint!
    private var appPlacementHeightConstraint: NSLayoutConstraint!
    
    // HACK: iOS 16 beta 5 sends multiple incorrect keyboard focus notifications when resuming from background.
    // As a workaround, we ignore all notifications when returning from background, and then wait an extra delay
    // after app becomes active before checking keyboard focus to ensure we get the correct value.
    private var isEnteringForeground: Bool = false
    private weak var delayCheckKeyboardFocusTimer: Timer?
    
    private var liveSkinTimer: Timer?
    
    /// UIViewController
    open override var prefersStatusBarHidden: Bool {
        return true
    }
    
    public required init()
    {
        super.init(nibName: nil, bundle: nil)
        
        self.initialize()
    }
    
    public required init?(coder aDecoder: NSCoder)
    {
        super.init(coder: aDecoder)
        
        self.initialize()
    }
    
    private func initialize()
    {
        NotificationCenter.default.addObserver(self, selector: #selector(GameViewController.keyboardWillShow(with:)), name: UIResponder.keyboardWillShowNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(GameViewController.keyboardWillChangeFrame(with:)), name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(GameViewController.keyboardWillHide(with:)), name: UIResponder.keyboardWillHideNotification, object: nil)
        
        NotificationCenter.default.addObserver(self, selector: #selector(GameViewController.willResignActive(with:)), name: UIScene.willDeactivateNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(GameViewController.didBecomeActive(with:)), name: UIScene.didActivateNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(GameViewController.willEnterForeground(_:)), name: UIScene.willEnterForegroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(GameViewController.sceneKeyboardFocusDidChange(_:)), name: UIScene.keyboardFocusDidChangeNotification, object: nil)
    }
    
    deinit
    {
        // controllerView might not be initialized by the time deinit is called.
        self.controllerView?.removeObserver(self, forKeyPath: #keyPath(ControllerView.isHidden), context: &kvoContext)
        
        self.emulatorCore?.stop()
    }
    
    // MARK: - UIViewController -
    /// UIViewController
    // These would normally be overridden in a public extension, but overriding these methods in subclasses of GameViewController segfaults compiler if so
    
    open override var prefersHomeIndicatorAutoHidden: Bool
    {
        let prefersHomeIndicatorAutoHidden = self.view.bounds.width > self.view.bounds.height
        return prefersHomeIndicatorAutoHidden
    }
    
    open dynamic override func viewDidLoad()
    {
        super.viewDidLoad()
        
        self.view.backgroundColor = UIColor.black
        
        self.appPlacementLayoutGuide = UILayoutGuide()
        self.view.addLayoutGuide(self.appPlacementLayoutGuide)
        
        self.view.addSubview(self.blurGameView)
        
        self.view.addSubview(self.blurTintView)
        
        self.blurGameViewBlurView = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterial))
        self.blurGameViewBlurView.frame = CGRect(x: 0, y: 0, width: self.view.bounds.width, height: self.view.bounds.height)
        self.blurGameViewBlurView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        
        self.view.addSubview(self.blurGameViewBlurView)
        
        let gameView = GameView(frame: CGRect.zero)
        self.view.addSubview(gameView)
        self.gameViews.append(gameView)
        
        self.controllerView = ControllerView(frame: CGRect.zero)
        self.controllerView.appPlacementLayoutGuide = self.appPlacementLayoutGuide
        self.view.addSubview(self.controllerView)
        
        self.controllerView.addObserver(self, forKeyPath: #keyPath(ControllerView.isHidden), options: [.old, .new], context: &kvoContext)
        NotificationCenter.default.addObserver(self, selector: #selector(GameViewController.updateGameViews), name: ControllerView.controllerViewDidChangeControllerSkinNotification, object: self.controllerView)
        NotificationCenter.default.addObserver(self, selector: #selector(GameViewController.controllerViewDidUpdateGameViews(_:)), name: ControllerView.controllerViewDidUpdateGameViewsNotification, object: self.controllerView)
        
        let tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(GameViewController.resumeEmulationIfNeeded))
        tapGestureRecognizer.delegate = self
        self.view.addGestureRecognizer(tapGestureRecognizer)
        
        self.prepareForGame()
        
        self.appPlacementXConstraint = self.appPlacementLayoutGuide.leftAnchor.constraint(equalTo: self.view.leftAnchor, constant: 0)
        self.appPlacementYConstraint = self.appPlacementLayoutGuide.topAnchor.constraint(equalTo: self.view.topAnchor, constant: 0)
        self.appPlacementWidthConstraint = self.appPlacementLayoutGuide.widthAnchor.constraint(equalToConstant: 0)
        self.appPlacementHeightConstraint = self.appPlacementLayoutGuide.heightAnchor.constraint(equalToConstant: 0)
        NSLayoutConstraint.activate([self.appPlacementXConstraint, self.appPlacementYConstraint, self.appPlacementWidthConstraint, self.appPlacementHeightConstraint])
    }
    
    open dynamic override func viewWillAppear(_ animated: Bool)
    {
        super.viewWillAppear(animated)
        
        self.emulatorCoreQueue.async {
            _ = self._startEmulation()
        }
    }
    
    open dynamic override func viewDidAppear(_ animated: Bool)
    {
        super.viewDidAppear(animated)
        
        UIApplication.delta_shared?.isIdleTimerDisabled = true
        
        if self.game != nil
        {
            self.controllerView.becomeFirstResponder()
        }
        
        if let scene = self.view.window?.windowScene
        {
            scene.startTrackingKeyboardFocus()
        }
    }
    
    open dynamic override func viewDidDisappear(_ animated: Bool)
    {
        super.viewDidDisappear(animated)
        
        UIApplication.delta_shared?.isIdleTimerDisabled = false
        
        self.emulatorCoreQueue.async {
            _ = self._pauseEmulation()
        }
    }
    
    override open func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator)
    {
        super.viewWillTransition(to: size, with: coordinator)
        
        self.controllerView.beginAnimatingUpdateControllerSkin()
        
        // Disable VideoManager temporarily to prevent random Metal crashes due to rendering while adjusting layout.
        let isVideoManagerEnabled = self.emulatorCore?.videoManager.isEnabled ?? true
        self.emulatorCore?.videoManager.isEnabled = false
        
        // As of iOS 11, the keyboard NSNotifications may return incorrect values for split view controller input view when rotating device.
        // As a workaround, we explicitly resign controllerView as first responder, then restore first responder status after rotation.
        let isControllerViewFirstResponder = self.controllerView.isFirstResponder
        self.controllerView.resignFirstResponder()
        
        self.view.setNeedsUpdateConstraints()
        
        coordinator.animate(alongsideTransition: { (context) in
            self.updateGameViews()
        }) { (context) in
            self.controllerView.finishAnimatingUpdateControllerSkin()
            
            if isControllerViewFirstResponder
            {
                self.controllerView.becomeFirstResponder()
            }
            
            // Re-enable VideoManager if necessary.
            self.emulatorCore?.videoManager.isEnabled = isVideoManagerEnabled
        }
    }
    
    open override func viewDidLayoutSubviews()
    {
        super.viewDidLayoutSubviews()
        
        let controllerViewFrame: CGRect
        let availableGameFrame: CGRect
        
        /* Controller View */
        switch self.controllerView.controllerSkinTraits
        {
        case let traits? where traits.displayType == .splitView:
            // Split-View:
            // - Controller View is pinned to bottom and spans width of device as keyboard input view.
            // - Game View should be vertically centered between top of screen and input view.
            
            controllerViewFrame = CGRect(x: 0, y: 0, width: self.view.bounds.width, height: self.view.bounds.height)
            (_, availableGameFrame) = self.view.bounds.divided(atDistance: self.splitViewInputViewHeight, from: .maxYEdge)
            
        case .none: fallthrough
        case _? where self.controllerView.isHidden:
            // Controller View Hidden:
            // - Controller View should have a height of 0.
            // - Game View should be centered in self.view.
             
            (controllerViewFrame, availableGameFrame) = self.view.bounds.divided(atDistance: 0, from: .maxYEdge)
            
        case let traits? where traits.orientation == .portrait && !(self.controllerView.controllerSkin?.screens(for: traits, alt: self.controllerView.isAltRepresentationsEnabled) ?? []).contains(where: { $0.placement == .controller }):
            // Portrait (and no custom screens with `controller` placement):
            // - Controller View should be pinned to bottom of self.view and centered horizontally.
            // - Game View should be vertically centered between top of screen and controller view.
            
            let intrinsicContentSize = self.controllerView.intrinsicContentSize
            if intrinsicContentSize.height != UIView.noIntrinsicMetric && intrinsicContentSize.width != UIView.noIntrinsicMetric
            {
                let controllerViewHeight = (self.view.bounds.width / intrinsicContentSize.width) * intrinsicContentSize.height
                (controllerViewFrame, availableGameFrame) = self.view.bounds.divided(atDistance: controllerViewHeight, from: .maxYEdge)
            }
            else
            {
                controllerViewFrame = self.view.bounds
                availableGameFrame = self.view.bounds
            }
            
        case _?:
            // Landscape (or Portrait with custom screens using `controller` placement):
            // - Controller View should be centered vertically in view (though most of the time its height will == self.view height).
            // - Game View should be centered in self.view.
                        
            let intrinsicContentSize = self.controllerView.intrinsicContentSize
            if intrinsicContentSize.height != UIView.noIntrinsicMetric && intrinsicContentSize.width != UIView.noIntrinsicMetric
            {
                controllerViewFrame = AVMakeRect(aspectRatio: intrinsicContentSize, insideRect: self.view.bounds)
            }
            else
            {
                controllerViewFrame = self.view.bounds
            }
            
            availableGameFrame = self.view.bounds
        }
        
        self.availableGameFrame = availableGameFrame
        
        self.controllerView.frame = controllerViewFrame
        
        let gameScreenDimensions = self.emulatorCore?.preferredRenderingSize ?? CGSize(width: 1, height: 1)
        
        self.screenSize = gameScreenDimensions
        
        let contentAspectRatio: CGSize
        
        if let traits = self.controllerView.controllerSkinTraits,
           let controllerSkin = self.controllerView.controllerSkin,
           let aspectRatio = controllerSkin.contentSize(for: traits, alt: false)
        {
            contentAspectRatio = aspectRatio
        }
        else
        {
            // Fall back to `gameScreenDimensions` if controller skin does not define `contentSize`.
            contentAspectRatio = gameScreenDimensions
        }
        
        let appPlacementFrame = AVMakeRect(aspectRatio: contentAspectRatio, insideRect: self.view.bounds).rounded()
        if self.appPlacementLayoutGuide.layoutFrame.rounded() != appPlacementFrame
        {
            self.appPlacementXConstraint.constant = appPlacementFrame.minX
            self.appPlacementYConstraint.constant = appPlacementFrame.minY
            self.appPlacementWidthConstraint.constant = appPlacementFrame.width
            self.appPlacementHeightConstraint.constant = appPlacementFrame.height
            
            // controllerView needs to reposition any items with `app` placement.
            self.controllerView.setNeedsLayout()
        }
        
        /* Game Views */
        if let traits = self.controllerView.controllerSkinTraits, let screens = self.screens(for: traits)
        {
            for (screen, gameView) in zip(screens, self.gameViews)
            {
                let placementFrame = (screen.placement == .controller) ? controllerViewFrame : appPlacementFrame
                
                if let outputFrame = screen.outputFrame
                {
                    let frame = outputFrame.scaled(to: placementFrame)
                    gameView.frame = frame
                }
                else
                {
                    // Nil outputFrame, so use gameView.outputImage's aspect ratio to determine default positioning.
                    // We check outputImage before inputFrame because we prefer to keep aspect ratio of whatever is currently being displayed.
                    // Otherwise, screen may resize to screenAspectRatio while still displaying partial content, appearing distorted.
                    let aspectRatio = gameView.outputImage?.extent.size ?? screen.inputFrame?.size ?? gameScreenDimensions
                    let containerFrame = (screen.placement == .controller) ? controllerViewFrame : availableGameFrame
                    
                    let screenFrame = AVMakeRect(aspectRatio: aspectRatio, insideRect: containerFrame)
                    gameView.frame = screenFrame
                }
            }
        }
        else
        {
            let gameScreenFrame = AVMakeRect(aspectRatio: gameScreenDimensions, insideRect: availableGameFrame)
            self.gameView.frame = gameScreenFrame
        }
        
        self.blurGameView.frame = availableGameFrame
        self.blurTintView.frame = availableGameFrame
        
        if let emulatorCore = self.emulatorCore, emulatorCore.state != .running
        {
            // WORKAROUND
            // Sometimes, iOS will cache the rendered image (such as when covered by a UIVisualEffectView), and as a result the game view might appear skewed
            // To compensate, we manually "refresh" the game screen
            emulatorCore.videoManager.render()
        }
        
        self.setNeedsUpdateOfHomeIndicatorAutoHidden()
    }
    
    // MARK: - KVO -
    /// KVO
    open dynamic override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?)
    {
        guard context == &kvoContext else { return super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context) }

        // Ensures the value is actually different, or else we might potentially run into an infinite loop if subclasses hide/show controllerView in viewDidLayoutSubviews()
        guard (change?[.newKey] as? Bool) != (change?[.oldKey] as? Bool) else { return }
        
        self.view.setNeedsLayout()
        self.view.layoutIfNeeded()
    }
    
    // MARK: - GameControllerReceiver -
    /// GameControllerReceiver
    // These would normally be declared in an extension, but non-ObjC compatible methods cannot be overridden if declared in extension :(
    open func gameController(_ gameController: GameController, didActivate input: Input, value: Double)
    {
        // This method intentionally left blank
    }
    
    open func gameController(_ gameController: GameController, didDeactivate input: Input)
    {
        // Wait until menu button is released before calling handleMenuInputFrom:
        // Fixes potentially missing key-up inputs due to showing pause menu.
        guard let standardInput = StandardGameControllerInput(input: input), standardInput == .menu else { return }
        self.delegate?.gameViewController(self, handleMenuInputFrom: gameController)
    }
}

// MARK: - Layout -
/// Layout
extension GameViewController
{
    func updateBlurScreen()
    {
        guard self.blurScreenEnabled else {
            return
        }
        
        if self.blurScreenKeepAspect
        {
            var filters = [CIFilter]()
            let scaleTransform = CGAffineTransform(scaleX: 1, y: 1)
            let scaleFilter = CIFilter(name: "CIAffineTransform", parameters: ["inputTransform": NSValue(cgAffineTransform: scaleTransform)])!
            
            filters.append(scaleFilter)
            
            if let inputExtent = self.gameView.inputImage?.extent
            {
                self.screenSize = inputExtent.size
            }
            
            let availableGameSize = CGSize(width: self.availableGameFrame.width, height: self.availableGameFrame.height)
            let gameRect = CGRect(origin: .zero, size: self.screenSize)
            
            let cropFrame = AVMakeRect(aspectRatio: availableGameSize, insideRect: gameRect).rounded()
            let cropFilter = CIFilter(name: "CICrop", parameters: ["inputRectangle": CIVector(cgRect: cropFrame)])!
            
            filters.append(cropFilter)
            
            self.blurScreen.filters = filters
        }
        else
        {
            self.blurScreen.filters = nil
        }
        
        self.blurGameView.update(for: self.blurScreen)
    }
    
    @objc func updateGameViews()
    {
        self.updateBlurScreen()
        
        var previousGameViews = Array(self.gameViews.reversed())
        var gameViews = [GameView]()
        
        if let traits = self.controllerView.controllerSkinTraits, let screens = self.screens(for: traits)
        {
            for screen in screens
            {
                let gameView = previousGameViews.popLast() ?? GameView(frame: .zero)
                gameView.update(for: screen, ignoringInputFrame: self.ignoreInputFrames)
                gameViews.append(gameView)
            }
        }
        else
        {
            for gameView in self.gameViews
            {
                gameView.filter = nil
                gameView.style = .flat
                gameView.isTouchScreen = false
            }
        }
        
        if gameViews.isEmpty
        {
            // gameViews needs to _always_ contain at least one game view.
            gameViews.append(self.gameView)
        }
        
        for gameView in gameViews
        {
            guard !self.gameViews.contains(gameView) else { continue }
            
            self.view.insertSubview(gameView, aboveSubview: self.gameView)
            self.emulatorCore?.add(gameView)
        }
        
        for gameView in previousGameViews
        {
            guard !gameViews.contains(gameView) else { continue }
            
            gameView.removeFromSuperview()
            self.emulatorCore?.remove(gameView)
        }
        
        self.gameViews = gameViews
        self.view.setNeedsLayout()
        
        self.delegate?.gameViewController(self, didUpdateGameViews: self.gameViews)
    }
}

// MARK: - Emulation -
/// Emulation
public extension GameViewController
{
    @discardableResult func startEmulation() -> Bool
    {
        return self.emulatorCoreQueue.sync {
            return self._startEmulation()
        }
    }
    
    @discardableResult func pauseEmulation() -> Bool
    {
        return self.emulatorCoreQueue.sync {
            return self._pauseEmulation()
        }
    }
    
    @discardableResult func resumeEmulation() -> Bool
    {
        return self.emulatorCoreQueue.sync {
            self._resumeEmulation()
        }
    }
}

private extension GameViewController
{
    func _startEmulation() -> Bool
    {
        guard let emulatorCore = self.emulatorCore else { return false }
        
        // Toggle audioManager.enabled to reset the audio buffer and ensure the audio isn't delayed from the beginning
        // This is especially noticeable when peeking a game
        emulatorCore.audioManager.isEnabled = false
        emulatorCore.audioManager.isEnabled = true
        
        if emulatorCore.deltaCore.isLiveSkinSupported
        {
            DispatchQueue.main.async {
                self.emulatorCore?.deltaCore.emulatorBridge.resetLiveSkin?()
                self.liveSkinTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { timer in
                    self.controllerView.updateLiveSkinOverlay()
                }
            }
        }
        else
        {
            self.controllerView.resetLiveSkinOverlay()
            self.liveSkinTimer?.invalidate()
            self.liveSkinTimer = nil
        }
        
        return self._resumeEmulation()
    }
    
    private func _pauseEmulation() -> Bool
    {
        guard let emulatorCore = self.emulatorCore, self.delegate?.gameViewControllerShouldPauseEmulation(self) ?? true else { return false }
        
        DispatchQueue.main.async {
            self.controllerView.clearLiveSkinOverlay()
        }
        self.liveSkinTimer?.invalidate()
        self.liveSkinTimer = nil

        let result = emulatorCore.pause()
        return result
    }
    
    private func _resumeEmulation() -> Bool
    {
        guard let emulatorCore = self.emulatorCore, self.delegate?.gameViewControllerShouldResumeEmulation(self) ?? true else { return false }
        
        DispatchQueue.main.async {
            if self.view.window != nil
            {
                self.controllerView.becomeFirstResponder()
            }

            if self.liveSkinTimer == nil, emulatorCore.deltaCore.isLiveSkinSupported
            {
                self.liveSkinTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { timer in
                    self.controllerView.updateLiveSkinOverlay()
                }
            }
        }
        
        let result: Bool
        
        switch emulatorCore.state
        {
        case .stopped: result = emulatorCore.start()
        case .paused: result = emulatorCore.resume()
        case .running: result = true
        }
        
        return result
    }
}

// MARK: - Preparation -
private extension GameViewController
{
    func prepareForGame()
    {
        guard
            let controllerView = self.controllerView,
            let emulatorCore = self.emulatorCore,
            let game = self.game
        else { return }
        
        var gameViews = self.gameViews + controllerView.gameViews
        gameViews.append(self.blurGameView)
        
        for gameView in gameViews
        {
            emulatorCore.add(gameView)
        }
        
        controllerView.addReceiver(self)
        controllerView.addReceiver(emulatorCore)
        
        controllerView.emulatorCore = emulatorCore
        
        let controllerSkin = ControllerSkin.standardControllerSkin(for: game.type)
        controllerView.controllerSkin = controllerSkin
        
        self.view.setNeedsUpdateConstraints()
    }
    
    @objc func resumeEmulationIfNeeded()
    {
        self.controllerView.becomeFirstResponder()
        
        // Pre-check whether we should actually resume while we're still on main queue.
        // This helps avoid potential deadlock due to calling dispatch_sync on main queue in _resumeEmulation.
        guard self.emulatorCore?.state == .paused, self.delegate?.gameViewControllerShouldResumeEmulation(self) ?? true else { return }
        
        self.emulatorCoreQueue.async {
            guard self.emulatorCore?.state == .paused else { return }
            _ = self._resumeEmulation()
        }
    }
}

//MARK: - Screens -
public extension GameViewController
{
    func screens(for traits: ControllerSkin.Traits) -> [ControllerSkin.Screen]?
    {
        guard let controllerSkin = self.controllerView.controllerSkin,
              let traits = self.controllerView.controllerSkinTraits,
              var screens = controllerSkin.screens(for: traits, alt: self.controllerView.isAltRepresentationsEnabled),
              !self.controllerView.isHidden
        else
        {
            return nil
        }
        
        guard traits.displayType == .splitView else {
            // When not in split view, manage all game views regardless of placement.
            return screens
        }
        
        // When in split view, only manage game views with `app` placement.
        screens = screens.filter { $0.placement == .app }

        if var screen = screens.first, screen.outputFrame == nil, !self.controllerView.isFirstResponder
        {
            // Keyboard is not visible, so set inputFrame to nil to display entire screen.
            // This essentially collapses all screens into a single main screen that we can manage easier.
            screen.inputFrame = nil
            screens = [screen]
        }
        
        return screens
    }
}

extension GameViewController: UIGestureRecognizerDelegate
{
    open func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool
    {
        // We only need tap-to-resume when using Split View/Stage Manager to handle edge cases where emulation doesn't resume automatically.
        // However, we'll also respond to direct taps on primary game screen just in case.
        let location = touch.location(in: self.gameView)
        let shouldReceiveTouch = self.controllerView.controllerSkinTraits?.displayType == .splitView || self.gameView.bounds.contains(location)
        return shouldReceiveTouch
    }
}

// MARK: - Notifications - 
private extension GameViewController
{
    @objc func willResignActive(with notification: Notification)
    {
        guard let scene = notification.object as? UIScene, scene == self.view.window?.windowScene else { return }
        
        self.emulatorCoreQueue.async {
            guard self.emulatorCore?.state == .running else { return }
            _ = self._pauseEmulation()
        }
    }
    
    @objc func didBecomeActive(with notification: Notification)
    {
        guard let scene = notification.object as? UIWindowScene, scene == self.view.window?.windowScene else { return }
                        
        if self.isEnteringForeground
        {
            // HACK: When returning from background, scene.hasKeyboardFocus may not be accurate when this method is called.
            // As a workaround, we wait an extra 0.5 seconds after becoming active before checking keyboard focus.
            
            self.delayCheckKeyboardFocusTimer?.invalidate()
            self.delayCheckKeyboardFocusTimer = nil
            
            self.delayCheckKeyboardFocusTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { timer in
                guard timer.isValid else { return }
                
                // Keep ignoring keyboard focus notifications until after 0.5 second delay.
                self.isEnteringForeground = false
                self.didBecomeActive(with: notification)
            }
            
            return
        }
        else
        {
            self.isEnteringForeground = false
        }
        
        // Make sure scene has keyboard focus before automatically resuming.
        guard let scene = self.view.window?.windowScene, scene.hasKeyboardFocus else { return }
        
        self.emulatorCoreQueue.async {
            guard self.emulatorCore?.state == .paused else { return }
            _ = self._resumeEmulation()
        }
    }
        
    @objc func willEnterForeground(_ notification: Notification)
    {
        guard let scene = notification.object as? UIScene, scene == self.view.window?.windowScene else { return }
        
        self.isEnteringForeground = true
    }
    
    @objc func controllerViewDidUpdateGameViews(_ notification: Notification)
    {
        guard let addedGameViews = notification.userInfo?[ControllerView.NotificationKey.addedGameViews] as? Set<GameView>,
              let removedGameViews = notification.userInfo?[ControllerView.NotificationKey.removedGameViews] as? Set<GameView>
        else { return }        
        
        for gameView in addedGameViews
        {
            self.emulatorCore?.add(gameView)
        }
        
        for gameView in removedGameViews
        {
            self.emulatorCore?.remove(gameView)
        }
    }
    
    @objc func keyboardWillShow(with notification: Notification)
    {
        guard let window = self.view.window, let traits = self.controllerView.controllerSkinTraits, traits.displayType == .splitView else { return }
        
        let systemKeyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as! CGRect
        guard systemKeyboardFrame.height > 0 else { return }

        // Keyboard frames are given in screen coordinates.
        let appFrame = window.screen.coordinateSpace.convert(window.bounds, from: window.coordinateSpace)
        let relativeHeight = appFrame.maxY - systemKeyboardFrame.minY
        
        let isLocalKeyboard = notification.userInfo?[UIResponder.keyboardIsLocalUserInfoKey] as? Bool ?? false
        if let scene = self.view.window?.windowScene, scene.isStageManagerEnabled, !isLocalKeyboard
        {
            self.splitViewInputViewHeight = 0
        }
        else
        {
            self.splitViewInputViewHeight = relativeHeight
        }
        
        self.updateGameViews()
        
        let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as! TimeInterval
        
        let rawAnimationCurve = notification.userInfo?[UIResponder.keyboardAnimationCurveUserInfoKey] as! Int
        let animationCurve = UIView.AnimationCurve(rawValue: rawAnimationCurve)!
        
        let animator = UIViewPropertyAnimator(duration: duration, curve: animationCurve) {
            self.view.setNeedsLayout()
            self.view.layoutIfNeeded()
        }
        animator.startAnimation()
    }
    
    @objc func keyboardWillChangeFrame(with notification: Notification)
    {
        self.keyboardWillShow(with: notification)
    }
    
    @objc func keyboardWillHide(with notification: Notification)
    {
        let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as! TimeInterval
        
        let rawAnimationCurve = notification.userInfo?[UIResponder.keyboardAnimationCurveUserInfoKey] as! Int
        let animationCurve = UIView.AnimationCurve(rawValue: rawAnimationCurve)!
        
        self.splitViewInputViewHeight = 0
        
        let animator = UIViewPropertyAnimator(duration: duration, curve: animationCurve) {
            self.view.setNeedsLayout()
            self.view.layoutIfNeeded()
        }
        animator.startAnimation()
        
        let isLocalKeyboard = notification.userInfo?[UIResponder.keyboardIsLocalUserInfoKey] as? Bool ?? false
        if let scene = self.view.window?.windowScene, scene.activationState == .foregroundInactive, isLocalKeyboard
        {
            // Explicitly resign first responder to prevent keyboard controller automatically appearing when not frontmost app.
            self.controllerView.resignFirstResponder()
        }
        
        self.updateGameViews()
    }
    
    @objc func sceneKeyboardFocusDidChange(_ notification: Notification)
    {
        guard let scene = notification.object as? UIWindowScene, scene == self.view.window?.windowScene else { return }
        
        guard !self.isEnteringForeground else { return }
        
        if !scene.hasKeyboardFocus && scene.activationState == .foregroundActive
        {
            // Explicitly resign first responder to prevent emulation resuming automatically when not frontmost app.
            self.controllerView.resignFirstResponder()
        }
        
        if let traits = self.controllerView.controllerSkinTraits,
           let screens = self.screens(for: traits), screens.first?.outputFrame == nil
        {
            // First screen is dynamic, so explicitly update game views.
            self.updateGameViews()
        }
        
        // Must run on emulatorCoreQueue to ensure emulatorCore state is accurate.
        self.emulatorCoreQueue.async {
            if scene.hasKeyboardFocus
            {
                guard self.emulatorCore?.state == .paused else { return }
                _ = self._resumeEmulation()
            }
            else
            {
                guard self.emulatorCore?.state == .running else { return }
                _ = self._pauseEmulation()
            }
        }
    }
}
