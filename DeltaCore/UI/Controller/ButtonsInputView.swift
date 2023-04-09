//
//  ButtonsInputView.swift
//  DeltaCore
//
//  Created by Riley Testut on 8/4/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import UIKit
import AVFoundation

class ButtonsInputView: UIView
{
    var isHapticFeedbackEnabled = true
    var isClickyHapticEnabled = true
    var isTouchOverlayEnabled = true
    var isAudioFeedbackEnabled = true
    
    var hapticFeedbackStrength = 1.0
    var touchOverlayOpacity = 1.0
    var touchOverlaySize = 1.0
    
    var touchOverlayColor = UIColor.white
    
    var items: [ControllerSkin.Item]?
    
    var activateInputsHandler: ((Set<AnyInput>) -> Void)?
    var deactivateInputsHandler: ((Set<AnyInput>) -> Void)?
    
    var image: UIImage? {
        get {
            return self.imageView.image
        }
        set {
            self.imageView.image = newValue
        }
    }
    
    var buttonPressedSoundID: SystemSoundID = 444
    var buttonPressedSoundURL: URL = URL(fileURLWithPath: "/System/Library/Audio/UISounds/Tock.caf") {
        didSet {
            AudioServicesCreateSystemSoundID(self.buttonPressedSoundURL as CFURL, &self.buttonPressedSoundID)
        }
    }
    
    private let imageView = UIImageView(frame: .zero)
    private let touchOverlayView = UIImageView(frame: .zero)
    private let feedbackGenerator: UIImpactFeedbackGenerator = UIImpactFeedbackGenerator(style: .rigid)
    
    private var touchInputsMappingDictionary: [UITouch: Set<AnyInput>] = [:]
    private var previousTouchInputs = Set<AnyInput>()
    private var touchInputs: Set<AnyInput> {
        return self.touchInputsMappingDictionary.values.reduce(Set<AnyInput>(), { $0.union($1) })
    }
    
    override var intrinsicContentSize: CGSize {
        return self.imageView.intrinsicContentSize
    }
    
    override init(frame: CGRect)
    {
        super.init(frame: frame)
        
        self.isMultipleTouchEnabled = true
        
        AudioServicesCreateSystemSoundID(self.buttonPressedSoundURL as CFURL, &self.buttonPressedSoundID)
        
        self.feedbackGenerator.prepare()
        
        self.imageView.translatesAutoresizingMaskIntoConstraints = false
        self.addSubview(self.imageView)
        
        NSLayoutConstraint.activate([self.imageView.leadingAnchor.constraint(equalTo: self.leadingAnchor),
                                     self.imageView.trailingAnchor.constraint(equalTo: self.trailingAnchor),
                                     self.imageView.topAnchor.constraint(equalTo: self.topAnchor),
                                     self.imageView.bottomAnchor.constraint(equalTo: self.bottomAnchor)])
        
        self.touchOverlayView.translatesAutoresizingMaskIntoConstraints = false
        self.addSubview(self.touchOverlayView)
        
        NSLayoutConstraint.activate([self.touchOverlayView.leadingAnchor.constraint(equalTo: self.leadingAnchor),
                                     self.touchOverlayView.trailingAnchor.constraint(equalTo: self.trailingAnchor),
                                     self.touchOverlayView.topAnchor.constraint(equalTo: self.topAnchor),
                                     self.touchOverlayView.bottomAnchor.constraint(equalTo: self.bottomAnchor)])
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?)
    {
        for touch in touches
        {
            self.touchInputsMappingDictionary[touch] = []
        }
        
        self.updateInputs(for: touches)
        
        if self.isTouchOverlayEnabled
        {
            self.updateTouchOverlay()
        }
    }
    
    public override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?)
    {
        self.updateInputs(for: touches)
        
        if self.isTouchOverlayEnabled
        {
            self.updateTouchOverlay()
        }
    }
    
    public override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?)
    {
        for touch in touches
        {
            self.touchInputsMappingDictionary[touch] = nil
        }
        
        self.updateInputs(for: touches)
        
        if self.isTouchOverlayEnabled
        {
            self.updateTouchOverlay()
        }
    }
    
    public override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?)
    {
        return self.touchesEnded(touches, with: event)
    }
}

