import UIKit
import AVFoundation

protocol RecordManagerDelegate: AnyObject {
    func recordStateDidChange(isRecording: Bool)
}

class RecordManager {
    // UI Elements
    private var recordButton: UIButton!
    private var recordIndicator: UIView!
    
    // State
    private(set) var isRecording = false
    private var blinkTimer: Timer?
    private let torchLevel: Float = 0.25 // 25% intensity
    
    // Reference to parent view
    private weak var parentView: UIView?
    private weak var delegate: RecordManagerDelegate?
    
    init(parentView: UIView, delegate: RecordManagerDelegate) {
        self.parentView = parentView
        self.delegate = delegate
        setupRecordUI()
    }
    
    // MARK: - UI Setup
    
    private func setupRecordUI() {
        guard let parentView = parentView else { return }
        
        // Create record button
        recordButton = UIButton(type: .system)
        recordButton.translatesAutoresizingMaskIntoConstraints = false
        recordButton.setTitle("Record", for: .normal)
        recordButton.setTitleColor(.white, for: .normal)
        recordButton.backgroundColor = UIColor.systemRed.withAlphaComponent(0.7)
        recordButton.layer.cornerRadius = 25
        recordButton.addTarget(self, action: #selector(toggleRecordMode), for: .touchUpInside)
        
        // Create record indicator (red dot)
        recordIndicator = UIView(frame: CGRect(x: 0, y: 0, width: 20, height: 20))
        recordIndicator.translatesAutoresizingMaskIntoConstraints = false
        recordIndicator.backgroundColor = .red
        recordIndicator.layer.cornerRadius = 10
        recordIndicator.isHidden = true
        recordIndicator.alpha = 1.0
        
        // Add to view hierarchy
        parentView.addSubview(recordButton)
        parentView.addSubview(recordIndicator)
        
        // Position button at bottom center
        NSLayoutConstraint.activate([
            recordButton.centerXAnchor.constraint(equalTo: parentView.centerXAnchor),
            recordButton.bottomAnchor.constraint(equalTo: parentView.safeAreaLayoutGuide.bottomAnchor, constant: -20),
            recordButton.widthAnchor.constraint(equalToConstant: 120),
            recordButton.heightAnchor.constraint(equalToConstant: 50),
            
            // Position indicator at top left
            recordIndicator.topAnchor.constraint(equalTo: parentView.safeAreaLayoutGuide.topAnchor, constant: 20),
            recordIndicator.leadingAnchor.constraint(equalTo: parentView.safeAreaLayoutGuide.leadingAnchor, constant: 20),
            recordIndicator.widthAnchor.constraint(equalToConstant: 20),
            recordIndicator.heightAnchor.constraint(equalToConstant: 20)
        ])
        
        // Bring to front
        parentView.bringSubviewToFront(recordButton)
        parentView.bringSubviewToFront(recordIndicator)
    }
    
    // MARK: - Action Methods
    
    @objc public func toggleRecordMode() {
        isRecording = !isRecording
        
        if isRecording {
            // Start recording mode
            startRecordingMode()
            recordButton.setTitle("Stop", for: .normal)
            recordButton.backgroundColor = UIColor.systemGray.withAlphaComponent(0.7)
        } else {
            // Stop recording mode
            stopRecordingMode()
            recordButton.setTitle("Record", for: .normal)
            recordButton.backgroundColor = UIColor.systemRed.withAlphaComponent(0.7)
        }
        
        // Notify delegate
        delegate?.recordStateDidChange(isRecording: isRecording)
    }
    
    private func startRecordingMode() {
        // Show record indicator and start blinking
        recordIndicator.isHidden = false
        startBlinkingIndicator()
        
        // Turn on torch at 25% intensity
        toggleTorch(on: true, level: torchLevel)
        
        // Provide haptic feedback
        let feedbackGenerator = UIImpactFeedbackGenerator(style: .medium)
        feedbackGenerator.prepare()
        feedbackGenerator.impactOccurred()
    }
    
    private func stopRecordingMode() {
        // Hide record indicator and stop blinking
        recordIndicator.isHidden = true
        stopBlinkingIndicator()
        
        // Turn off torch
        toggleTorch(on: false)
        
        // Provide haptic feedback
        let feedbackGenerator = UIImpactFeedbackGenerator(style: .medium)
        feedbackGenerator.prepare()
        feedbackGenerator.impactOccurred()
    }
    
    // MARK: - Helper Methods
    
    private func startBlinkingIndicator() {
        stopBlinkingIndicator() // Stop any existing timer
        
        blinkTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            UIView.animate(withDuration: 0.25) {
                self?.recordIndicator.alpha = self?.recordIndicator.alpha == 1.0 ? 0.3 : 1.0
            }
        }
    }
    
    private func stopBlinkingIndicator() {
        blinkTimer?.invalidate()
        blinkTimer = nil
        recordIndicator.alpha = 1.0
    }
    
    private func toggleTorch(on: Bool, level: Float = 1.0) {
        guard let device = AVCaptureDevice.default(for: .video) else { return }
        
        do {
            try device.lockForConfiguration()
            
            if on && device.hasTorch && device.isTorchAvailable {
                try device.setTorchModeOn(level: level)
            } else {
                device.torchMode = .off
            }
            
            device.unlockForConfiguration()
        } catch {
            print("Torch could not be used: \(error.localizedDescription)")
        }
    }
}
