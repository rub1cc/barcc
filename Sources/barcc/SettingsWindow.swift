import SwiftUI
import AppKit

enum SettingsSection: String, CaseIterable, Identifiable {
    case general = "General"
    case statusBar = "Status Bar"
    case usage = "Usage"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .general:
            return "slider.horizontal.3"
        case .statusBar:
            return "menubar.rectangle"
        case .usage:
            return "gauge"
        }
    }
}

final class SettingsWindowController: NSObject, ObservableObject, NSWindowDelegate {
    private var window: NSWindow?

    func show(stats: StatsParser) {
        if let window = window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let view = SettingsWindowView(stats: stats)
        let hostingController = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Settings"
        window.setContentSize(NSSize(width: 700, height: 520))
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        window.center()
        window.delegate = self
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
    }
}

struct SettingsWindowView: View {
    @ObservedObject var stats: StatsParser
    @State private var selection: SettingsSection = .general

    var body: some View {
        NavigationSplitView {
            List(SettingsSection.allCases, selection: $selection) { section in
                Label(section.rawValue, systemImage: section.systemImage)
                    .font(.system(size: 12, weight: .medium))
                    .tag(section)
            }
            .listStyle(.sidebar)
            .frame(minWidth: 180)
        } detail: {
            SettingsDetailView(stats: stats, section: selection)
        }
        .navigationTitle("Settings")
        .frame(minWidth: 700, minHeight: 520)
    }
}

struct SettingsDetailView: View {
    @ObservedObject var stats: StatsParser
    let section: SettingsSection
    @FocusState private var isLimitFieldFocused: Bool

    private let intervalOptions: [(label: String, value: TimeInterval)] = [
        ("15s", 15),
        ("30s", 30),
        ("1m", 60),
        ("2m", 120),
        ("5m", 300),
    ]
    private let limitRange: ClosedRange<Double> = 1...1000
    private let limitStep: Double = 1

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(section.rawValue)
                    .font(.system(size: 18, weight: .semibold))

                switch section {
                case .general:
                    generalSection
                case .statusBar:
                    statusBarSection
                case .usage:
                    usageSection
                }
            }
            .padding(24)
        }
        .background(Color(NSColor.windowBackgroundColor))
    }

    private var generalSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsCard(
                title: "Token totals",
                subtitle: "Include cache tokens in totals and charts."
            ) {
                Toggle("", isOn: $stats.includeCacheTokens)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }

            SettingsCard(
                title: "Refresh interval",
                subtitle: "How often usage data refreshes in the background."
            ) {
                Picker("", selection: $stats.refreshInterval) {
                    ForEach(intervalOptions, id: \.value) { option in
                        Text(option.label).tag(option.value)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 140, alignment: .trailing)
            }
        }
    }

    private var statusBarSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsCard(
                title: "Status bar display",
                subtitle: "Choose what appears next to the icon."
            ) {
                Picker("", selection: $stats.statusBarMode) {
                    ForEach(StatusBarDisplayMode.allCases) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 180, alignment: .trailing)
            }
        }
    }

    private var usageSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsCard(
                title: "Daily limit",
                subtitle: "Sets the color of the status icon by spend."
            ) {
                HStack(spacing: 6) {
                    Text("$")
                        .foregroundColor(.secondary)
                    TextField("", value: limitBinding, format: .number)
                        .frame(width: 80)
                        .multilineTextAlignment(.trailing)
                        .focused($isLimitFieldFocused)
                        .onKeyPress(.upArrow) {
                            adjustLimit(by: limitStep)
                            return .handled
                        }
                        .onKeyPress(.downArrow) {
                            adjustLimit(by: -limitStep)
                            return .handled
                        }
                    Stepper("", value: limitBinding, in: limitRange, step: limitStep)
                        .labelsHidden()
                }
            }

            Text("Colors: <25% green, <50% yellow, <75% orange, >=75% red")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
    }

    private var limitBinding: Binding<Double> {
        Binding(
            get: { stats.dailySpendLimit },
            set: { stats.dailySpendLimit = max(1, $0) }
        )
    }

    private func adjustLimit(by delta: Double) {
        let next = min(max(limitRange.lowerBound, stats.dailySpendLimit + delta), limitRange.upperBound)
        if next != stats.dailySpendLimit {
            stats.dailySpendLimit = next
        }
    }
}

struct SettingsCard<Content: View>: View {
    let title: String
    let subtitle: String?
    let content: Content

    init(title: String, subtitle: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.primary)
                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
            content
        }
        .padding(12)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}
