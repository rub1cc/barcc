import Foundation

enum StatsFormatting {
    private static let decimalFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        return formatter
    }()

    private static func formatCompact(_ value: Double, suffix: String, decimals: Int = 1) -> String {
        let formatted = String(format: "%.\(decimals)f", value)
        let trimmed = formatted.hasSuffix(".0") ? String(formatted.dropLast(2)) : formatted
        return "\(trimmed)\(suffix)"
    }

    static func formatCount(_ value: Int) -> String {
        decimalFormatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    static func formatTokensFull(_ tokens: Int) -> String {
        formatCount(tokens)
    }

    static func formatTokensCompact(_ tokens: Int) -> String {
        if tokens >= 1_000_000_000 {
            return formatCompact(Double(tokens) / 1_000_000_000, suffix: "B")
        } else if tokens >= 1_000_000 {
            return formatCompact(Double(tokens) / 1_000_000, suffix: "M")
        } else if tokens >= 1_000 {
            return formatCompact(Double(tokens) / 1_000, suffix: "K")
        } else {
            return formatTokensFull(tokens)
        }
    }

    static func formatCost(_ cost: Double) -> String {
        String(format: "$%.2f", cost)
    }

    static func formatDuration(_ duration: TimeInterval) -> String {
        let totalSeconds = max(Int(duration.rounded()), 0)
        if totalSeconds < 60 {
            return "\(totalSeconds)s"
        }

        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        if minutes < 60 {
            if seconds == 0 {
                return "\(minutes)m"
            }
            return "\(minutes)m \(seconds)s"
        }

        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        if remainingMinutes == 0 {
            return "\(hours)h"
        }
        return "\(hours)h \(remainingMinutes)m"
    }

    static func formatPercent(_ value: Double, includeSign: Bool = false, maximumFractionDigits: Int = 0) -> String {
        let percentValue = abs(value * 100)
        let numberString: String
        if maximumFractionDigits == 0 {
            numberString = String(format: "%.0f", percentValue)
        } else {
            numberString = String(format: "%.\(maximumFractionDigits)f", percentValue)
        }

        let sign: String
        if includeSign {
            if value > 0 {
                sign = "+"
            } else if value < 0 {
                sign = "-"
            } else {
                sign = ""
            }
        } else {
            sign = ""
        }

        return "\(sign)\(numberString)%"
    }
}
