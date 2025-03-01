/*
See the LICENSE.txt file for this sample's licensing information.

Abstract:
Main view controller for the AR experience.
*/

import UIKit
import SceneKit
import ARKit
import Vision

class ViewController: UIViewController, ARSCNViewDelegate, ARSessionDelegate {
    // MARK: - IBOutlets

    @IBOutlet weak var sessionInfoView: UIView!
    @IBOutlet weak var sessionInfoLabel: UILabel!
    @IBOutlet weak var sceneView: ARSCNView!
    
    // Debug UI elements
    private var debugView: UIView!
    private var debugLabel: UILabel!
    private var debugButton: UIButton!
    private var showDebugInfo = false
    
    // Store detected objects to avoid creating duplicates
    private var detectedObjects = [UUID: SCNNode]()
    
    // Vision request for object detection
    private var visionRequests = [VNCoreMLRequest]()
    private let objectDetectionQueue = DispatchQueue(label: "objectDetectionQueue")
    
    // Debug stats
    private var objectDetectionCount = 0
    private var frameProcessingCount = 0
    private var lastProcessingTime: TimeInterval = 0

    // MARK: - View Life Cycle

    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Setup Vision ML model for object detection
        setupVision()
        
        // Setup debug UI
        setupDebugUI()
        
        // Log AR support information
        logARSupportInfo()
    }
    
    /// - Tag: StartARSession
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        // Start the view's AR session with a configuration that uses the rear camera,
        // device position and orientation tracking, and plane detection.
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = [.horizontal, .vertical]
        
        // Enable object detection if we have reference objects
        if #available(iOS 12.0, *) {
            configuration.environmentTexturing = .automatic
            
            // If you have predefined reference objects, use this:
            if let objects = ARReferenceObject.referenceObjects(inGroupNamed: "DetectedObjects", bundle: nil) {
                configuration.detectionObjects = objects
            }
        }
        
        sceneView.session.run(configuration)

        // Set a delegate to track the number of plane anchors for providing UI feedback.
        sceneView.session.delegate = self
        
        // Prevent the screen from being dimmed after a while as users will likely
        // have long periods of interaction without touching the screen or buttons.
        UIApplication.shared.isIdleTimerDisabled = true
        
        // Show debug UI to view performance metrics (e.g. frames per second).
        sceneView.showsStatistics = true
        
        // Enable automatic light estimation
        sceneView.automaticallyUpdatesLighting = true
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        // Pause the view's AR session.
        sceneView.session.pause()
    }
    
    // MARK: - Vision Setup
    
    private func setupVision() {
        // Setup CoreML model
        guard let modelURL = Bundle.main.url(forResource: "YOLOv3", withExtension: "mlmodelc") else {
            print("DEBUG: Failed to find the ML model in the app bundle")
            updateDebugInfo("ML Model not found in bundle")
            return
        }
        
        do {
            let visionModel = try VNCoreMLModel(for: MLModel(contentsOf: modelURL))
            let objectRecognition = VNCoreMLRequest(model: visionModel) { (request, error) in
                if let error = error {
                    print("DEBUG: Vision ML request error: \(error)")
                    DispatchQueue.main.async {
                        self.updateDebugInfo("Vision error: \(error.localizedDescription)")
                    }
                    return
                }
                
                guard let results = request.results as? [VNRecognizedObjectObservation] else {
                    print("DEBUG: No results or invalid type returned")
                    return
                }
                
                // Calculate processing time
                let processingTime = CACurrentMediaTime() - self.lastProcessingTime
                
                print("DEBUG: Detected \(results.count) objects in \(String(format: "%.2f", processingTime * 1000))ms")
                
                // Log detailed information about each detection
                for (index, observation) in results.enumerated() {
                    if let topLabel = observation.labels.first {
                        print("DEBUG: Object \(index): \(topLabel.identifier) (\(String(format: "%.1f", observation.confidence * 100))%)")
                    }
                }
                
                DispatchQueue.main.async {
                    self.objectDetectionCount += results.count
                    self.updateDebugInfo("Processed frame in \(String(format: "%.2f", processingTime * 1000))ms")
                    self.handleVisionResults(results)
                }
            }
            
            objectRecognition.imageCropAndScaleOption = .scaleFill
            self.visionRequests = [objectRecognition]
            print("DEBUG: Vision model setup successfully")
        } catch {
            print("DEBUG: Failed to create Vision ML model: \(error)")
            updateDebugInfo("ML Model initialization failed: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Debug UI
    
    private func setupDebugUI() {
        // Create debug overlay view
        debugView = UIView(frame: CGRect(x: 20, y: 100, width: view.bounds.width - 40, height: 180))
        debugView.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        debugView.layer.cornerRadius = 10
        debugView.isHidden = !showDebugInfo
        
        // Create debug label
        debugLabel = UILabel(frame: CGRect(x: 10, y: 10, width: debugView.bounds.width - 20, height: debugView.bounds.height - 60))
        debugLabel.textColor = .white
        debugLabel.font = UIFont.systemFont(ofSize: 12)
        debugLabel.numberOfLines = 0
        debugLabel.text = "Debug information will appear here..."
        
        // Create debug toggle button
        debugButton = UIButton(type: .system)
        debugButton.frame = CGRect(x: view.bounds.width - 120, y: 40, width: 100, height: 40)
        debugButton.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.7)
        debugButton.layer.cornerRadius = 8
        debugButton.setTitle("Show Debug", for: .normal)
        debugButton.setTitleColor(.white, for: .normal)
        debugButton.addTarget(self, action: #selector(toggleDebugView), for: .touchUpInside)
        
        // Add UI elements
        debugView.addSubview(debugLabel)
        view.addSubview(debugView)
        view.addSubview(debugButton)
        
        // Bring debug elements to front
        view.bringSubviewToFront(debugView)
        view.bringSubviewToFront(debugButton)
    }
    
    @objc private func toggleDebugView() {
        showDebugInfo = !showDebugInfo
        debugView.isHidden = !showDebugInfo
        debugButton.setTitle(showDebugInfo ? "Hide Debug" : "Show Debug", for: .normal)
    }
    
    private func updateDebugInfo(_ message: String? = nil) {
        if let message = message {
            print("DEBUG: \(message)")
        }
        
        // Update debug information display
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "HH:mm:ss.SSS"
        
        var debugText = """
        Time: \(dateFormatter.string(from: Date()))
        Frames Processed: \(frameProcessingCount)
        Objects Detected: \(objectDetectionCount)
        """
        
        if let message = message {
            debugText += "\n\nLast event: \(message)"
        }
    }
    
    private func logARSupportInfo() {
        print("DEBUG: ARKit Support Information")
        print("DEBUG: ARWorldTrackingConfiguration supported: \(ARWorldTrackingConfiguration.isSupported)")
        
        if #available(iOS 12.0, *) {
            print("DEBUG: ARObjectScanningConfiguration supported: \(ARObjectScanningConfiguration.isSupported)")
            print("DEBUG: ARPlaneClassification supported: \(ARPlaneAnchor.isClassificationSupported)")
        }
        
        print("DEBUG: Device: \(UIDevice.current.model), iOS \(UIDevice.current.systemVersion)")
    }
    
    private func handleVisionResults(_ results: [VNRecognizedObjectObservation]) {
        // Get current ARFrame
        guard let currentFrame = sceneView.session.currentFrame else {
            print("DEBUG: No current frame available")
            return
        }
        
        var detectedCount = 0
        var lowConfidenceCount = 0
        var hitTestFailCount = 0
        
        // Process each detected object
        for observation in results {
            // Filter out low confidence detections
            guard observation.confidence >= 0.7 else {
                lowConfidenceCount += 1
                continue
            }
            
            // Get the object label with highest confidence
            guard let topLabelObservation = observation.labels.first else {
                print("DEBUG: Object had no labels")
                continue
            }
            
            // Get bounding box in normalized coordinates (0,0 to 1,1)
            let boundingBox = observation.boundingBox
            
            // Convert normalized coordinates to screen coordinates
            let viewportSize = sceneView.bounds.size
            let viewBox = CGRect(
                x: boundingBox.minX * viewportSize.width,
                y: (1 - boundingBox.maxY) * viewportSize.height,
                width: boundingBox.width * viewportSize.width,
                height: boundingBox.height * viewportSize.height
            )
            
            // Log bounding box info
            print("DEBUG: Object: \(topLabelObservation.identifier) - Confidence: \(observation.confidence)")
            print("DEBUG: Bounding box: Origin(\(viewBox.minX), \(viewBox.minY)), Size(\(viewBox.width), \(viewBox.height))")
            
            // Perform hit testing to find position in 3D space
            let hitTestPoint = CGPoint(x: viewBox.midX, y: viewBox.midY)
            print("DEBUG: Hit testing at point: \(hitTestPoint.x), \(hitTestPoint.y)")
            
            let hitTestResults = sceneView.hitTest(hitTestPoint, types: [.existingPlaneUsingExtent, .estimatedHorizontalPlane])
            
            if let hitResult = hitTestResults.first {
                // Create a unique identifier based on the object label and position to avoid duplicates
                let position = hitResult.worldTransform.columns.3
                let positionKey = "\(topLabelObservation.identifier)_\(Int(position.x*10))_\(Int(position.z*10))"
                
                print("DEBUG: Hit test successful - World position: (\(position.x), \(position.y), \(position.z))")
                
                if detectedObjects[UUID(uuidString: positionKey) ?? UUID()] == nil {
                    // Calculate approximate size based on bounding box and distance
                    let distanceFromCamera = simd_length(SIMD3<Float>(position.x, position.y, position.z) - SIMD3<Float>(currentFrame.camera.transform.columns.3.x, currentFrame.camera.transform.columns.3.y, currentFrame.camera.transform.columns.3.z))
                    let boxWidth = Float(boundingBox.width) * distanceFromCamera * 0.2
                    let boxHeight = Float(boundingBox.height) * distanceFromCamera * 0.2
                    let boxLength = min(boxWidth, boxHeight) // Approximate depth
                    
                    print("DEBUG: Creating bounding box - Size: Width(\(boxWidth)), Height(\(boxHeight)), Length(\(boxLength))")
                    
                    // Create a bounding box node
                    createObjectBoundingBox(
                        at: hitResult.worldTransform,
                        width: CGFloat(boxWidth),
                        height: CGFloat(boxHeight),
                        length: CGFloat(boxLength),
                        label: topLabelObservation.identifier,
                        confidence: observation.confidence,
                        positionKey: positionKey
                    )
                    
                    detectedCount += 1
                } else {
                    print("DEBUG: Object already exists at this position")
                }
            } else {
                hitTestFailCount += 1
                print("DEBUG: Hit test failed - No surfaces detected at point")
            }
        }
        
        // Log summary of processing
        print("DEBUG: Processing summary - Objects placed: \(detectedCount), Low confidence: \(lowConfidenceCount), Hit test failures: \(hitTestFailCount)")
        updateDebugInfo("Placed: \(detectedCount), Low conf: \(lowConfidenceCount), Hit fail: \(hitTestFailCount)")
    }
    
    private func createObjectBoundingBox(at transform: matrix_float4x4, width: CGFloat, height: CGFloat, length: CGFloat, label: String, confidence: VNConfidence, positionKey: String) {
        let boxNode = BoundingBoxNode(
            width: width,
            height: height,
            length: length,
            label: label,
            confidence: Float(confidence)
        )
        
        // Position the box node
        boxNode.simdTransform = transform
        
        // Add to the scene
        sceneView.scene.rootNode.addChildNode(boxNode)
        
        // Store reference to avoid duplicates
        if let uuid = UUID(uuidString: positionKey) {
            detectedObjects[uuid] = boxNode
            print("DEBUG: Added object \(label) to scene at position key: \(positionKey)")
        } else {
            print("DEBUG: Failed to create UUID from position key: \(positionKey)")
            // Create a random UUID as fallback
            let randomUUID = UUID()
            detectedObjects[randomUUID] = boxNode
            print("DEBUG: Used random UUID instead: \(randomUUID)")
        }
        
        // Visualization helper - add axes to show coordinate system
        if showDebugInfo {
            let axesNode = createDebugAxes(length: 0.1)
            boxNode.addChildNode(axesNode)
        }
    }
    
    private func createDebugAxes(length: CGFloat) -> SCNNode {
        let axesNode = SCNNode()
        
        // X axis - red
        let xAxis = SCNCylinder(radius: 0.001, height: length)
        xAxis.firstMaterial?.diffuse.contents = UIColor.red
        let xAxisNode = SCNNode(geometry: xAxis)
        xAxisNode.position = SCNVector3(length/2, 0, 0)
        xAxisNode.eulerAngles = SCNVector3(0, 0, Float.pi/2)
        
        // Y axis - green
        let yAxis = SCNCylinder(radius: 0.001, height: length)
        yAxis.firstMaterial?.diffuse.contents = UIColor.green
        let yAxisNode = SCNNode(geometry: yAxis)
        yAxisNode.position = SCNVector3(0, length/2, 0)
        
        // Z axis - blue
        let zAxis = SCNCylinder(radius: 0.001, height: length)
        zAxis.firstMaterial?.diffuse.contents = UIColor.blue
        let zAxisNode = SCNNode(geometry: zAxis)
        zAxisNode.position = SCNVector3(0, 0, length/2)
        zAxisNode.eulerAngles = SCNVector3(Float.pi/2, 0, 0)
        
        axesNode.addChildNode(xAxisNode)
        axesNode.addChildNode(yAxisNode)
        axesNode.addChildNode(zAxisNode)
        
        return axesNode
    }

    // MARK: - ARSCNViewDelegate
    
    func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
        if let planeAnchor = anchor as? ARPlaneAnchor {
            // Create a custom object to visualize the plane geometry and extent.
            let plane = Plane(anchor: planeAnchor, in: sceneView)
            
            // Add the visualization to the ARKit-managed node so that it tracks
            // changes in the plane anchor as plane estimation continues.
            node.addChildNode(plane)
        } else if let objectAnchor = anchor as? ARObjectAnchor {
            // Create a bounding box for the detected reference object
            let objectNode = ObjectNode(anchor: objectAnchor)
            node.addChildNode(objectNode)
        }
    }

    func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
        // Update only anchors and nodes set up by `renderer(_:didAdd:for:)`.
        if let planeAnchor = anchor as? ARPlaneAnchor,
            let plane = node.childNodes.first as? Plane {
            // Update ARSCNPlaneGeometry to the anchor's new estimated shape.
            if let planeGeometry = plane.meshNode.geometry as? ARSCNPlaneGeometry {
                planeGeometry.update(from: planeAnchor.geometry)
            }

            // Update extent visualization to the anchor's new bounding rectangle.
            if let extentGeometry = plane.extentNode.geometry as? SCNPlane {
                extentGeometry.width = CGFloat(planeAnchor.extent.x)
                extentGeometry.height = CGFloat(planeAnchor.extent.z)
                plane.extentNode.simdPosition = planeAnchor.center
            }
            
            // Update the plane's classification and the text position
            if #available(iOS 12.0, *),
                let classificationNode = plane.classificationNode,
                let classificationGeometry = classificationNode.geometry as? SCNText {
                let currentClassification = planeAnchor.classification.description
                if let oldClassification = classificationGeometry.string as? String, oldClassification != currentClassification {
                    classificationGeometry.string = currentClassification
                    classificationNode.centerAlign()
                }
            }
        } else if let objectAnchor = anchor as? ARObjectAnchor,
                  let objectNode = node.childNodes.first as? ObjectNode {
            // Update the object node with new anchor information
            objectNode.update(with: objectAnchor)
        }
    }
    
    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        // Process current camera frame for object detection
        guard let currentFrame = sceneView.session.currentFrame else { return }
        
        // Detect objects at regular intervals to avoid performance issues
        let currentFrameTime = currentFrame.timestamp
        var lastFrameTime: TimeInterval = 0
        
        // Update debug info about frame rate
        frameProcessingCount += 1
        if frameProcessingCount % 30 == 0 { // Update every 30 frames
            updateDebugInfo("FPS: \(String(format: "%.1f", 1.0 / (time - lastFrameTime)))")
        }
        
        if currentFrameTime - lastFrameTime >= 0.5 { // Process every half second
            // Set the start time for performance measurement
            self.lastProcessingTime = CACurrentMediaTime()
            
            print("DEBUG: Processing frame at time \(currentFrameTime), \(currentFrameTime - lastFrameTime) seconds since last frame")
            lastFrameTime = currentFrameTime
            
            // Convert ARFrame's image to CVPixelBuffer for Vision request
            let pixelBuffer = currentFrame.capturedImage
            
            // Log camera info
            let cameraIntrinsics = currentFrame.camera.intrinsics
            let cameraImageResolution = currentFrame.camera.imageResolution
            print("DEBUG: Camera image resolution: \(cameraImageResolution.width) x \(cameraImageResolution.height)")
            print("DEBUG: Camera intrinsics: \(cameraIntrinsics)")
            
            // Process the image using Vision framework
            objectDetectionQueue.async {
                let imageRequestHandler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up)
                do {
                    print("DEBUG: Starting Vision processing")
                    try imageRequestHandler.perform(self.visionRequests)
                } catch {
                    print("DEBUG: Failed to perform Vision request: \(error)")
                    DispatchQueue.main.async {
                        self.updateDebugInfo("Vision error: \(error.localizedDescription)")
                    }
                }
            }
            
            // Check for detected planes (if needed for debugging)
            if showDebugInfo {
                let planes = currentFrame.anchors.compactMap { $0 as? ARPlaneAnchor }
                DispatchQueue.main.async {
                    self.updateDebugInfo("Planes detected: \(planes.count)")
                }
            }
        }
    }

    // MARK: - ARSessionDelegate

    func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        guard let frame = session.currentFrame else { return }
        updateSessionInfoLabel(for: frame, trackingState: frame.camera.trackingState)
    }

    func session(_ session: ARSession, didRemove anchors: [ARAnchor]) {
        guard let frame = session.currentFrame else { return }
        updateSessionInfoLabel(for: frame, trackingState: frame.camera.trackingState)
    }

    func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        updateSessionInfoLabel(for: session.currentFrame!, trackingState: camera.trackingState)
    }

    // MARK: - ARSessionObserver

    func sessionWasInterrupted(_ session: ARSession) {
        // Inform the user that the session has been interrupted, for example, by presenting an overlay.
        sessionInfoLabel.text = "Session was interrupted"
    }

    func sessionInterruptionEnded(_ session: ARSession) {
        // Reset tracking and/or remove existing anchors if consistent tracking is required.
        sessionInfoLabel.text = "Session interruption ended"
        resetTracking()
    }
    
    func session(_ session: ARSession, didFailWithError error: Error) {
        sessionInfoLabel.text = "Session failed: \(error.localizedDescription)"
        guard error is ARError else { return }
        
        let errorWithInfo = error as NSError
        let messages = [
            errorWithInfo.localizedDescription,
            errorWithInfo.localizedFailureReason,
            errorWithInfo.localizedRecoverySuggestion
        ]
        
        // Remove optional error messages.
        let errorMessage = messages.compactMap({ $0 }).joined(separator: "\n")
        
        DispatchQueue.main.async {
            // Present an alert informing about the error that has occurred.
            let alertController = UIAlertController(title: "The AR session failed.", message: errorMessage, preferredStyle: .alert)
            let restartAction = UIAlertAction(title: "Restart Session", style: .default) { _ in
                alertController.dismiss(animated: true, completion: nil)
                self.resetTracking()
            }
            alertController.addAction(restartAction)
            self.present(alertController, animated: true, completion: nil)
        }
    }

    // MARK: - Private methods

    private func updateSessionInfoLabel(for frame: ARFrame, trackingState: ARCamera.TrackingState) {
        // Update the UI to provide feedback on the state of the AR experience.
        let message: String

        switch trackingState {
        case .normal where frame.anchors.isEmpty:
            // No planes detected; provide instructions for this app's AR interactions.
            message = "Move the device around to detect horizontal and vertical surfaces."
            
        case .notAvailable:
            message = "Tracking unavailable."
            
        case .limited(.excessiveMotion):
            message = "Tracking limited - Move the device more slowly."
            
        case .limited(.insufficientFeatures):
            message = "Tracking limited - Point the device at an area with visible surface detail, or improve lighting conditions."
            
        case .limited(.initializing):
            message = "Initializing AR session."
            
        default:
            // No feedback needed when tracking is normal and planes are visible.
            // (Nor when in unreachable limited-tracking states.)
            message = ""

        }

        sessionInfoLabel.text = message
        sessionInfoView.isHidden = message.isEmpty
    }

    private func resetTracking() {
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = [.horizontal, .vertical]
        
        // Re-enable object detection if available
        if #available(iOS 12.0, *) {
            configuration.environmentTexturing = .automatic
            if let objects = ARReferenceObject.referenceObjects(inGroupNamed: "DetectedObjects", bundle: nil) {
                configuration.detectionObjects = objects
            }
        }
        
        // Clear the detected objects dictionary
        for (_, node) in detectedObjects {
            node.removeFromParentNode()
        }
        detectedObjects.removeAll()
        
        sceneView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
    }
}
