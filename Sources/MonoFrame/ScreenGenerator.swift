import Foundation
import Security

// Generates ScreenLayout JSON from a plain-language description using the
// user's own LLM API key (bring-your-own-key: calls go straight from the
// phone to the chosen provider, nothing is proxied). Groq is the default —
// it has a free tier. No key at all? CreateScreenView also offers a
// copy-the-prompt / paste-the-reply path for any AI chat app.
enum LLMProvider: String, CaseIterable, Identifiable, Codable {
    case groq
    case openRouter
    case openAI
    case ollama
    case anthropic

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .groq: "Groq (free)"
        case .openRouter: "OpenRouter"
        case .openAI: "OpenAI"
        case .ollama: "Ollama (local)"
        case .anthropic: "Anthropic"
        }
    }

    var defaultModel: String {
        switch self {
        case .groq: "llama-3.3-70b-versatile"
        case .openRouter: "openai/gpt-4o-mini"
        case .openAI: "gpt-4o-mini"
        case .ollama: "llama3.1"
        case .anthropic: "claude-haiku-4-5-20251001"
        }
    }

    var endpoint: URL {
        switch self {
        case .groq: URL(string: "https://api.groq.com/openai/v1/chat/completions")!
        case .openRouter: URL(string: "https://openrouter.ai/api/v1/chat/completions")!
        case .openAI: URL(string: "https://api.openai.com/v1/chat/completions")!
        case .ollama: URL(string: "http://127.0.0.1:11434/v1/chat/completions")!
        case .anthropic: URL(string: "https://api.anthropic.com/v1/messages")!
        }
    }

    var needsKey: Bool { self != .ollama }
}

enum ScreenGenerator {

    enum GeneratorError: LocalizedError {
        case missingKey(LLMProvider)
        case badResponse(Int, String)
        case emptyReply
        case invalidLayout(String)

        var errorDescription: String? {
            switch self {
            case .missingKey(let p):
                return "No API key saved for \(p.displayName). Add one in the form below."
            case .badResponse(let code, let body):
                return "\(code) from provider: \(body.prefix(200))"
            case .emptyReply:
                return "The model returned an empty reply."
            case .invalidLayout(let why):
                return "The model's JSON didn't decode: \(why)"
            }
        }
    }

    /// The full prompt for the copy-paste path: everything an external AI
    /// chat needs to produce JSON this app can ingest, including panel size.
    static func clipboardPrompt(request: String, for model: DeviceModel) -> String {
        systemPrompt(for: model) + "\n\nRequest: " + request
    }

    /// One generation attempt plus one self-repair retry on invalid JSON.
    static func generate(request: String, provider: LLMProvider, model: String,
                         apiKey: String, for deviceModel: DeviceModel) async throws -> ScreenLayout {
        let system = systemPrompt(for: deviceModel)
        do {
            let reply = try await complete(system: system, user: request,
                                           provider: provider, model: model, apiKey: apiKey)
            return try parseLayout(from: reply)
        } catch let error as GeneratorError {
            guard case .invalidLayout(let why) = error else { throw error }
            let repair = request + "\n\nYour previous reply was not valid layout JSON (\(why)). " +
                "Respond with ONLY the corrected JSON object — no prose, no code fences."
            let reply = try await complete(system: system, user: repair,
                                           provider: provider, model: model, apiKey: apiKey)
            return try parseLayout(from: reply)
        }
    }

    // MARK: - Prompt

    static func systemPrompt(for model: DeviceModel) -> String {
        """
        You design screens for a black & white e-ink display, \(model.width)x\(model.height) \
        pixels, 1-bit (pure black on white, no grays).

        Reply with ONLY one JSON object matching this schema — no markdown fences, no commentary:
        {"version":1,"name":"Short Name","description":"one sentence","widgets":[
          {"type":"<type>","frame":{"x":0.0,"y":0.0,"w":1.0,"h":1.0},"props":{...}}]}

        frame values are FRACTIONS of the screen (0.0-1.0); x,y is the top-left corner.
        Widget types and their props (all props optional unless noted):
        - "text": props.text (required), props.weight "regular"|"bold", props.align \
        "leading"|"center"|"trailing", props.inverted true = white-on-black banner
        - "date": today's date. props.style "long"|"short"
        - "clock": time of render. props.twentyFourHour, props.style "hm"|"hms"
        - "countdown": days until props.target "YYYY-MM-DD" (required), props.label caption
        - "calendarMonth": this month's grid, today circled. Needs w>=0.4 and h>=0.5 to be legible.
        - "divider": horizontal line
        - "box": outline rectangle for grouping

        Rules:
        - The screen is sent as a static picture: prefer date-stable content (calendar, \
        countdown, text). Use "clock" only if the user asks for one.
        - Text height comes from frame.h — a hero line wants h 0.2-0.4, a caption 0.08-0.12.
        - Don't overlap text widgets; leave 0.02-0.04 gaps. 3-6 widgets is usually right.
        - Keep name under 24 characters.
        """
    }

