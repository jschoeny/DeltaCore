//
//  TouchControllerSkin.swift
//  DeltaCore
//
//  Created by Riley Testut on 12/1/20.
//  Copyright © 2020 Riley Testut. All rights reserved.
//

import UIKit
import AVFoundation

extension TouchControllerSkin
{
    public enum LayoutAxis: String, CaseIterable
    {
        case vertical
        case horizontal
    }
}

public struct TouchControllerSkin
{
    public var name: String { "TouchControllerSkin" }
    public var identifier: String { "com.ignited.TouchControllerSkin" }
    public var gameType: GameType { self.controllerSkin.gameType }
    public var isDebugModeEnabled: Bool { false }
    public var hasAltRepresentations: Bool { false }
    
    public var screenLayoutAxis: LayoutAxis = .vertical
    public var screenPredicate: ((ControllerSkin.Screen) -> Bool)?
    
    private let controllerSkin: ControllerSkinProtocol
    
    public init(controllerSkin: ControllerSkinProtocol)
    {
        self.controllerSkin = controllerSkin
    }
}

extension TouchControllerSkin: ControllerSkinProtocol
{
    public func supports(_ traits: ControllerSkin.Traits, alt: Bool = false) -> Bool
    {
        return true
    }
    
    public func image(for traits: ControllerSkin.Traits, preferredSize: ControllerSkin.Size, alt: Bool = false) -> UIImage?
    {
        return nil
    }
    
    public func anyImage(for traits: ControllerSkin.Traits, preferredSize: ControllerSkin.Size, alt: Bool = false) -> UIImage?
    {
        return nil
    }
    
    public func thumbstick(for item: ControllerSkin.Item, traits: ControllerSkin.Traits, preferredSize: ControllerSkin.Size, alt: Bool = false) -> (UIImage, CGSize)?
    {
        return nil
    }
    
    public func items(for traits: ControllerSkin.Traits, alt: Bool = false) -> [ControllerSkin.Item]?
    {
        guard
            var touchScreenItem = self.controllerSkin.items(for: traits, alt: alt)?.first(where: { $0.kind == .touchScreen }),
            let screens = self.screens(for: traits, alt: alt), let touchScreen = screens.first(where: { $0.isTouchScreen }),
            let outputFrame = touchScreen.outputFrame
        else { return nil }
        
        // For now, we assume touchScreenItem completely covers the touch screen.
        
        touchScreenItem.placement = .app
        touchScreenItem.frame = outputFrame
        touchScreenItem.extendedFrame = outputFrame
        return [touchScreenItem]
    }

    public func liveSkinItems(for traits: ControllerSkin.Traits, alt: Bool = false) -> [ControllerSkin.LiveSkinItem]?
    {
        return nil
    }

    public func liveSkinImage(for item: ControllerSkin.LiveSkinItem, traits: ControllerSkin.Traits, preferredSize: ControllerSkin.Size, alt: Bool = false) -> UIImage?
    {
        return nil
    }
    
    public func isTranslucent(for traits: ControllerSkin.Traits, alt: Bool = false) -> Bool?
    {
        return false
    }

    public func screens(for traits: ControllerSkin.Traits, alt: Bool = false) -> [ControllerSkin.Screen]?
    {
        guard let screens = self.controllerSkin.screens(for: traits, alt: alt) else { return nil }

        // Filter screens first so we can use filteredScreens.count in calculations.
        let filteredScreens = screens.filter(self.screenPredicate ?? { _ in true })

        let updatedScreens = filteredScreens.enumerated().map { (index, screen) -> ControllerSkin.Screen in
            let unsafeArea: CGFloat
            
            if traits.orientation == .landscape,
               filteredScreens.count > 1
            {
                unsafeArea = self.unsafeArea(for: traits, alt: alt) ?? 0
            }
            else
            {
                unsafeArea = 0
            }
            
            let horizontalLength = (1 - (unsafeArea * 2)) / CGFloat(filteredScreens.count)
            let verticalLength = 1 / CGFloat(filteredScreens.count)
            
            var screen = screen
            screen.placement = .app
            screen.style = .flat
            
            switch self.screenLayoutAxis
            {
            case .horizontal: screen.outputFrame = CGRect(x: (horizontalLength * CGFloat(index)) + unsafeArea, y: 0, width: horizontalLength, height: 1.0)
            case .vertical: screen.outputFrame = CGRect(x: 0, y: verticalLength * CGFloat(index), width: 1.0, height: verticalLength)
            }
            
            return screen
        }
        
        return updatedScreens
    }
    
    public func aspectRatio(for traits: ControllerSkin.Traits, alt: Bool = false) -> CGSize?
    {
        return self.controllerSkin.aspectRatio(for: traits, alt: alt)
    }
    
    public func contentSize(for traits: ControllerSkin.Traits, alt: Bool = false) -> CGSize?
    {
        guard let screens = self.screens(for: traits) else { return nil }

        var compositeScreenSize = screens.reduce(into: CGSize.zero) { (size, screen) in
            guard let inputFrame = screen.inputFrame else { return }

            switch self.screenLayoutAxis
            {
            case .horizontal:
                size.width += inputFrame.width
                size.height = max(inputFrame.height, size.height)

            case .vertical:
                size.width = max(inputFrame.width, size.width)
                size.height += inputFrame.height
            }
        }
        
        guard traits.orientation == .landscape,
              screens.count > 1 else { return compositeScreenSize }
        
        let unsafeArea = self.unsafeArea(for: traits, alt: alt) ?? 0
            
        compositeScreenSize.width *= (1 - unsafeArea)

        return compositeScreenSize
    }
    
    public func previewSize(for traits: ControllerSkin.Traits, alt: Bool = false) -> CGSize? {
        return self.controllerSkin.previewSize(for: traits, alt: alt)
    }
    
    public func anyPreviewSize(for traits: ControllerSkin.Traits, alt: Bool = false) -> CGSize? {
        return self.controllerSkin.previewSize(for: traits, alt: alt)
    }
    
    public func unsafeArea(for traits: ControllerSkin.Traits, alt: Bool) -> CGFloat? {
        return (self.controllerSkin.unsafeArea(for: traits, alt: alt) ?? 0) / UIScreen.main.bounds.width
    }
}
