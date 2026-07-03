import SwiftUI
import Network

// Manage paired frames: add (setup wizard), rename, delete, last-seen, and
// an optional local-network scan for awake frames.
struct FramesView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: FrameStore

    @State private var showWizard = false
    @State private var renameTarget: Frame?
    @State private var renameText = ""
    @State private var deleteTarget: Frame?
    @State private var statuses: [String: FrameService.Status] = [:]
    @StateObject private var scanner = BonjourScanner()

    var body: some View {
        NavigationStack {
            List {
                if store.frames.isEmpty {
                    Section {
                        Text("No frames yet. Add one to get started!")
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    ForEach(store.frames) { frame in
                        frameRow(frame)
                    }
                } footer: {
                    if !store.frames.isEmpty {
                        Text("Frames check for new pictures every 30 minutes.")
                    }
                }

                Section {
                    Button {
                        showWizard = true
                    } label: {
                        Label("Add a Frame", systemImage: "plus.circle.fill")
                    }
                }

                scanSection
            }
            .navigationTitle("My Frames")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showWizard) {
                SetupWizardView()
            }
            .alert("Rename Frame", isPresented: .init(
                get: { renameTarget != nil },
                set: { if !$0 { renameTarget = nil } }
            )) {
                TextField("Name", text: $renameText)
                Button("Save") {
                    if let target = renameTarget, !renameText.trimmingCharacters(in: .whitespaces).isEmpty {
                        store.rename(target, to: renameText.trimmingCharacters(in: .whitespaces))
                    }
                    renameTarget = nil
                }
                Button("Cancel", role: .cancel) { renameTarget = nil }
            }
            .confirmationDialog(
                "Remove \(deleteTarget?.name ?? "frame")? The frame itself keeps its last picture; to pair it again you'll need to re-run setup.",
                isPresented: .init(
                    get: { deleteTarget != nil },
                    set: { if !$0 { deleteTarget = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Remove Frame", role: .destructive) {
                    if let target = deleteTarget { store.remove(target) }
                    deleteTarget = nil
                }
            }
            .task { await refreshStatuses() }
            .onDisappear { scanner.stop() }
        }
    }

    // MARK: - Rows

    private func frameRow(_ frame: Frame) -> some View {
        DisclosureGroup {
            detailRow(label: "Frame ID", value: frame.frameId)
            detailRow(label: "Device Token", value: frame.token)
            detailRow(label: "Frame URL", value: FrameService.deviceURL(for: frame))
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(frame.name).font(.headline)
                Text(lastSeenText(for: frame))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .contextMenu {
                Button {
                    renameText = frame.name
                    renameTarget = frame
                } label: {
                    Label("Rename", systemImage: "pencil")
                }
                Button(role: .destructive) {
                    deleteTarget = frame
                } label: {
                    Label("Remove", systemImage: "trash")
                }
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                deleteTarget = frame
            } label: {
                Label("Remove", systemImage: "trash")
            }
            Button {
                renameText = frame.name
                renameTarget = frame
            } label: {
                Label("Rename", systemImage: "pencil")
            }
        }
    }

    private func detailRow(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label).font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                Button {
                    UIPasteboard.general.string = value
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
            }
            Text(value)
                .font(.system(.footnote, design: .monospaced))
                .textSelection(.enabled)
        }
        .padding(.vertical, 2)
    }

    private func lastSeenText(for frame: Frame) -> String {
        guard let status = statuses[frame.frameId] else { return "Checking…" }
        guard let seen = status.lastSeen else { return "Never checked in" }
        let fmt = RelativeDateTimeFormatter()
        fmt.unitsStyle = .abbreviated
        return "Last seen \(fmt.localizedString(for: seen, relativeTo: Date()))"
    }

    private func refreshStatuses() async {
        await withTaskGroup(of: (String, FrameService.Status?).self) { group in
            for frame in store.frames {
                group.addTask {
                    (frame.frameId, try? await FrameService.status(of: frame))
                }
            }
            for await (id, status) in group {
                if let status { statuses[id] = status }
            }
        }
    }

    // MARK: - Network scan

    @ViewBuilder
    private var scanSection: some View {
        Section {
            if scanner.isScanning {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Scanning your network…").foregroundStyle(.secondary)
                }
                ForEach(scanner.results, id: \.self) { name in
                    Label(name, systemImage: "wifi")
                }
                Button("Stop Scanning") { scanner.stop() }
            } else {
                Button {
                    scanner.start()
                } label: {
                    Label("Find frames on my network", systemImage: "magnifyingglass")
                }
            }
        } footer: {
            Text("""
            Frames sleep between picture checks, so only frames that are awake \
            or in setup mode will appear here.
            """)
        }
    }
}

// Browses for _monoframe._tcp services (frames advertise while awake).
@MainActor
final class BonjourScanner: ObservableObject {
    @Published private(set) var results: [String] = []
    @Published private(set) var isScanning = false

    private var browser: NWBrowser?

    func start() {
        stop()
        results = []
        isScanning = true
        let browser = NWBrowser(
            for: .bonjour(type: "_monoframe._tcp", domain: nil),
            using: NWParameters())
        browser.browseResultsChangedHandler = { [weak self] browseResults, _ in
            let names: [String] = browseResults.compactMap {
                if case .service(let name, _, _, _) = $0.endpoint { return name }
                return nil
            }
            Task { @MainActor in self?.results = names.sorted() }
        }
        browser.stateUpdateHandler = { [weak self] state in
            if case .failed = state {
                Task { @MainActor in self?.stop() }
            }
        }
        browser.start(queue: .main)
        self.browser = browser
    }

    func stop() {
        browser?.cancel()
        browser = nil
        isScanning = false
    }
}
