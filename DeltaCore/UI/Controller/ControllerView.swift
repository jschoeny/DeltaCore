//
//  ControllerView.swift
//  DeltaCore
//
//  Created by Riley Testut on 5/3/15.
//  Copyright (c) 2015 Riley Testut. All rights reserved.
//

import UIKit
import AVFoundation

private struct ControllerViewInputMapping: GameControllerInputMappingProtocol
{
    let controllerView: ControllerView
    
    var name: String {
        return self.controllerView.name
    }
    
    var gameControllerInputType: GameControllerInputType {
        return self.controllerView.inputType
    }
    
    func input(forControllerInput controllerInput: Input) -> Input?
    {
        guard let gameType = self.controllerView.controllerSkin?.gameType, let deltaCore = Delta.core(for: gameType) else { return nil }
        
        if let gameInput = deltaCore.gameInputType.init(stringValue: controllerInput.stringValue)
        {
            return gameInput
        }
        
        if let standardInput = StandardGameControllerInput(stringValue: controllerInput.stringValue)
        {
            return standardInput
        }
        
        return nil
    }
}

extension ControllerView
{
    public static let controllerViewDidChangeControllerSkinNotification = Notification.Name("controllerViewDidChangeControllerSkinNotification")
    public static let controllerViewDidUpdateGameViewsNotification = Notification.Name("controllerViewDidUpdateGameViewsNotification")
    
    public enum NotificationKey: String
    {
        case addedGameViews
        case removedGameViews
    }
}

public class ControllerView: UIView, GameController
{
    //MARK: - Properties -
    /** Properties **/
    public var controllerSkin: ControllerSkinProtocol? {
        didSet {
            self.updateControllerSkin()
            NotificationCenter.default.post(name: ControllerView.controllerViewDidChangeControllerSkinNotification, object: self)
        }
    }
    
    public var controllerSkinTraits: ControllerSkin.Traits? {
        if let traits = self.overrideControllerSkinTraits
        {
            return traits
        }
        
        guard let window = self.window else { return nil }
        
        let traits = ControllerSkin.Traits.defaults(for: window)
        
        guard let controllerSkin = self.controllerSkin else { return traits }
        
        guard let supportedTraits = controllerSkin.supportedTraits(for: traits, alt: self._useAltRepresentations) else { return traits }
        return supportedTraits
    }

    public var controllerSkinSize: ControllerSkin.Size! {
        let size = self.overrideControllerSkinSize ?? UIScreen.main.defaultControllerSkinSize
        return size
    }
    
    public var overrideControllerSkinTraits: ControllerSkin.Traits?
    public var overrideControllerSkinSize: ControllerSkin.Size?
    
    public var translucentControllerSkinOpacity: CGFloat = 0.7
    
    public var isDiagonalDpadInputsEnabled = true {
        didSet {
            self.buttonsView.isDiagonalDpadInputsEnabled = self.isDiagonalDpadInputsEnabled
        }
    }
    
    public var hapticFeedbackStrength = 1.0 {
        didSet {
            self.buttonsView.hapticFeedbackStrength = self.hapticFeedbackStrength
            self.thumbstickViews.values.forEach { $0.hapticFeedbackStrength = self.hapticFeedbackStrength }
        }
    }
    
    public var isButtonHapticFeedbackEnabled = true {
        didSet {
            self.buttonsView.isHapticFeedbackEnabled = self.isButtonHapticFeedbackEnabled
        }
    }
    
    public var isClickyHapticEnabled = true {
        didSet {
            self.buttonsView.isClickyHapticEnabled = self.isClickyHapticEnabled
            self.thumbstickViews.values.forEach { $0.isClickyHapticEnabled = self.isClickyHapticEnabled }
        }
    }
    
    public var isThumbstickHapticFeedbackEnabled = true {
        didSet {
            self.thumbstickViews.values.forEach { $0.isHapticFeedbackEnabled = self.isThumbstickHapticFeedbackEnabled }
        }
    }
    
    public var isButtonTouchOverlayEnabled = true {
        didSet {
            self.buttonsView.isTouchOverlayEnabled = self.isButtonTouchOverlayEnabled
            self.controllerInputView?.controllerView.buttonsView.isTouchOverlayEnabled = self.isButtonTouchOverlayEnabled
        }
    }
    
    public var touchOverlayOpacity = 1.0 {
        didSet {
            self.buttonsView.touchOverlayOpacity = self.touchOverlayOpacity
            self.controllerInputView?.controllerView.buttonsView.touchOverlayOpacity = self.touchOverlayOpacity
        }
    }
    
    public var touchOverlaySize = 1.0 {
        didSet {
            self.buttonsView.touchOverlaySize = self.touchOverlaySize
            self.controllerInputView?.controllerView.buttonsView.touchOverlaySize = self.touchOverlaySize
        }
    }
    
    public var touchOverlayColor = UIColor.white {
        didSet {
            self.buttonsView.touchOverlayColor = self.touchOverlayColor
            self.controllerInputView?.controllerView.buttonsView.touchOverlayColor = self.touchOverlayColor
        }
    }
    
    public var touchOverlayStyle = ButtonOverlayStyle.bubble {
        didSet {
            self.buttonsView.touchOverlayStyle = self.touchOverlayStyle
            self.controllerInputView?.controllerView.buttonsView.touchOverlayStyle = self.touchOverlayStyle
        }
    }
    
    public var isAltRepresentationsEnabled = true {
        didSet {
            self._useAltRepresentations = self.isAltRepresentationsEnabled
            self.controllerInputView?.controllerView.isAltRepresentationsEnabled = self.isAltRepresentationsEnabled
        }
    }
    
    public var isDebugModeEnabled = true {
        didSet {
            self._showDebugMode = self.isDebugModeEnabled
            self.controllerInputView?.controllerView.isDebugModeEnabled = self.isDebugModeEnabled
        }
    }
    
    public var buttonPressedHandler: (() -> Void)?

    public var emulatorCore: EmulatorCore? {
        get {
            return self._emulatorCore
        }
        set {
            self._emulatorCore = newValue
        }
    }
    
