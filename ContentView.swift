import SwiftUI
import GameController

// Mobile Macro v0.4
// iPadOS 17+ starter app. Controller input is observed while this app is active.
// Playback currently previews/times a sequence inside this app; iPadOS does not
// allow a normal app to inject arbitrary controller inputs into unrelated games.

@main
struct MobileMacroApp: App {
    var body: some Scene {
        WindowGroup { ContentView() }
    }
}

enum MacroStepKind: String, CaseIterable, Identifiable, Codable {
    case button = "Button"
    case wait = "Wait"
    var id: String { rawValue }
}

struct MacroStep: Identifiable, Codable {
    var id = UUID()
    var kind: MacroStepKind = .button
    var button = "A"
    var milliseconds = 100
}

struct MacroProfile: Identifiable, Codable {
    var id = UUID()
    var name = "Default Profile"
    var steps: [MacroStep] = [
        MacroStep(kind: .button, button: "A", milliseconds: 80),
        MacroStep(kind: .wait, button: "A", milliseconds: 120),
        MacroStep(kind: .button, button: "B", milliseconds: 80)
    ]
}

@MainActor
final class ControllerStore: ObservableObject {
    @Published var controllers: [GCController] = GCController.controllers()
    @Published var connectedName = "No controller connected"
    @Published var lastInput = "Waiting for controller input…"
    @Published var inputLog: [String] = []

    init() {
        NotificationCenter.default.addObserver(self, selector: #selector(connect(_:)),
            name: .GCControllerDidConnect, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(disconnect(_:)),
            name: .GCControllerDidDisconnect, object: nil)
        refresh()
    }

    func refresh() {
        controllers = GCController.controllers()
        connectedName = controllers.first?.vendorName ?? "No controller connected"
        controllers.forEach(configure)
    }

    @objc private func connect(_ note: Notification) { refresh() }
    @objc private func disconnect(_ note: Notification) { refresh() }

    private func configure(_ controller: GCController) {
        guard let pad = controller.extendedGamepad else { return }
        pad.valueChangedHandler = { [weak self] _, element in
            let name: String
            switch element {
            case pad.buttonA: name = "A"
            case pad.buttonB: name = "B"
            case pad.buttonX: name = "X"
            case pad.buttonY: name = "Y"
            case pad.leftShoulder: name = "Left Shoulder"
            case pad.rightShoulder: name = "Right Shoulder"
            case pad.leftTrigger: name = "Left Trigger"
            case pad.rightTrigger: name = "Right Trigger"
            case pad.dpad: name = "D-pad"
            case pad.leftThumbstick: name = "Left Stick"
            case pad.rightThumbstick: name = "Right Stick"
            default: name = "Controller input"
            }
            Task { @MainActor in
                guard let self else { return }
                self.lastInput = name
                self.inputLog.insert(name, at: 0)
                self.inputLog = Array(self.inputLog.prefix(12))
            }
        }
    }
}

@MainActor
final class MacroRunner: ObservableObject {
    @Published var isRunning = false
    @Published var status = "Ready"
    @Published var currentStep = 0
    private var task: Task<Void, Never>?

