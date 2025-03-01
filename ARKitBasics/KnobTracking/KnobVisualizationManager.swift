import SceneKit
import ARKit
import UIKit

protocol KnobVisualizationDelegate: AnyObject {
    func knobAdjustedToTargetValue(knob: ControlKnob)
}

class KnobVisualizationManager {
    // MARK: - Properties
    
    private var knobOverlayNode: SCNNode
    private var detectedKnobs: [UUID: ControlKnob] = [:]
    private weak var sceneView: ARSCNView?
    private weak var delegate: KnobVisualizationDelegate?
    
    // MARK: - Initialization
    
    init(sceneView: ARSCNView, delegate: KnobVisualizationDelegate) {
        self.sceneView = sceneView
        self.delegate = delegate
        
        // Create overlay node for visualizations
        knobOverlayNode = SCNNode()
        knobOverlayNode.position = SCNVector3(0, 0, -0.3) // Position in front of the camera
        
        // Add to scene
        sceneView.pointOfView?.addChildNode(knobOverlayNode)
    }
    
    // MARK: - Public Methods
    
    func clearKnobs() {
        // Remove all visualizations
        knobOverlayNode.childNodes.forEach { $0.removeFromParentNode() }
        detectedKnobs.removeAll()
    }
    
    func addKnob(_ knob: ControlKnob) {
        detectedKnobs[knob.id] = knob
        updateVisualizations()
    }
    
    func updateKnob(id: UUID, newValue: Float) {
        guard var knob = detectedKnobs[id] else { return }
        
        // Update value
        knob.currentValue = newValue
        
        // Check if knob is now at target value
        let wasAdjusted = knob.isAdjusted
        knob.isAdjusted = knob.isWithinAdjustmentTolerance()
        
        // Store updated knob
        detectedKnobs[id] = knob
        
        // Notify delegate if the knob is newly adjusted
        if !wasAdjusted && knob.isAdjusted {
            delegate?.knobAdjustedToTargetValue(knob: knob)
        }
        
        // Update visualization
        if let knobNode = knobOverlayNode.childNode(withName: knob.id.uuidString, recursively: true) {
            updateKnobNodeColor(knobNode: knobNode, isAdjusted: knob.isAdjusted)
        }
        
        // Update all visualizations
        updateVisualizations()
    }
    
    func simulateKnobValueChanges(step: Float = 0.01) {
        for (id, knob) in detectedKnobs {
            var updatedKnob = knob
            
            // Move value toward target
            updatedKnob.moveTowardsTarget(step: step)
            
            // Check if adjustment state changed
            let wasAdjusted = updatedKnob.isAdjusted
            updatedKnob.isAdjusted = updatedKnob.isWithinAdjustmentTolerance()
            
            // Store updated knob
            detectedKnobs[id] = updatedKnob
            
            // Notify delegate if newly adjusted
            if !wasAdjusted && updatedKnob.isAdjusted {
                delegate?.knobAdjustedToTargetValue(knob: updatedKnob)
            }
        }
        
        // Update visualizations
        updateVisualizations()
    }
    
    // MARK: - Visualization Methods
    
    func updateVisualizations() {
        // Clear existing visualizations
        knobOverlayNode.childNodes.forEach { $0.removeFromParentNode() }
        
        // Add visualization for each knob
        for (_, knob) in detectedKnobs {
            let visualNode = createKnobVisualization(for: knob)
            visualNode.name = knob.id.uuidString
            
            // Position within the overlay
            let xOffset: Float = knob.type == .potentiometer ? -0.05 : 0.05
            visualNode.position = SCNVector3(xOffset, 0, 0)
            
            knobOverlayNode.addChildNode(visualNode)
        }
    }
    
    private func createKnobVisualization(for knob: ControlKnob) -> SCNNode {
        let node = SCNNode()
        
        switch knob.type {
        case .potentiometer:
            // Create a circle with a dot for potentiometer
            let circleGeometry = SCNTorus(ringRadius: 0.02, pipeRadius: 0.002)
            let circleNode = SCNNode(geometry: circleGeometry)
            
            // Create the indicator dot
            let dotGeometry = SCNSphere(radius: 0.004)
            let dotNode = SCNNode(geometry: dotGeometry)
            
            // Position the dot at the edge of the circle
            let angle = 2 * Float.pi * knob.currentValue
            dotNode.position = SCNVector3(0.02 * sin(angle), 0.02 * cos(angle), 0)
            
            // Set color based on whether the knob is adjusted correctly
            let color = knob.isAdjusted ? UIColor.green : UIColor.white
            circleGeometry.firstMaterial?.diffuse.contents = color.withAlphaComponent(0.7)
            dotGeometry.firstMaterial?.diffuse.contents = color
            
            node.addChildNode(circleNode)
            node.addChildNode(dotNode)
            
        case .fader:
            // Create a line for fader
            let lineGeometry = SCNCylinder(radius: 0.001, height: 0.05)
            let lineNode = SCNNode(geometry: lineGeometry)
            lineNode.eulerAngles.x = Float.pi / 2
            
            // Create the indicator
            let indicatorGeometry = SCNBox(width: 0.01, height: 0.003, length: 0.003, chamferRadius: 0.001)
            let indicatorNode = SCNNode(geometry: indicatorGeometry)
            
            // Position indicator along the line
            let position = 0.05 * (knob.currentValue - 0.5)
            indicatorNode.position = SCNVector3(0, position, 0)
            
            // Set color based on whether the fader is adjusted correctly
            let color = knob.isAdjusted ? UIColor.green : UIColor.white
            lineGeometry.firstMaterial?.diffuse.contents = color.withAlphaComponent(0.7)
            indicatorGeometry.firstMaterial?.diffuse.contents = color
            
            node.addChildNode(lineNode)
            node.addChildNode(indicatorNode)
        }
        
        return node
    }
    
    private func updateKnobNodeColor(knobNode: SCNNode, isAdjusted: Bool) {
        let color = isAdjusted ? UIColor.green : UIColor.white
        
        // Update all materials in the node
        knobNode.enumerateChildNodes { (node, _) in
            if let geometry = node.geometry {
                geometry.firstMaterial?.diffuse.contents = color.withAlphaComponent(node == knobNode ? 0.7 : 1.0)
            }
        }
    }
}