    private var liveSkinImages: [String: UIImage] = [:]
    private var liveSkinImageSizes: [String: CGSize] = [:]
    private var liveSkinImageTiles: NSCache<NSString, NSCache<NSString, UIImage>> = NSCache()
    private var liveSkinItems: [String: [ControllerSkin.LiveSkinItem]] = [:]
    
    //MARK: - <GameControllerType>
    /// <GameControllerType>
    public var name: String {
        return self.controllerSkin?.name ?? NSLocalizedString("Game Controller", comment: "")
    }
    
    public var playerIndex: Int? {
        didSet {
            self.reloadInputViews()
        }
    }
    
    public var triggerDeadzone: Float = 0
    
    public var backgroundBlur: Bool? {
        return self._useBackgroundBlur
    }
    
    public let inputType: GameControllerInputType = .controllerSkin
    public lazy var defaultInputMapping: GameControllerInputMappingProtocol? = ControllerViewInputMapping(controllerView: self)
    
    internal weak var appPlacementLayoutGuide: UILayoutGuide? {
        didSet {
            self.controllerDebugView.appPlacementLayoutGuide = self.appPlacementLayoutGuide
        }
    }
    
    internal var isControllerInputView = false
    internal var gameViews: [GameView] {
        var sortedGameViews = self.gameViewsByScreenID.lazy.sorted { $0.key < $1.key }.map { $0.value }
        
        if let controllerView = self.controllerInputView?.controllerView
        {
            // Include controllerInputView's gameViews, if there are any.
            let gameViews = controllerView.gameViews
            sortedGameViews.append(contentsOf: gameViews)
        }
        
        return sortedGameViews
    }
    private var gameViewsByScreenID = [ControllerSkin.Screen.ID: GameView]()
    
    //MARK: - Private Properties
    private let contentView = UIView(frame: .zero)
    private var transitionSnapshotView: UIView? = nil
    private let controllerDebugView = ControllerDebugView()
    
    private let buttonsView = ButtonsInputView(frame: CGRect.zero)
    private var thumbstickViews = [ControllerSkin.Item.ID: ThumbstickInputView]()
    private var touchViews = [ControllerSkin.Item.ID: TouchInputView]()
    
    private var _emulatorCore: EmulatorCore? = nil
    private var _performedInitialLayout = false
    private var _delayedUpdatingControllerSkin = false
    private var _useAltRepresentations = false
    private var _showDebugMode = false
    private var _isCurrentSkinTranslucent = false
    private var _useBackgroundBlur: Bool? = nil
    
    private var controllerInputView: ControllerInputView?
    
    private(set) var imageCache = NSCache<NSString, NSCache<NSString, UIImage>>()
    
    public override var intrinsicContentSize: CGSize {
        return self.buttonsView.intrinsicContentSize
    }
    
    private let keyboardResponder = KeyboardResponder(nextResponder: nil)
    
    //MARK: - Initializers -
    /** Initializers **/
    public override init(frame: CGRect)
    {
        super.init(frame: frame)
        
        self.initialize()
    }
    
    public required init?(coder aDecoder: NSCoder)
    {
        super.init(coder: aDecoder)
        
        self.initialize()
    }
    
    private func initialize()
    {
        self.backgroundColor = UIColor.clear
        
        self.contentView.translatesAutoresizingMaskIntoConstraints = false
        self.addSubview(self.contentView)
        
        self.buttonsView.translatesAutoresizingMaskIntoConstraints = false
        self.buttonsView.activateInputsHandler = { [weak self] (inputs) in
            self?.activateButtonInputs(inputs)
        }
        self.buttonsView.deactivateInputsHandler = { [weak self] (inputs) in
            self?.deactivateButtonInputs(inputs)
        }
        self.contentView.addSubview(self.buttonsView)
        
        self.controllerDebugView.translatesAutoresizingMaskIntoConstraints = false
        self.contentView.addSubview(self.controllerDebugView)
        
        self.isMultipleTouchEnabled = true
        
        // Remove shortcuts from shortcuts bar so it doesn't appear when using external keyboard as input.
        self.inputAssistantItem.leadingBarButtonGroups = []
        self.inputAssistantItem.trailingBarButtonGroups = []
        
        NotificationCenter.default.addObserver(self, selector: #selector(ControllerView.keyboardDidDisconnect(_:)), name: .externalKeyboardDidDisconnect, object: nil)
        
        NSLayoutConstraint.activate([self.contentView.leadingAnchor.constraint(equalTo: self.leadingAnchor),
                                     self.contentView.trailingAnchor.constraint(equalTo: self.trailingAnchor),
                                     self.contentView.topAnchor.constraint(equalTo: self.topAnchor),
                                     self.contentView.bottomAnchor.constraint(equalTo: self.bottomAnchor)])
        
        NSLayoutConstraint.activate([self.buttonsView.leadingAnchor.constraint(equalTo: self.contentView.leadingAnchor),
                                     self.buttonsView.trailingAnchor.constraint(equalTo: self.contentView.trailingAnchor),
                                     self.buttonsView.topAnchor.constraint(equalTo: self.contentView.topAnchor),
                                     self.buttonsView.bottomAnchor.constraint(equalTo: self.contentView.bottomAnchor)])
        
        NSLayoutConstraint.activate([self.controllerDebugView.leadingAnchor.constraint(equalTo: self.contentView.leadingAnchor),
                                     self.controllerDebugView.trailingAnchor.constraint(equalTo: self.contentView.trailingAnchor),
                                     self.controllerDebugView.topAnchor.constraint(equalTo: self.contentView.topAnchor),
                                     self.controllerDebugView.bottomAnchor.constraint(equalTo: self.contentView.bottomAnchor)])
    }
    
    //MARK: - UIView
    /// UIView
    public override func layoutSubviews()
    {
        self.controllerDebugView.setNeedsLayout()
        
        super.layoutSubviews()
        
        _performedInitialLayout = true
        
        guard !_delayedUpdatingControllerSkin else {
            _delayedUpdatingControllerSkin = false
            self.updateControllerSkin()
            return
        }
        
        // updateControllerSkin() calls layoutSubviews(), so don't call again to avoid infinite loop.
        // self.updateControllerSkin()
        
        guard let traits = self.controllerSkinTraits, let controllerSkin = self.controllerSkin, let items = controllerSkin.items(for: traits, alt: self._useAltRepresentations) else { return }
        
        for item in items
        {
            var containingFrame = self.bounds
            if let layoutGuide = self.appPlacementLayoutGuide, item.placement == .app
            {
                containingFrame = layoutGuide.layoutFrame
            }
            
            let frame = item.frame.scaled(to: containingFrame)
            
            switch item.kind
            {
            case .button, .dPad: break
            case .thumbstick:
                guard let thumbstickView = self.thumbstickViews[item.id] else { continue }
                thumbstickView.frame = frame
                
                if thumbstickView.thumbstickSize == nil, let (image, size) = controllerSkin.thumbstick(for: item, traits: traits, preferredSize: self.controllerSkinSize, alt: self._useAltRepresentations)
                {
                    // Update thumbstick in first layoutSubviews() post-updateControllerSkin() to ensure correct size.
                    
                    let size = CGSize(width: size.width * self.bounds.width, height: size.height * self.bounds.height)
                    thumbstickView.thumbstickImage = image
                    thumbstickView.thumbstickSize = size
                }
                
            case .touchScreen:
                guard let touchView = self.touchViews[item.id] else { continue }
                touchView.frame = frame
            }
        }
        
        if let screens = controllerSkin.screens(for: traits, alt: self._useAltRepresentations)
        {
            for screen in screens where screen.placement == .controller
            {
                guard let normalizedFrame = screen.outputFrame, let gameView = self.gameViewsByScreenID[screen.id] else { continue }
                
                let frame = normalizedFrame.scaled(to: self.bounds)
                gameView.frame = frame
            }
        }
    }
    
    public override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView?
    {
        guard self.bounds.contains(point) else { return super.hitTest(point, with: event) }
        
        for (_, thumbstickView) in self.thumbstickViews
        {
            guard thumbstickView.frame.contains(point) else { continue }
            return thumbstickView
        }

        for (_, touchView) in self.touchViews
        {
            guard touchView.frame.contains(point) else { continue }

            if let inputs = self.buttonsView.inputs(at: point)
            {
                // No other inputs at this position, so return touchView.
                if inputs.isEmpty
                {
                    return touchView
                }
            }
        }
        
        return self.buttonsView
    }
    
    //MARK: - <UITraitEnvironment>
    /// <UITraitEnvironment>
    public override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?)
    {
        super.traitCollectionDidChange(previousTraitCollection)
        
        self.setNeedsLayout()
    }
}

