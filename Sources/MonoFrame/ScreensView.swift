import SwiftUI

// Picker for the bundled dashboard screens: live previews rendered for the
// selected frame's panel, and a send path that reuses the photo pipeline.
struct ScreensView: View {
    @EnvironmentObject private var store: FrameStore
    @Environment(\.dismiss) private var dismiss

    // User-created screens (LLM-generated or pasted) live alongside samples.
    @StateObject private var customStore = CustomScreenStore()
    @State private var showCreate = false

    @State private var status: String = ""
    @State private var sendingScreen: String?

    private var targetModel: DeviceModel {
        store.selectedFrame?.model ?? .crowPanel42
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if store.frames.count > 1 {
                        Picker("Frame", selection: $store.selectedFrameId) {
                            ForEach(store.frames) { frame in
                                Text(frame.name).tag(Optional(frame.frameId))
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                        .background(.gray.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }

                    Button {
                        showCreate = true
                    } label: {
                        Label("Create New Screen", systemImage: "sparkles")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(.tint.opacity(0.15))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }

                    if !customStore.screens.isEmpty {
                        sectionHeader("My Screens")
                        ForEach(customStore.screens) { layout in
                            screenCard(layout, deletable: true)
                        }
                        sectionHeader("Samples")
                    }

                    ForEach(SampleScreens.all) { layout in
                        screenCard(layout)
                    }

                    if !status.isEmpty {
                        Text(status)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding()
            }
            .navigationTitle("Screens")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showCreate) {
                CreateScreenView(customStore: customStore)
            }
        }
    }

    @ViewBuilder
    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.title3.bold())
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
    }

    @ViewBuilder
    private func screenCard(_ layout: ScreenLayout, deletable: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            preview(of: layout)
                .aspectRatio(CGFloat(targetModel.width) / CGFloat(targetModel.height),
                             contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8)
                    .stroke(.gray.opacity(0.3), lineWidth: 1))

            HStack {
                Text(layout.name)
                    .font(.headline)
                Spacer()
                if deletable {
                    Button(role: .destructive) {
                        customStore.remove(layout)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                }
            }
            if let description = layout.description {
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if layout.containsClock {
                Label("Shows the time it was sent — frames can't tick yet.",
                      systemImage: "clock.badge.exclamationmark")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Button {
                Task { await send(layout) }
            } label: {
                Group {
                    if sendingScreen == layout.name {
                        ProgressView()
                    } else {
                        Label(sendButtonTitle, systemImage: "paperplane.fill")
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .disabled(store.frames.isEmpty || sendingScreen != nil)
        }
        .padding(12)
        .background(.gray.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var sendButtonTitle: String {
        if let frame = store.selectedFrame, store.frames.count > 1 {
            return "Send to \(frame.name)"
        }
        return "Send to Frame"
    }

    @ViewBuilder
    private func preview(of layout: ScreenLayout) -> some View {
        let rendered = ScreenRenderer.render(layout, for: targetModel)
        if let cg = rendered.cgImage {
            Image(decorative: cg, scale: 1, orientation: .up)
                .resizable()
                .interpolation(.none)
        } else {
            Rectangle().fill(.gray.opacity(0.15))
        }
    }

    private func send(_ layout: ScreenLayout) async {
        guard let frame = store.selectedFrame else {
            status = "No frame selected."
            return
        }
        sendingScreen = layout.name
        defer { sendingScreen = nil }

        let rendered = ScreenRenderer.render(layout, for: frame.model)
        guard let blob = EinkConverter.convert(rendered, for: frame.model) else {
            status = "Could not render \(layout.name)."
            return
        }
        do {
            try await FrameService.upload(blob, to: frame)
            AppAnalytics.log("screen_sent", [
                "panel": frame.model.rawValue,
                "custom": customStore.screens.contains { $0.name == layout.name } ? 1 : 0,
            ])
            status = "Sent! \(frame.name) will show \(layout.name) within 30 minutes — or press \(frame.model.syncButtonHint) to show it now."
        } catch {
            status = "Send failed — \(error.localizedDescription)"
        }
    }
}
