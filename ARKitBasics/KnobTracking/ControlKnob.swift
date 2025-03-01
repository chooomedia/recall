//
//  ControlKnob.swift
//  ARKitBasics
//
//  Created by Christopher Matt on 01.03.25.
//  Copyright © 2025 Apple. All rights reserved.
//

import SceneKit

class ControlKnob {
    // MARK: - Types
    
    enum KnobType {
        case potentiometer
        case fader
    }
    
    // MARK: - Properties
    
    let id: UUID
    let type: KnobType
    var position: SCNVector3
    var currentValue: Float
    var targetValue: Float
    var isAdjusted: Bool = false
    
    // Additional properties for edge detection
    var deviceEdgePosition: SCNVector3?
    var isBeingAdjusted: Bool = false
    
    // MARK: - Initialization
    
    init(id: UUID = UUID(), type: KnobType, position: SCNVector3, currentValue: Float, targetValue: Float) {
        self.id = id
        self.type = type
        self.position = position
        self.currentValue = currentValue
        self.targetValue = targetValue
    }
    
    // MARK: - Methods
    
    func isWithinAdjustmentTolerance() -> Bool {
        let tolerance: Float = 0.05
        return abs(currentValue - targetValue) < tolerance
    }
    
    func moveTowardsTarget(step: Float = 0.01) {
        if currentValue < targetValue {
            currentValue += step
            if currentValue > targetValue {
                currentValue = targetValue
            }
        } else if currentValue > targetValue {
            currentValue -= step
            if currentValue < targetValue {
                currentValue = targetValue
            }
        }
    }
    
    func setDeviceEdgePosition(_ position: SCNVector3) {
        self.deviceEdgePosition = position
    }
}