//MARK: - UIResponder -
/// UIResponder
extension ControllerView
{
    public override var canBecomeFirstResponder: Bool {
        // "canBecomeFirstResponder" = "should display keyboard controller view" OR "should receive hardware keyboard events"
        // In latter case, we return a nil inputView to prevent software keyboard from appearing.
        
        guard let controllerSkin = self.controllerSkin, let traits = self.controllerSkinTraits else { return false }
        
        if let keyboardController = ExternalGameControllerManager.shared.keyboardController, keyboardController.playerIndex != nil
        {
            // Keyboard is connected and has non-nil player index, so return true to receive keyboard presses.
            return true
        }
        
        guard !(controllerSkin is TouchControllerSkin) else {
            // Unless keyboard is connected, we never want to become first responder with
            // TouchControllerSkin because that will make the software keyboard appear.
            return false
        }
        
        guard self.playerIndex != nil else {
            // Only show keyboard controller if we've been assigned a playerIndex.
            return false
        }
        
        // Finally, only show keyboard controller if we're in Split View and the controller skin supports it.
        let canBecomeFirstResponder = traits.displayType == .splitView && controllerSkin.supports(traits, alt: self._useAltRepresentations)
        return canBecomeFirstResponder
    }
    
    public override var next: UIResponder? {
        return super.next
    }
    
    public override var inputView: UIView? {
        if let keyboardController = ExternalGameControllerManager.shared.keyboardController, keyboardController.playerIndex != nil
        {
            // Don't display any inputView if keyboard is connected and has non-nil player index.
            return nil
        }
        
        return self.controllerInputView
    }
    
    @discardableResult public override func becomeFirstResponder() -> Bool
    {
        guard super.becomeFirstResponder() else { return false }
        
        self.reloadInputViews()
        
        return self.isFirstResponder
    }
    
    internal override func _keyCommand(for event: UIEvent, target: UnsafeMutablePointer<UIResponder>) -> UIKeyCommand?
    {
        let keyCommand = super._keyCommand(for: event, target: target)
        
        _ = self.keyboardResponder._keyCommand(for: event, target: target)
        
        return keyCommand
    }
}

//MARK: - Update Skins -
/// Update Skins
public extension ControllerView
{
    func beginAnimatingUpdateControllerSkin()
    {
        guard self.transitionSnapshotView == nil else { return }
        
        guard let transitionSnapshotView = self.contentView.snapshotView(afterScreenUpdates: false) else { return }
        transitionSnapshotView.frame = self.contentView.frame
        transitionSnapshotView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        transitionSnapshotView.alpha = self.contentView.alpha
        self.addSubview(transitionSnapshotView)
        
        self.transitionSnapshotView = transitionSnapshotView
        
        self.contentView.alpha = 0.0
    }
    