    // MARK: - Provider calls

    private static func complete(system: String, user: String, provider: LLMProvider,
                                 model: String, apiKey: String) async throws -> String {
        if provider.needsKey && apiKey.isEmpty {
            throw GeneratorError.missingKey(provider)
        }

        var req = URLRequest(url: provider.endpoint)
        req.httpMethod = "POST"
        req.timeoutInterval = 90
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any]
        if provider == .anthropic {
            req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            body = [
                "model": model,
                "max_tokens": 1500,
                "system": system,
                "messages": [["role": "user", "content": user]],
            ]
        } else {
            if provider.needsKey {
                req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            }
            body = [
                "model": model,
                "temperature": 0.7,
                "messages": [
                    ["role": "system", "content": system],
                    ["role": "user", "content": user],
                ],
            ]
        }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
            throw GeneratorError.badResponse(code, String(data: data, encoding: .utf8) ?? "")
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw GeneratorError.emptyReply
        }
        let content: String?
        if provider == .anthropic {
            let blocks = json["content"] as? [[String: Any]]
            content = blocks?.compactMap { $0["text"] as? String }.joined()
        } else {
            let choices = json["choices"] as? [[String: Any]]
            let message = choices?.first?["message"] as? [String: Any]
            content = message?["content"] as? String
        }
        guard let content, !content.isEmpty else { throw GeneratorError.emptyReply }
        return content
    }

    // MARK: - Parsing

    /// Pulls the outermost JSON object out of the reply (models love fences
    /// and preambles despite instructions) and decodes it.
    static func parseLayout(from reply: String) throws -> ScreenLayout {
        guard let start = reply.firstIndex(of: "{"),
              let end = reply.lastIndex(of: "}"), start < end else {
            throw GeneratorError.invalidLayout("no JSON object found in the reply")
        }
        let json = String(reply[start...end])
        do {
            let layout = try ScreenLayout.decode(fromJSON: json)
            guard !layout.widgets.isEmpty else {
                throw GeneratorError.invalidLayout("layout has no widgets")
            }
            guard !layout.name.trimmingCharacters(in: .whitespaces).isEmpty else {
                throw GeneratorError.invalidLayout("layout has no name")
            }
            return layout
        } catch let error as GeneratorError {
            throw error
        } catch {
            throw GeneratorError.invalidLayout(error.localizedDescription)
        }
    }
}

// API keys per provider, in the Keychain; model overrides and the selected
// provider in UserDefaults (not secret).
enum LLMSettings {
    private static let service = "com.jamesbaker.MonoFrame.llmKeys"

    static var selectedProvider: LLMProvider {
        get {
            UserDefaults.standard.string(forKey: "llmProvider")
                .flatMap(LLMProvider.init(rawValue:)) ?? .groq
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "llmProvider") }
    }

    static func model(for provider: LLMProvider) -> String {
        UserDefaults.standard.string(forKey: "llmModel.\(provider.rawValue)")
            ?? provider.defaultModel
    }

    static func setModel(_ model: String, for provider: LLMProvider) {
        UserDefaults.standard.set(model, forKey: "llmModel.\(provider.rawValue)")
    }

    static func apiKey(for provider: LLMProvider) -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    static func setAPIKey(_ key: String, for provider: LLMProvider) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider.rawValue,
        ]
        SecItemDelete(query as CFDictionary)
        guard !key.isEmpty else { return }
        var add = query
        add[kSecValueData as String] = Data(key.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }
}
