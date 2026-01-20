import SwiftUI
import Charts

enum DashboardTab: String, CaseIterable {
    case summary = "Summary"
    case daily = "Daily"
}

struct MenuBarView: View {
    @ObservedObject var stats: StatsParser
    @State private var selectedTab: DashboardTab = .summary

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Tab Picker
            Picker("", selection: $selectedTab) {
                ForEach(DashboardTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.bottom, 16)

            // Content based on selected tab
            if selectedTab == .summary {
                SummaryView(stats: stats)
            } else {
                DailyView(stats: stats)
            }

            Spacer(minLength: 16)

            // Footer
            HStack {
                Button(action: {
                    stats.loadStats()
                }) {
                    Label("Refresh", systemImage: "arrow.clockwise")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)

                Spacer()

                Text(timeAgo(stats.lastUpdated))
                    .font(.caption)
                    .foregroundColor(.secondary.opacity(0.7))

                Spacer()

                Button(action: {
                    NSApplication.shared.terminate(nil)
                }) {
                    Text("Quit")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
            }
            .padding(.top, 12)
        }
        .padding(16)
        .frame(width: 350)
    }

    private func timeAgo(_ date: Date) -> String {
        let seconds = Int(-date.timeIntervalSinceNow)
        if seconds < 60 {
            return "just now"
        } else if seconds < 3600 {
            return "\(seconds / 60)m ago"
        } else {
            return "\(seconds / 3600)h ago"
        }
    }
}

// MARK: - Section Header

struct SectionHeader: View {
    let title: String
    var trailing: String? = nil

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.primary)
            Spacer()
            if let trailing = trailing {
                Text(trailing)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.bottom, 8)
    }
}

// MARK: - Section Divider

struct SectionDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.08))
            .frame(height: 1)
            .padding(.vertical, 14)
    }
}

// MARK: - Summary View

struct SummaryView: View {
    @ObservedObject var stats: StatsParser

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Today Section
            SectionHeader(title: "Today", trailing: timeOfDay())

            StatRow(label: "Cost", value: String(format: "$ %.2f", stats.todayStats.cost), detail: "\(formatTokens(stats.todayStats.inputTokens + stats.todayStats.outputTokens)) tokens")
            StatRow(label: "Messages", value: "\(stats.todayStats.messages)", detail: "\(stats.todayStats.sessions) sessions")

            SectionDivider()

            // Tokens Section
            SectionHeader(title: "Tokens")

            TokenRow(label: "Input", tokens: stats.todayStats.inputTokens, color: .blue)
            TokenRow(label: "Output", tokens: stats.todayStats.outputTokens, color: .green)
            TokenRow(label: "Cache Read", tokens: stats.todayStats.cacheReadTokens, color: .orange)

            SectionDivider()

            // Monthly Section
            SectionHeader(title: "Last 30 Days")

            let monthlyTotal = stats.monthlyStats.reduce(0) { $0 + $1.cost }
            StatRow(label: "Cost", value: String(format: "$ %.2f", monthlyTotal), detail: nil)

            if !stats.monthlyStats.isEmpty && stats.monthlyStats.contains(where: { $0.cost > 0 }) {
                MiniChart(data: stats.monthlyStats)
                    .padding(.top, 8)
            }

            SectionDivider()

            // Models Section
            SectionHeader(title: "Models", trailing: "all time")

            let usedModels = stats.modelStats.filter { $0.totalTokens > 0 || $0.cost > 0 }
            if usedModels.isEmpty {
                Text("No data")
                    .font(.caption)
                    .foregroundColor(.secondary.opacity(0.7))
            } else {
                ForEach(usedModels) { model in
                    ModelRow(model: model)
                }
            }

            SectionDivider()

