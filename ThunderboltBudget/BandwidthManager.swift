import Foundation
import Combine
import IOKit
import CoreGraphics

class BandwidthManager: ObservableObject {
    @Published var displayUsage: Double = 0.0
    @Published var diskUsage: Double = 0.0
    private let totalCapacity: Double = 40.0 // 40 Gbps limit
    
    init() {
        startMonitoring()
    }
    
    func startMonitoring() {
        // Create a timer to refresh data every 2 seconds
        Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            self.updateMetrics()
        }
    }
    
    private func updateMetrics() {
        // 1. Calculate Display Reservation
        let displays = CGDisplayCopyDisplayMode(CGMainDisplayID())
        let width = displays?.width ?? 0
        let refresh = displays?.refreshRate ?? 60.0
        // Rough math: (Res * Refresh * 30bits) / 10^9
        self.displayUsage = (Double(width * (displays?.height ?? 0)) * refresh * 30) / 1_000_000_000
        
        // 2. Logic for Disk I/O (Placeholder for iostat/StorageKit)
        self.diskUsage = 1.2 // Assume 1.2 Gbps for now
    }
}//
//  BandwidthManager.swift
//  ThunderboltBudget
//
//  Created by Ben McCarthy on 18/3/2026.
//