    func updateControllerSkin()
    {
        guard _performedInitialLayout else {
            _delayedUpdatingControllerSkin = true
            return
        }

        self.controllerDebugView.isHidden = !self._showDebugMode
        
        var isTranslucent = false
        
        if let traits = self.controllerSkinTraits
        {
            var items = self.controllerSkin?.items(for: traits, alt: self._useAltRepresentations)
       
            if traits.displayType == .splitView
            {
                if self.isControllerInputView
                {
                    // Filter out all items without `controller` placement.
                    items = items?.filter { $0.placement == .controller }
                }
                else
                {
                    // Filter out all items without `app` placement.
                    items = items?.filter { $0.placement == .app }
                }
            }
            
            if traits.displayType == .splitView && !self.isControllerInputView
            {
                self.buttonsView.image = nil
            }
            else
            {
                let image: UIImage?
                
                if let controllerSkin = self.controllerSkin
                {
                    let cacheKey = String(describing: traits) + "-" + String(describing: self.controllerSkinSize) + "-" + String(describing: self._useAltRepresentations)
                    
                    if
                        let cache = self.imageCache.object(forKey: controllerSkin.identifier as NSString),
                        let cachedImage = cache.object(forKey: cacheKey as NSString)
                    {
                        image = cachedImage
                    }
                    else
                    {
                        image = controllerSkin.image(for: traits, preferredSize: self.controllerSkinSize, alt: self._useAltRepresentations)
                    }
                    
                    if let image = image
                    {
                        let cache = self.imageCache.object(forKey: controllerSkin.identifier as NSString) ?? NSCache<NSString, UIImage>()
                        cache.setObject(image, forKey: cacheKey as NSString)
                        self.imageCache.setObject(cache, forKey: controllerSkin.identifier as NSString)
                    }
                }
                else
                {
                    image = nil
                }
                
                self.buttonsView.image = image
            }
            
            self.buttonsView.items = items
            self.controllerDebugView.items = items
            
            isTranslucent = self.controllerSkin?.isTranslucent(for: traits, alt: self._useAltRepresentations) ?? false
            self._isCurrentSkinTranslucent = isTranslucent
            
            var thumbstickViews = [ControllerSkin.Item.ID: ThumbstickInputView]()
            var previousThumbstickViews = self.thumbstickViews
            
            var touchViews = [ControllerSkin.Item.ID: TouchInputView]()
            var previousTouchViews = self.touchViews
            
            for item in items ?? []
            {
                switch item.kind
                {
                case .button, .dPad: break
                case .thumbstick:
                    let thumbstickView: ThumbstickInputView
                    
                    if let previousThumbstickView = previousThumbstickViews[item.id]
                    {
                        thumbstickView = previousThumbstickView
                        previousThumbstickViews[item.id] = nil
                    }
                    else
                    {
                        thumbstickView = ThumbstickInputView(frame: .zero)
                        self.contentView.addSubview(thumbstickView)
                    }
                    
                    thumbstickView.valueChangedHandler = { [weak self] (xAxis, yAxis) in
                        self?.updateThumbstickValues(item: item, xAxis: xAxis, yAxis: yAxis)
                    }
                    
                    // Calculate correct `thumbstickSize` in layoutSubviews().
                    thumbstickView.thumbstickSize = nil
                    
                    thumbstickView.isHapticFeedbackEnabled = self.isThumbstickHapticFeedbackEnabled
                    
                    thumbstickViews[item.id] = thumbstickView
                    
                case .touchScreen:
                    let touchView: TouchInputView
                    
                    if let previousTouchView = previousTouchViews[item.id]
                    {
                        touchView = previousTouchView
                        previousTouchViews[item.id] = nil
                    }
                    else
                    {
                        touchView = TouchInputView(frame: .zero)
                        self.contentView.addSubview(touchView)
                    }
                    
                    touchView.valueChangedHandler = { [weak self] (point) in
                        self?.updateTouchValues(item: item, point: point)
                    }
                    
                    touchViews[item.id] = touchView
                }
            }
            
            previousThumbstickViews.values.forEach { $0.removeFromSuperview() }
            self.thumbstickViews = thumbstickViews
            
            previousTouchViews.values.forEach { $0.removeFromSuperview() }
            self.touchViews = touchViews
            
            self.initializeLiveSkin()
        }
        else
        {
            self.buttonsView.items = nil
            self.controllerDebugView.items = nil
            
            self.thumbstickViews.values.forEach { $0.removeFromSuperview() }
            self.thumbstickViews = [:]
            
            self.touchViews.values.forEach { $0.removeFromSuperview() }
            self.touchViews = [:]
        }
        
        self.updateGameViews()
        
        if self.transitionSnapshotView != nil
        {
            // Wrap in an animation closure to ensure it actually animates correctly
            // As of iOS 8.3, calling this within transition coordinator animation closure without wrapping
            // in this animation closure causes the change to be instantaneous
            UIView.animate(withDuration: 0.0) {
                self.contentView.alpha = isTranslucent ? self.translucentControllerSkinOpacity : 1.0
            }
        }
        else
        {
            self.contentView.alpha = isTranslucent ? self.translucentControllerSkinOpacity : 1.0
        }
        
        self.transitionSnapshotView?.alpha = 0.0
        
        if self.controllerSkinTraits?.displayType == .splitView
        {
            self.presentInputControllerView()
        }
        else
        {
            self.dismissInputControllerView()
        }
        
        self.controllerInputView?.controllerView.overrideControllerSkinTraits = self.controllerSkinTraits
        
        self.invalidateIntrinsicContentSize()
        self.setNeedsUpdateConstraints()
        self.setNeedsLayout()
        
        self.reloadInputViews()
    }
    
