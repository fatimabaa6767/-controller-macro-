import SwiftUI
import GameController

// Mobile Macro v0.3 — TGMacro-inspired editor for iPadOS.
// Records supported controller button events while this app is active.
// Playback is an in-app sequence preview; iOS apps cannot inject inputs into other games.

struct MacroAction: Identifiable, Codable, Equatable {
    var id = UUID()
    var kind: String = "Button"
    var control: String = "Button A"
    var duration: Double = 0.10
    var enabled: Bool = true
}

struct MacroProfile: Codable, Identifiable {
    var id = UUID()
    var name: String
    var actions: [MacroAction]
    var loopEnabled: Bool = false
    var loopCount: Int = 1
    var trigger: String = "None"
}

@MainActor
final class ControllerHub: ObservableObject {
    @Published var controllers: [GCController] = []
    @Published var selected = 0
    @Published var latestEvent = "Waiting for controller input"
    @Published var recording = false
    var onRecordedControl: ((String) -> Void)?
    private var observers: [NSObjectProtocol] = []

    init() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: .GCControllerDidConnect, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        })
        observers.append(center.addObserver(forName: .GCControllerDidDisconnect, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        })
        refresh()
    }

    deinit { observers.forEach(NotificationCenter.default.removeObserver) }

    var current: GCController? {
        guard controllers.indices.contains(selected) else { return nil }
        return controllers[selected]
    }

    func refresh() {
        controllers = GCController.controllers()
        if controllers.isEmpty { selected = 0 }
        else if selected >= controllers.count { selected = 0 }
        attachHandlers()
    }

    func discover() {
        GCController.startWirelessControllerDiscovery { [weak self] in
            Task { @MainActor in self?.refresh() }
        }
        refresh()
    }

    func attachHandlers() {
        guard let pad = current?.extendedGamepad else { return }
        let buttons: [(String, GCControllerButtonInput)] = [
            ("Button A", pad.buttonA), ("Button B", pad.buttonB),
            ("Button X", pad.buttonX), ("Button Y", pad.buttonY),
            ("Left Bumper", pad.leftShoulder), ("Right Bumper", pad.rightShoulder),
            ("D-pad Up", pad.dpad.up), ("D-pad Down", pad.dpad.down),
            ("D-pad Left", pad.dpad.left), ("D-pad Right", pad.dpad.right)
        ]
        for (name, button) in buttons {
            button.pressedChangedHandler = { [weak self] _, _, pressed in
                guard pressed else { return }
                Task { @MainActor in
                    self?.latestEvent = "\(name) pressed"
                    if self?.recording == true { self?.onRecordedControl?(name) }
                }
            }
        }
    }
}

@MainActor
final class MacroStore: ObservableObject {
    @Published var profiles: [MacroProfile] = []
    private let key = "MobileMacro.profiles.v3"

    init() { load() }

