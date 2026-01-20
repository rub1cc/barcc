import AppKit
import SwiftUI
import Combine

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var statsParser: StatsParser?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide dock icon
        NSApp.setActivationPolicy(.accessory)

        // Initialize stats parser
        statsParser = StatsParser()

        // Create status bar item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        // Setup popover
        popover = NSPopover()
        popover?.contentSize = NSSize(width: 350, height: 520)
        popover?.behavior = .transient
        popover?.animates = true

        if let parser = statsParser {
            popover?.contentViewController = NSHostingController(rootView: MenuBarView(stats: parser))
        }

        // Setup button
        if let button = statusItem?.button {
            button.action = #selector(togglePopover)
            button.target = self
            updateStatusButton()
        }

        // Subscribe to stats updates
        statsParser?.$todayStats
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateStatusButton()
            }
            .store(in: &cancellables)
    }

    private func updateStatusButton() {
        guard let button = statusItem?.button, let stats = statsParser else { return }

        let cost = stats.todayStats.cost
        let costText = cost > 0 ? String(format: "$%.2f", cost) : "$0"

        // Create attributed string with icon and cost
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)

        // Color based on daily spend
        let color: NSColor
        if cost < 1.0 {
            color = .systemGreen
        } else if cost < 5.0 {
            color = .systemYellow
        } else {
            color = .systemOrange
        }

        let colorConfig = NSImage.SymbolConfiguration(paletteColors: [color])
        let combinedConfig = config.applying(colorConfig)

        if let icon = NSImage(systemSymbolName: "dollarsign.circle.fill", accessibilityDescription: "Usage")?.withSymbolConfiguration(combinedConfig) {
            let attachment = NSTextAttachment()
            attachment.image = icon

            let attrString = NSMutableAttributedString(attachment: attachment)
            attrString.append(NSAttributedString(string: " \(costText)", attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
                .foregroundColor: NSColor.labelColor
            ]))

            button.attributedTitle = attrString
        } else {
            button.title = costText
        }
    }

    @objc private func togglePopover() {
        guard let button = statusItem?.button, let popover = popover else { return }

        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