    func updateGameViews()
    {
        guard self.isControllerInputView else { return }
        
        var previousGameViews = self.gameViewsByScreenID
        var gameViews = [ControllerSkin.Screen.ID: GameView]()
        
        if let controllerSkin = self.controllerSkin,
           let traits = self.controllerSkinTraits,
           let screens = controllerSkin.screens(for: traits, alt: self._useAltRepresentations)
        {
            for screen in screens where screen.placement == .controller
            {
                // Only manage screens with explicit outputFrames.
                guard screen.outputFrame != nil else { continue }
                
                let gameView = previousGameViews[screen.id] ?? GameView(frame: .zero)
                gameView.update(for: screen)

                previousGameViews[screen.id] = nil
                gameViews[screen.id] = gameView
            }
        }
        else
        {
            for (_, gameView) in previousGameViews
            {
                gameView.filter = nil
            }
            
            gameViews = [:]
        }
        
        var addedGameViews = Set<GameView>()
        var removedGameViews = Set<GameView>()
        
        // Sort them in controller skin order, so that early screens can be covered by later ones.
        let sortedGameViews = gameViews.lazy.sorted { $0.key < $1.key }.map { $0.value }
        for gameView in sortedGameViews
        {
            guard !self.gameViewsByScreenID.values.contains(gameView) else { continue }
            
            self.contentView.insertSubview(gameView, belowSubview: self.buttonsView)
            addedGameViews.insert(gameView)
        }
        
        for gameView in previousGameViews.values
        {
            gameView.removeFromSuperview()
            removedGameViews.insert(gameView)
        }
        
        self.gameViewsByScreenID = gameViews
        
        // Use destination controllerView as Notification object, since that is what client expects.
        let controllerView = self.receivers.lazy.compactMap { $0 as? ControllerView }.first ?? self
        
        NotificationCenter.default.post(name: ControllerView.controllerViewDidUpdateGameViewsNotification, object: controllerView, userInfo: [
            ControllerView.NotificationKey.addedGameViews: addedGameViews,
            ControllerView.NotificationKey.removedGameViews: removedGameViews
        ])
    }
    
    func finishAnimatingUpdateControllerSkin()
    {
        if let transitionImageView = self.transitionSnapshotView
        {
            transitionImageView.removeFromSuperview()
            self.transitionSnapshotView = nil
        }
        
        self.contentView.alpha = self._isCurrentSkinTranslucent ? self.translucentControllerSkinOpacity : 1.0
    }
    
    func invalidateImageCache()
    {
        self.imageCache.removeAllObjects()
        self.controllerInputView?.controllerView.imageCache.removeAllObjects()
    }
}

private extension ControllerView
{
    func presentInputControllerView()
    {
        guard !self.isControllerInputView else { return }

        guard let controllerSkin = self.controllerSkin, let traits = self.controllerSkinTraits else { return }

        if self.controllerInputView == nil
        {
            let inputControllerView = ControllerInputView(frame: CGRect(x: 0, y: 0, width: 1024, height: 300))
            inputControllerView.controllerView.addReceiver(self, inputMapping: nil)
            self.controllerInputView = inputControllerView
        }

        if controllerSkin.supports(traits, alt: self._useAltRepresentations)
        {
            self.controllerInputView?.controllerView.controllerSkin = controllerSkin
        }
        else
        {
            self.controllerInputView?.controllerView.controllerSkin = ControllerSkin.standardControllerSkin(for: controllerSkin.gameType)
        }
    }
    
    func dismissInputControllerView()
    {
        guard !self.isControllerInputView else { return }
        
        guard self.controllerInputView != nil else { return }
        
        self.controllerInputView = nil
    }
}

//MARK: - Activating/Deactivating Inputs -
/// Activating/Deactivating Inputs
private extension ControllerView
{
    func activateButtonInputs(_ inputs: Set<AnyInput>)
    {
        self.buttonPressedHandler?()
        
        for input in inputs
        {
            self.activate(input)
        }
    }
    
    func deactivateButtonInputs(_ inputs: Set<AnyInput>)
    {
        for input in inputs
        {
            self.deactivate(input)
        }
    }
    
    func updateThumbstickValues(item: ControllerSkin.Item, xAxis: Double, yAxis: Double)
    {
        guard case .directional(let up, let down, let left, let right) = item.inputs else { return }
        
        switch xAxis
        {
        case ..<0:
            self.activate(left, value: -xAxis)
            self.deactivate(right)
            
        case 0:
            self.deactivate(left)
            self.deactivate(right)
            
        default:
            self.deactivate(left)
            self.activate(right, value: xAxis)
        }
        
        switch yAxis
        {
        case ..<0:
            self.activate(down, value: -yAxis)
            self.deactivate(up)
            
        case 0:
            self.deactivate(down)
            self.deactivate(up)
            
        default:
            self.deactivate(down)
            self.activate(up, value: yAxis)
        }
    }
    
    func updateTouchValues(item: ControllerSkin.Item, point: CGPoint?)
    {
        guard case .touch(let x, let y) = item.inputs else { return }
        
        if let point = point
        {
            self.activate(x, value: Double(point.x))
            self.activate(y, value: Double(point.y))
        }
        else
        {
            self.deactivate(x)
            self.deactivate(y)
        }
    }
}

private extension ControllerView
{
    @objc func keyboardDidDisconnect(_ notification: Notification)
    {
        guard self.isFirstResponder else { return }
        
        self.resignFirstResponder()
        
        if self.canBecomeFirstResponder
        {
            self.becomeFirstResponder()
        }
    }
}

//MARK: - GameControllerReceiver -
/// GameControllerReceiver
extension ControllerView: GameControllerReceiver
{
    public func gameController(_ gameController: GameController, didActivate input: Input, value: Double)
    {
        guard gameController == self.controllerInputView?.controllerView else { return }
        
        self.activate(input, value: value)
    }
    
    public func gameController(_ gameController: GameController, didDeactivate input: Input)
    {
        guard gameController == self.controllerInputView?.controllerView else { return }
        
        self.deactivate(input)
    }
}

//MARK: - UIKeyInput
/// UIKeyInput
// Becoming first responder doesn't steal keyboard focus from other apps in split view unless the first responder conforms to UIKeyInput.
// So, we conform ControllerView to UIKeyInput and provide stub method implementations.
extension ControllerView: UIKeyInput
{
    public var hasText: Bool {
        return false
    }
    
    public func insertText(_ text: String)
    {
    }
    
    public func deleteBackward()
    {
    }
}

