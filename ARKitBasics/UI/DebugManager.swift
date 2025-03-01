//
//  DeubManager.swift
//  ARKitBasics
//
//  Created by Christopher Matt on 01.03.25.
//  Copyright © 2025 Apple. All rights reserved.
//

import UIKit

class DebugManager {
    // UI Elements
    private var debugView: UIView!
    private var debugTextView: UITextView!
    private var debugButton: UIButton!
    
    // Debug state
    private var showDebugInfo = false
    private var debugMessages = [String]()
    private let maxDebugLines = 20
    private var debugUpdateTimer: Timer?
    
    // Statistics
    private var frameProcessingCount = 0
    private var objectDetectionCount = 0
    
    // Reference to parent view
    private weak var parentView: UIView?
    
    init(parentView: UIView) {
        self.parentView = parentView
        setupDebugUI()
    }
    
    // MARK: - Public Interface
    
    func incrementFrameCount() {
        frameProcessingCount += 1
    }
    
    func incrementObjectCount(by count: Int = 1) {
        objectDetectionCount += count
    }
    
    func logMessage(_ message: String) {
        print("DEBUG: \(message)")
        
        // Add to message queue with timestamp
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "HH:mm:ss"
        let timestamp = dateFormatter.string(from: Date())
        let timestampedMessage = "[\(timestamp)] \(message)"
        
        // Add message and trim if needed
        debugMessages.append(timestampedMessage)
        if debugMessages.count > maxDebugLines {
            debugMessages.removeFirst(debugMessages.count - maxDebugLines)
        }
    }
    
    // MARK: - UI Setup
    
    private func setupDebugUI() {
        guard let parentView = parentView else { return }
        
        // Create debug overlay view
        debugView = UIView(frame: CGRect(x: 20, y: 100, width: parentView.bounds.width - 40, height: 200))
        debugView.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        debugView.layer.cornerRadius = 10
        debugView.isHidden = !showDebugInfo
        
        // Create debug text view
        debugTextView = UITextView(frame: CGRect(x: 5, y: 5, width: debugView.bounds.width - 10, height: debugView.bounds.height - 10))
        debugTextView.backgroundColor = .clear
        debugTextView.textColor = .white
        debugTextView.font = UIFont.monospacedSystemFont(ofSize: 10, weight: .regular)
        debugTextView.isEditable = false
        debugTextView.isSelectable = false
        debugTextView.showsVerticalScrollIndicator = true
        debugTextView.text = "Debug information will appear here..."
        
        // Create debug toggle button
        debugButton = UIButton(type: .system)
        debugButton.frame = CGRect(x: parentView.bounds.width - 120, y: 40, width: 100, height: 40)
        debugButton.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.7)
        debugButton.layer.cornerRadius = 8
        debugButton.setTitle("Show Debug", for: .normal)
        debugButton.setTitleColor(.white, for: .normal)
        debugButton.addTarget(self, action: #selector(toggleDebugView), for: .touchUpInside)
        
        // Add UI elements
        debugView.addSubview(debugTextView)
        parentView.addSubview(debugView)
        parentView.addSubview(debugButton)
        
        // Bring debug elements to front
        parentView.bringSubviewToFront(debugView)
        parentView.bringSubviewToFront(debugButton)
        
        // Start debug update timer
        startDebugUpdateTimer()
    }
    
    @objc private func toggleDebugView() {
        showDebugInfo = !showDebugInfo
        debugView.isHidden = !showDebugInfo
        debugButton.setTitle(showDebugInfo ? "Hide Debug" : "Show Debug", for: .normal)
    }
    
    private func startDebugUpdateTimer() {
        stopDebugUpdateTimer()
        
        // Update debug view every half second instead of every frame
        debugUpdateTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.refreshDebugView()
        }
    }
    
    private func stopDebugUpdateTimer() {
        debugUpdateTimer?.invalidate()
        debugUpdateTimer = nil
    }
    
    private func refreshDebugView() {
        guard showDebugInfo else { return }
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "HH:mm:ss.SSS"
        
        // Create standard stats text
        let statsText = """
        Time: \(dateFormatter.string(from: Date()))
        Frames Processed: \(frameProcessingCount)
        Objects Detected: \(objectDetectionCount)
        """
        
        // Combine stats with message list
        var fullText = statsText
        if !debugMessages.isEmpty {
            fullText += "\n\nEvents:"
            for message in debugMessages {
                fullText += "\n- \(message)"
            }
        }
        
        // Update text view and scroll to bottom
        debugTextView.text = fullText
        let range = NSRange(location: fullText.count, length: 0)
        debugTextView.scrollRangeToVisible(range)
    }
}
