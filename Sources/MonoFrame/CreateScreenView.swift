import SwiftUI

// "Create new screen": describe a screen in plain words and either (a) let
// the app call an LLM with your own API key (Groq free tier by default), or
// (b) copy a ready-made prompt into any AI chat app and paste its reply
// back. Both paths validate against the ScreenLayout schema and preview
// before saving to CustomScreenStore.
struct CreateScreenView: View {
    @ObservedObject var customStore: CustomScreenStore
    @EnvironmentObject private var frameStore: FrameStore
    @Environment(\.dismiss) private var dismiss

    @State private var request = ""
    @State private var provider = LLMSettings.selectedProvider
    @State private var model = LLMSettings.model(for: LLMSettings.selectedProvider)
    @State private var apiKey = LLMSettings.apiKey(for: LLMSettings.selectedProvider)
    @State private var generated: ScreenLayout?
    @State private var isBusy = false
    @State private var errorText = ""
    @State private var pastedReply = ""
    @State private var promptCopied = false

    private var targetModel: DeviceModel {
        frameStore.selectedFrame?.model ?? .reTerminalE1001
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("What should the screen show?") {
                    TextField("e.g. A big countdown to Dec 25 labeled UNTIL CHRISTMAS, with today's date small at the bottom",
                              text: $request, axis: .vertical)
                        .lineLimit(3...6)
                }

                Section("Model") {
                    Picker("Provider", selection: $provider) {
                        ForEach(LLMProvider.allCases) { p in
                            Text(p.displayName).tag(p)
                        }
                    }
                    .onChange(of: provider) { _, p in
                        LLMSettings.selectedProvider = p
                        model = LLMSettings.model(for: p)
                        apiKey = LLMSettings.apiKey(for: p)
                    }
                    TextField("Model", text: $model)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .onChange(of: model) { _, m in
                            LLMSettings.setModel(m, for: provider)
                        }
                    if provider.needsKey {
                        SecureField("API key", text: $apiKey)
                            .onChange(of: apiKey) { _, k in
                                LLMSettings.setAPIKey(k, for: provider)
                            }
                    }
                    Text("Your key stays on this device and calls go straight to the provider. Groq keys are free at console.groq.com.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Button {
                        Task { await generate() }
                    } label: {
                        HStack {
                            Spacer()
                            if isBusy {
                                ProgressView()
                            } else {
                                Label(generated == nil ? "Generate" : "Regenerate",
                                      systemImage: "sparkles")
                            }
                            Spacer()
                        }
                    }
                    .disabled(request.trimmingCharacters(in: .whitespaces).isEmpty || isBusy)
                }

                Section("No API key? Use any AI chat") {
                    Text("Copy the prompt, run it in ChatGPT, Claude, Gemini — anything — then paste the reply here.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button {
                        UIPasteboard.general.string = ScreenGenerator.clipboardPrompt(
                            request: request, for: targetModel)
                        promptCopied = true
                    } label: {
                        Label(promptCopied ? "Prompt Copied" : "Copy Prompt",
                              systemImage: promptCopied ? "checkmark" : "doc.on.doc")
                    }
                    .disabled(request.trimmingCharacters(in: .whitespaces).isEmpty)
                    TextField("Paste the AI's reply here", text: $pastedReply, axis: .vertical)
                        .lineLimit(2...5)
                        .font(.footnote.monospaced())
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    Button {
                        useReply()
                    } label: {
                        Label("Use Reply", systemImage: "arrow.down.doc")
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
            errorText = error.localizedDescription
        }
    }

    private func generate() async {
        isBusy = true
        errorText = ""
        defer { isBusy = false }
        do {
            generated = try await ScreenGenerator.generate(
                request: request,
                provider: provider,
                model: model,
                apiKey: apiKey,
                for: targetModel
            )
        } catch {
            errorText = error.localizedDescription
        }
    }
}
