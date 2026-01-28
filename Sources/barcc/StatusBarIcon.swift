import AppKit

// Helper for creating dynamic status bar icons
struct StatusBarIcon {
    static func createIcon(for cost: Double, limit: Double = 100) -> NSImage? {
        let config = NSImage.SymbolConfiguration(pointSize: 16, weight: .medium)

        let color = color(for: cost, limit: limit)

        let colorConfig = NSImage.SymbolConfiguration(paletteColors: [color])
        let combinedConfig = config.applying(colorConfig)

        return NSImage(systemSymbolName: "dollarsign.circle.fill", accessibilityDescription: "Usage")?
            .withSymbolConfiguration(combinedConfig)
    }

    static func createChartIcon(for cost: Double, limit: Double = 100) -> NSImage? {
        let config = NSImage.SymbolConfiguration(pointSize: 16, weight: .medium)

        let color = color(for: cost, limit: limit)

        let colorConfig = NSImage.SymbolConfiguration(paletteColors: [color])
        let combinedConfig = config.applying(colorConfig)

        return NSImage(systemSymbolName: "chart.bar.fill", accessibilityDescription: "Usage")?
            .withSymbolConfiguration(combinedConfig)
    }

    static func color(for cost: Double, limit: Double) -> NSColor {
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
}
