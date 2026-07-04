import SwiftUI

// Guided pairing: register a frame on the backend, join the frame's setup
// hotspot, hand it the user's WiFi + credentials, then wait until the frame
// phones home. No ads anywhere in this flow.
struct SetupWizardView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: FrameStore

    static let flasherURL = URL(string: "https://jbaker00.github.io/MonoFrame/flasher/")!

    // The device steps are faked in two cases: demo mode (lets anyone — App
    // Store reviewers especially — walk the whole flow without hardware; the
    // backend registration and uploads are real) and the simulator, where
    // NEHotspotConfiguration and the 192.168.4.1 device don't exist.
    #if targetEnvironment(simulator)
    private static let isSimulator = true
    #else
    private static let isSimulator = false
    #endif
    @State private var isDemo = false
    private var simulateDevice: Bool { isDemo || Self.isSimulator }

    private enum Step {
        case intro
        case connect
        case wifi
        case provisioning
        case confirm
        case name
    }

    @State private var step: Step = .intro
    @State private var creds: FrameService.RegisterResponse?
    @State private var deviceName: String = ""
    @State private var deviceModel: DeviceModel = .crowPanel42
    @State private var ssid: String = ""
    @State private var password: String = ""
    @State private var frameName: String = ""
    @State private var errorText: String = ""
    @State private var isWorking = false
    @State private var workingMessage = ""
    @State private var wizardStart = Date()
    @State private var confirmElapsed = 0

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    stepHeader
                    stepBody
                    if !errorText.isEmpty {
                        Text(errorText)
                            .font(.callout)
                            .foregroundStyle(.red)
                    }
                }
                .padding()
            }
            .navigationTitle("Add a Frame")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .interactiveDismissDisabled(isWorking)
        }
    }

    // MARK: - Steps

    private var stepHeader: some View {
        let (index, title): (Int, String) = switch step {
        case .intro:        (1, "Get your frame ready")
        case .connect:      (2, "Connect to your frame")
        case .wifi:         (3, "Your home WiFi")
        case .provisioning: (4, "Setting up…")
        case .confirm:      (5, "Waiting for your frame")
        case .name:         (6, "Name your frame")
        }
        return VStack(alignment: .leading, spacing: 4) {
            Text("Step \(index) of 6")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.title2.bold())
        }
    }

    @ViewBuilder
    private var stepBody: some View {
        switch step {
        case .intro: introStep
        case .connect: connectStep
        case .wifi: wifiStep
        case .provisioning: provisioningStep
        case .confirm: confirmStep
        case .name: nameStep
        }
    }

    private var introStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label {
                Text("**Brand-new frame?** Flash it first: plug it into a computer with a USB-C cable and open our web flasher in Chrome or Edge — one click, no software to install.")
            } icon: {
                Image(systemName: "bolt.fill")
            }
            Link(destination: Self.flasherURL) {
                Label("Open the web flasher", systemImage: "safari")
            }
            .font(.callout)
            .padding(.leading, 32)

            Label {
                Text("**Power it on.** Within a minute the screen should say **Setup Mode** and show a hotspot name like *MonoFrame-A1B2*.")
            } icon: {
                Image(systemName: "power")
            }

            Label {
                Text("If it shows a picture instead, it's already set up — you can still re-run setup by keeping it near you and waiting for its next wake, or re-flashing it.")
            } icon: {
                Image(systemName: "info.circle")
            }
            .foregroundStyle(.secondary)
            .font(.callout)

            Button {
                Task { await beginConnect() }
            } label: {
                buttonLabel("My frame shows Setup Mode")
            }
            .buttonStyle(.borderedProminent)
            .disabled(isWorking)

            Button {
                isDemo = true
                ssid = "Demo Network"
                Task { await beginConnect() }
            } label: {
                buttonLabel("No frame yet? Try a demo")
            }
            .disabled(isWorking)
        }
    }

    private var connectStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            if isWorking {
                HStack(spacing: 10) {
                    ProgressView()
                    Text(workingMessage.isEmpty
                         ? "Connecting to your frame's hotspot…"
                         : workingMessage)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("MonoFrame will ask to join your frame's WiFi hotspot. Nothing leaves your home network in this step.")
                Button {
                    Task { await connectToDevice() }
                } label: {
                    buttonLabel("Connect to Frame")
                }
                .buttonStyle(.borderedProminent)

                DisclosureGroup("Having trouble?") {
                    Text("""
                    Open **Settings → WiFi** on this iPhone and join the network \
                    shown on the frame's screen (it starts with *MonoFrame-*), \
                    then come back and tap **Connect to Frame** again.
                    """)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
                }
            }
        }
    }

    private var wifiStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !deviceName.isEmpty {
                Label("Connected to \(deviceName)", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
            Text("Enter the WiFi network your frame should use. This is sent directly to the frame and stored only on it.")
                .font(.callout)
            if isDemo {
                Text("Demo mode: any network name works — nothing is sent to a real device.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 0) {
                TextField("WiFi network name (SSID)", text: $ssid)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(12)
                Divider()
                SecureField("WiFi password", text: $password)
                    .padding(12)
            }
            .background(.gray.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 10))

            Button {
                Task { await provision() }
            } label: {
                buttonLabel("Send to Frame")
            }
            .buttonStyle(.borderedProminent)
            .disabled(ssid.isEmpty || isWorking)
        }
    }

    private var provisioningStep: some View {
        HStack(spacing: 10) {
            ProgressView()
            Text("Sending WiFi details to your frame…")
                .foregroundStyle(.secondary)
        }
    }

    private var confirmStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                ProgressView()
                Text("Your frame is restarting and joining your WiFi… (\(confirmElapsed)s) Tip: pressing the button on the back of the frame wakes it right away.")
                    .foregroundStyle(.secondary)
            }
            if confirmElapsed > 45 {
                Text("""
                Taking a while? Double-check the WiFi password, and make sure \
                your network is 2.4 GHz — the frame can't join 5 GHz-only networks.
                """)
                .font(.callout)
                .foregroundStyle(.secondary)
                Button("Start over") {
                    errorText = ""
                    step = .intro
                }
            }
        }
    }

    private var nameStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Your frame is online!", systemImage: "checkmark.circle.fill")
                .font(.title3)
                .foregroundStyle(.green)
            Text("Give it a name so you can tell your frames apart.")
                .font(.callout)
            TextField("e.g. Living Room", text: $frameName)
                .padding(12)
                .background(.gray.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            if isDemo {
                Text("This demo frame works like a real one — pictures you send are uploaded and would appear on a paired frame.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Button {
                finish()
            } label: {
                buttonLabel("Done")
            }
            .buttonStyle(.borderedProminent)
            .disabled(frameName.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    private func buttonLabel(_ title: String) -> some View {
        Text(title)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
    }

    // MARK: - Actions

    // Register while the phone still has normal internet — once it's on the
    // frame's hotspot, WiFi has no route out and WiFi-only iPads would fail.
    private func beginConnect() async {
        errorText = ""
        isWorking = true
        defer { isWorking = false }
        do {
            if creds == nil {
                creds = try await FrameService.register()
            }
            wizardStart = Date()
            step = .connect
        } catch {
            errorText = "Could not reach the MonoFrame service: \(error.localizedDescription)"
        }
    }

    private func connectToDevice() async {
        errorText = ""
        isWorking = true
        defer { isWorking = false }

        if simulateDevice {
            try? await Task.sleep(for: .seconds(1))
            deviceName = isDemo ? "MonoFrame-DEMO" : "MonoFrame-SIM1"
            step = .wifi
            return
        }

        do {
            try await HotspotJoiner.joinFrameHotspot()
        } catch {
            errorText = """
            Couldn't join automatically (\(error.localizedDescription)). \
            Try the manual steps under "Having trouble?".
            """
            // The user may already be on the hotspot manually — still try polling.
        }

        for _ in 0..<10 {
            if let info = try? await DeviceClient.info() {
                deviceName = info.name
                deviceModel = DeviceModel(infoModel: info.model)
                errorText = ""
                if FirmwareBundle.isOutdated(info.fw),
                   let image = FirmwareBundle.otaImage(for: deviceModel) {
                    guard await updateFrameFirmware(image) else { return }
                }
                step = .wifi
                return
            }
            try? await Task.sleep(for: .seconds(2))
        }
        if errorText.isEmpty {
            errorText = """
            Couldn't find the frame at 192.168.4.1. Make sure this iPhone is \
            on the frame's *MonoFrame-…* network and the frame still shows \
            Setup Mode, then try again.
            """
        }
    }

    // Pushes the firmware bundled in the app to the frame over its hotspot —
    // phone to frame only, no internet or computer involved. The frame
    // reboots back into setup mode, so we rejoin and wait for it.
    private func updateFrameFirmware(_ image: Data) async -> Bool {
        workingMessage = "Updating your frame's software — keep it plugged in…"
        defer { workingMessage = "" }
        do {
            try await DeviceClient.updateFirmware(image)
        } catch {
            errorText = """
            Software update failed: \(error.localizedDescription) \
            Tap Connect to Frame to try again.
            """
            return false
        }
        workingMessage = "Frame is restarting with its new software…"
        try? await Task.sleep(for: .seconds(8))
        for _ in 0..<20 {
            try? await HotspotJoiner.joinFrameHotspot()
            if let info = try? await DeviceClient.info(),
               !FirmwareBundle.isOutdated(info.fw) {
                return true
            }
            try? await Task.sleep(for: .seconds(3))
        }
        errorText = """
        The frame didn't reappear after the update. Power-cycle it, wait for \
        Setup Mode, then tap Connect to Frame again.
        """
        return false
    }

    private func provision() async {
        guard let creds else { return }
        errorText = ""
        isWorking = true
        step = .provisioning
        defer { isWorking = false }

        if simulateDevice {
            try? await Task.sleep(for: .seconds(1))
            step = .confirm
            await confirmOnline()
            return
        }

        do {
            try await DeviceClient.provision(ssid: ssid, pass: password,
                                             frameId: creds.frameId, token: creds.token)
            step = .confirm
            await confirmOnline()
        } catch {
            errorText = "Setup failed: \(error.localizedDescription)"
            step = .wifi
        }
    }

    // The frame reboots, joins home WiFi, and its first getFrame stamps
    // lastSeen — that's our proof the whole chain works.
    private func confirmOnline() async {
        guard let creds else { return }
        let frame = Frame(frameId: creds.frameId, token: creds.token,
                          name: "New Frame", createdAt: Date())
        confirmElapsed = 0

        if simulateDevice {
            try? await Task.sleep(for: .seconds(2))
            if isDemo && frameName.isEmpty { frameName = "Demo Frame" }
            step = .name
            return
        }

        let deadline = Date().addingTimeInterval(120)
        while Date() < deadline {
            if let status = try? await FrameService.status(of: frame),
               let seen = status.lastSeen, seen > wizardStart {
                step = .name
                return
            }
            try? await Task.sleep(for: .seconds(3))
            confirmElapsed += 3
            if step != .confirm { return }   // user tapped "Start over"
        }
        errorText = """
        The frame hasn't come online yet. It may still be retrying — if its \
        screen shows an error, tap Start over and re-check the WiFi password.
        """
    }

    private func finish() {
        guard let creds else { return }
        let frame = Frame(frameId: creds.frameId, token: creds.token,
                          name: frameName.trimmingCharacters(in: .whitespaces),
                          createdAt: Date(), model: deviceModel)
        store.add(frame)
        dismiss()
    }
}
