import SwiftUI

// "Create new screen", no API key required: describe the screen, copy a
// ready-made prompt into any AI chat (ChatGPT, Claude, Gemini, …), paste the
// reply back, preview, save. The prompt embeds the target panel's size and
// the widget schema; parseLayout repairs common chat-app JSON damage.
struct CreateScreenView: View {
    @ObservedObject var customStore: CustomScreenStore
    @EnvironmentObject private var frameStore: FrameStore
    @Environment(\.dismiss) private var dismiss

    @State private var request = ""
    @State private var pastedReply = ""
    @State private var promptCopied = false
    @State private var generated: ScreenLayout?
    @State private var errorText = ""

    private var targetModel: DeviceModel {
        frameStore.selectedFrame?.model ?? .crowPanel42
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("1. What should the screen show?") {
                    TextField("e.g. A big countdown to Dec 25 labeled UNTIL CHRISTMAS, with today's date small at the bottom",
                              text: $request, axis: .vertical)
                        .lineLimit(3...6)
                        .onChange(of: request) { _, _ in promptCopied = false }
                }

                Section("2. Ask any AI chat") {
                    Button {
                        UIPasteboard.general.string = ScreenGenerator.clipboardPrompt(
                            request: request, for: targetModel)
                        promptCopied = true
                    } label: {
                        Label(promptCopied ? "Prompt Copied — paste it in your AI app" : "Copy Prompt",
                              systemImage: promptCopied ? "checkmark" : "doc.on.doc")
                    }
                    .disabled(request.trimmingCharacters(in: .whitespaces).isEmpty)
                    Text("Works with ChatGPT, Claude, Gemini — anything. The prompt already knows your frame is \(targetModel.resolutionText).")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Link(destination: URL(string: "https://jbaker00.github.io/MonoFrame/support.html#mcp")!) {
                        Label("Using Claude or another MCP assistant? Registration options here",
                              systemImage: "link")
                            .font(.footnote)
                    }
                }

                Section("3. Paste the AI's reply") {
                    TextField("Paste the whole reply here", text: $pastedReply, axis: .vertical)
                        .lineLimit(2...6)
                        .font(.footnote.monospaced())
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    Button {
                        useReply()
                    } label: {
                        Label("Build Screen", systemImage: "wand.and.stars")
                    }
                    .disabled(pastedReply.trimmingCharacters(in: .whitespaces).isEmpty)
                }

                if !errorText.isEmpty {
                    Section {
                        Text(errorText)
                            .font(.callout)
                            .foregroundStyle(.red)
                    }
                }

                if let layout = generated {
                    Section(layout.name) {
                        preview(of: layout)
                            .aspectRatio(CGFloat(targetModel.width) / CGFloat(targetModel.height),
                                         contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        if let description = layout.description {
                            Text(description)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Button {
                            customStore.add(layout)
                            dismiss()
                        } label: {
                            Label("Save to My Screens", systemImage: "square.and.arrow.down")
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
            .navigationTitle("Create Screen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
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

    private func useReply() {
        errorText = ""
        do {
            generated = try ScreenGenerator.parseLayout(from: pastedReply)
        } catch {
            generated = nil
            errorText = error.localizedDescription
        }
    }
}
