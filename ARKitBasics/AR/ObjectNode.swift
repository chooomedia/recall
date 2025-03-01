/*
See the LICENSE.txt file for this sample's licensing information.

Abstract:
Class for visualizing detected ARKit reference objects
*/

import ARKit
import SceneKit

// Color for object bounding boxes
extension UIColor {
    static let objectBoxColor = UIColor.systemBlue.withAlphaComponent(0.6)
}

class ObjectNode: SCNNode {
    private let boxNode: SCNNode
    private let labelNode: SCNNode
    // Debug info for tracking performance and status
    private var detectionTimestamp: TimeInterval
    private var debugInfoNode: SCNNode?
    
    init(anchor: ARObjectAnchor) {
        detectionTimestamp = CACurrentMediaTime()
        print("DEBUG: Creating ObjectNode for \(anchor.referenceObject.name ?? "unnamed object")")
        // Create a bounding box to visualize the object
        let extent = anchor.referenceObject.extent
        let boxGeometry = SCNBox(
            width: CGFloat(extent.x),
            height: CGFloat(extent.y),
            length: CGFloat(extent.z),
            chamferRadius: 0.01
        )
        boxNode = SCNNode(geometry: boxGeometry)
        
        // Set up box appearance
        let material = SCNMaterial()
        material.diffuse.contents = UIColor.objectBoxColor
        material.transparency = 0.7
        material.isDoubleSided = true
        material.fillMode = .lines
        // SceneKit materials don't actually have a lineWidth property
        // The line effect is achieved through the fillMode
        boxGeometry.materials = [material]
        
        // Create text label for the object name
        let textGeometry = SCNText(
            string: anchor.referenceObject.name ?? "Unknown Object",
            extrusionDepth: 0.1
        )
        textGeometry.font = UIFont.systemFont(ofSize: 0.5)
        textGeometry.firstMaterial?.diffuse.contents = UIColor.white
        textGeometry.firstMaterial?.isDoubleSided = true
        labelNode = SCNNode(geometry: textGeometry)
        
        // Scale down the text and position above the box
        labelNode.scale = SCNVector3(0.01, 0.01, 0.01)
        labelNode.position = SCNVector3(-(extent.x/2), extent.y + 0.05, -(extent.z/2))
        
        super.init()
        
        // Add child nodes
        addChildNode(boxNode)
        addChildNode(labelNode)
        
        // Position the node at the center of the anchor
        simdPosition = SIMD3<Float>(anchor.transform.columns.3.x, anchor.transform.columns.3.y, anchor.transform.columns.3.z)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func update(with anchor: ARObjectAnchor) {
        // Update position if the anchor moved
        let oldPosition = simdPosition
        let newPosition = SIMD3<Float>(anchor.transform.columns.3.x, anchor.transform.columns.3.y, anchor.transform.columns.3.z)
        
        // Log movement information for debugging
        let distance = simd_distance(oldPosition, newPosition)
        if distance > 0.01 { // Only log significant movements
            print("DEBUG: Object moved \(String(format: "%.4f", distance))m from (\(oldPosition.x), \(oldPosition.y), \(oldPosition.z)) to (\(newPosition.x), \(newPosition.y), \(newPosition.z))")
        }
        
        simdPosition = newPosition
        
        // Update debug info
        if let debugNode = debugInfoNode {
            let trackingDuration = CACurrentMediaTime() - detectionTimestamp
            let textGeometry = SCNText(string: "Tracking: \(String(format: "%.1f", trackingDuration))s", extrusionDepth: 0.1)
            textGeometry.font = UIFont.systemFont(ofSize: 0.5)
            debugNode.geometry = textGeometry
        }
    }
    
    // Add debug visualization
    func addDebugInfo() {
        let textGeometry = SCNText(string: "New detection", extrusionDepth: 0.1)
        textGeometry.font = UIFont.systemFont(ofSize: 0.5)
        textGeometry.firstMaterial?.diffuse.contents = UIColor.yellow
        
        let debugNode = SCNNode(geometry: textGeometry)
        debugNode.scale = SCNVector3(0.01, 0.01, 0.01)
        debugNode.position = SCNVector3(0, 0.1, 0)
        
        debugInfoNode = debugNode
        addChildNode(debugNode)
        
        print("DEBUG: Added debug visualization to object")
    }
}

// Class for bounding boxes created from Vision detection
class BoundingBoxNode: SCNNode {
    // Debug properties
    let creationTime: Date = Date()
    let dimensions: (width: CGFloat, height: CGFloat, length: CGFloat)
    let detectedLabel: String
    let confidenceValue: Float
    var framesSinceUpdate: Int = 0
    
    init(width: CGFloat, height: CGFloat, length: CGFloat, label: String, confidence: Float) {
        self.dimensions = (width, height, length)
        self.detectedLabel = label
        self.confidenceValue = confidence
        
        print("DEBUG: Creating BoundingBoxNode for \(label) (Confidence: \(confidence))")
        print("DEBUG: Dimensions - Width: \(width), Height: \(height), Length: \(length)")
        super.init()
        
        // Create a bounding box with the calculated dimensions
        let boxGeometry = SCNBox(
            width: width,
            height: height,
            length: length,
            chamferRadius: 0.01
        )
        
        // Create wireframe material
        let material = SCNMaterial()
        material.diffuse.contents = UIColor.red.withAlphaComponent(0.7)
        material.transparency = 0.5
        material.isDoubleSided = true
        material.fillMode = .lines
        // SceneKit materials don't actually have a lineWidth property
        // The line effect is achieved through the fillMode
        boxGeometry.materials = [material]
        
        let boxNode = SCNNode(geometry: boxGeometry)
        addChildNode(boxNode)
        
        // Create label with object name and confidence
        let confidencePercent = Int(confidence * 100)
        let textGeometry = SCNText(
            string: "\(label) \(confidencePercent)%",
            extrusionDepth: 0.1
        )
        textGeometry.font = UIFont.boldSystemFont(ofSize: 0.5)
        textGeometry.firstMaterial?.diffuse.contents = UIColor.white
        textGeometry.firstMaterial?.isDoubleSided = true
        
        let textNode = SCNNode(geometry: textGeometry)
        textNode.scale = SCNVector3(0.01, 0.01, 0.01)
        textNode.position = SCNVector3(-(width/2), height + 0.05, -(length/2))
        addChildNode(textNode)
        
        // Add a pulsing animation to make the bounding box more visible
        let fadeOut = SCNAction.fadeOpacity(to: 0.3, duration: 1.0)
        let fadeIn = SCNAction.fadeOpacity(to: 0.7, duration: 1.0)
        let pulse = SCNAction.sequence([fadeOut, fadeIn])
        let repeatPulse = SCNAction.repeatForever(pulse)
        boxNode.runAction(repeatPulse)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
