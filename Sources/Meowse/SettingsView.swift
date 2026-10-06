import SwiftUI
import MeowseCore


private extension View {
    func settingsTab() -> some View {
        formStyle(.grouped)
            .frame(width: 480)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private func caption(_ text: String) -> some View {
    Text(text).font(.caption).foregroundStyle(.secondary)
}

// MARK: - General

struct GeneralTab: View {
    @ObservedObject var store: SettingsStore
    let requestPermission: () -> Void

    var body: some View {
        Form {
            Section {
                LabeledContent("Accessibility") {
                    if store.accessibilityTrusted {
                        Label("Allowed", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Button("Allow Access…", action: requestPermission)
                    }
                }
                LabeledContent("Scroll engine") {
                    switch store.engineStatus {
                    case .active:
                        Label("Running", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    case .failed:
                        Label("Couldn’t start", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    case .off:
                        Text(store.accessibilityTrusted ? "Off (nothing enabled)" : "Waiting for access")
                            .foregroundStyle(.secondary)
                    }
                }
            } footer: {
                if !store.accessibilityTrusted {
                    caption("Turn on Meowse in System Settings → Privacy & Security → Accessibility. It takes effect within a few seconds.")
                }
            }

            Section {
                Toggle("Launch at login", isOn: Binding(
                    get: { store.launchAtLogin },
                    set: { store.setLaunchAtLogin($0) }
                ))
                Toggle("Show in menu bar", isOn: $store.settings.showMenuBarIcon)
            } footer: {
                if !store.settings.showMenuBarIcon {
                    caption("Open Meowse again from Finder or Spotlight to return to Settings.")
                }
            }

            Section {
                HStack {
                    Text("Meowse \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Restore Defaults") {
                        let keepIcon = store.settings.showMenuBarIcon
                        store.settings = Settings()
                        store.settings.showMenuBarIcon = keepIcon
                    }
                }
            }
        }
        .settingsTab()
    }
}

// MARK: - Scrolling

struct ScrollingTab: View {
    @ObservedObject var store: SettingsStore

    var body: some View {
        Form {
            Section {
                Toggle("Enable scroll enhancements", isOn: $store.settings.enabled)
            } footer: {
                caption("Only scroll wheels are affected. Trackpads and the Magic Mouse are left alone.")
            }

            Section("Smoothing") {
                Toggle("Smooth scrolling", isOn: $store.settings.smooth)
                Group {
                    Toggle("Vertical", isOn: $store.settings.smoothVertical)
                    Toggle("Horizontal", isOn: $store.settings.smoothHorizontal)
                    SliderRow("Scroll distance", value: $store.settings.notchDistance, range: Settings.notchDistanceRange, format: "%.0f pt")
                    SliderRow("Smoothness", value: $store.settings.glideTime, range: Settings.glideTimeRange, format: "%.2f s")
                    Toggle("Trackpad-style momentum", isOn: $store.settings.trackpadPhases)
                }
                .disabled(!store.settings.smooth)
            }

            Section("Direction") {
                Toggle("Reverse vertical", isOn: $store.settings.reverseVertical)
                Toggle("Reverse horizontal", isOn: $store.settings.reverseHorizontal)
            }
        }
        .disabled(!store.settings.enabled)
        .settingsTab()
    }
}

// MARK: - Hotkeys

struct HotkeysTab: View {
    @ObservedObject var store: SettingsStore

    private static let choices: [Hotkey] =
        [.none] + ModifierKey.allCases.map { .modifier($0) } + [.mouseButton(2), .mouseButton(3), .mouseButton(4)]

    var body: some View {
        Form {
            Section {
                picker("Scroll faster", $store.settings.fasterKey)
                picker("Scroll sideways", $store.settings.sidewaysKey)
                picker("Scroll without smoothing", $store.settings.unsmoothedKey)
                SliderRow("Faster by", value: $store.settings.fasterFactor, range: Settings.fasterFactorRange, format: "%.1f×")
            } header: {
                Text("Hold while scrolling")
            }

            Section {
                Toggle("Stop glide on click", isOn: $store.settings.stopOnClick)
            }
        }
        .disabled(!store.settings.enabled)
        .settingsTab()
    }

    private func picker(_ title: String, _ selection: Binding<Hotkey>) -> some View {
        Picker(title, selection: selection) {
            ForEach(Self.choices, id: \.self) { Text($0.displayName).tag($0) }
        }
    }
}

// MARK: - Awake

struct AwakeTab: View {
    @ObservedObject var store: SettingsStore
    @ObservedObject var awake: AwakeController

    var body: some View {
        Form {
            Section {
                Toggle("Keep awake now", isOn: Binding(
                    get: { awake.isAwake },
                    set: { $0 ? awake.startAwake(duration: store.settings.awakeDuration,
                                                 allowDisplaySleep: store.settings.awakeAllowDisplaySleep)
                              : awake.stopAwake() }
                ))
                Picker("Duration", selection: $store.settings.awakeDuration) {
                    ForEach(Awake.durations, id: \.self) { Text(Awake.durationLabel($0)).tag($0) }
                }
                Toggle("Allow display to sleep", isOn: $store.settings.awakeAllowDisplaySleep)
            } header: {
                Text("Keep Awake")
            } footer: {
                caption("Timed sessions end on schedule even if Meowse quits. Closing the lid still puts the Mac to sleep.")
            }

            Section {
                Toggle("Wiggle cursor now", isOn: Binding(
                    get: { awake.isWiggling },
                    set: { $0 ? awake.startWiggle(interval: store.settings.wiggleInterval) : awake.stopWiggle() }
                ))
                Picker("When idle for", selection: $store.settings.wiggleInterval) {
                    ForEach(Awake.wiggleIntervals, id: \.self) { Text(Awake.intervalLabel($0)).tag($0) }
                }
            } header: {
                Text("Wiggle Cursor")
            } footer: {
                caption("Moves the pointer by one point and back after you’ve been idle, so you stay active in chat apps and the display stays on. Paused while the screen is locked or asleep.")
            }
        }
        .settingsTab()
    }
}

// MARK: - Updates

struct UpdatesTab: View {
    @ObservedObject var store: SettingsStore
    @ObservedObject var updater: Updater

    var body: some View {
        Form {
            Section {
                LabeledContent("Installed version", value: updater.currentVersion.description)
                LabeledContent("Status") { status }
                HStack {
                    if let checked = updater.lastChecked {
                        Text("Last checked \(checked.formatted(.relative(presentation: .named)))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Check Now") { updater.check(userInitiated: true) }
                        .disabled(updater.state == .checking || updater.state == .installing)
                }
            }

            if case .available(let version, let notes) = updater.state {
                Section("Meowse \(version)") {
                    if !notes.isEmpty {
                        Text(Self.markdown(notes))
                            .font(.callout)
                            .lineLimit(10)
                            .textSelection(.enabled)
                    }
                    HStack {
                        if let page = updater.releasePage {
                            Link("Release Notes", destination: page)
                        }
                        Spacer()
                        Button("Install and Relaunch") { updater.install() }
                            .keyboardShortcut(.defaultAction)
                    }
                }
            }

            Section {
                Toggle("Check for updates automatically", isOn: $store.settings.checkForUpdates)
            } footer: {
                caption("Checks GitHub at most once a day. This is the only network request Meowse makes. Updates are verified against the developer’s signature before installing.")
            }
        }
        .settingsTab()
    }

    /// Release notes are Markdown; render bold, italics, code and links, keeping line breaks.
    private static func markdown(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }

    @ViewBuilder private var status: some View {
        switch updater.state {
        case .idle:
            Text("Not checked yet").foregroundStyle(.secondary)
        case .checking:
            HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Checking…") }
        case .upToDate:
            Label("Up to date", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case .available(let version, _):
            Label("Version \(version) available", systemImage: "arrow.down.circle.fill").foregroundStyle(.blue)
        case .installing:
            HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Installing…") }
        case .failed(let message):
            Text(message).foregroundStyle(.orange).multilineTextAlignment(.trailing)
        }
    }
}

// MARK: - Components

private struct SliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let format: String

    init(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, format: String) {
        self.title = title
        self._value = value
        self.range = range
        self.format = format
    }

    var body: some View {
        LabeledContent(title) {
            HStack {
                Slider(value: $value, in: range)
                Text(String(format: format, value))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 64, alignment: .trailing)
            }
        }
    }
}
