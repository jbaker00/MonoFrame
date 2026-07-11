import XCTest
@testable import MonoFrame


final class ScreenGeneratorTests: XCTestCase {

    private let validJSON = """
    {"version":1,"name":"Test","widgets":[
      {"type":"text","frame":{"x":0.1,"y":0.1,"w":0.8,"h":0.3},"props":{"text":"HI"}}]}
    """

    func testParsesBareJSON() throws {
        let layout = try ScreenGenerator.parseLayout(from: validJSON)
        XCTAssertEqual(layout.name, "Test")
        XCTAssertEqual(layout.widgets.count, 1)
    }

    // Models add fences and prose no matter what the prompt says.
    func testParsesFencedAndPrefacedJSON() throws {
        let reply = "Here is your screen!\n```json\n\(validJSON)\n```\nEnjoy."
        let layout = try ScreenGenerator.parseLayout(from: reply)
        XCTAssertEqual(layout.name, "Test")
    }

    func testRejectsReplyWithoutJSON() {
        XCTAssertThrowsError(try ScreenGenerator.parseLayout(from: "sorry, I can't"))
    }

    func testRejectsEmptyWidgets() {
        let empty = #"{"version":1,"name":"Empty","widgets":[]}"#
        XCTAssertThrowsError(try ScreenGenerator.parseLayout(from: empty))
    }

    // Out-of-range frames from a sloppy model must clamp, not crash or reject.
    func testClampsWildFrames() throws {
        let wild = """
        {"version":1,"name":"Wild","widgets":[
          {"type":"text","frame":{"x":-0.5,"y":0.9,"w":9,"h":3},"props":{"text":"X"}}]}
        """
        let layout = try ScreenGenerator.parseLayout(from: wild)
        let frame = layout.widgets[0].frame
        XCTAssertEqual(frame.x, 0)
        XCTAssertLessThanOrEqual(frame.y + frame.h, 1.0001)
        XCTAssertLessThanOrEqual(frame.x + frame.w, 1.0001)
    }

    // A realistic claude.ai-style reply: prose, a fenced block, a trailing
    // comma, and a closing question. This shape failed in the field before
    // the repair pass existed.
    func testParsesChatAppReplyWithTrailingComma() throws {
        let reply = """
        Here's a screen layout for your frame:

        ```json
        {
          "version": 1,
          "name": "Coffee Fund",
          "description": "Days until payday with a banner.",
          "widgets": [
            {"type": "text", "frame": {"x": 0.0, "y": 0.05, "w": 1.0, "h": 0.2}, \
        "props": {"text": "PAYDAY", "weight": "bold", "inverted": true}},
            {"type": "countdown", "frame": {"x": 0.1, "y": 0.35, "w": 0.8, "h": 0.4}, \
        "props": {"target": "2026-07-31", "label": "to go"}},
          ]
        }
        ```

        Want me to adjust the spacing or add today's date?
        """
        let layout = try ScreenGenerator.parseLayout(from: reply)
        XCTAssertEqual(layout.name, "Coffee Fund")
        XCTAssertEqual(layout.widgets.count, 2)
    }

    // Smart punctuation (iOS keyboards / some chat renderers) turns straight
    // quotes curly — the paste must survive it.
    func testParsesSmartQuotedJSON() throws {
        let smart = validJSON.replacingOccurrences(of: "\"", with: "\u{201C}")
        let layout = try ScreenGenerator.parseLayout(from: smart)
        XCTAssertEqual(layout.name, "Test")
    }

    // Invented widget types drop out; the rest of the screen survives.
    func testDropsUnknownWidgetTypes() throws {
        let reply = """
        {"version":1,"name":"Mixed","widgets":[
          {"type":"weatherRadar","frame":{"x":0,"y":0,"w":1,"h":0.4},"props":{}},
          {"type":"text","frame":{"x":0,"y":0.5,"w":1,"h":0.3},"props":{"text":"OK"}}]}
        """
        let layout = try ScreenGenerator.parseLayout(from: reply)
        XCTAssertEqual(layout.widgets.count, 1)
        XCTAssertEqual(layout.widgets[0].type, .text)
    }

    // All-invented widgets should fail with the helpful message, not render
    // an empty screen.
    func testAllUnknownWidgetsFailsClearly() {
        let reply = """
        {"version":1,"name":"Nope","widgets":[
          {"type":"stockTicker","frame":{"x":0,"y":0,"w":1,"h":1},"props":{}}]}
        """
        XCTAssertThrowsError(try ScreenGenerator.parseLayout(from: reply)) { error in
            XCTAssertTrue(error.localizedDescription.contains("widget types"))
        }
    }

    // A missing "version" key shouldn't sink the screen either.
    func testMissingVersionDefaultsTo1() throws {
        let reply = #"{"name":"NoVer","widgets":[{"type":"date","frame":{"x":0,"y":0.4,"w":1,"h":0.2}}]}"#
        let layout = try ScreenGenerator.parseLayout(from: reply)
        XCTAssertEqual(layout.version, 1)
    }

    // Verbatim llama-3.3-70b-versatile output from the real system prompt
    // (Groq, 2026-07-11) — the generator's contract, end to end.
    func testRealGroqOutputDecodesAndRenders() throws {
        let reply = """
        {"version": 1, "name": "Hawaii", "description": "Countdown to Hawaii vacation", \
        "widgets": [{"type": "text", "frame": {"x": 0.0, "y": 0.0, "w": 1.0, "h": 0.2}, \
        "props": {"text": "HAWAII", "weight": "bold", "align": "center"}}, \
        {"type": "countdown", "frame": {"x": 0.0, "y": 0.25, "w": 1.0, "h": 0.3}, \
        "props": {"target": "2026-08-20", "label": "Days to Vacation"}}, \
        {"type": "date", "frame": {"x": 0.0, "y": 0.9, "w": 1.0, "h": 0.08}, \
        "props": {"style": "short"}}]}
        """
        let layout = try ScreenGenerator.parseLayout(from: reply)
        XCTAssertEqual(layout.widgets.count, 3)
        for model in DeviceModel.allCases {
            let image = ScreenRenderer.render(layout, for: model)
            XCTAssertEqual(EinkConverter.convert(image, for: model)?.count, model.byteCount)
        }
        let png = ScreenRenderer.render(layout, for: .reTerminalE1001).pngData()
        try png?.write(to: URL(fileURLWithPath: "/tmp/monoframe-screens/Generated-Hawaii.png"))
    }

    @MainActor
    func testCustomStoreUniquesNames() {
        let store = CustomScreenStore()
        let before = store.screens
        defer { before.isEmpty ? store.screens.forEach { store.remove($0) } : () }

        let layout = try! ScreenGenerator.parseLayout(from: validJSON)
        store.add(layout)
        store.add(layout)
        let names = store.screens.map(\.name)
        XCTAssertTrue(names.contains("Test"))
        XCTAssertTrue(names.contains("Test 2"))
        store.remove(store.screens.first { $0.name == "Test" }!)
        store.remove(store.screens.first { $0.name == "Test 2" }!)
    }
}