    func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([MacroProfile].self, from: data) else {
            profiles = [MacroProfile(name: "My First Macro", actions: [
                MacroAction(kind: "Button", control: "Button A", duration: 0.10),
                MacroAction(kind: "Wait", control: "Delay", duration: 0.20)
            ])]
            save()
            return
        }
        profiles = decoded
    }

    func save() {
        guard let data = try? JSONEncoder().encode(profiles) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

struct ContentView: View {
    @StateObject private var hub = ControllerHub()
    @StateObject private var store = MacroStore()

    @State private var tab = "Editor"
    @State private var selectedProfile = 0
    @State private var isPlaying = false
    @State private var playbackTask: Task<Void, Never>?
    @State private var playbackStatus = "Ready"
    @State private var recordingStart = Date()
    @State private var triggerChoice = "None"
    @State private var loopEnabled = false
    @State private var loopCount = 1
    @State private var profileName = "My Macro"
    @State private var showNewProfile = false

    private let blue = Color(red: 0.22, green: 0.48, blue: 1)
    private let bg = Color(red: 0.035, green: 0.055, blue: 0.12)
    private let panel = Color(red: 0.10, green: 0.15, blue: 0.29)
    private let tabs = ["Editor", "Recorder", "Controller", "Profiles", "Settings"]

    private var activeProfile: MacroProfile {
        guard store.profiles.indices.contains(selectedProfile) else {
            return MacroProfile(name: "Untitled", actions: [])
        }
        return store.profiles[selectedProfile]
    }

    var body: some View {
        ZStack {
            bg.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                tabStrip
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        switch tab {
                        case "Editor": editorPage
                        case "Recorder": recorderPage
                        case "Controller": controllerPage
                        case "Profiles": profilesPage
                        default: settingsPage
                        }
                    }
                    .padding()
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            hub.onRecordedControl = { name in appendRecorded(name) }
        }
        .onDisappear { playbackTask?.cancel() }
    }

    private var header: some View {
        HStack(spacing: 11) {
            Image(systemName: "gamecontroller.fill")
                .font(.title2).foregroundStyle(.white)
                .frame(width: 44, height: 44).background(blue, in: RoundedRectangle(cornerRadius: 13))
            VStack(alignment: .leading, spacing: 3) {
                Text("MOBILE MACRO").font(.headline.bold()).tracking(0.5)
                Text("Macro Studio  •  iPad Edition").font(.caption).foregroundStyle(.white.opacity(0.6))
            }
            Spacer()
            Circle().fill(hub.controllers.isEmpty ? .orange : .green).frame(width: 8, height: 8)
            Text(hub.controllers.isEmpty ? "OFFLINE" : "CONNECTED")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(hub.controllers.isEmpty ? .orange : .green)
        }
        .padding()
        .background(Color.white.opacity(0.045))
    }

    private var tabStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(tabs, id: \.self) { item in
                    Button { tab = item } label: {
                        Text(item).font(.caption.bold())
                            .padding(.horizontal, 14).padding(.vertical, 10)
                            .background(tab == item ? blue : Color.white.opacity(0.08))
                            .foregroundStyle(.white)
                            .clipShape(Capsule())
                    }.buttonStyle(.plain)
                }
            }.padding(.horizontal).padding(.vertical, 10)
        }
    }

    private var editorPage: some View {
        VStack(alignment: .leading, spacing: 15) {
            heading("MACRO EDITOR", "Edit actions, timing, order, loops, and triggers.")
            card {
                HStack {
                    Text(activeProfile.name).font(.headline)
                    Spacer()
                    Text("\(activeProfile.actions.count) ACTIONS")
                        .font(.caption.bold()).foregroundStyle(.cyan)
                }
                ForEach(activeProfile.actions.indices, id: \.self) { index in
                    actionEditor(index)
                }
                Button {
                    updateProfile { $0.actions.append(MacroAction()) }
                } label: {
                    Label("Add Action", systemImage: "plus.circle.fill")
                        .frame(maxWidth: .infinity).padding(12).background(blue)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }.buttonStyle(.plain)
            }
            card {
                Text("PLAYBACK").font(.headline)
                HStack {
                    Toggle("Loop sequence", isOn: $loopEnabled).tint(blue)
                }
                if loopEnabled {
                    Stepper("Loop count: \(loopCount)", value: $loopCount, in: 1...50)
                }
                HStack {
                    Button { playMacro() } label: {
                        Label("Play Preview", systemImage: "play.fill")
                            .frame(maxWidth: .infinity).padding(12).background(blue)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }.disabled(isPlaying)
                    Button {
                        playbackTask?.cancel()
                        isPlaying = false
                        playbackStatus = "Stopped"
                    } label: {
                        Label("Stop", systemImage: "stop.fill")
                            .padding(12).background(.red.opacity(0.75))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }.disabled(!isPlaying)
                }.buttonStyle(.plain)
                Text(playbackStatus).font(.caption.monospaced()).foregroundStyle(.cyan)
                Text("Preview playback runs in this app only. It does not send inputs to other games.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            card {
                Text("TRIGGER").font(.headline)
                Picker("Start trigger", selection: $triggerChoice) {
                    ForEach(["None", "Button A", "Button B", "Button X", "Button Y",
                             "Left Bumper", "Right Bumper", "D-pad Up", "D-pad Down"], id: \.self) {
                        Text($0)
                    }
                }.onChange(of: triggerChoice) { _, value in
                    updateProfile { $0.trigger = value }
                }
                Text("A trigger can be configured for in-app actions and tests. Background/global hotkeys are limited by iPadOS.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private func actionEditor(_ index: Int) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text(String(format: "%02d", index + 1))
                    .font(.caption.bold()).foregroundStyle(.cyan)
                Picker("Action type", selection: actionBinding(index, \.kind)) {
                    Text("Button").tag("Button")
                    Text("Wait").tag("Wait")
                }.pickerStyle(.menu)
                Spacer()
                Button {
                    updateProfile { profile in
                        guard profile.actions.indices.contains(index) else { return }
                        profile.actions.remove(at: index)
                    }
                } label: { Image(systemName: "trash").foregroundStyle(.red) }
            }
            if activeProfile.actions.indices.contains(index),
               activeProfile.actions[index].kind == "Button" {
                Picker("Control", selection: actionBinding(index, \.control)) {
                    ForEach(["Button A", "Button B", "Button X", "Button Y",
                             "D-pad Up", "D-pad Down", "D-pad Left", "D-pad Right",
                             "Left Bumper", "Right Bumper", "Left Trigger", "Right Trigger"], id: \.self) {
                        Text($0).tag($0)
                    }
                }.pickerStyle(.menu)
            } else {
                Text("Wait / Delay").font(.caption).foregroundStyle(.secondary)
            }
            if activeProfile.actions.indices.contains(index) {
                HStack {
                    Text("Duration / delay")
                    Spacer()
                    TextField("0.10", value: durationBinding(index),
                              format: .number.precision(.fractionLength(2)))
                        .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 75)
                    Text("sec").foregroundStyle(.secondary)
                }.font(.caption)
            }
            if index < activeProfile.actions.count - 1 {
                HStack {
                    Button("Move Up") { moveAction(index, by: -1) }.disabled(index == 0)
                    Button("Move Down") { moveAction(index, by: 1) }
                        .disabled(index == activeProfile.actions.count - 1)
                    Spacer()
                }.font(.caption)
            }
        }
        .padding(11).background(Color.white.opacity(0.055))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var recorderPage: some View {
        VStack(alignment: .leading, spacing: 15) {
            heading("MACRO RECORDER", "Capture supported controller button presses while this app is open.")
            card {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(hub.recording ? "RECORDING" : "STANDBY").font(.headline)
                        Text("Controller: \(hub.current?.vendorName ?? "Not connected")")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Circle().fill(hub.recording ? .red : .gray).frame(width: 12, height: 12)
                }
                Button {
                    if hub.recording {
                        hub.recording = false
                    } else {
                        recordingStart = Date()
                        hub.recording = true
                        tab = "Recorder"
                    }
                } label: {
                    Label(hub.recording ? "Stop Recording" : "Start Recording",
                          systemImage: hub.recording ? "stop.fill" : "record.circle")
                        .frame(maxWidth: .infinity).padding(14)
                        .background(hub.recording ? Color.red : blue)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }.buttonStyle(.plain)
                Text("Last input: \(hub.latestEvent)")
                    .font(.caption.monospaced()).foregroundStyle(.cyan)
                Text("Recorded button-down events become editable Button actions. Wait actions can be inserted and adjusted in the Editor.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            card {
                Text("RECORDED ACTIONS").font(.headline)
                Text("\(activeProfile.actions.count) actions in \(activeProfile.name)")
                    .font(.caption).foregroundStyle(.secondary)
                Button {
                    tab = "Editor"
                } label: {
                    Label("Edit Recorded Sequence", systemImage: "slider.horizontal.3")
                }
            }
        }
    }

    private var controllerPage: some View {
        VStack(alignment: .leading, spacing: 15) {
            heading("CONTROLLER", "Connect supported game controllers through iPadOS.")
            card {
                Label(hub.current?.vendorName ?? "No controller selected",
                      systemImage: "gamecontroller.fill").font(.headline)
                Button {
                    hub.discover()
                } label: {
                    Label("Discover Wireless Controllers", systemImage: "antenna.radiowaves.left.and.right")
                        .frame(maxWidth: .infinity).padding(12).background(blue)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }.buttonStyle(.plain)
                Button("Refresh Connected Controllers") { hub.refresh() }
                ForEach(Array(hub.controllers.enumerated()), id: \.offset) { index, device in
                    Button {
                        hub.selected = index
                        hub.attachHandlers()
                    } label: {
                        HStack {
                            Text(device.vendorName ?? "Game Controller")
                            Spacer()
                            if hub.selected == index { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
                        }.padding(9).background(Color.white.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }.buttonStyle(.plain)
                }
                Text("Latest input: \(hub.latestEvent)")
                    .font(.caption.monospaced()).foregroundStyle(.cyan)
            }
            card {
                Text("COMPATIBILITY").font(.headline)
                Text("Works with controllers exposed by Apple's GameController framework. Many Xbox, PlayStation, MFi, and other supported controllers are recognized. No app can promise compatibility with every generic Bluetooth device.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var profilesPage: some View {
        VStack(alignment: .leading, spacing: 15) {
            heading("PROFILES", "Save and switch between macro configurations.")
            card {
                ForEach(store.profiles.indices, id: \.self) { index in
                    HStack {
                        Button {
                            selectedProfile = index
                            triggerChoice = store.profiles[index].trigger
                            tab = "Editor"
                        } label: {
                            VStack(alignment: .leading) {
                                Text(store.profiles[index].name).font(.headline)
                                Text("\(store.profiles[index].actions.count) actions")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }.buttonStyle(.plain)
                        Spacer()
                        Button(role: .destructive) {
                            if store.profiles.count > 1 {
                                store.profiles.remove(at: index)
                                selectedProfile = min(selectedProfile, store.profiles.count - 1)
                                store.save()
                            }
                        } label: { Image(systemName: "trash") }
                    }
                    Divider().overlay(Color.white.opacity(0.1))
                }
                Button {
                    let new = MacroProfile(name: "Macro \(store.profiles.count + 1)",
                                           actions: [MacroAction()])
                    store.profiles.append(new)
                    selectedProfile = store.profiles.count - 1
                    store.save()
                } label: {
                    Label("New Profile", systemImage: "plus")
                        .frame(maxWidth: .infinity).padding(12).background(blue)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }.buttonStyle(.plain)
                Button("Save Profiles") { store.save() }
            }
        }
    }

    private var settingsPage: some View {
        VStack(alignment: .leading, spacing: 15) {
            heading("SETTINGS", "General preferences and app information.")
            card {
                Text("Mobile Macro").font(.headline)
                Text("TGMacro-inspired iPad macro editor.")
                    .font(.caption).foregroundStyle(.secondary)
                Text("Profiles are stored locally on this iPad. Macro playback and recording are limited to supported in-app functionality.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func heading(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.title2.bold()).tracking(0.4)
            Text(subtitle).font(.caption).foregroundStyle(.white.opacity(0.6))
        }
    }

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14, content: content)
            .padding().background(panel)
            .clipShape(RoundedRectangle(cornerRadius: 15))
            .overlay(RoundedRectangle(cornerRadius: 15).stroke(blue.opacity(0.25), lineWidth: 1))
    }

    private func updateProfile(_ change: (inout MacroProfile) -> Void) {
        guard store.profiles.indices.contains(selectedProfile) else { return }
        change(&store.profiles[selectedProfile])
        store.save()
    }

    private func actionBinding<T>(_ index: Int, _ keyPath: WritableKeyPath<MacroAction, T>) -> Binding<T> {
        Binding(
            get: {
                guard activeProfile.actions.indices.contains(index) else {
                    return store.profiles[selectedProfile].actions[0][keyPath: keyPath]
                }
                return activeProfile.actions[index][keyPath: keyPath]
            },
            set: { value in
                updateProfile { profile in
                    guard profile.actions.indices.contains(index) else { return }
                    profile.actions[index][keyPath: keyPath] = value
                }
            }
        )
    }

    private func durationBinding(_ index: Int) -> Binding<Double> {
        Binding(
            get: { activeProfile.actions.indices.contains(index) ? activeProfile.actions[index].duration : 0.1 },
            set: { value in
                updateProfile { profile in
                    guard profile.actions.indices.contains(index) else { return }
                    profile.actions[index].duration = max(0, min(value, 60))
                }
            }
        )
    }

    private func moveAction(_ index: Int, by offset: Int) {
        updateProfile { profile in
            let destination = index + offset
            guard profile.actions.indices.contains(index),
                  profile.actions.indices.contains(destination) else { return }
            profile.actions.swapAt(index, destination)
        }
    }

    private func appendRecorded(_ control: String) {
        updateProfile { profile in
            profile.actions.append(MacroAction(kind: "Button", control: control, duration: 0.10))
        }
    }

    private func playMacro() {
        let actions = activeProfile.actions.filter(\.enabled)
        let repeats = loopEnabled ? loopCount : 1
        isPlaying = true
        playbackStatus = "Starting preview…"
        playbackTask?.cancel()
        playbackTask = Task { @MainActor in
            for cycle in 0..<repeats {
                for (index, action) in actions.enumerated() {
                    if Task.isCancelled { break }
                    playbackStatus = "Pass \(cycle + 1): \(index + 1)/\(actions.count) — \(action.kind == "Wait" ? "Wait" : action.control)"
                    let wait = max(0, min(action.duration, 60))
                    try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
                }
                if Task.isCancelled { break }
            }
            if !Task.isCancelled { playbackStatus = "Preview complete" }
            isPlaying = false
        }
    }
}