//MARK: - Live Skin Items -
/// Live Skin Items
extension UIImage
{
    func extractTiles(with tileSize: CGSize) -> [UIImage]?
    {
        let verticalCount = max(1, Int(size.height / tileSize.height))
        let horizontalCount = max(1, Int(size.width / tileSize.width))
        let tileWidth = min(tileSize.width, size.width)
        let tileHeight = min(tileSize.height, size.height)
        let tileSizeNormalized = CGSize(width: tileWidth, height: tileHeight)

        var tiles = [UIImage]()

        for verticalIndex in 0...verticalCount - 1
        {
            for horizontalIndex in 0...horizontalCount - 1
            {
                let imagePoint = CGPoint(x: CGFloat(horizontalIndex) * tileWidth * -1,
                                         y: CGFloat(verticalIndex) * tileHeight * -1)
                UIGraphicsBeginImageContextWithOptions(tileSizeNormalized, false, 0.0)
                draw(at: imagePoint)
                if let newImage = UIGraphicsGetImageFromCurrentImageContext()
                {
                    tiles.append(newImage)
                }
                UIGraphicsEndImageContext()
            }
        }

        return tiles
    }

    func extractTile(at index: Int, with tileSize: CGSize) -> UIImage?
    {
        let verticalCount = max(1, Int(size.height / tileSize.height))
        let horizontalCount = max(1, Int(size.width / tileSize.width))
        let tileWidth = min(tileSize.width, size.width)
        let tileHeight = min(tileSize.height, size.height)
        let tileSizeNormalized = CGSize(width: tileWidth, height: tileHeight)

        let verticalIndex = index / horizontalCount
        let horizontalIndex = index % horizontalCount

        // Return nil if the index is out of bounds
        if verticalIndex >= verticalCount || horizontalIndex >= horizontalCount
        {
            return nil
        }

        let imagePoint = CGPoint(x: CGFloat(horizontalIndex) * tileWidth * -1,
                                 y: CGFloat(verticalIndex) * tileHeight * -1)
        UIGraphicsBeginImageContextWithOptions(tileSizeNormalized, false, 0.0)
        draw(at: imagePoint)
        let newImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        return newImage
    }
}

extension ControllerView
{
    public func initializeLiveSkin()
    {
        guard let controllerSkin = self.controllerSkin, let traits = self.controllerSkinTraits else { return }
        
        self.resetLiveSkinOverlay()

        if let items = controllerSkin.liveSkinItems(for: traits, alt: self._useAltRepresentations)
        {
            let cacheKey = String(describing: traits) + "-" + String(describing: self.controllerSkinSize) + "-" + String(describing: self._useAltRepresentations)
            
            for item in items
            {
                switch item.decryptionMethod
                {
                case .none: break
                case .xor(let keyAddress, let keyBitInfo):
                    setLiveSkinAddress(keyAddress, with: keyBitInfo)
                case .gbaPokemonParty(_, let personalityAddress, let otIdAddress):
                    let bitInfo = ControllerSkin.LiveSkinItem.BitInfo(width: 32, offset: 0)
                    setLiveSkinAddress(personalityAddress, with: bitInfo)
                    setLiveSkinAddress(otIdAddress, with: bitInfo)
                }

                switch item.data
                {
                    case .image(let address, let bitInfo, let filename, let size):
                        if let image = controllerSkin.liveSkinImage(for: item, traits: traits, preferredSize: self.controllerSkinSize, alt: self._useAltRepresentations)
                        {
                            self.tryAddLiveSkinImage(image: image, for: filename, with: size)
                            setLiveSkinAddress(address, with: bitInfo)
                        }
                    case .circularHP(let hpAddress, let hpMaxAddress, let hpBitInfo, let hpMaxBitInfo, _):
                        setLiveSkinAddress(hpAddress, with: hpBitInfo)
                        setLiveSkinAddress(hpMaxAddress, with: hpMaxBitInfo)
                    case .rectangularHP(let hpAddress, let hpMaxAddress, let hpBitInfo, let hpMaxBitInfo, _):
                        setLiveSkinAddress(hpAddress,  with: hpBitInfo)
                        setLiveSkinAddress(hpMaxAddress, with: hpMaxBitInfo)
                    case .number(let address, let bitInfo, _, _):
                        setLiveSkinAddress(address, with: bitInfo)
                    case .indexedText(let address, let bitInfo, _, _, _):
                        setLiveSkinAddress(address, with: bitInfo)
                }
            }
            self.liveSkinItems[cacheKey] = items
        }
    }

    private func addressToKey(_ address: ControllerSkin.LiveSkinItem.Address, bitWidth: Int, bitOffset: Int = 0) -> String
    {
        switch address
        {
            case .address(let value):
                return String(value) + ":" + String(bitWidth) + ">>" + String(bitOffset)
            case .pointer(let value, let offset):
                return String(value) + "+" + String(offset) + ":" + String(bitWidth) + ">>" + String(bitOffset)
        }
    }

    private func setLiveSkinAddress(_ address: ControllerSkin.LiveSkinItem.Address, with bitInfo: ControllerSkin.LiveSkinItem.BitInfo) -> String?
    {
        guard let emulatorBridge = self._emulatorCore?.deltaCore.emulatorBridge else { return nil }
        guard let setAddress = emulatorBridge.setLiveSkinAddress else { return nil }
        guard let setPointer = emulatorBridge.setLiveSkinPointer else { return nil }
        let key = addressToKey(address, bitWidth: bitInfo.width, bitOffset: bitInfo.offset)

        switch address
        {
            case .address(let value):
                setAddress(key, value, bitInfo.width, bitInfo.offset)
            case .pointer(let value, let offset):
                setPointer(key, value, offset, bitInfo.width, bitInfo.offset)
        }
        return key
    }

