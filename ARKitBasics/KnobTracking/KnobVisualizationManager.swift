import SceneKit
import ARKit
import UIKit

protocol KnobVisualizationDelegate: AnyObject {
    func knobAdjustedToTargetValue(knob: ControlKnob)
    func completedAllKnobAdjustments()
}

class KnobVisualizationManager {
    // MARK: - Properties
    
    private var detectedKnobs: [UUID: ControlKnob] = [:]
    private weak var sceneView: ARSCNView?
    private weak var delegate: KnobVisualizationDelegate?
    
    // Node references
    private var knobNodes: [UUID: SCNNode] = [:]
    private var labelNodes: [UUID: SCNNode] = [:]
    private var targetIndicatorNodes: [UUID: SCNNode] = [:]
    
    // Visual settings
    private let knobScale: CGFloat = 1.0
    private let labelHeight: CGFloat = 0.02
    private let labelOffset: CGFloat = 0.05
    
    // Tracking state
    private var allKnobsAdjusted = false
    
    // MARK: - Initialization
    
    init(sceneView: ARSCNView, delegate: KnobVisualizationDelegate) {
        self.sceneView = sceneView
        self.delegate = delegate
    }
    
    // MARK: - Public Methods
    
    func clearKnobs() {
        // Remove all visualizations
        for (_, node) in knobNodes {
            node.removeFromParentNode()
        }
        
        for (_, node) in labelNodes {
            node.removeFromParentNode()
        }
        
        for (_, node) in targetIndicatorNodes {
            node.removeFromParentNode()
        }
        
        // Clear collections
        knobNodes.removeAll()
        labelNodes.removeAll()
        targetIndicatorNodes.removeAll()
        detectedKnobs.removeAll()
        allKnobsAdjusted = false
    }
    
    func addKnob(_ knob: ControlKnob) {
        // Add or update knob in local storage
        detectedKnobs[knob.id] = knob
        
        // Create visualization
        createKnobVisualization(knob)
    }
    
    func updateKnob(id: UUID, newValue: Float) {
        guard var knob = detectedKnobs[id] else { return }
        
        // Update value with smoothing
        let oldStatus = knob.status
        knob.updateValue(newValue)
        
        // Store updated knob
        detectedKnobs[id] = knob
        
        // Update visualization
        updateKnobVisualization(knob)
        
        // Check if adjusted state changed
        if oldStatus != .adjusted && knob.status == .adjusted {
            delegate?.knobAdjustedToTargetValue(knob: knob)
            checkAllKnobsAdjusted()
        }
    }
    
    func simulateKnobValueChanges(step: Float = 0.01) {
        for (id, knob) in detectedKnobs {
            var updatedKnob = knob
            
            // Skip already adjusted knobs
            if updatedKnob.status == .adjusted {
                continue
            }
            
            // Move value toward target
            let oldStatus = updatedKnob.status
            updatedKnob.moveTowardsTarget(step: step)
            
            // Store updated knob
            detectedKnobs[id] = updatedKnob
            
            // Update visualization
            updateKnobVisualization(updatedKnob)
            
            // Check if adjusted state changed
            if oldStatus != .adjusted && updatedKnob.status == .adjusted {
                delegate?.knobAdjustedToTargetValue(knob: updatedKnob)
                checkAllKnobsAdjusted()
            }
        }
    }
    
    // MARK: - Visualization Methods
    
    private func createKnobVisualization(_ knob: ControlKnob) {
        guard let sceneView = sceneView else { return }
        
        // Create node based on knob type
        let visualNode = SCNNode()
        
        if knob.type == .potentiometer {
            createPotentiometerVisualization(knob, parentNode: visualNode)
        } else {
            createFaderVisualization(knob, parentNode: visualNode)
        }
        
        // Position at the detected knob position
        visualNode.position = knob.position
        
        // Create label node
        let labelNode = createLabelNode(for: knob)
        
        // Add to scene
        sceneView.scene.rootNode.addChildNode(visualNode)
        sceneView.scene.rootNode.addChildNode(labelNode)
        
        // Store references
        knobNodes[knob.id] = visualNode
        labelNodes[knob.id] = labelNode
        
        // Create target indicator
        createTargetIndicator(for: knob)
    }
    
