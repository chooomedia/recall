import SceneKit
import UIKit

class ControlKnob {
    // MARK: - Types
    
    enum KnobType {
        case potentiometer
        case fader
    }
    
    enum KnobStatus {
        case detected
        case adjusting
        case adjusted
    }
    
    // MARK: - Properties
    
    let id: UUID
    let type: KnobType
    var position: SCNVector3
    var currentValue: Float
    var targetValue: Float
    var status: KnobStatus = .detected
    var isAdjusted: Bool = false
    var color: UIColor {
        switch status {
        case .detected: return .systemYellow
        case .adjusting: return .systemBlue
        case .adjusted: return .systemGreen
        }
    }
    
    // Tracking properties
    var deviceEdgePosition: SCNVector3?
    var isBeingAdjusted: Bool = false
    
    // Dimensions (for visualization)
    var diameter: Float = 0.03 // For potentiometer
    var length: Float = 0.1    // For fader
    var width: Float = 0.02    // For fader
    
    // History of value changes for smoothing
    private var valueHistory: [Float] = []
    private let maxHistoryLength = 5
    
    // MARK: - Initialization
    
    init(id: UUID = UUID(), type: KnobType, position: SCNVector3, currentValue: Float, targetValue: Float) {
        self.id = id
        self.type = type
        self.position = position
        self.currentValue = currentValue
        self.targetValue = targetValue
        
        // Add initial value to history
        valueHistory.append(currentValue)
    }
    
    // MARK: - Methods
    
    func isWithinAdjustmentTolerance() -> Bool {
        let tolerance: Float = 0.05
        return abs(currentValue - targetValue) < tolerance
    }
    
    func updateValue(_ newValue: Float) {
        // Add to history and maintain max length
        valueHistory.append(newValue)
        if valueHistory.count > maxHistoryLength {
            valueHistory.removeFirst()
        }
        
        // Apply smoothing to reduce jitter
        currentValue = smoothedValue()
        
        // Update status
        if isWithinAdjustmentTolerance() {
            status = .adjusted
            isAdjusted = true
        } else if isBeingAdjusted {
            status = .adjusting
        }
    }
    
    func smoothedValue() -> Float {
        // Simple moving average for smoothing
        guard !valueHistory.isEmpty else { return currentValue }
        let sum = valueHistory.reduce(0, +)
        return sum / Float(valueHistory.count)
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
        
        // Update status if we've reached the target
        if isWithinAdjustmentTolerance() {
            status = .adjusted
            isAdjusted = true
        }
    }
    
    func setDeviceEdgePosition(_ position: SCNVector3) {
        self.deviceEdgePosition = position
    }
    
    func calculateDistanceFromDevice() -> Float? {
        guard let deviceEdge = deviceEdgePosition else { return nil }
        
        let dx = position.x - deviceEdge.x
        let dy = position.y - deviceEdge.y
        let dz = position.z - deviceEdge.z
        
        return sqrt(dx*dx + dy*dy + dz*dz)
    }
    
    // Creates a descriptive label for the knob
    func createLabel() -> String {
        let typeLabel = type == .potentiometer ? "Potentiometer" : "Fader"
        let valuePercent = Int(currentValue * 100)
        return "\(typeLabel): \(valuePercent)%"
    }
}
