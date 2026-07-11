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
