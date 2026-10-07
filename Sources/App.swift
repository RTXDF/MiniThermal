import AppKit
import SwiftUI
import UniformTypeIdentifiers
import Darwin

final class AppDelegate: NSObject, NSApplicationDelegate {
    var monitor: Monitor!
    var item: NSStatusItem!
    var popover: NSPopover!

    func applicationDidFinishLaunching(_ notification: Notification) {
        monitor = Monitor()
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "fanblades", accessibilityDescription: "MiniThermal 温度与风扇")
        item.button?.imagePosition = .imageLeading
        item.button?.title = " —°"
        item.button?.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        item.button?.target = self; item.button?.action = #selector(toggle)
        popover = NSPopover(); popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: ThermalPanel(monitor: monitor))
        popover.contentSize = NSSize(width: 382, height: 620)
        monitor.onUpdate = { [weak self] fresh in
            self?.item.button?.title = fresh.chip.map { " \(Int($0.rounded()))°" } ?? " —°"
            self?.item.button?.toolTip = "MiniThermal · \(fresh.actualRPM.map { "\(Int($0)) RPM" } ?? "转速不可用")"
        }
        if CommandLine.arguments.contains("--show") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { self.toggle() }
        }
    }
    @objc func toggle() {
        guard let button = item.button else { return }
        if popover.isShown { popover.performClose(nil) }
        else { NSApp.activate(ignoringOtherApps: true); popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY) }
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        monitor.shutdown(); return .terminateNow
    }
}

@main enum MiniThermalMain {
    static func main() {
        if CommandLine.arguments.contains("--diagnose") {
            let snapshot = SMCReader().snapshot()
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601
            if let data = try? encoder.encode(snapshot), let text = String(data: data, encoding: .utf8) { print(text) }
            mt_close(); exit(snapshot.actualRPM != nil && snapshot.chip != nil ? 0 : 1)
        }
        if let index = CommandLine.arguments.firstIndex(of: "--render-preview"), CommandLine.arguments.count > index + 1 {
            let app = NSApplication.shared
            app.setActivationPolicy(.accessory)
            let monitor = Monitor()
            let reader = SMCReader(); let snapshot = reader.snapshot()
            monitor.snapshot = snapshot
            monitor.requestedRPM = snapshot.minimumRPM ?? 1000
            monitor.history = [snapshot.chip].compactMap { $0 }
            monitor.message = "实时监测中 · 每 2 秒更新"
            let view = NSHostingView(rootView: ThermalPanel(monitor: monitor))
            view.frame = NSRect(x: 0, y: 0, width: 382, height: 620)
            let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.contentView = view; window.orderFrontRegardless()
            RunLoop.main.run(until: Date().addingTimeInterval(1))
            view.layoutSubtreeIfNeeded()
            if let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                view.cacheDisplay(in: view.bounds, to: bitmap)
                if let data = bitmap.representation(using: .png, properties: [:]) { try? data.write(to: URL(fileURLWithPath: CommandLine.arguments[index+1])) }
            }
            monitor.shutdown(); exit(0)
        }
        // Single instance, preserving the first process's control session.
        let lockPath = NSHomeDirectory() + "/Library/Caches/local.MiniThermal.lock"
        let lock = open(lockPath, O_CREAT | O_RDWR, 0600)
        guard lock >= 0 && flock(lock, LOCK_EX | LOCK_NB) == 0 else { exit(0) }
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let delegate = AppDelegate(); app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
        close(lock)
    }
}