            // Totals
            HStack(spacing: 0) {
                TotalItem(value: "\(stats.totalMessages)", label: "messages")
                Spacer()
                TotalItem(value: "\(stats.totalSessions)", label: "sessions")
                Spacer()
                TotalItem(value: String(format: "$%.2f", stats.totalCost), label: "total cost")
            }
        }
    }

    private func timeOfDay() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: Date())
    }

    private func formatTokens(_ tokens: Int) -> String {
        if tokens >= 1_000_000 {
            return String(format: "%.1fM", Double(tokens) / 1_000_000)
        } else if tokens >= 1_000 {
            return String(format: "%.1fK", Double(tokens) / 1_000)
        } else {
            return "\(tokens)"
        }
    }
}

// MARK: - Stat Row

struct StatRow: View {
    let label: String
    let value: String
    let detail: String?

    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .medium, design: .rounded))
            if let detail = detail {
                Text("·")
                    .foregroundColor(.secondary.opacity(0.7))
                Text(detail)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 3)
    }
}

// MARK: - Token Row

struct TokenRow: View {
    let label: String
    let tokens: Int
    let color: Color

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Text(formatTokens(tokens))
                .font(.system(size: 12, weight: .medium, design: .monospaced))
        }
        .padding(.vertical, 2)
    }

    private func formatTokens(_ tokens: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: tokens)) ?? "\(tokens)"
    }
}

// MARK: - Model Row

struct ModelRow: View {
    let model: ModelStats

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(modelColor)
                .frame(width: 6, height: 6)
            Text(model.displayName)
                .font(.caption)
                .foregroundColor(.primary)
            Spacer()
            Text(formatTokens(model.totalTokens))
                .font(.caption)
                .foregroundColor(.secondary.opacity(0.7))
            Text(String(format: "$%.2f", model.cost))
                .font(.system(size: 12, weight: .medium, design: .monospaced))
        }
        .padding(.vertical, 2)
    }

    private var modelColor: Color {
        if model.displayName.contains("Opus") { return .purple }
        else if model.displayName.contains("Haiku") { return .cyan }
        else { return .blue }
    }

    private func formatTokens(_ tokens: Int) -> String {
        if tokens >= 1_000_000_000 {
            return String(format: "%.1fB", Double(tokens) / 1_000_000_000)
        } else if tokens >= 1_000_000 {
            return String(format: "%.1fM", Double(tokens) / 1_000_000)
        } else if tokens >= 1_000 {
            return String(format: "%.0fK", Double(tokens) / 1_000)
        } else {
            return "\(tokens)"
        }
    }
}

// MARK: - Mini Chart

struct MiniChart: View {
    let data: [DailyCost]
    @State private var hoveredDay: DailyCost?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Chart(data) { day in
                BarMark(
                    x: .value("Date", day.date, unit: .day),
                    y: .value("Cost", day.cost)
                )
                .foregroundStyle(
                    hoveredDay?.id == day.id
                        ? Color.blue
                        : Color.blue.opacity(0.5)
                )
                .cornerRadius(1)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: 7)) { value in
                    AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                        .font(.system(size: 8))
                }
            }
            .chartYAxis(.hidden)
            .chartOverlay { proxy in
                GeometryReader { _ in
                    Rectangle()
                        .fill(Color.clear)
                        .contentShape(Rectangle())
                        .onContinuousHover { phase in
                            switch phase {
                            case .active(let location):
                                if let date: Date = proxy.value(atX: location.x) {
                                    let calendar = Calendar.current
                                    hoveredDay = data.first { day in
                                        calendar.isDate(day.date, inSameDayAs: date)
                                    }
                                }
                            case .ended:
                                hoveredDay = nil
                            }
                        }
                }
            }
            .frame(height: 60)

            // Tooltip
            if let day = hoveredDay {
                HStack(spacing: 4) {
                    Text(dayString(day.date))
                        .foregroundColor(.secondary)
                    Text(String(format: "$%.2f", day.cost))
                        .fontWeight(.medium)
                }
                .font(.system(size: 11))
            } else {
                Text(" ")
                    .font(.system(size: 11))
            }
        }
    }

    private func dayString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "E, MMM d"
        return formatter.string(from: date)
    }
}

// MARK: - Total Item

struct TotalItem: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .center, spacing: 2) {
            Text(value)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(.secondary.opacity(0.7))
        }
    }
}

// MARK: - Daily View