    private func createPotentiometerVisualization(_ knob: ControlKnob, parentNode: SCNNode) {
        // Ring visualization
        let ringGeometry = SCNTorus(ringRadius: 0.015 * knobScale,
                                    pipeRadius: 0.002 * knobScale)
        ringGeometry.firstMaterial?.diffuse.contents = knob.color.withAlphaComponent(0.7)
        let ringNode = SCNNode(geometry: ringGeometry)
        
        // Create indicator dot showing current value
        let dotGeometry = SCNSphere(radius: 0.004 * knobScale)
        dotGeometry.firstMaterial?.diffuse.contents = knob.color
        let dotNode = SCNNode(geometry: dotGeometry)
        
        // Position dot at the appropriate angle based on current value
        let angle = 2 * CGFloat.pi * CGFloat(knob.currentValue)
        dotNode.position = SCNVector3(
            Float(0.015 * knobScale * cos(angle)),
            0,
            Float(0.015 * knobScale * sin(angle))
        )
        
        // Add to parent
        parentNode.addChildNode(ringNode)
        parentNode.addChildNode(dotNode)
    }
    
    private func createFaderVisualization(_ knob: ControlKnob, parentNode: SCNNode) {
        // Create track
        let trackLength = 0.1 * knobScale
        let trackGeometry = SCNCylinder(radius: 0.002 * knobScale, height: trackLength)
        trackGeometry.firstMaterial?.diffuse.contents = UIColor.lightGray.withAlphaComponent(0.7)
        let trackNode = SCNNode(geometry: trackGeometry)
        trackNode.eulerAngles.x = Float.pi / 2 // Rotate to vertical
        
        // Create slider knob
        let sliderGeometry = SCNBox(
            width: 0.01 * knobScale,
            height: 0.004 * knobScale,
            length: 0.008 * knobScale,
            chamferRadius: 0.001 * knobScale
        )
        sliderGeometry.firstMaterial?.diffuse.contents = knob.color
        let sliderNode = SCNNode(geometry: sliderGeometry)
        
        // Position slider based on current value
        let position = Float(CGFloat(knob.currentValue - 0.5) * trackLength)
        sliderNode.position = SCNVector3(0, position, 0)
        
        // Add to parent
        parentNode.addChildNode(trackNode)
        parentNode.addChildNode(sliderNode)
    }
    
    private func createLabelNode(for knob: ControlKnob) -> SCNNode {
        // Create text geometry
        let labelText = knob.createLabel()
        let textGeometry = SCNText(string: labelText, extrusionDepth: 0.001)
        textGeometry.font = UIFont.systemFont(ofSize: 3)
        textGeometry.firstMaterial?.diffuse.contents = knob.color
        textGeometry.firstMaterial?.isDoubleSided = true
        textGeometry.alignmentMode = CATextLayerAlignmentMode.center.rawValue
        textGeometry.truncationMode = CATextLayerTruncationMode.end.rawValue
        
        // Create node
        let textNode = SCNNode(geometry: textGeometry)
        
        // Scale down the text
        textNode.scale = SCNVector3(0.005, 0.005, 0.005)
        
        // Position above the knob
        let labelOffset = knob.type == .potentiometer ? 0.04 : 0.07
        textNode.position = SCNVector3(
            knob.position.x - 0.05, // Center adjust
            knob.position.y + Float(labelOffset),
            knob.position.z
        )
        
        return textNode
    }
    
