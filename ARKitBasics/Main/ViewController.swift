import UIKit
import SceneKit
import ARKit
import Vision
import AVFoundation

class ViewController: UIViewController, ARSCNViewDelegate, ARSessionDelegate,
                     RecordManagerDelegate, KnobDetectorDelegate, KnobVisualizationDelegate {
    // MARK: - IBOutlets

    @IBOutlet weak var sessionInfoView: UIView!
    @IBOutlet weak var sessionInfoLabel: UILabel!
    @IBOutlet weak var sceneView: ARSCNView!
    
    // MARK: - Properties
    
    // Managers
    private var debugManager: DebugManager!
    private var recordManager: RecordManager!
    private var knobDetector: KnobDetector!
    private var knobVisualizer: KnobVisualizationManager!
    
    // AR Tracking
    private var detectedObjects = [UUID: SCNNode]()
    private var lastProcessingTime: TimeInterval = 0
    private var lastFrameTime: TimeInterval = 0
    
    // Edge detection
    private var isWaitingForEdgeSelection = false
    private var edgeSelectionTapGesture: UITapGestureRecognizer?
    
    // Vision request for object detection
    private var visionRequests = [VNCoreMLRequest]()
    private let objectDetectionQueue = DispatchQueue(label: "objectDetectionQueue")

    // MARK: - View Life Cycle

    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Setup debug manager
        debugManager = DebugManager(parentView: view)
        
        // Setup record manager
        recordManager = RecordManager(parentView: view, delegate: self)
        
        // Setup knob detection and visualization
        knobVisualizer = KnobVisualizationManager(sceneView: sceneView, delegate: self)
        knobDetector = KnobDetector(sceneView: sceneView, delegate: self)
        
        // Setup edge selection gesture
        setupEdgeSelectionGesture()
        
        // Setup Vision ML model for object detection
        setupVision()
        
        // Log AR support information
        logARSupportInfo()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        // Start the view's AR session
        startARSession()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        // Pause the view's AR session
        sceneView.session.pause()
    }
    
    // MARK: - AR Session Setup
    
    private func startARSession() {
        // Configure AR session
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = [.horizontal, .vertical]
        
        // Enable object detection if available
        if #available(iOS 12.0, *) {
            configuration.environmentTexturing = .automatic
            
            // If you have predefined reference objects, use this:
            if let objects = ARReferenceObject.referenceObjects(inGroupNamed: "DetectedObjects", bundle: nil) {
                configuration.detectionObjects = objects
            }
        }
        
        // Run the session
        sceneView.session.run(configuration)

        // Set delegates
        sceneView.session.delegate = self
        sceneView.delegate = self
        
        // Prevent screen from dimming
        UIApplication.shared.isIdleTimerDisabled = true
        
        // Enable statistics for debugging
        sceneView.showsStatistics = true
        
        // Enable automatic light estimation
        sceneView.automaticallyUpdatesLighting = true
    }
    
    // MARK: - Edge Selection
    
    private func setupEdgeSelectionGesture() {
        edgeSelectionTapGesture = UITapGestureRecognizer(target: self, action: #selector(handleEdgeSelectionTap(_:)))
        edgeSelectionTapGesture?.isEnabled = false
        view.addGestureRecognizer(edgeSelectionTapGesture!)
    }
    
    @objc private func handleEdgeSelectionTap(_ gestureRecognizer: UITapGestureRecognizer) {
        guard isWaitingForEdgeSelection,
              let sceneView = self.sceneView else { return }
        
        // Get tap location
        let tapLocation = gestureRecognizer.location(in: sceneView)
        
        // Perform hit test at tap location
        let hitTestResults = sceneView.hitTest(tapLocation, types: [.existingPlaneUsingExtent, .estimatedHorizontalPlane])
        
        if let hitResult = hitTestResults.first {
            // Get position in 3D space
            let position = SCNVector3(
                hitResult.worldTransform.columns.3.x,
                hitResult.worldTransform.columns.3.y,
                hitResult.worldTransform.columns.3.z
            )
            
            // Set the position as the device edge
            knobDetector.setDeviceEdgePosition(position)
            
            // Create a visual marker at the edge position
            addVisualMarkerAtEdge(position: position)
            
            // Disable edge selection mode
            isWaitingForEdgeSelection = false
            edgeSelectionTapGesture?.isEnabled = false
            
            // Update UI
            showMessage("Edge position set. Recording enabled.")
        } else {
            showMessage("Could not detect surface. Try again.")
        }
    }
    
    private func addVisualMarkerAtEdge(position: SCNVector3) {
        // Create a small sphere to mark the edge position
        let markerGeometry = SCNSphere(radius: 0.01)
        markerGeometry.firstMaterial?.diffuse.contents = UIColor.yellow
        
        let markerNode = SCNNode(geometry: markerGeometry)
        markerNode.position = position
        
        // Add a text label
        let textGeometry = SCNText(string: "Device Edge", extrusionDepth: 0.001)
        textGeometry.font = UIFont.systemFont(ofSize: 0.1)
        textGeometry.firstMaterial?.diffuse.contents = UIColor.white
        
        let textNode = SCNNode(geometry: textGeometry)
        textNode.scale = SCNVector3(0.01, 0.01, 0.01)
        textNode.position = SCNVector3(position.x, position.y + 0.02, position.z)
        
        // Add to scene
        sceneView.scene.rootNode.addChildNode(markerNode)
        sceneView.scene.rootNode.addChildNode(textNode)
    }
    
    // MARK: - Vision Setup
    
    private func setupVision() {
        // Setup CoreML model for object detection
        guard let modelURL = Bundle.main.url(forResource: "YOLOv3", withExtension: "mlmodelc") else {
            debugManager.logMessage("Failed to find the ML model in the app bundle")
            return
        }
        
        do {
            let visionModel = try VNCoreMLModel(for: MLModel(contentsOf: modelURL))
            let objectRecognition = VNCoreMLRequest(model: visionModel) { [weak self] (request, error) in
                guard let self = self else { return }
                
                if let error = error {
                    self.debugManager.logMessage("Vision ML request error: \(error)")
                    return
                }
                
                guard let results = request.results as? [VNRecognizedObjectObservation] else {
                    self.debugManager.logMessage("No results or invalid type returned")
                    return
                }
                
                // Calculate processing time
                let processingTime = CACurrentMediaTime() - self.lastProcessingTime
                self.debugManager.logMessage("Detected \(results.count) objects in \(String(format: "%.2f", processingTime * 1000))ms")
                
                // Process results
                DispatchQueue.main.async {
                    self.debugManager.incrementObjectCount(by: results.count)
                    self.handleVisionResults(results)
                }
            }
            
            objectRecognition.imageCropAndScaleOption = .scaleFill
            self.visionRequests = [objectRecognition]
            debugManager.logMessage("Vision model setup successfully")
        } catch {
            debugManager.logMessage("Failed to create Vision ML model: \(error)")
        }
    }
    
    private func handleVisionResults(_ results: [VNRecognizedObjectObservation]) {
        // Get current ARFrame
        guard let currentFrame = sceneView.session.currentFrame else {
            debugManager.logMessage("No current frame available")
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
                debugManager.logMessage("Object had no labels")
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
            
            // Perform hit testing to find position in 3D space
            let hitTestPoint = CGPoint(x: viewBox.midX, y: viewBox.midY)
            let hitTestResults = sceneView.hitTest(hitTestPoint, types: [.existingPlaneUsingExtent, .estimatedHorizontalPlane])
            
            if let hitResult = hitTestResults.first {
                // Create a unique identifier based on the object label and position
                let position = hitResult.worldTransform.columns.3
                let positionKey = "\(topLabelObservation.identifier)_\(Int(position.x*10))_\(Int(position.z*10))"
                
                if detectedObjects[UUID(uuidString: positionKey) ?? UUID()] == nil {
                    // Calculate size based on bounding box and distance
                    let distanceFromCamera = simd_length(
                        SIMD3<Float>(position.x, position.y, position.z) -
                        SIMD3<Float>(currentFrame.camera.transform.columns.3.x,
                                     currentFrame.camera.transform.columns.3.y,
                                     currentFrame.camera.transform.columns.3.z))
                    
                    let boxWidth = Float(boundingBox.width) * distanceFromCamera * 0.2
                    let boxHeight = Float(boundingBox.height) * distanceFromCamera * 0.2
                    let boxLength = min(boxWidth, boxHeight) // Approximate depth
                    
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
                }
            } else {
                hitTestFailCount += 1
            }
        }
        
        // Log summary
        debugManager.logMessage("Objects placed: \(detectedCount), Low confidence: \(lowConfidenceCount), Hit test failures: \(hitTestFailCount)")
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
        } else {
            // Create a random UUID as fallback
            let randomUUID = UUID()
            detectedObjects[randomUUID] = boxNode
        }
    }
    
    private func logARSupportInfo() {
        debugManager.logMessage("ARKit Support Information")
        debugManager.logMessage("ARWorldTrackingConfiguration supported: \(ARWorldTrackingConfiguration.isSupported)")
        
        if #available(iOS 12.0, *) {
            debugManager.logMessage("ARObjectScanningConfiguration supported: \(ARObjectScanningConfiguration.isSupported)")
            debugManager.logMessage("ARPlaneClassification supported: \(ARPlaneAnchor.isClassificationSupported)")
        }
        
        debugManager.logMessage("Device: \(UIDevice.current.model), iOS \(UIDevice.current.systemVersion)")
    }
    
    // MARK: - Helper Methods
    
    func showMessage(_ message: String) {
        // Create alert controller
        let alertController = UIAlertController(
            title: nil,
            message: message,
            preferredStyle: .alert
        )
        
        // Dismiss automatically after 2 seconds
        self.present(alertController, animated: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            alertController.dismiss(animated: true)
        }
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
        
        // Update frame count for debugging
        debugManager.incrementFrameCount()
        
        // Process knob detection when in recording mode
        if recordManager.isRecording {
            knobDetector.processFrame(currentFrame)
            
            // Simulate knob value changes for prototype
            if arc4random_uniform(100) < 10 { // 10% chance each frame
                knobVisualizer.simulateKnobValueChanges()
            }
        }
        
        // Process object detection at regular intervals
        let currentFrameTime = currentFrame.timestamp
        if currentFrameTime - lastFrameTime >= 0.5 { // Process every half second
            // Set the start time for performance measurement
            self.lastProcessingTime = CACurrentMediaTime()
            
            // Process the image using Vision framework
            objectDetectionQueue.async {
                let imageRequestHandler = VNImageRequestHandler(cvPixelBuffer: currentFrame.capturedImage, orientation: .up)
                do {
                    try imageRequestHandler.perform(self.visionRequests)
                } catch {
                    self.debugManager.logMessage("Failed to perform Vision request: \(error)")
                }
            }
            
            lastFrameTime = currentFrameTime
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
    
    private func updateSessionInfoLabel(for frame: ARFrame, trackingState: ARCamera.TrackingState) {
        // Update the UI to provide feedback on the state of the AR experience.
        let message: String

        switch trackingState {
        case .normal where frame.anchors.isEmpty:
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
            message = ""
        }

        sessionInfoLabel.text = message
        sessionInfoView.isHidden = message.isEmpty
    }
    
    // MARK: - ARSessionObserver

    func sessionWasInterrupted(_ session: ARSession) {
        sessionInfoLabel.text = "Session was interrupted"
    }

    func sessionInterruptionEnded(_ session: ARSession) {
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
    
    // MARK: - RecordManagerDelegate
    
    func recordStateDidChange(isRecording: Bool) {
        if isRecording {
            // Clear previous detections when starting new recording
            knobVisualizer.clearKnobs()
            
            // Enable edge selection mode
            isWaitingForEdgeSelection = true
            edgeSelectionTapGesture?.isEnabled = true
            
            // Prompt user to select the edge
            showMessage("Tap on the edge of the audio device to start detection")
        } else {
            // Disable edge selection
            isWaitingForEdgeSelection = false
            edgeSelectionTapGesture?.isEnabled = false
            
            // Clear visualizations
            knobVisualizer.clearKnobs()
        }
    }
    
    // MARK: - KnobDetectorDelegate
    
    func didDetectKnob(_ knob: ControlKnob) {
        knobVisualizer.addKnob(knob)
        debugManager.logMessage("Detected \(knob.type == .potentiometer ? "potentiometer" : "fader")")
    }
    
    func didDetectHandInteraction(withKnobID id: UUID, newValue: Float) {
        knobVisualizer.updateKnob(id: id, newValue: newValue)
        debugManager.logMessage("Hand interaction detected, new value: \(newValue)")
    }
    
    func didCompleteRecording(knobs: [ControlKnob]) {
        debugManager.logMessage("Recording complete! Detected \(knobs.count) knobs")
        
        // Show a success message
        showMessage("Recording complete! Found \(knobs.count) controls.")
        
        // Disable recording mode if needed
        if recordManager.isRecording {
            recordManager.toggleRecordMode()
        }
    }
    
    func didEncounterError(_ error: Error) {
        debugManager.logMessage("Error in knob detection: \(error.localizedDescription)")
        
        // Only show error messages when in recording mode
        if recordManager.isRecording {
            showMessage("Detection error: \(error.localizedDescription)")
        }
    }
    
    // MARK: - KnobVisualizationDelegate
    
    func knobAdjustedToTargetValue(knob: ControlKnob) {
        // Provide haptic feedback when a knob is correctly adjusted
        let feedbackGenerator = UINotificationFeedbackGenerator()
        feedbackGenerator.notificationOccurred(.success)
        
        // Show message
        let knobTypeString = knob.type == .potentiometer ? "Potentiometer" : "Fader"
        debugManager.logMessage("\(knobTypeString) adjusted to target value!")
    }

    func completedAllKnobAdjustments() {
        // Diese Methode musst du noch hinzufügen
        debugManager.logMessage("All knobs adjusted correctly!")
        
        // Optional: Zeige eine Erfolgsmeldung an
        showMessage("All controls adjusted correctly!")
        
        // Optional: Weitere Aktionen wie Speichern der Konfiguration, etc.
    }
}
