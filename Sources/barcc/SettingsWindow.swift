import SwiftUI
import AppKit
import Foundation

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
            VStack(alignment: .leading, spacing: 20) {
                SettingsGroup(title: "General") {
                    SettingsRow(
                        title: "Token totals",
                        subtitle: "Include cache tokens in totals and charts."
                    ) {
                        Toggle("", isOn: $stats.includeCacheTokens)
                            .labelsHidden()
                            .toggleStyle(.switch)
                    }
                    SettingsGroupDivider()
                    SettingsRow(
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
                    SettingsGroupDivider()
                    SettingsRow(title: "App version") {
                        Text(appVersion)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                }

                SettingsGroup(title: "Status Bar") {
                    SettingsRow(
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

                VStack(alignment: .leading, spacing: 8) {
                    SettingsGroup(title: "Usage") {
                        SettingsRow(
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
                    }

                    Text("Colors: <25% green, <50% yellow, <75% orange, >=75% red")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
            .padding(24)
        }
        .background(Color(NSColor.windowBackgroundColor))
        .frame(minWidth: 700, minHeight: 520)
    }

    private var limitBinding: Binding<Double> {
        Binding(
            get: { stats.dailySpendLimit },
            set: { stats.dailySpendLimit = max(1, $0) }
        )
    }

    private var appVersion: String {
        let shortVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String

        if let shortVersion, !shortVersion.isEmpty {
            return shortVersion
        }

        return "Unknown"
    }

    private func adjustLimit(by delta: Double) {
        let next = min(max(limitRange.lowerBound, stats.dailySpendLimit + delta), limitRange.upperBound)
        if next != stats.dailySpendLimit {
            stats.dailySpendLimit = next
        }
    }
}

struct SettingsGroup<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.primary)

            VStack(spacing: 0) {
                content
            }
            .background(Color(NSColor.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
        }
    }
}

struct SettingsRow<Content: View>: View {
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
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}

struct SettingsGroupDivider: View {
    var body: some View {
        Divider()
            .padding(.leading, 12)
    }
}
