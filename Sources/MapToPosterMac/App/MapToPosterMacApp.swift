import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@main
struct MapToPosterMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup("Map to Poster Generator") {
            ContentView()
                .frame(minWidth: 1320, idealWidth: 1320, minHeight: 860, idealHeight: 860)
        }
        .defaultSize(width: 1320, height: 860)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Generate Poster") {
                    NotificationCenter.default.post(name: .generatePosterRequested, object: nil)
                }
                .keyboardShortcut(.return, modifiers: [.command])
            }
        }
    }
}

extension Notification.Name {
    static let generatePosterRequested = Notification.Name("generatePosterRequested")
}
