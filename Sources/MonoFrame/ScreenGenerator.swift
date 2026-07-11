import Foundation

// The copy-paste screen designer: builds a prompt any AI chat can answer,
// and ingests the reply back into a ScreenLayout. There is deliberately no
// API-key path — the user's own chat app (ChatGPT, Claude, Gemini, …) does
// the generation; this code only has to be forgiving about what comes back.
enum ScreenGenerator {

    enum GeneratorError: LocalizedError {
        case noJSON
        case invalidLayout(String)

        var errorDescription: String? {
            switch self {
            case .noJSON:
                return "No JSON found — paste the AI's whole reply, including the {...} block."
            case .invalidLayout(let why):
                return "Couldn't read the layout: \(why)"
            }
        }
    }

    // MARK: - Prompt

    /// Everything an external AI chat needs to produce JSON this app can
    /// ingest, including the target panel's exact size.
    static func clipboardPrompt(request: String, for model: DeviceModel) -> String {
        systemPrompt(for: model)
            + "\n\nRequest: " + request
            + "\n\nReply with ONLY the JSON object in a single code block."
    }

    static func systemPrompt(for model: DeviceModel) -> String {
        """
        You design screens for a black & white e-ink display, \(model.width)x\(model.height) \
        pixels, 1-bit (pure black on white, no grays).

        Output one JSON object matching this schema exactly:
        {"version":1,"name":"Short Name","description":"one sentence","widgets":[
          {"type":"<type>","frame":{"x":0.0,"y":0.0,"w":1.0,"h":1.0},"props":{...}}]}

        frame values are FRACTIONS of the screen (0.0-1.0); x,y is the top-left corner.
        The ONLY valid widget types and their props (all props optional unless noted):
        - "text": props.text (required), props.weight "regular"|"bold", props.align \
        "leading"|"center"|"trailing", props.inverted true = white-on-black banner
        - "date": today's date. props.style "long"|"short"
        - "clock": time of render. props.twentyFourHour, props.style "hm"|"hms"
        - "countdown": days until props.target "YYYY-MM-DD" (required), props.label caption
        - "calendarMonth": this month's grid, today circled. Needs w>=0.4 and h>=0.5 to be legible.
        - "divider": horizontal line
        - "box": outline rectangle for grouping

        Rules:
        - Strict JSON only: straight double quotes, no trailing commas, no comments.
        - Do not invent widget types — anything not in the list above is dropped.
        - The screen is sent as a static picture: prefer date-stable content (calendar, \
        countdown, text). Use "clock" only if the user asks for one.
        - Text height comes from frame.h — a hero line wants h 0.2-0.4, a caption 0.08-0.12.
        - Don't overlap text widgets; leave 0.02-0.04 gaps. 3-6 widgets is usually right.
        - Keep name under 24 characters.
        """
    }

    // MARK: - Parsing

    /// Pulls the outermost JSON object out of a pasted reply and decodes it.
    /// Chat apps mangle JSON in predictable ways (code fences, prose around
    /// the block, smart quotes, trailing commas) — all are repaired here.
    static func parseLayout(from reply: String) throws -> ScreenLayout {
        guard let start = reply.firstIndex(of: "{"),
              let end = reply.lastIndex(of: "}"), start < end else {
            throw GeneratorError.noJSON
        }
        let raw = String(reply[start...end])

        var lastProblem = "unknown"
        for candidate in [raw, repaired(raw)] {
            do {
                return try validate(try ScreenLayout.decode(fromJSON: candidate))
            } catch let error as GeneratorError {
                throw error // validation problems don't improve with repair
            } catch {
                lastProblem = describe(error)
            }
        }
        throw GeneratorError.invalidLayout(lastProblem)
    }

    private static func validate(_ layout: ScreenLayout) throws -> ScreenLayout {
        guard !layout.widgets.isEmpty else {
            throw GeneratorError.invalidLayout(
                "no usable widgets — the reply may have invented widget types")
        }
        guard !layout.name.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw GeneratorError.invalidLayout("the layout has no name")
        }
        return layout
    }

    /// Undoes the damage chat apps and keyboards do to copied JSON.
    static func repaired(_ json: String) -> String {
        var s = json
        // Smart punctuation (iOS keyboards, some chat renderers).
        for (bad, good) in [("\u{201C}", "\""), ("\u{201D}", "\""), ("\u{201E}", "\""),
                            ("\u{2018}", "'"), ("\u{2019}", "'")] {
            s = s.replacingOccurrences(of: bad, with: good)
        }
        // Trailing commas before a closing brace/bracket.
        s = s.replacingOccurrences(of: #",\s*([}\]])"#, with: "$1",
                                   options: .regularExpression)
        return s
    }

    private static func describe(_ error: Error) -> String {
        guard let decoding = error as? DecodingError else {
            return error.localizedDescription
        }
        switch decoding {
        case .keyNotFound(let key, let ctx):
            return "missing \"\(key.stringValue)\" at \(path(ctx))"
        case .typeMismatch(_, let ctx):
            return "wrong value type at \(path(ctx))"
        case .valueNotFound(_, let ctx):
            return "missing value at \(path(ctx))"
        case .dataCorrupted(let ctx):
            return ctx.debugDescription.isEmpty ? "malformed JSON" : ctx.debugDescription
        @unknown default:
            return decoding.localizedDescription
        }
    }

    private static func path(_ ctx: DecodingError.Context) -> String {
        let p = ctx.codingPath.map { $0.intValue.map { "[\($0)]" } ?? $0.stringValue }
            .joined(separator: ".")
        return p.isEmpty ? "top level" : p
    }
}