    private func setLiveSkinAddress(_ address: ControllerSkin.LiveSkinItem.Address, with bitInfo: ControllerSkin.LiveSkinItem.BitInfo, decryptionMethod: ControllerSkin.LiveSkinItem.DecryptionMethod) -> String?
    {
        guard let emulatorBridge = self._emulatorCore?.deltaCore.emulatorBridge else { return nil }
        guard let setAddress = emulatorBridge.setLiveSkinAddress else { return nil }
        guard let setPointer = emulatorBridge.setLiveSkinPointer else { return nil }
        guard let getValue = emulatorBridge.getLiveSkinValue else { return nil }

        switch decryptionMethod
        {
            case .gbaPokemonParty(let monAddress, let personalityAddress, let otIdAddress):
                let personalityKey = addressToKey(personalityAddress, bitWidth: 32)
                let personality = getValue(personalityKey)
                let substructSelector: [[Int]] = [
                    [0, 1, 2, 3], // 0
                    [0, 1, 3, 2], // 1
                    [0, 2, 1, 3], // 2
                    [0, 3, 1, 2], // 3
                    [0, 2, 3, 1], // 4
                    [0, 3, 2, 1], // 5
                    [1, 0, 2, 3], // 6
                    [1, 0, 3, 2], // 7
                    [2, 0, 1, 3], // 8
                    [3, 0, 1, 2], // 9
                    [2, 0, 3, 1], // 10
                    [3, 0, 2, 1], // 11
                    [1, 2, 0, 3], // 12
                    [1, 3, 0, 2], // 13
                    [2, 1, 0, 3], // 14
                    [3, 1, 0, 2], // 15
                    [2, 3, 0, 1], // 16
                    [3, 2, 0, 1], // 17
                    [1, 2, 3, 0], // 18
                    [1, 3, 2, 0], // 19
                    [2, 1, 3, 0], // 20
                    [3, 1, 2, 0], // 21
                    [2, 3, 1, 0], // 22
                    [3, 2, 1, 0]  // 23
                ]
                let pSelect = substructSelector[personality % 24]
                var baseAddress: Int
                switch monAddress
                {
                    case .address(let value):
                        baseAddress = value
                    case .pointer: return nil
                }
                switch address
                {
                    case .address(let value):
                        // Value should be the offset from monAddress
                        // We need to translate that offset according to the mon's encryption algorithm
                        // First, we need to find which substruct the value belongs to
                        // Each substruct is 12 bytes long
                        // The first substruct starts at monAddress + 32
                        let originalSubstruct = (value - 32) / 12
                        let localOffset = (value - 32) % 12
                        let newSubstruct = pSelect[originalSubstruct]
                        let newValue = baseAddress + 32 + (newSubstruct * 12) + localOffset
                        let key = String(newValue) + ":" + String(bitInfo.width) + ">>" + String(bitInfo.offset)
                        setAddress(key, newValue, bitInfo.width, bitInfo.offset)
                        return key
                    case .pointer(_, _):
                        break
                }
            default:
                break
        }
        return nil
    }

    func tryAddLiveSkinImage(image: UIImage, for key: String, with size: CGSize)
    {
        // Check if the image has already been added
        if self.liveSkinImages[key] != nil && self.liveSkinImageSizes[key] != nil { return }
        
        // Add the image to liveSkinImages
        self.liveSkinImages[key] = image
        self.liveSkinImageSizes[key] = size
    }

    func getLiveSkinImage(for key: String, with index: Int) -> UIImage?
    {
        guard let image = self.liveSkinImages[key] else { return nil }
        guard let size = self.liveSkinImageSizes[key] else { return nil }
        
        guard let cache = self.liveSkinImageTiles.object(forKey: key as NSString) else {
            // Create a new cache and extract the image
            let newCache = NSCache<NSString, UIImage>()
            guard let extractedImage = image.extractTile(at: index, with: size) else { return nil }
            newCache.setObject(extractedImage, forKey: String(index) as NSString)
            self.liveSkinImageTiles.setObject(newCache, forKey: key as NSString)
            return extractedImage
        }

        guard let extractedImage = cache.object(forKey: String(index) as NSString) else {
            // Extract the image
            guard let extractedImage = image.extractTile(at: index, with: size) else { return nil }
            cache.setObject(extractedImage, forKey: String(index) as NSString)
            return extractedImage
        }

        return extractedImage
    }

    private func tryDecryptValue(item: ControllerSkin.LiveSkinItem, address: ControllerSkin.LiveSkinItem.Address, bitInfo: ControllerSkin.LiveSkinItem.BitInfo) -> Int
    {
        guard let getValue = self._emulatorCore?.deltaCore.emulatorBridge.getLiveSkinValue else { return 0 }
        let method = item.decryptionMethod
        switch method
        {
            case .none:
                let valueID = addressToKey(address, bitWidth: bitInfo.width, bitOffset: bitInfo.offset)
                let value = getValue(valueID)
                return value
            case .xor(let keyAddress, _):
                let keyKey = addressToKey(keyAddress, bitWidth: 32)
                let key = getValue(keyKey)
                let valueID = addressToKey(address, bitWidth: bitInfo.width, bitOffset: bitInfo.offset)
                let value = getValue(valueID)
                return value ^ key
            case .gbaPokemonParty(_, let personalityAddress, let otIdAddress):
                let personalityKey = addressToKey(personalityAddress, bitWidth: 32)
                let personality = getValue(personalityKey)
                let otIdKey = addressToKey(otIdAddress, bitWidth: 32)
                let otId = getValue(otIdKey)
                var addressOffset = 0
                switch address
                {
                    case .address(let baseValue):
                        addressOffset = baseValue
                    case .pointer: return 0
                }
                // Line up the key properly
                let mask = (1 << bitInfo.width) - 1
                let key = ((otId ^ personality) >> (((addressOffset % 4) * 8) + bitInfo.offset)) & mask
                // Update the live skin address for whenever personality or otId changes
                if let valueID = setLiveSkinAddress(address, with: bitInfo, decryptionMethod: method) {
                    let value = getValue(valueID)
                    let retValue = value ^ key
                    return retValue
                }
                return 0
        }
    }

