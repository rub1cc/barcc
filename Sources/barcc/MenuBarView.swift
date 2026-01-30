import SwiftUI
import Charts
import UniformTypeIdentifiers

enum DashboardTab: String, CaseIterable {
    case summary = "Summary"
    case daily = "Daily"
}

// MARK: - Card Section

struct CardSection<Content: View>: View {
    let content: Content
    private let contentPadding: CGFloat

    init(padding: CGFloat = 12, @ViewBuilder content: () -> Content) {
        self.content = content()
        self.contentPadding = padding
    }

    var body: some View {
        content
            .padding(contentPadding)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

struct MenuBarView: View {
    @ObservedObject var stats: StatsParser
    @State private var selectedTab: DashboardTab = .summary
    @State private var spinTrigger: Int = 0
    @State private var showSettings: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Tab Picker
            Picker("", selection: $selectedTab) {
                ForEach(DashboardTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            // Content based on selected tab
            if selectedTab == .summary {
                SummaryView(stats: stats)
                Spacer(minLength: 8)
            } else {
                DailyView(stats: stats)
                    .frame(maxHeight: .infinity)
            }

            // Footer
            HStack {
                Button(action: {
                    spinTrigger += 1
                    stats.loadStats()
                }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12))
                        .rotationEffect(.degrees(Double(spinTrigger) * 360))
                        .animation(.easeInOut(duration: 0.5), value: spinTrigger)
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                .help("Refresh")
                .disabled(stats.isLoading)

                Button(action: {
                    saveScreenshot(stats: stats)
                }) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                .help("Save Screenshot")

                Button(action: {
                    showSettings.toggle()
                }) {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                .help("Settings")
                .popover(isPresented: $showSettings, arrowEdge: .bottom) {
                    SettingsPanel(stats: stats)
                }

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
            .padding(.top, 4)
        }
        .padding(14)
        .frame(width: 350)
        .background(VisualEffectBackground())
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

    @MainActor
    private func saveScreenshot(stats: StatsParser) {
        let view = ShareableStatsView(stats: stats)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2.0

        guard let nsImage = renderer.nsImage else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "barcc-\(dateString()).png"

        panel.begin { response in
            if response == .OK, let url = panel.url {
                guard let tiffData = nsImage.tiffRepresentation,
                      let bitmap = NSBitmapImageRep(data: tiffData),
                      let pngData = bitmap.representation(using: .png, properties: [:]) else { return }
                try? pngData.write(to: url)
            }
        }
    }

    private func dateString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }
}

// MARK: - Settings Panel

struct SettingsPanel: View {
    @ObservedObject var stats: StatsParser

    private let intervalOptions: [(label: String, value: TimeInterval)] = [
        ("15s", 15),
        ("30s", 30),
        ("1m", 60),
        ("2m", 120),
        ("5m", 300),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Settings")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)

            HStack {
                Text("Status bar")
                    .font(.system(size: 11, weight: .medium))
                Spacer()
                Picker("", selection: $stats.statusBarMode) {
                    ForEach(StatusBarDisplayMode.allCases) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 160, alignment: .trailing)
            }

            HStack {
                Text("Refresh")
                    .font(.system(size: 11, weight: .medium))
                Spacer()
                Picker("", selection: $stats.refreshInterval) {
                    ForEach(intervalOptions, id: \.value) { option in
                        Text(option.label).tag(option.value)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 120, alignment: .trailing)
            }

            Toggle("Include cache tokens", isOn: $stats.includeCacheTokens)
                .font(.system(size: 11, weight: .medium))
                .toggleStyle(.switch)

            Divider()

            HStack {
                Text("Daily limit")
                    .font(.system(size: 11, weight: .medium))
                Spacer()
                HStack(spacing: 6) {
                    Text("$")
                        .foregroundColor(.secondary)
                    TextField("", value: limitBinding, format: .number)
                        .frame(width: 70)
                        .multilineTextAlignment(.trailing)
                    Stepper("", value: limitBinding, in: 1...1000, step: 5)
                        .labelsHidden()
                }
            }

            Text("Colors: <25% green, <50% yellow, <75% orange, ≥75% red")
                .font(.system(size: 9))
                .foregroundColor(.secondary)
        }
        .padding(12)
        .frame(width: 280)
    }

    private var limitBinding: Binding<Double> {
        Binding(
            get: { stats.dailySpendLimit },
            set: { stats.dailySpendLimit = max(1, $0) }
        )
    }
}

// MARK: - Visual Effect Background

struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        view.alphaValue = 0.7
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

// MARK: - Section Header

struct SectionHeader: View {
    let title: String
    var trailing: String? = nil

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)
            Spacer()
            if let trailing = trailing {
                Text(trailing)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary.opacity(0.7))
            }
        }
        .padding(.bottom, 6)
    }
}

// MARK: - Summary View

struct SummaryView: View {
    @ObservedObject var stats: StatsParser

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CardSection {
                TodayOverviewCard(stats: stats)
            }

            CardSection {
                TrendOverviewCard(stats: stats)
            }