extension ButtonsInputView
{
    func inputs(at point: CGPoint) -> [Input]?
    {
        guard let items = self.items else { return nil }
        
        var point = point
        point.x /= self.bounds.width
        point.y /= self.bounds.height
        
        var inputs: [Input] = []
        
        for item in items
        {
            guard item.extendedFrame.contains(point) else { continue }
            
            switch item.inputs
            {
            // Don't return inputs for thumbsticks or touch screens since they're handled separately.
            case .directional where item.kind == .thumbstick: break
            case .touch: break
                
            case .standard(let itemInputs):
                inputs.append(contentsOf: itemInputs)
            
            case let .directional(up, down, left, right):

                let divisor: CGFloat
                if case .thumbstick = item.kind
                {
                    divisor = 2.0
                }
                else
                {
                    divisor = 3.0
                }
                
                let topRect = CGRect(x: item.extendedFrame.minX, y: item.extendedFrame.minY, width: item.extendedFrame.width, height: (item.frame.height / divisor) + (item.frame.minY - item.extendedFrame.minY))
                let bottomRect = CGRect(x: item.extendedFrame.minX, y: item.frame.maxY - item.frame.height / divisor, width: item.extendedFrame.width, height: (item.frame.height / divisor) + (item.extendedFrame.maxY - item.frame.maxY))
                let leftRect = CGRect(x: item.extendedFrame.minX, y: item.extendedFrame.minY, width: (item.frame.width / divisor) + (item.frame.minX - item.extendedFrame.minX), height: item.extendedFrame.height)
                let rightRect = CGRect(x: item.frame.maxX - item.frame.width / divisor, y: item.extendedFrame.minY, width: (item.frame.width / divisor) + (item.extendedFrame.maxX - item.frame.maxX), height: item.extendedFrame.height)
                
                if topRect.contains(point)
                {
                    inputs.append(up)
                }
                
                if bottomRect.contains(point)
                {
                    inputs.append(down)
                }
                
                if leftRect.contains(point)
                {
                    inputs.append(left)
                }
                
                if rightRect.contains(point)
                {
                    inputs.append(right)
                }
            }
        }
        
        return inputs
    }
}

private extension ButtonsInputView
{
    func updateInputs(for touches: Set<UITouch>)
    {
        // Don't add the touches if it has been removed in touchesEnded:/touchesCancelled:
        for touch in touches where self.touchInputsMappingDictionary[touch] != nil
        {
            guard touch.view == self else { continue }
            
            let point = touch.location(in: self)
            let inputs = Set((self.inputs(at: point) ?? []).map { AnyInput($0) })
            
            let menuInput = AnyInput(stringValue: StandardGameControllerInput.menu.stringValue, intValue: nil, type: .controller(.controllerSkin))
            if inputs.contains(menuInput)
            {
                // If the menu button is located at this position, ignore all other inputs that might be overlapping.
                self.touchInputsMappingDictionary[touch] = [menuInput]
            }
            else
            {
                self.touchInputsMappingDictionary[touch] = Set(inputs)
            }
        }
        
        let activatedInputs = self.touchInputs.subtracting(self.previousTouchInputs)
        let deactivatedInputs = self.previousTouchInputs.subtracting(self.touchInputs)
        
        // We must update previousTouchInputs *before* calling activate() and deactivate().
        // Otherwise, race conditions that cause duplicate touches from activate() or deactivate() calls can result in various bugs.
        self.previousTouchInputs = self.touchInputs
        
        if !activatedInputs.isEmpty
        {
            self.activateInputsHandler?(activatedInputs)
            
            if self.isAudioFeedbackEnabled
            {
                AudioServicesPlaySystemSound(self.buttonPressedSoundID)
            }
            
            if self.isHapticFeedbackEnabled
            {
                switch UIDevice.current.feedbackSupportLevel
                {
                case .feedbackGenerator: self.feedbackGenerator.impactOccurred(intensity: self.hapticFeedbackStrength)
                case .basic, .unsupported: UIDevice.current.vibrate(self.hapticFeedbackStrength)
                }
            }
        }
        
        if !deactivatedInputs.isEmpty
        {
            self.deactivateInputsHandler?(deactivatedInputs)
            
            if self.isHapticFeedbackEnabled, self.isClickyHapticEnabled
            {
                switch UIDevice.current.feedbackSupportLevel
                {
                case .feedbackGenerator: self.feedbackGenerator.impactOccurred(intensity: self.hapticFeedbackStrength)
                case .basic, .unsupported: UIDevice.current.vibrate(self.hapticFeedbackStrength)
                }
            }
        }
    }
    
    func updateTouchOverlay() {
        guard self.image != nil else { return }
        guard let items = self.items else { return }
        
        let overlayImage: UIImage?
        
        let touchOverlayGradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [self.touchOverlayColor.withAlphaComponent(self.touchOverlayOpacity).cgColor, self.touchOverlayColor.withAlphaComponent(0.0).cgColor] as CFArray, locations: [0.3, 1.0])!
        