    public func updateLiveSkinOverlay() {
        guard let traits = self.controllerSkinTraits else { return }
        guard self._emulatorCore?.deltaCore.emulatorBridge.getLiveSkinValue != nil else { return }

        let cacheKey = String(describing: traits) + "-" + String(describing: self.controllerSkinSize) + "-" + String(describing: self._useAltRepresentations)
        guard let items = self.liveSkinItems[cacheKey] else {
            self.buttonsView.updateLiveSkinOverlayView(overlayImage: nil)
            return
        }

        let overlayLineWidth = 4.0
        let renderer = UIGraphicsImageRenderer(bounds: self.bounds)

        let overlayImage: UIImage = renderer.image { (context) in
            let cgContext = context.cgContext
            
            var containingFrame = self.bounds
            
            for item in items
            {
                if let layoutGuide = self.appPlacementLayoutGuide, item.placement == .app
                {
                    containingFrame = layoutGuide.layoutFrame
                }
                let frame = item.frame.scaled(to: containingFrame)
                switch item.data
                {
                    case .image(let address, let bitInfo, let imageName, _):
                        let value = tryDecryptValue(item: item, address: address, bitInfo: bitInfo)
                        if value < 0 { continue }

                        if let image = self.getLiveSkinImage(for: imageName, with: Int(value))
                        {
                            image.draw(in: frame)
                        }

                    case .circularHP(let hpAddress, let hpMaxAddress, let hpBitInfo, let hpMaxBitInfo, let colors):
                        let hp = tryDecryptValue(item: item, address: hpAddress, bitInfo: hpBitInfo)
                        let hpMax = tryDecryptValue(item: item, address: hpMaxAddress, bitInfo: hpMaxBitInfo)
                        if hpMax == 0 { continue }
                    
                        let healthRatio = 1.0 - (Double(hp) / Double(hpMax))
                        if healthRatio >= 0.75
                        {
                            cgContext.setStrokeColor(colors[2].cgColor)
                        }
                        else if healthRatio >= 0.5
                        {
                            cgContext.setStrokeColor(colors[1].cgColor)
                        }
                        else
                        {
                            cgContext.setStrokeColor(colors[0].cgColor)
                        }
                        cgContext.setLineWidth(overlayLineWidth * 2)
                    
                        if healthRatio == 0.0
                        {
                            let radius = frame.width/2
                            cgContext.addArc(center: CGPoint(x: frame.minX + radius, y: frame.minY + radius), radius: radius - overlayLineWidth, startAngle: 0, endAngle: 2 * .pi, clockwise: true) 
                        }
                        else
                        {
                            let startAngle = 1.5 * .pi
                            let endAngle = startAngle + (CGFloat(healthRatio) * 2.0 * .pi)
                        
                            let radius = frame.width/2
                            cgContext.addArc(center: CGPoint(x: frame.minX + radius, y: frame.minY + radius), radius: radius - overlayLineWidth, startAngle: startAngle, endAngle: endAngle, clockwise: true)
                        }
                        cgContext.drawPath(using: .stroke)

                    case .rectangularHP(let hpAddress, let hpMaxAddress, let hpBitInfo, let hpMaxBitInfo, let colors):
                        let hp = tryDecryptValue(item: item, address: hpAddress, bitInfo: hpBitInfo)
                        let hpMax = tryDecryptValue(item: item, address: hpMaxAddress, bitInfo: hpMaxBitInfo)
                        if hpMax == 0 { continue }

                        let healthRatio = (Double(hp) / Double(hpMax))
                        if healthRatio <= 0.25
                        {
                            cgContext.setFillColor(colors[2].cgColor)
                        }
                        else if healthRatio <= 0.5
                        {
                            cgContext.setFillColor(colors[1].cgColor)
                        }
                        else
                        {
                            cgContext.setFillColor(colors[0].cgColor)
                        }

                        let healthWidth = frame.width * CGFloat(healthRatio)
                        let healthFrame = CGRect(x: frame.minX, y: frame.minY, width: healthWidth, height: frame.height)

                        cgContext.addRect(healthFrame)
                        cgContext.drawPath(using: .fill)

                    case .number(let address, let bitInfo, let font, let color):
                        // Draw number as text
                        let value = self.tryDecryptValue(item: item, address: address, bitInfo: bitInfo)
                        let string = String(value)
                        let attributes: [NSAttributedString.Key : Any] = [.font: font, .foregroundColor: color]
                        let attributedString = NSAttributedString(string: string, attributes: attributes)
                        
                        // Render
                        let line = CTLineCreateWithAttributedString(attributedString)
                        let stringRect = CTLineGetImageBounds(line, cgContext)
                        let textTransform = CGAffineTransform(scaleX: 1.0, y: -1.0).translatedBy(x: frame.minX + (frame.width/2) - (stringRect.width/2), y: -frame.minY - (frame.height/2) - (stringRect.height/2))
                        cgContext.textMatrix = textTransform
                        CTLineDraw(line, cgContext)

                    case .indexedText(let address, let bitInfo, let font, let color, let strings):
                        let value = self.tryDecryptValue(item: item, address: address, bitInfo: bitInfo)
                        if value < 0 || value >= strings.count { continue }
                        let string = strings[value]
                        let attributes: [NSAttributedString.Key : Any] = [.font: font, .foregroundColor: color]
                        let attributedString = NSAttributedString(string: string, attributes: attributes)

                        // Render
                        let line = CTLineCreateWithAttributedString(attributedString)
                        let stringRect = CTLineGetImageBounds(line, cgContext)
                        let textTransform = CGAffineTransform(scaleX: 1.0, y: -1.0).translatedBy(x: frame.minX + (frame.width/2) - (stringRect.width/2), y: -frame.minY - (frame.height/2) - (stringRect.height/2))
                        cgContext.textMatrix = textTransform
                        CTLineDraw(line, cgContext)
                }
            }
        }
        
        self.buttonsView.updateLiveSkinOverlayView(overlayImage: overlayImage)
    }

    public func clearLiveSkinOverlay()
    {
        self.buttonsView.updateLiveSkinOverlayView(overlayImage: nil)
    }

    public func resetLiveSkinOverlay()
    {
        self.buttonsView.updateLiveSkinOverlayView(overlayImage: nil)
        self.liveSkinImages.removeAll()
        self.liveSkinImageSizes.removeAll()
        self.liveSkinImageTiles.removeAllObjects()
        self.liveSkinItems.removeAll()
    }
}