            CardSection {
                ModelSummaryCard(stats: stats)
            }

            CardSection {
                TotalsSummaryCard(stats: stats)
            }
        }
    }
}

// MARK: - Today Overview

struct TodayOverviewCard: View {
    @ObservedObject var stats: StatsParser

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Today", trailing: timeOfDay())

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(StatsFormatting.formatCost(stats.todayStats.cost))
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                TrendBadge(deltaPercent: stats.todayCostDeltaPercent)
            }

            HStack(spacing: 8) {
                StatTile(title: "Tokens", value: StatsFormatting.formatTokensCompact(stats.todayDisplayTokens))
                StatTile(title: "Messages", value: StatsFormatting.formatCount(stats.todayStats.messages))
                StatTile(title: "Sessions", value: StatsFormatting.formatCount(stats.todayStats.sessions))
            }

            Divider()
                .padding(.vertical, 6)

            TokenRow(label: "Input", tokens: stats.todayStats.inputTokens, color: .blue)
            TokenRow(label: "Output", tokens: stats.todayStats.outputTokens, color: .green)
            if stats.includeCacheTokens {
                TokenRow(label: "Cache Read", tokens: stats.todayStats.cacheReadTokens, color: .orange)
                if stats.todayStats.cacheCreationTokens > 0 {
                    TokenRow(label: "Cache Write", tokens: stats.todayStats.cacheCreationTokens, color: .mint)
                }
            }
        }
    }

    private func timeOfDay() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: Date())
    }
}

// MARK: - Trend Overview

struct TrendOverviewCard: View {
    @ObservedObject var stats: StatsParser

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Last 7 Days", trailing: StatsFormatting.formatCost(stats.weekTotalCost))

            let hasData = stats.weeklyStats.contains { $0.cost > 0 || $0.tokens > 0 }
            if hasData {
                MiniChart(data: stats.weeklyStats, labelStrideDays: 2)

                SummaryRow(label: "Avg/day", value: StatsFormatting.formatCost(stats.weekAvgCost))
                SummaryRow(label: "30d total", value: StatsFormatting.formatCost(monthlyTotal))
            } else {
                Text("No data")
                    .font(.caption)
                    .foregroundColor(.secondary.opacity(0.7))
            }
        }
    }

    private var monthlyTotal: Double {
        stats.monthlyStats.reduce(0) { $0 + $1.cost }
    }
}

// MARK: - Model Overview

struct ModelSummaryCard: View {
    @ObservedObject var stats: StatsParser

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader(title: "Top Models", trailing: "all time")

            let totalCost = stats.totalCost
            let topModels = stats.modelStats.filter { $0.cost > 0 }.prefix(3)

            if topModels.isEmpty {
                Text("No data")
                    .font(.caption)
                    .foregroundColor(.secondary.opacity(0.7))
            } else {
                ForEach(Array(topModels)) { model in
                    let share = totalCost > 0 ? model.cost / totalCost : 0
                    ModelShareRow(model: model, share: share)
                }
            }
        }
    }
}

// MARK: - Totals Overview

struct TotalsSummaryCard: View {
    @ObservedObject var stats: StatsParser

    var body: some View {
        HStack(spacing: 0) {
            TotalItem(value: StatsFormatting.formatCount(stats.totalMessages), label: "messages")
            Spacer()
            TotalItem(value: StatsFormatting.formatCount(stats.totalSessions), label: "sessions")
            Spacer()
            TotalItem(value: StatsFormatting.formatCost(stats.totalCost), label: "total")
        }
    }
}

// MARK: - Summary Helpers

struct TrendBadge: View {
    let deltaPercent: Double?

    var body: some View {
        Text(badgeText)
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(badgeColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(badgeColor.opacity(0.12))
            .clipShape(Capsule())
    }

    private var badgeText: String {
        if let percent = deltaPercent {
            return "\(StatsFormatting.formatPercent(percent, includeSign: true)) vs yesterday"
        }
        return "No prior day"
    }

    private var badgeColor: Color {
        guard let percent = deltaPercent else { return .secondary }
        if percent > 0 {
            return .green
        }
        if percent < 0 {
            return .red
        }
        return .secondary
    }
}

struct StatTile: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .monospacedDigit()
            Text(title)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Color.primary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct SummaryRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
        }
        .padding(.vertical, 2)
    }
}

struct ModelShareRow: View {
    let model: ModelStats
    let share: Double

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(modelColor)
                .frame(width: 6, height: 6)
            Text(model.displayName)
                .font(.caption)
                .foregroundColor(.primary)
            Spacer()
            Text(StatsFormatting.formatPercent(share, maximumFractionDigits: 0))
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(.secondary)
            Text(StatsFormatting.formatCost(model.cost))
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
        }
        .padding(.vertical, 2)
    }

    private var modelColor: Color {
        if model.displayName.contains("Opus") { return .orange }
        if model.displayName.contains("Haiku") { return .teal }
        return .blue
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
            Text(StatsFormatting.formatTokensFull(tokens))
                .font(.system(size: 12, weight: .medium, design: .monospaced))
        }
        .padding(.vertical, 2)
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
            Text(StatsFormatting.formatTokensCompact(model.totalTokens))
                .font(.caption)
                .foregroundColor(.secondary.opacity(0.7))
            Text(StatsFormatting.formatCost(model.cost))
                .font(.system(size: 12, weight: .medium, design: .monospaced))
        }
        .padding(.vertical, 2)
    }

    private var modelColor: Color {
        if model.displayName.contains("Opus") { return .purple }
        else if model.displayName.contains("Haiku") { return .cyan }
        else { return .blue }
    }
}

