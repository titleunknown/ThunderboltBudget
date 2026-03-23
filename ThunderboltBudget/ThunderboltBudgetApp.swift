import SwiftUI
import AppKit

extension NSImage {
    // Generate a raw vector image that ignores SwiftUI's strict MenuBar constraints
    static var menuBarIcon: NSImage {
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .bold)
        let image = NSImage(systemSymbolName: "bolt.horizontal.circle", accessibilityDescription: nil)!
        let scaledImage = image.withSymbolConfiguration(config) ?? image
        scaledImage.isTemplate = true
        return scaledImage
    }
}

@main
struct ThunderboltBudgetApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        
        MenuBarExtra {
            MenuBarView()
        } label: {
            Image(nsImage: NSImage.menuBarIcon)
        }
        .menuBarExtraStyle(.window)
    }
}
