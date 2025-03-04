import ARKit
import Vision
import SceneKit
import CoreML
import CoreImage

protocol KnobDetectorDelegate: AnyObject {
    func didDetectKnob(_ knob: ControlKnob)
    func didDetectHandInteraction(withKnobID id: UUID, newValue: Float)
    func didCompleteRecording(knobs: [ControlKnob])
    func didEncounterError(_ error: Error)
}

class KnobDetector {
    // MARK: - Configuration
    
    struct Configuration {
        var maxKnobCount: Int = 6
        var detectionThreshold: Float = 0.3 // Distance threshold for knob detection
        var handDetectionConfidence: Float = 0.3
        var processingInterval: TimeInterval = 0.3
        var frameSkipInterval: Int = 10
    }
    
    // MARK: - Properties
    
    private weak var sceneView: ARSCNView?
    private weak var delegate: KnobDetectorDelegate?
    private var configuration: Configuration
    
    // Device and spatial reference
    private var deviceEdgePosition: SCNVector3?
    private var deviceBoundingBox: (width: Float, height: Float, depth: Float)?
    
    // Vision and ML properties
    private var knobDetectionRequest: VNDetectContoursRequest?
    private var handPoseRequest: VNDetectHumanHandPoseRequest?
    private let detectionQueue = DispatchQueue(label: "com.arapp.knobdetection", attributes: .concurrent)
    
    // Tracking properties
    private var detectedKnobs: [UUID: ControlKnob] = [:]
    private var knobDetectionCount = 0
    private var frameSkipCounter = 0
    
    // Feature detection
    private var lastProcessedFrame: TimeInterval = 0
    
    // Synchronization
    private let knobLock = NSLock()
    
    // MARK: - Initialization
    
    init(
        sceneView: ARSCNView,
        delegate: KnobDetectorDelegate,
        configuration: Configuration = Configuration()
    ) {
        self.sceneView = sceneView
        self.delegate = delegate
        self.configuration = configuration
        
        setupVision()
    }
    
    // MARK: - Vision Setup
    