    func run(_ steps: [MacroStep], repeats: Int, loop: Bool) {
        stop()
        guard !steps.isEmpty else { status = "Add steps first"; return }
        isRunning = true
        status = "Preview running"
        task = Task {
            repeat {
                for (index, step) in steps.enumerated() {
                    if Task.isCancelled { return }
                    currentStep = index + 1
                    status = step.kind == .wait ? "Waiting \(step.milliseconds) ms" : "Preview: \(step.button)"
                    try? await Task.sleep(for: .milliseconds(max(10, step.milliseconds)))
                }
            } while loop && !Task.isCancelled
            if !Task.isCancelled {
                status = "Preview complete"
                isRunning = false
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        isRunning = false
        status = "Stopped"
        currentStep = 0
    }
}

struct ContentView: View {
    @StateObject private var controller = ControllerStore()
    @StateObject private var runner = MacroRunner()
    @AppStorage("mobileMacro.profileName") private var savedProfileName = "Default Profile"
    @State private var steps = MacroProfile().steps
    @State private var selectedTab = "Editor"
    @State private var repeats = 2
    @State private var loopForever = false
    @State private var mapping: [String: String] = [
        "A": "Primary Action", "B": "Secondary Action", "X": "Utility",
        "Y": "Jump", "Left Shoulder": "Previous Slot", "Right Shoulder": "Next Slot"
    ]
    @State private var sensitivity = 50.0
    @State private var snowballDelay = 100.0
    @State private var showInputNames = true
    @State private var haptics = true
    @State private var autoSave = true
    @State private var statusMessage = ""

    private let tabs = ["Editor", "Recorder", "Controller", "Mapping", "Combat", "Snowball", "Visuals", "Utilities", "General"]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        switch selectedTab {
                        case "Editor": editorPage
                        case "Recorder": recorderPage
                        case "Controller": controllerPage
                        case "Mapping": mappingPage
                        case "Combat": combatPage
                        case "Snowball": snowballPage
                        case "Visuals": visualsPage
                        case "Utilities": utilitiesPage
                        default: generalPage
                        }
                    }
                    .padding()
                }
            }
            .background(Color(red: 0.035, green: 0.055, blue: 0.10))
            .toolbar(.hidden, for: .navigationBar)
            .preferredColorScheme(.dark)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("MOBILE MACRO").font(.system(size: 23, weight: .black, design: .rounded))
                    Text("Controller profiles • sequence studio").font(.caption).foregroundStyle(.white.opacity(0.6))
                }
                Spacer()
                Image(systemName: "gamecontroller.fill").font(.title).foregroundStyle(.cyan)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(tabs, id: \.self) { tab in
                        Button(tab) { selectedTab = tab }
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 13).padding(.vertical, 9)
                            .background(selectedTab == tab ? Color.cyan.opacity(0.24) : Color.white.opacity(0.07))
                            .foregroundStyle(selectedTab == tab ? .cyan : .white.opacity(0.8))
                            .clipShape(Capsule())
                    }
                }
            }
        }
        .padding()
        .background(Color(red: 0.055, green: 0.085, blue: 0.15))
    }

    private func panel<Content: View>(_ title: String, subtitle: String? = nil, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                if let subtitle { Text(subtitle).font(.caption).foregroundStyle(.white.opacity(0.55)) }
            }
            content()
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.065))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var editorPage: some View {
        VStack(spacing: 14) {
            panel("Sequence Editor", subtitle: "Build and reorder a macro sequence") {
                HStack {
                    TextField("Profile name", text: $savedProfileName)
                        .textFieldStyle(.roundedBorder)
                    Button { saveProfile() } label: { Image(systemName: "square.and.arrow.down") }
                        .buttonStyle(.borderedProminent)
                }
                ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                    HStack(spacing: 8) {
                        Text("\(index + 1)").foregroundStyle(.cyan).frame(width: 22)
                        Picker("Type", selection: binding(for: step.id, keyPath: \.kind)) {
                            ForEach(MacroStepKind.allCases) { Text($0.rawValue).tag($0) }
                        }.labelsHidden().frame(width: 105)
                        if step.kind == .button {
                            Picker("Button", selection: binding(for: step.id, keyPath: \.button)) {
                                ForEach(["A","B","X","Y","LB","RB","LT","RT","D-pad Up","D-pad Down"], id: \.self) {
                                    Text($0).tag($0)
                                }
                            }.labelsHidden()
                        } else {
                            Text("Wait")
                        }
                        Spacer(minLength: 4)
                        TextField("ms", value: binding(for: step.id, keyPath: \.milliseconds), format: .number)
                            .keyboardType(.numberPad).textFieldStyle(.roundedBorder).frame(width: 66)
                        Button { moveStep(step.id, by: -1) } label: { Image(systemName: "arrow.up") }
                            .disabled(index == 0)
                        Button { moveStep(step.id, by: 1) } label: { Image(systemName: "arrow.down") }
                            .disabled(index == steps.count - 1)
                        Button(role: .destructive) { steps.removeAll { $0.id == step.id } } label: { Image(systemName: "trash") }
                    }
                    .font(.caption)
                    .padding(8)
                    .background(Color.black.opacity(0.18))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                Button { steps.append(MacroStep()) } label: {
                    Label("Add sequence step", systemImage: "plus.circle.fill").frame(maxWidth: .infinity)
                }.buttonStyle(.bordered)
            }
            panel("Playback Preview", subtitle: "Runs a timed preview inside Mobile Macro only") {
                Stepper("Repeat count: \(repeats)", value: $repeats, in: 1...20)
                Toggle("Loop continuously", isOn: $loopForever)
                HStack {
                    Button("Preview") { runner.run(steps, repeats: repeats, loop: loopForever) }
                        .buttonStyle(.borderedProminent).disabled(runner.isRunning)
                    Button("Stop") { runner.stop() }.buttonStyle(.bordered)
                    Spacer()
                    Text(runner.status).font(.caption).foregroundStyle(.cyan)
                }
                Text("Current step: \(runner.currentStep) / \(steps.count)").font(.caption).foregroundStyle(.white.opacity(0.6))
            }
        }
    }

    private var recorderPage: some View {
        VStack(spacing: 14) {
            panel("Input Recorder", subtitle: "Records button names received while this app is active") {
                Text(controller.lastInput).font(.title3.weight(.semibold)).foregroundStyle(.cyan)
                Button("Add last input to sequence") {
                    steps.append(MacroStep(kind: .button, button: controller.lastInput, milliseconds: 100))
                }.buttonStyle(.borderedProminent)
                ForEach(Array(controller.inputLog.enumerated()), id: \.offset) { _, item in
                    HStack { Image(systemName: "dot.circle"); Text(item); Spacer(); Text("Detected").foregroundStyle(.white.opacity(0.45)) }
                    Divider()
                }
                Text("This is an input event log, not a background recorder. Keep Mobile Macro open while testing.")
                    .font(.caption).foregroundStyle(.white.opacity(0.55))
            }
        }
    }

    private var controllerPage: some View {
        panel("Controller Connection", subtitle: "Uses Apple's GameController framework") {
            HStack {
                Image(systemName: "gamecontroller.fill").font(.largeTitle).foregroundStyle(.cyan)
                VStack(alignment: .leading) {
                    Text(controller.connectedName).font(.headline)
                    Text("\(controller.controllers.count) controller(s) detected").font(.caption).foregroundStyle(.white.opacity(0.55))
                }
                Spacer()
                Button("Refresh") { controller.refresh() }.buttonStyle(.bordered)
            }
            Text("Supported devices depend on what iPadOS exposes through GameController. Not every generic Bluetooth controller is guaranteed to work.")
                .font(.caption).foregroundStyle(.white.opacity(0.55))
        }
    }

    private var mappingPage: some View {
        panel("Controller Button Mapping", subtitle: "Assign in-app action labels to detected controller buttons") {
            ForEach(mapping.keys.sorted(), id: \.self) { key in
                HStack {
                    Text(key).frame(width: 120, alignment: .leading).foregroundStyle(.cyan)
                    TextField("Action", text: Binding(
                        get: { mapping[key, default: "Unassigned"] },
                        set: { mapping[key] = $0 }
                    )).textFieldStyle(.roundedBorder)
                }
            }
            Text("These mappings configure Mobile Macro's own profile labels; they do not remap buttons inside other games.")
                .font(.caption).foregroundStyle(.white.opacity(0.55))
        }
    }

    private var combatPage: some View {
        panel("Combat Settings", subtitle: "Practice/profile preferences only") {
            settingRow("Input sensitivity", value: $sensitivity, suffix: "%")
            Toggle("Show active combat profile indicator", isOn: $showInputNames)
            Text("No aim assistance, hitbox changes, or game-memory modifications are provided.")
                .font(.caption).foregroundStyle(.white.opacity(0.55))
        }
    }

    private var snowballPage: some View {
        panel("Snowball Settings", subtitle: "Timing values for your own sequence profiles") {
            settingRow("Action delay", value: $snowballDelay, suffix: " ms")
            Stepper("Delay: \(Int(snowballDelay)) ms", value: $snowballDelay, in: 10...2000, step: 10)
            Button("Add snowball timing step") {
                steps.append(MacroStep(kind: .wait, milliseconds: Int(snowballDelay)))
            }.buttonStyle(.borderedProminent)
        }
    }

    private var visualsPage: some View {
        panel("Visual Settings") {
            Toggle("Show detected input names", isOn: $showInputNames)
            Toggle("Show sequence step numbers", isOn: .constant(true))
            Toggle("Compact editor rows", isOn: .constant(false))
        }
    }

    private var utilitiesPage: some View {
        panel("Utilities") {
            Button { UIPasteboard.general.string = steps.map { "\($0.kind.rawValue):\($0.button):\($0.milliseconds)ms" }.joined(separator: "\n"); statusMessage = "Sequence copied" } label: {
                Label("Copy sequence summary", systemImage: "doc.on.doc")
            }.buttonStyle(.bordered)
            Button { steps = []; statusMessage = "Sequence cleared" } label: {
                Label("Clear current sequence", systemImage: "trash")
            }.buttonStyle(.bordered)
            if !statusMessage.isEmpty { Text(statusMessage).font(.caption).foregroundStyle(.cyan) }
        }
    }

    private var generalPage: some View {
        panel("General Settings") {
            Toggle("Auto-save profile name", isOn: $autoSave)
            Toggle("Haptic feedback preference", isOn: $haptics)
            HStack { Text("App version"); Spacer(); Text("0.4").foregroundStyle(.white.opacity(0.55)) }
            Text("Profiles are stored locally in this starter build. Export/import and cloud sync can be added in a later version.")
                .font(.caption).foregroundStyle(.white.opacity(0.55))
        }
    }

    private func settingRow(_ title: String, value: Binding<Double>, suffix: String) -> some View {
        VStack(alignment: .leading) {
            HStack { Text(title); Spacer(); Text("\(Int(value.wrappedValue))\(suffix)").foregroundStyle(.cyan) }
            Slider(value: value, in: 0...100)
        }
    }

    private func binding<T>(for id: UUID, keyPath: WritableKeyPath<MacroStep, T>) -> Binding<T> {
        Binding(
            get: { steps.first(where: { $0.id == id })?[keyPath: keyPath] ?? steps[0][keyPath: keyPath] },
            set: { newValue in
                guard let index = steps.firstIndex(where: { $0.id == id }) else { return }
                steps[index][keyPath: keyPath] = newValue
            }
        )
    }

    private func moveStep(_ id: UUID, by offset: Int) {
        guard let index = steps.firstIndex(where: { $0.id == id }) else { return }
        let destination = index + offset
        guard steps.indices.contains(destination) else { return }
        steps.swapAt(index, destination)
    }

    private func saveProfile() {
        guard autoSave else { statusMessage = "Auto-save is off"; return }
        let profile = MacroProfile(name: savedProfileName, steps: steps)
        if let data = try? JSONEncoder().encode(profile) {
            UserDefaults.standard.set(data, forKey: "mobileMacro.profile.\(savedProfileName)")
            statusMessage = "Profile saved on this iPad"
        }
    }
}
