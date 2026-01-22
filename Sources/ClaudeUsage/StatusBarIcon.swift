import AppKit

// Helper for creating dynamic status bar icons
struct StatusBarIcon {
    static func createIcon(for cost: Double) -> NSImage? {
        let config = NSImage.SymbolConfiguration(pointSize: 16, weight: .medium)

        // Color based on daily spend
        let color: NSColor
        if cost < 10.0 {
            color = .systemGreen
        } else if cost < 20.0 {
            color = .systemYellow
        } else if cost < 50.0 {
            color = .systemOrange
        } else {
            color = .systemRed
        }

        let colorConfig = NSImage.SymbolConfiguration(paletteColors: [color])
        let combinedConfig = config.applying(colorConfig)

        return NSImage(systemSymbolName: "dollarsign.circle.fill", accessibilityDescription: "Usage")?
            .withSymbolConfiguration(combinedConfig)
    }

    static func createChartIcon(for cost: Double) -> NSImage? {
        let config = NSImage.SymbolConfiguration(pointSize: 16, weight: .medium)

        let color: NSColor
        if cost < 10.0 {
            color = .systemGreen
        } else if cost < 20.0 {
            color = .systemYellow
        } else if cost < 50.0 {
            color = .systemOrange
        } else {
            color = .systemRed
        }

        let colorConfig = NSImage.SymbolConfiguration(paletteColors: [color])
        let combinedConfig = config.applying(colorConfig)

        return NSImage(systemSymbolName: "chart.bar.fill", accessibilityDescription: "Usage")?
            .withSymbolConfiguration(combinedConfig)
    }
}