// MARK: - Mini Chart

struct MiniChart: View {
    let data: [DailyCost]
    var labelStrideDays: Int = 7
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
                AxisMarks(values: .stride(by: .day, count: labelStrideDays)) { value in
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
                    Text(StatsFormatting.formatCost(day.cost))
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
        VStack(alignment: .leading, spacing: 10) {
            // Daily list card
            CardSection(padding: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    // Header
                    HStack(spacing: 0) {
                        Text("Date")
                            .frame(minWidth: 80, alignment: .leading)
                        Spacer()
                        Text("Tokens")
                            .frame(width: 60, alignment: .trailing)
                            .help(stats.includeCacheTokens ? "Includes cache tokens" : "Excludes cache tokens")
                        Text("Cost")
                            .frame(width: 55, alignment: .trailing)
                    }
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary.opacity(0.7))
                    .padding(.top, 12)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)

                    Divider()
                        .padding(.horizontal, 12)

                    // Scrollable list
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(stats.dailyBreakdown) { day in
                                DailyRow(day: day, displayTokens: stats.displayTokens(for: day))
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.bottom, 12)
                    }
                    .frame(maxHeight: .infinity)
                }
                .frame(maxHeight: .infinity, alignment: .top)
            }
            .frame(maxHeight: .infinity)

            // Total card
            CardSection {
                HStack(spacing: 0) {
                    Text("Total")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(minWidth: 80, alignment: .leading)
                    Spacer()
                    Text(StatsFormatting.formatTokensCompact(stats.dailyBreakdown.reduce(0) { $0 + stats.displayTokens(for: $1) }))
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .frame(width: 60, alignment: .trailing)
                    Text(StatsFormatting.formatCost(stats.totalCost))
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundColor(.primary)
                        .frame(width: 55, alignment: .trailing)
                }
            }
        }
    }
}

struct DailyRow: View {
    let day: DailyBreakdown
    let displayTokens: Int
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

            Text(formatTokens(displayTokens))
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 60, alignment: .trailing)

            Text(StatsFormatting.formatCost(day.cost))
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .frame(width: 55, alignment: .trailing)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isHovered ? Color.primary.opacity(0.06) : Color.clear)
        )
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
        StatsFormatting.formatTokensCompact(tokens)
    }
}

// MARK: - Shareable Stats View (for screenshot)

struct ShareableStatsView: View {
    @ObservedObject var stats: StatsParser

    private let cardBackground = Color.primary.opacity(0.06)

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Text("barcc")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                Spacer()
                Text(formattedDate())
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            }

            // Today stats - full width
            VStack(alignment: .leading, spacing: 12) {
                Text("TODAY")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                    .tracking(1)

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(StatsFormatting.formatCost(stats.todayStats.cost))
                        .font(.system(size: 42, weight: .bold, design: .rounded))
                    Text("spent")
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)
                }

                HStack(spacing: 0) {
                    StatBubble(value: StatsFormatting.formatCount(stats.todayStats.messages), label: "messages")
                    Spacer()
                    StatBubble(value: StatsFormatting.formatCount(stats.todayStats.sessions), label: "sessions")
                    Spacer()
                    StatBubble(value: StatsFormatting.formatTokensCompact(stats.todayDisplayTokens), label: "tokens")
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            // Tokens breakdown - equal width cards
            HStack(spacing: 12) {
                TokenBubble(label: "Input", tokens: stats.todayStats.inputTokens, color: .blue, background: cardBackground)
                TokenBubble(label: "Output", tokens: stats.todayStats.outputTokens, color: .green, background: cardBackground)
                TokenBubble(label: "Cache", tokens: stats.todayStats.cacheReadTokens, color: .orange, background: cardBackground)
            }

            // Footer
            HStack {
                Spacer()
                Text("generated with barcc")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary.opacity(0.5))
            }
        }
        .padding(28)
        .frame(width: 520)
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func formattedDate() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter.string(from: Date())
    }

}

struct StatBubble: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 20, weight: .semibold, design: .rounded))
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
    }
}

struct TokenBubble: View {
    let label: String
    let tokens: Int
    let color: Color
    let background: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
            }
            Text(formatTokens(tokens))
                .font(.system(size: 15, weight: .semibold, design: .monospaced))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(background)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func formatTokens(_ tokens: Int) -> String {
        StatsFormatting.formatTokensFull(tokens)
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