struct DailyView: View {
    @ObservedObject var stats: StatsParser

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 0) {
                Text("Date")
                    .frame(minWidth: 80, alignment: .leading)
                Spacer()
                Text("Tokens")
                    .frame(width: 60, alignment: .trailing)
                Text("Cost")
                    .frame(width: 55, alignment: .trailing)
            }
            .font(.system(size: 10, weight: .medium))
            .foregroundColor(.secondary.opacity(0.7))
            .padding(.bottom, 8)

            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(height: 1)

            // Scrollable list
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(stats.dailyBreakdown) { day in
                        DailyRow(day: day)
                    }
                }
            }
            .frame(height: 320)

            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(height: 1)

            // Total row
            HStack(spacing: 0) {
                Text("Total")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(minWidth: 80, alignment: .leading)
                Spacer()
                Text(formatTokens(stats.dailyBreakdown.reduce(0) { $0 + $1.inputTokens + $1.outputTokens }))
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .frame(width: 60, alignment: .trailing)
                Text(String(format: "$%.2f", stats.totalCost))
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(.primary)
                    .frame(width: 55, alignment: .trailing)
            }
            .padding(.top, 10)
        }
    }

    private func formatTokens(_ tokens: Int) -> String {
        if tokens >= 1_000_000 {
            return String(format: "%.1fM", Double(tokens) / 1_000_000)
        } else if tokens >= 1_000 {
            return String(format: "%.0fK", Double(tokens) / 1_000)
        } else {
            return "\(tokens)"
        }
    }
}

struct DailyRow: View {
    let day: DailyBreakdown
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text(formatDate(day.date))
                    .font(.system(size: 12, weight: .medium))

                // Model badges
                HStack(spacing: 4) {
                    ForEach(day.models, id: \.self) { model in
                        ModelBadge(name: model)
                    }
                }
            }
            .frame(minWidth: 80, alignment: .leading)

            Spacer()

            Text(formatTokens(day.inputTokens + day.outputTokens))
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 60, alignment: .trailing)

            Text(String(format: "$%.2f", day.cost))
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .frame(width: 55, alignment: .trailing)
        }
        .padding(.vertical, 8)
        .background(isHovered ? Color.primary.opacity(0.04) : Color.clear)
        .onHover { hovering in
            isHovered = hovering
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "Today"
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            formatter.dateFormat = "MMM d"
            return formatter.string(from: date)
        }
    }

    private func formatTokens(_ tokens: Int) -> String {
        if tokens >= 1_000_000 {
            return String(format: "%.1fM", Double(tokens) / 1_000_000)
        } else if tokens >= 1_000 {
            return String(format: "%.0fK", Double(tokens) / 1_000)
        } else {
            return "\(tokens)"
        }
    }
}

struct ModelBadge: View {
    let name: String

    var body: some View {
        Text(shortName)
            .font(.system(size: 9, weight: .medium))
            .foregroundColor(.primary.opacity(0.7))
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Color.primary.opacity(0.08))
            .cornerRadius(4)
    }

    private var shortName: String {
        // Extract version number (e.g., "4-5" -> "4.5", "3-5" -> "3.5")
        let version = extractVersion(from: name)

        if name.lowercased().contains("opus") {
            return version.isEmpty ? "Opus" : "Opus \(version)"
        } else if name.lowercased().contains("sonnet") {
            return version.isEmpty ? "Sonnet" : "Sonnet \(version)"
        } else if name.lowercased().contains("haiku") {
            return version.isEmpty ? "Haiku" : "Haiku \(version)"
        } else {
            return String(name.prefix(8))
        }
    }

    private func extractVersion(from name: String) -> String {
        // Match patterns like "4-5", "3-5", "3-0" and convert to "4.5", "3.5", "3.0"
        let pattern = #"(\d+)-(\d+)"#
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)),
           let majorRange = Range(match.range(at: 1), in: name),
           let minorRange = Range(match.range(at: 2), in: name) {
            return "\(name[majorRange]).\(name[minorRange])"
        }
        return ""
    }
}