    private func createTargetIndicator(for knob: ControlKnob) {
        guard let sceneView = sceneView else { return }
        
        let indicatorNode = SCNNode()
        
        // Create different indicators based on knob type
        if knob.type == .potentiometer {
            // Create arc segment to show target area
            let arcGeometry = SCNTorus(ringRadius: 0.018 * knobScale, pipeRadius: 0.0015 * knobScale)
            arcGeometry.firstMaterial?.diffuse.contents = UIColor.systemGreen.withAlphaComponent(0.5)
            let arcNode = SCNNode(geometry: arcGeometry)
            
            // Add shader to only show a segment around target value
            let targetAngle = 2 * Float.pi * knob.targetValue
            let tolerance = 0.05 * (2 * Float.pi) // 5% tolerance window
            
            // Apply rotation to align with target value
            arcNode.eulerAngles.y = -targetAngle
            
            indicatorNode.addChildNode(arcNode)
        } else {
            // For fader, create a target marker on the track
            let markerGeometry = SCNBox(
                width: 0.012 * knobScale,
                height: 0.002 * knobScale,
                length: 0.006 * knobScale,
                chamferRadius: 0.001 * knobScale
            )
            markerGeometry.firstMaterial?.diffuse.contents = UIColor.systemGreen.withAlphaComponent(0.5)
            let markerNode = SCNNode(geometry: markerGeometry)
            
            // Position marker at target value
            let trackLength = 0.1 * knobScale
            let position = Float(CGFloat(knob.targetValue - 0.5) * trackLength)
            markerNode.position = SCNVector3(0, position, 0)
            
            // Rotate to align with track
            markerNode.eulerAngles.x = Float.pi / 2
            
            indicatorNode.addChildNode(markerNode)
        }
        
        // Position at knob location
        indicatorNode.position = knob.position
        
        // Add to scene
        sceneView.scene.rootNode.addChildNode(indicatorNode)
        
        // Store reference
        targetIndicatorNodes[knob.id] = indicatorNode
    }
    
    private func updateKnobVisualization(_ knob: ControlKnob) {
        guard let knobNode = knobNodes[knob.id],
              let labelNode = labelNodes[knob.id] else { return }
        
        // Update color based on knob status
        if knob.type == .potentiometer {
            // Update ring color
            if let ringNode = knobNode.childNodes.first,
               let material = ringNode.geometry?.firstMaterial {
                material.diffuse.contents = knob.color.withAlphaComponent(0.7)
            }
            
            // Update dot position and color
            if let dotNode = knobNode.childNodes.last,
               let material = dotNode.geometry?.firstMaterial {
                material.diffuse.contents = knob.color
                
                // Update position based on current value
                let angle = 2 * CGFloat.pi * CGFloat(knob.currentValue)
                dotNode.position = SCNVector3(
                    Float(0.015 * knobScale * cos(angle)),
                    0,
                    Float(0.015 * knobScale * sin(angle))
                )
            }
        } else {
            // Update fader slider position and color
            if let sliderNode = knobNode.childNodes.last,
               let material = sliderNode.geometry?.firstMaterial {
                material.diffuse.contents = knob.color
                
                // Update position based on current value
                let trackLength = 0.1 * knobScale
                let position = Float(CGFloat(knob.currentValue - 0.5) * trackLength)
                sliderNode.position = SCNVector3(0, position, 0)
            }
        }
        
        // Update label text and color
        if let textGeometry = labelNode.geometry as? SCNText {
            textGeometry.string = knob.createLabel()
            textGeometry.firstMaterial?.diffuse.contents = knob.color
        }
        
        // Add pulse animation if adjusted
        if knob.status == .adjusted {
            addPulseAnimation(to: knobNode)
        }
    }
    
    private func addPulseAnimation(to knobNode: SCNNode) {
        // Skip if node already has animation
        if knobNode.animationKeys.contains("pulse") {
            return
        }
        
        // Create pulse animation
        let pulseAction = SCNAction.sequence([
            SCNAction.scale(to: 1.2, duration: 0.5),
            SCNAction.scale(to: 1.0, duration: 0.5)
        ])
        
        // Run continuously
        let repeatPulse = SCNAction.repeatForever(pulseAction)
        knobNode.runAction(repeatPulse, forKey: "pulse")
    }
    
    private func checkAllKnobsAdjusted() {
        // Skip if already detected all adjustments
        if allKnobsAdjusted {
            return
        }
        
        // Check if all knobs are adjusted
        let allAdjusted = !detectedKnobs.isEmpty && detectedKnobs.values.allSatisfy { $0.status == .adjusted }
        
        if allAdjusted {
            allKnobsAdjusted = true
            delegate?.completedAllKnobAdjustments()
        }
    }
}
