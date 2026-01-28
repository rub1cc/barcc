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

        statsParser?.$statusBarMode
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateStatusButton()
            }
            .store(in: &cancellables)

        statsParser?.$dailySpendLimit
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateStatusButton()
            }
            .store(in: &cancellables)

        statsParser?.$includeCacheTokens
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateStatusButton()
            }
            .store(in: &cancellables)
    }

    private func updateStatusButton() {
        guard let button = statusItem?.button, let stats = statsParser else { return }

        let cost = stats.todayStats.cost
        let costText = cost > 0 ? StatsFormatting.formatCost(cost) : "$0"
        let tokensText = "\(StatsFormatting.formatTokensCompact(stats.todayDisplayTokens)) tok"

        // Create attributed string with icon and cost
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)

        // Color based on daily spend
        let color = statusColor(for: cost, limit: stats.dailySpendLimit)

        let colorConfig = NSImage.SymbolConfiguration(paletteColors: [color])
        let combinedConfig = config.applying(colorConfig)

        let titleText: String
        switch stats.statusBarMode {
        case .iconOnly:
            titleText = ""
        case .iconAndCost:
            titleText = costText
        case .iconAndTokens:
            titleText = tokensText
        case .compact:
            titleText = "\(costText) \(tokensText)"
        }

        if let icon = NSImage(systemSymbolName: "dollarsign.circle.fill", accessibilityDescription: "Usage")?.withSymbolConfiguration(combinedConfig) {
            let attachment = NSTextAttachment()
            attachment.image = icon

            let attrString = NSMutableAttributedString(attachment: attachment)
            if !titleText.isEmpty {
                attrString.append(NSAttributedString(string: " \(titleText)", attributes: [
                    .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
                    .foregroundColor: NSColor.labelColor
                ]))
            }

            button.attributedTitle = attrString
            button.image = nil
        } else {
            button.title = titleText.isEmpty ? costText : titleText
        }
    }

    private func statusColor(for cost: Double, limit: Double) -> NSColor {
        let safeLimit = max(limit, 1)
        let percent = cost / safeLimit

        if percent < 0.25 {
            return .systemGreen
        } else if percent < 0.5 {
            return .systemYellow
        } else if percent < 0.75 {
            return .systemOrange
        }
        return .systemRed
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
