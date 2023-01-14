//
//  EAGLContext+BestAvailable.swift
//  DeltaCore
//
//  Created by Ian Clawson on 1/12/23.
//  Copyright © 2023 Riley Testut. All rights reserved.
//

import GLKit

extension EAGLContext {
    static func createWithBestAvailableAPI(_ sharegroup: EAGLSharegroup? = nil) -> EAGLContext {
        if let sharegroup = sharegroup {
            var context = EAGLContext(api: .openGLES3, sharegroup: sharegroup)
            if context == nil {
                context = EAGLContext(api: .openGLES2, sharegroup: sharegroup)
                if context == nil {
                    context = EAGLContext(api: .openGLES1, sharegroup: sharegroup)
                }
            }
            
            return context!
        }
        
        var context = EAGLContext(api: .openGLES3)
        if context == nil {
            context = EAGLContext(api: .openGLES2)
            if context == nil {
                context = EAGLContext(api: .openGLES1)
            }
        }
        
        return context!
    }
}
