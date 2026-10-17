import AppKit
import Combine
import MacDictatorCore
import SwiftUI

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var standaloneWindow: NSWindow?
    private var appState: AppState!
    private var cancellables = Set<AnyCancellable>()

    private let defaultWidth: CGFloat = 375
    private let defaultHeight: CGFloat = 460

    public func applicationDidFinishLaunching(_ notification: Notification) {
        // Run as background accessory menu bar app (no dock icon by default)
        NSApp.setActivationPolicy(.accessory)

        self.appState = AppState()

        // Create status bar item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.title = "⚡ -- W"
            button.action = #selector(togglePopover)
            button.target = self
        }

        // Create Popover
        let pop = NSPopover()
        pop.contentSize = NSSize(width: defaultWidth, height: defaultHeight)
        pop.behavior = appState.isPinned ? .applicationDefined : .transient

        let hostingController = NSHostingController(
            rootView: DashboardView(
                state: appState,
                onDetachWindow: { [weak self] in
                    self?.openStandaloneWindow()
                },
                onQuit: {
                    NSApp.terminate(nil)
                }
            )
        )
        hostingController.sizingOptions = []
        hostingController.preferredContentSize = NSSize(width: defaultWidth, height: defaultHeight)
        pop.contentViewController = hostingController
        self.popover = pop

        // Bind AppState changes to Menu Bar Title
        appState.$reading
            .receive(on: DispatchQueue.main)
            .sink { [weak self] reading in
                self?.updateStatusBarTitle(reading: reading)
            }
            .store(in: &cancellables)

        appState.$config
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                if let reading = self?.appState.reading {
                    self?.updateStatusBarTitle(reading: reading)
                }
            }
            .store(in: &cancellables)

        // Bind Pin State changes
        appState.$isPinned
            .receive(on: DispatchQueue.main)
            .sink { [weak self] pinned in
                self?.applyPinState(pinned: pinned)
            }
            .store(in: &cancellables)
    }

    private func updateStatusBarTitle(reading: PowerReading) {
        guard let button = statusItem.button else { return }

        let totalW = reading.systemTotalWatts
        let cpuW = reading.cpuPowerWatts
        let isGov = appState.config.isGovernorEnabled
        let limit = appState.config.cpuLimitWatts
        let isBattery = reading.isBatteryPowered
        let icon = isBattery ? "🔋" : "⚡"

        if isGov {
            let isOver = cpuW > limit || totalW > appState.config.totalSocLimitWatts
            let statusIcon = isOver ? "⚠️" : icon
            button.title = String(format: "%@ %.1fW [Cap %.0fW]", statusIcon, totalW, limit)
        } else {
            button.title = String(format: "%@ %.1fW", icon, totalW)
        }
    }

    private func applyPinState(pinned: Bool) {
        if pinned {
            popover.behavior = .applicationDefined
            if let window = popover.contentViewController?.view.window {
                window.level = .floating
            }
            standaloneWindow?.level = .floating
        } else {
            popover.behavior = .transient
            if let window = popover.contentViewController?.view.window {
                window.level = .normal
            }
            standaloneWindow?.level = .normal
        }
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }

        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.contentSize = NSSize(width: defaultWidth, height: defaultHeight)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
            applyPinState(pinned: appState.isPinned)
        }
    }

    private func openStandaloneWindow() {
        if popover.isShown {
            popover.performClose(nil)
        }

        if let win = standaloneWindow {
            win.makeKeyAndOrderFront(nil)
            win.level = appState.isPinned ? .floating : .normal
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: defaultWidth, height: defaultHeight),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        win.minSize = NSSize(width: 350, height: 460)
        win.title = "Mac Dictator — Hardware Power Governor"
        win.center()
        win.level = appState.isPinned ? .floating : .normal
        let winHost = NSHostingController(
            rootView: DashboardView(
                state: appState,
                onDetachWindow: nil,
                onQuit: {
                    NSApp.terminate(nil)
                }
            )
        )
        winHost.sizingOptions = []
        win.contentViewController = winHost
        win.isReleasedWhenClosed = false
        self.standaloneWindow = win
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
