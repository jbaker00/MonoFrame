import SwiftUI
import PhotosUI

struct ContentView: View {
    @State private var pickedItem: PhotosPickerItem?
    @State private var pickedImage: UIImage?
    @State private var previewCGImage: CGImage?
    @State private var status: String = ""
    @State private var isBusy = false
    @State private var showFrames = false

    @EnvironmentObject private var store: FrameStore

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    previewBox

                    PhotosPicker(selection: $pickedItem,
                                 matching: .images,
                                 photoLibrary: .shared()) {
                        Label("Pick a Photo", systemImage: "photo.on.rectangle.angled")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(.tint.opacity(0.15))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .onChange(of: pickedItem) { _, item in
                        Task { await loadPick(item) }
                    }
                    .onChange(of: store.selectedFrameId) { _, _ in
                        rerenderPreview()
                    }

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

                    if store.frames.isEmpty {
                        Button {
                            showFrames = true
                        } label: {
                            Label("Set Up Your Frame", systemImage: "plus.circle.fill")
                                .frame(maxWidth: .infinity)
                                .padding()
                        }
                        .buttonStyle(.borderedProminent)
                    } else {
                        Button {
                            Task { await send(to: store.selectedFrame.map { [$0] } ?? []) }
                        } label: {
                            Group {
                                if isBusy {
                                    ProgressView()
                                } else {
                                    Label(sendButtonTitle, systemImage: "paperplane.fill")
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(pickedImage == nil || isBusy)

                        if store.frames.count > 1 {
                            Button {
                                Task { await send(to: store.frames) }
                            } label: {
                                Label("Send to All Frames", systemImage: "paperplane")
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                            }
                            .buttonStyle(.bordered)
                            .disabled(pickedImage == nil || isBusy)
                        }
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
            .navigationTitle("MonoFrame")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showFrames = true
                    } label: {
                        Label("My Frames", systemImage: "photo.tv")
                    }
                }
            }
            .sheet(isPresented: $showFrames) {
                FramesView()
            }
        }
    }

    private var sendButtonTitle: String {
        if let frame = store.selectedFrame, store.frames.count > 1 {
            return "Send to \(frame.name)"
        }
        return "Send to Frame"
    }

    // The preview (and payload) is rendered for the selected frame's panel.
    private var targetModel: DeviceModel {
        store.selectedFrame?.model ?? .crowPanel42
    }

    @ViewBuilder
    private var previewBox: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(.gray.opacity(0.15))
            if let cg = previewCGImage {
                Image(decorative: cg, scale: 1, orientation: .up)
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
                    .padding(8)
            } else {
                VStack(spacing: 6) {
                    Image(systemName: "photo")
                        .font(.system(size: 36))
                        .foregroundStyle(.secondary)
                    Text(targetModel.resolutionText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .aspectRatio(CGFloat(targetModel.width) / CGFloat(targetModel.height),
                     contentMode: .fit)
        .frame(maxWidth: 480)
    }

    private func loadPick(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        status = "Processing…"
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let img = UIImage(data: data) else {
                status = "Could not load image."
                return
            }
            pickedImage = img
            previewCGImage = EinkConverter.previewCGImage(from: img, for: targetModel)
            status = previewCGImage == nil
                ? "Could not render preview."
                : "Ready to send."
        } catch {
            status = "Load error: \(error.localizedDescription)"
        }
    }

    private func rerenderPreview() {
        guard let img = pickedImage else { return }
        previewCGImage = EinkConverter.previewCGImage(from: img, for: targetModel)
    }

    private func send(to frames: [Frame]) async {
        guard !frames.isEmpty else {
            status = "No frame selected."
            return
        }
        guard let img = pickedImage else {
            status = "Could not convert image."
            return
        }
        isBusy = true
        defer { isBusy = false }

        // Frames can have different panels; dither once per resolution.
        var blobs: [DeviceModel: Data] = [:]
        var failures: [String] = []
        for frame in frames {
            let blob: Data
            if let cached = blobs[frame.model] {
                blob = cached
            } else if let converted = EinkConverter.convert(img, for: frame.model) {
                blobs[frame.model] = converted
                blob = converted
            } else {
                failures.append("\(frame.name): could not convert image")
                continue
            }
            do {
                try await FrameService.upload(blob, to: frame)
            } catch {
                failures.append("\(frame.name): \(error.localizedDescription)")
            }
        }
        if failures.isEmpty {
            status = frames.count == 1
                ? "Sent! \(frames[0].name) will show it within 30 minutes — or press the button on the back to show it now."
                : "Sent to all \(frames.count) frames. They'll show it within 30 minutes — or press the button on the back of a frame to show it now."
        } else {
            status = "Some sends failed — \(failures.joined(separator: "; "))"
        }
    }
}