    private func setupVision() {
        // Contour detection setup
        knobDetectionRequest = VNDetectContoursRequest()
        knobDetectionRequest?.contrastAdjustment = 1.0
        knobDetectionRequest?.detectsDarkOnLight = true
        
        // Hand pose detection
        if #available(iOS 14.0, *) {
            handPoseRequest = VNDetectHumanHandPoseRequest()
            handPoseRequest?.maximumHandCount = 2
        }
    }
    
    // MARK: - Public Configuration Methods
    
    func setDeviceEdgePosition(_ position: SCNVector3) {
        deviceEdgePosition = position
        print("Device edge position updated: \(position)")
    }
    
    func setDeviceBoundingBox(width: Float, height: Float, depth: Float) {
        deviceBoundingBox = (width, height, depth)
        print("Device bounding box updated: \(width)x\(height)x\(depth)")
    }
    
    func resetDetection() {
        knobLock.lock()
        defer { knobLock.unlock() }
        
        detectedKnobs.removeAll()
        knobDetectionCount = 0
        frameSkipCounter = 0
        lastProcessedFrame = 0
    }
    
    // MARK: - Frame Processing
    
    func processFrame(_ frame: ARFrame) {
        // Check for device reference and skip frames for performance
        guard let deviceEdgePosition = deviceEdgePosition else { return }
        
        frameSkipCounter += 1
        if frameSkipCounter < configuration.frameSkipInterval {
            return
        }
        frameSkipCounter = 0
        
        // Throttle processing
        let currentTime = CACurrentMediaTime()
        guard currentTime - lastProcessedFrame >= configuration.processingInterval else {
            return
        }
        lastProcessedFrame = currentTime
        
        // Asynchronous processing
        detectionQueue.async { [weak self] in
            guard let self = self else { return }
            
            self.detectControlElements(in: frame, devicePosition: deviceEdgePosition)
            
            // Process hand interactions if supported
            if #available(iOS 14.0, *), let handPoseRequest = self.handPoseRequest {
                self.processHandInteraction(frame: frame, request: handPoseRequest)
            }
            
            self.checkRecordingProgress()
        }
    }
    
    // MARK: - Detection Methods
    
    private func detectControlElements(in frame: ARFrame, devicePosition: SCNVector3) {
        guard let sceneView = sceneView else { return }
        
        let pixelBuffer = frame.capturedImage
        let imageRequestHandler = VNImageRequestHandler(
            cvPixelBuffer: pixelBuffer,
            orientation: .up,
            options: [:]
        )
        
        do {
            // Contour detection
            if let contoursRequest = knobDetectionRequest {
                try imageRequestHandler.perform([contoursRequest])
                processContours(contoursRequest, frame: frame, devicePosition: devicePosition)
            }
            
        } catch {
            delegate?.didEncounterError(error)
        }
    }
    
    // MARK: - Contour Processing
    
    private func processContours(_ request: VNDetectContoursRequest, frame: ARFrame, devicePosition: SCNVector3) {
        guard let results = request.results as? [VNContoursObservation],
              !results.isEmpty,
              let sceneView = sceneView else { return }
        
        for contour in results.prefix(10) {
            // For safety, use default center coordinates
            var centerX: CGFloat = 0.5
            var centerY: CGFloat = 0.5
            
            // Attempt to get the bounding box of the path
            let path = contour.normalizedPath
            let boundingBox = path.boundingBoxOfPath
            
            if !boundingBox.isEmpty && boundingBox.width > 0 && boundingBox.height > 0 {
                centerX = boundingBox.midX
                centerY = boundingBox.midY
            }
            
            // Convert to screen coordinates
            let point = CGPoint(
                x: centerX * sceneView.bounds.width,
                y: (1 - centerY) * sceneView.bounds.height
            )
            
            // Perform hit test to position in 3D space
            let hitResults = sceneView.hitTest(point, types: [.existingPlaneUsingExtent, .estimatedHorizontalPlane])
            
            guard let hitResult = hitResults.first else { continue }
            
            // Get position in 3D space
            let position = SCNVector3(
                hitResult.worldTransform.columns.3.x,
                hitResult.worldTransform.columns.3.y,
                hitResult.worldTransform.columns.3.z
            )
            
            // Check if the position is near our device reference point
            let distance = calculateDistance(from: position, to: devicePosition)
            guard distance < configuration.detectionThreshold else { continue }
            
            // Alternate between potentiometer and fader based on index
            let index = results.firstIndex(of: contour) ?? 0
            let type: ControlKnob.KnobType = (index % 2 == 0) ? .potentiometer : .fader
            
            // Create and store the knob
            createAndStoreKnob(
                position: position,
                type: type,
                devicePosition: devicePosition
            )
        }
    }
    
    // MARK: - Hand Interaction
    
    @available(iOS 14.0, *)
    private func processHandInteraction(frame: ARFrame, request: VNDetectHumanHandPoseRequest) {
        guard let sceneView = sceneView, !detectedKnobs.isEmpty else { return }
        
        let imageRequestHandler = VNImageRequestHandler(
            cvPixelBuffer: frame.capturedImage,
            orientation: .up,
            options: [:]
        )
        
        do {
            try imageRequestHandler.perform([request])
            
            guard let results = request.results as? [VNHumanHandPoseObservation] else { return }
            
            for observation in results {
                guard let indexTip = try? observation.recognizedPoint(.indexTip),
                      indexTip.confidence > configuration.handDetectionConfidence else {
                    continue
                }
                
                let screenPoint = CGPoint(
                    x: indexTip.location.x * sceneView.bounds.width,
                    y: (1 - indexTip.location.y) * sceneView.bounds.height
                )
                
                let hitResults = sceneView.hitTest(screenPoint, types: [.existingPlaneUsingExtent, .estimatedHorizontalPlane])
                
                guard let hitResult = hitResults.first else { continue }
                
                let fingerPosition = SCNVector3(
                    hitResult.worldTransform.columns.3.x,
                    hitResult.worldTransform.columns.3.y,
                    hitResult.worldTransform.columns.3.z
                )
                
                processFingerInteraction(at: fingerPosition)
            }
            
        } catch {
            delegate?.didEncounterError(error)
        }
    }
    
    private func processFingerInteraction(at fingerPosition: SCNVector3) {
        knobLock.lock()
        defer { knobLock.unlock() }
        
        for (id, knob) in detectedKnobs {
            let distanceToKnob = calculateDistance(from: fingerPosition, to: knob.position)
            
            guard distanceToKnob < 0.05 else { continue }
            
            let newValue = calculateInteractionValue(for: knob, fingerPosition: fingerPosition)
            
            var updatedKnob = knob
            updatedKnob.isBeingAdjusted = true
            updatedKnob.currentValue = newValue
            detectedKnobs[id] = updatedKnob
            
            DispatchQueue.main.async { [weak self] in
                self?.delegate?.didDetectHandInteraction(withKnobID: id, newValue: newValue)
            }
            
            break  // Interact with only one knob
        }
    }
    
    // MARK: - Helper Methods
    
    private func createAndStoreKnob(position: SCNVector3, type: ControlKnob.KnobType, devicePosition: SCNVector3) {
        knobLock.lock()
        defer { knobLock.unlock() }
        
        guard detectedKnobs.count < configuration.maxKnobCount else { return }
        
        let idString = "knob_\(position.x)_\(position.y)_\(position.z)"
        let id = UUID(uuidString: idString) ?? UUID()
        
        guard detectedKnobs[id] == nil else { return }
        
        let knob = ControlKnob(
            id: id,
            type: type,
            position: position,
            currentValue: 0.0,
            targetValue: type == .potentiometer ? 0.75 : 0.8
        )
        knob.setDeviceEdgePosition(devicePosition)
        
        detectedKnobs[id] = knob
        knobDetectionCount += 1
        
        DispatchQueue.main.async { [weak self] in
            self?.delegate?.didDetectKnob(knob)
        }
    }
    
    private func calculateDistance(from point1: SCNVector3, to point2: SCNVector3) -> Float {
        let dx = point1.x - point2.x
        let dy = point1.y - point2.y
        let dz = point1.z - point2.z
        return sqrt(dx*dx + dy*dy + dz*dz)
    }
    
    private func calculateInteractionValue(for knob: ControlKnob, fingerPosition: SCNVector3) -> Float {
        switch knob.type {
        case .potentiometer:
            let dx = fingerPosition.x - knob.position.x
            let dz = fingerPosition.z - knob.position.z
            let angle = atan2(dz, dx)
            return Float((angle + .pi) / (2 * .pi))
            
        case .fader:
            let minY = knob.position.y - 0.05
            let maxY = knob.position.y + 0.05
            let normalizedY = (fingerPosition.y - minY) / (maxY - minY)
            return max(0, min(1, Float(normalizedY)))
        }
    }
    
    private func checkRecordingProgress() {
        knobLock.lock()
        defer { knobLock.unlock() }
        
        guard knobDetectionCount >= configuration.maxKnobCount else { return }
        
        let knobsArray = Array(detectedKnobs.values)
        
        DispatchQueue.main.async { [weak self] in
            self?.delegate?.didCompleteRecording(knobs: knobsArray)
            self?.resetDetection()
        }
    }
}