        UIGraphicsBeginImageContextWithOptions(self.bounds.size, false, self.touchOverlayOpacity)
        let context = UIGraphicsGetCurrentContext()!
        
        for item in items
        {
            guard item.kind != .touchScreen, item.kind != .thumbstick else { continue }
            
            for touch in self.touchInputsMappingDictionary.keys
            {
                var scaledTouch = touch.location(in: self)
                scaledTouch.x /= self.bounds.width
                scaledTouch.y /= self.bounds.height
                
                let frame = item.extendedFrame
                
                guard frame.contains(scaledTouch) else { continue }
                
                var inputCenter = CGPoint()
                
                switch item.inputs
                {
                case .directional where item.kind == .thumbstick:
                    // thumbstick  code
                    break
                case .touch:
                    // touch code
                    break
                case .standard:
                    // normal button code
                    inputCenter = self.centerPoint(rect: item.frame)
                
                case .directional:
                    // calculate input rectangles for up down left right to test if touch lies within them
                    let topRect = CGRect(x: item.extendedFrame.minX, y: item.extendedFrame.minY, width: item.extendedFrame.width, height: (item.frame.height / 3) + (item.frame.minY - item.extendedFrame.minY))
                    let bottomRect = CGRect(x: item.extendedFrame.minX, y: item.frame.maxY - item.frame.height / 3, width: item.extendedFrame.width, height: (item.frame.height / 3) + (item.extendedFrame.maxY - item.frame.maxY))
                    let leftRect = CGRect(x: item.extendedFrame.minX, y: item.extendedFrame.minY, width: (item.frame.width / 3) + (item.frame.minX - item.extendedFrame.minX), height: item.extendedFrame.height)
                    let rightRect = CGRect(x: item.frame.maxX - item.frame.width / 3, y: item.extendedFrame.minY, width: (item.frame.width / 3) + (item.extendedFrame.maxX - item.frame.maxX), height: item.extendedFrame.height)
                    
                    // offset to move the corner inputs in by so they're not sticking so far out
                    let offsetX = item.frame.width * 0.1; let offsetY = item.frame.height * 0.1
                    
                    // determine which section of the dpad touch is in, set inputCenter to that location
                    if topRect.contains(scaledTouch)
                    {
                        inputCenter.y = self.centerPoint(rect: topRect).y
                        if leftRect.contains(scaledTouch)
                        {
                            inputCenter.x = self.centerPoint(rect: leftRect).x + offsetX
                            inputCenter.y += offsetY
                        }
                        else if rightRect.contains(scaledTouch)
                        {
                            inputCenter.x = self.centerPoint(rect: rightRect).x - offsetX
                            inputCenter.y += offsetY
                        }
                        else
                        {
                            inputCenter.x = self.centerPoint(rect: item.frame).x
                        }
                    }
                    else if bottomRect.contains(scaledTouch)
                    {
                        inputCenter.y = self.centerPoint(rect: bottomRect).y
                        if leftRect.contains(scaledTouch)
                        {
                            inputCenter.x = self.centerPoint(rect: leftRect).x + offsetX
                            inputCenter.y -= offsetY
                        }
                        else if rightRect.contains(scaledTouch)
                        {
                            inputCenter.x = self.centerPoint(rect: rightRect).x - offsetY
                            inputCenter.y -= offsetY
                        }
                        else
                        {
                            inputCenter.x = self.centerPoint(rect: item.frame).x
                        }
                    }
                    else if leftRect.contains(scaledTouch)
                    {
                        inputCenter = self.centerPoint(rect: leftRect)
                    }
                    else if rightRect.contains(scaledTouch)
                    {
                        inputCenter = self.centerPoint(rect: rightRect)
                    }
                    else
                    {
                        inputCenter = self.centerPoint(rect: item.frame)
                    }
                }
                
                inputCenter.x *= self.bounds.width; inputCenter.y *= self.bounds.height
                
                context.drawRadialGradient(touchOverlayGradient, startCenter: inputCenter, startRadius: 0, endCenter: inputCenter, endRadius: 40 * self.touchOverlaySize, options: [])
            }
        }
        
        overlayImage = UIGraphicsGetImageFromCurrentImageContext()
        self.touchOverlayView.image = overlayImage
    }
    
    func centerPoint(rect: CGRect) -> CGPoint
    {
        return CGPoint(x: rect.midX, y: rect.midY)
    }
}
