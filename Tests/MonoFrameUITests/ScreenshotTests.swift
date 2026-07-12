import XCTest

// Drives the app through the demo-frame flow and saves marketing screenshots
// as PNGs. Run on a fresh simulator; output dir comes from the MF_SHOT_DIR
// test-runner env var (default /tmp/mf-shots).
final class ScreenshotTests: XCTestCase {

    var app: XCUIApplication!
    let shotDir = URL(fileURLWithPath:
        ProcessInfo.processInfo.environment["MF_SHOT_DIR"] ?? "/tmp/mf-shots")

    override func setUpWithError() throws {
        continueAfterFailure = false
        try FileManager.default.createDirectory(at: shotDir, withIntermediateDirectories: true)
        app = XCUIApplication()
        app.launchArguments = ["-screenshots"]
        app.launch()
    }

    func snap(_ name: String) {
        // Let animations settle.
        Thread.sleep(forTimeInterval: 1.0)
        let png = XCUIScreen.main.screenshot().pngRepresentation
        try? png.write(to: shotDir.appendingPathComponent("\(name).png"))
    }

    func testCaptureScreenshots() throws {
        // ---- Pair first demo frame (capture wizard on the way) ----
        openAddFrameWizard(firstFrame: true)
        XCTAssertTrue(app.staticTexts["Get your frame ready"].waitForExistence(timeout: 10))
        snap("03-wizard-intro")
        pairDemoFrame(named: "Living Room", captureSuccess: true)

        // ---- Pair second demo frame ----
        openAddFrameWizard(firstFrame: false)
        _ = app.staticTexts["Get your frame ready"].waitForExistence(timeout: 10)
        pairDemoFrame(named: "Kitchen", captureSuccess: false)

        // ---- Stamp lastSeen for both frames so the list looks alive ----
        for name in ["Living Room", "Kitchen"] {
            stampLastSeen(frameNamed: name)
        }

        // Reopen My Frames so statuses refresh, then capture the list.
        app.buttons["Done"].firstMatch.tap()
        openMyFrames()
        _ = app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH 'Last seen'")
        ).firstMatch.waitForExistence(timeout: 20)
        snap("02-my-frames")
        app.buttons["Done"].firstMatch.tap()

        // ---- Pick a photo, capture the dithered hero shot ----
        app.buttons["Pick a Photo"].tap()
        pickFirstLibraryPhoto()
        XCTAssertTrue(app.staticTexts["Ready to send."].waitForExistence(timeout: 30))
        snap("01-hero-preview")

        // ---- Send and capture confirmation ----
        let send = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH 'Send to'")
        ).firstMatch
        if send.waitForExistence(timeout: 5) {
            send.tap()
            let sent = app.staticTexts.matching(
                NSPredicate(format: "label BEGINSWITH 'Sent!'")
            ).firstMatch
            if sent.waitForExistence(timeout: 30) {
                snap("04-sent")
            }
        }
    }

    // Re-captures just the photo-preview and sent shots; assumes frames are
    // already paired on the simulator.
    func testHeroShots() throws {
        app.buttons["Pick a Photo"].tap()
        pickFirstLibraryPhoto()
        XCTAssertTrue(app.staticTexts["Ready to send."].waitForExistence(timeout: 30))
        snap("01-hero-preview")

        let send = app.buttons.matching(NSPredicate(
            format: "label BEGINSWITH 'Send to' AND NOT (label CONTAINS 'All')"
        )).firstMatch
        XCTAssertTrue(send.waitForExistence(timeout: 5))
        send.tap()
        let sent = app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH 'Sent'")
        ).firstMatch
        XCTAssertTrue(sent.waitForExistence(timeout: 30))
        snap("04-sent")
    }

    // Captures the Screens picker and the AI Create Screen flow (v1.2).
    // Assumes frames are already paired on the simulator.
    func testScreensShots() throws {
        app.buttons["Screens"].firstMatch.tap()
        // Sample cards render live previews; give the renderer a beat.
        XCTAssertTrue(app.staticTexts["Month at a Glance"].waitForExistence(timeout: 15))
        snap("06-screens")

        app.buttons["Create New Screen"].firstMatch.tap()
        _ = app.navigationBars["Create Screen"].waitForExistence(timeout: 10)
        // Two text inputs in the sheet: [0] the description, [1] the reply.
        let request = app.textFields.element(boundBy: 0)
        XCTAssertTrue(request.waitForExistence(timeout: 10))
        request.tap()
        request.typeText("A countdown to our Hawaii vacation on Aug 20 with a bold HAWAII banner")
        app.buttons["Copy Prompt"].firstMatch.tap()

        let reply = app.textFields.element(boundBy: 1)
        XCTAssertTrue(reply.waitForExistence(timeout: 10))
        reply.tap()
        let layoutJSON = """
        {"version":1,"name":"Hawaii Countdown","description":"Days until the trip, at a glance.",\
        "widgets":[{"type":"text","frame":{"x":0,"y":0.05,"w":1,"h":0.18},\
        "props":{"text":"HAWAII","weight":"bold","inverted":true}},\
        {"type":"countdown","frame":{"x":0.1,"y":0.3,"w":0.8,"h":0.42},\
        "props":{"target":"2026-08-20","label":"until vacation"}},\
        {"type":"date","frame":{"x":0.1,"y":0.85,"w":0.8,"h":0.1},"props":{"style":"short"}}]}
        """
        reply.typeText(layoutJSON)
        app.buttons["Build Screen"].firstMatch.tap()
        // The preview section renders below the fold, and Form rows are lazy
        // — scroll until the Save button materializes.
        let save = app.buttons["Save to My Screens"]
        for _ in 0..<4 where !save.exists {
            app.swipeUp()
            Thread.sleep(forTimeInterval: 0.5)
        }
        XCTAssertTrue(save.waitForExistence(timeout: 10))
        snap("07-create-screen")

        // Save it and capture the picker with the My Screens section.
        save.tap()
        XCTAssertTrue(app.staticTexts["My Screens"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Hawaii Countdown"].waitForExistence(timeout: 10))
        snap("08-my-screens")

        // Clean up so reruns don't accumulate "Hawaii Countdown 2, 3, …".
        let delete = app.buttons["Delete"].firstMatch.exists
            ? app.buttons["Delete"].firstMatch
            : app.buttons["trash"].firstMatch
        if delete.exists { delete.tap() }
    }

    // Diagnostic: dump the photo picker's cell labels.
    func testDumpPickerLabels() throws {
        app.buttons["Pick a Photo"].tap()
        let cells = app.scrollViews.otherElements.images
        _ = cells.firstMatch.waitForExistence(timeout: 20)
        Thread.sleep(forTimeInterval: 2.0)
        snap("debug-picker")
        for (i, el) in cells.allElementsBoundByIndex.enumerated() {
            guard el.exists else { continue }
            print("PICKERCELL[\(i)] hittable=\(el.isHittable) frame=\(el.frame) label=\(el.label)")
        }
    }

    // MARK: - Flow helpers

    private func openMyFrames() {
        app.buttons["My Frames"].firstMatch.tap()
        _ = app.navigationBars["My Frames"].waitForExistence(timeout: 10)
    }

    private func openAddFrameWizard(firstFrame: Bool) {
        if firstFrame && app.buttons["Set Up Your Frame"].waitForExistence(timeout: 5) {
            app.buttons["Set Up Your Frame"].tap()
        } else if app.navigationBars["My Frames"].exists {
            // already in FramesView
        } else {
            openMyFrames()
        }
        let add = app.buttons["Add a Frame"]
        XCTAssertTrue(add.waitForExistence(timeout: 10))
        add.tap()
    }

    private func pairDemoFrame(named name: String, captureSuccess: Bool) {
        let demo = app.buttons["No frame yet? Try a demo"]
        XCTAssertTrue(demo.waitForExistence(timeout: 10))
        demo.tap()

        // registerFrame hits the real backend; allow time.
        let connect = app.buttons["Connect to Frame"]
        XCTAssertTrue(connect.waitForExistence(timeout: 40))
        connect.tap()

        // The main screen behind the sheet also has a "Send to Frame" button
        // once a frame exists; tap the hittable (wizard) one.
        XCTAssertTrue(app.buttons["Send to Frame"].firstMatch.waitForExistence(timeout: 20))
        let sendToFrame = app.buttons.matching(identifier: "Send to Frame")
            .allElementsBoundByIndex.first { $0.isHittable }
        XCTAssertNotNil(sendToFrame, "wizard Send to Frame button not found")
        sendToFrame?.tap()

        XCTAssertTrue(app.staticTexts["Your frame is online!"].waitForExistence(timeout: 40))

        let field = app.textFields["e.g. Living Room"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        // Demo mode pre-fills "Demo Frame"; clear it before typing.
        if let existing = field.value as? String, !existing.isEmpty, existing != "e.g. Living Room" {
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: existing.count + 2))
        }
        field.typeText(name)
        if captureSuccess { snap("05-wizard-success") }
        field.typeText("\n")

        // Two "Done" buttons exist (wizard + the My Frames toolbar behind the
        // sheet); the wizard's is the full-width prominent one.
        let done = app.buttons.matching(identifier: "Done").allElementsBoundByIndex
            .first { $0.isHittable && $0.frame.width > 200 }
        XCTAssertNotNil(done, "wizard Done button not found")
        done?.tap()
        // Back in FramesView; wait for the new row.
        XCTAssertTrue(app.staticTexts[name].waitForExistence(timeout: 10))
    }

    // Expands a frame row, reads Frame ID + Device Token, and calls the
    // backend getFrame endpoint so the frame's lastSeen gets stamped.
    private func tapHittableStaticText(_ label: String) {
        let el = app.staticTexts.matching(identifier: label)
            .allElementsBoundByIndex.first { $0.isHittable }
        XCTAssertNotNil(el, "no hittable static text '\(label)'")
        el?.tap()
    }

    private func stampLastSeen(frameNamed name: String) {
        tapHittableStaticText(name)   // expand DisclosureGroup
        _ = app.staticTexts["Frame ID"].waitForExistence(timeout: 10)

        let labels = app.staticTexts.allElementsBoundByIndex.map(\.label)
        guard let idIdx = labels.firstIndex(of: "Frame ID"), idIdx + 1 < labels.count,
              let tokIdx = labels.firstIndex(of: "Device Token"), tokIdx + 1 < labels.count
        else {
            XCTFail("Could not read credentials for \(name)")
            return
        }
        let frameId = labels[idIdx + 1]
        let token = labels[tokIdx + 1]

        let url = URL(string:
            "https://us-central1-monoframe-app.cloudfunctions.net/getFrame?id=\(frameId)")!
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let sem = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: req) { _, resp, _ in
            let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
            print("stampLastSeen \(name): HTTP \(code)")
            sem.signal()
        }.resume()
        _ = sem.wait(timeout: .now() + 30)

        tapHittableStaticText(name)   // collapse again
    }

    // The PHPicker sheet is a remote view but its photo cells are exposed to
    // XCUITest under the picker's own scroll view. The picker opens scrolled
    // to the newest photo, so the last visible cell is the seeded sample.
    private func pickFirstLibraryPhoto() {
        let cells = app.scrollViews.otherElements.images
        guard cells.firstMatch.waitForExistence(timeout: 20) else {
            snap("debug-picker")
            XCTFail("no photo cells visible in picker")
            return
        }
        Thread.sleep(forTimeInterval: 1.0)
        // The seeded dog photo has no capture date, so its cell is labeled
        // just "Photo" and reports a bogus tiny frame — it can't be tapped
        // directly. But it's the newest photo, so it always occupies the
        // grid's top-left slot. Reconstruct that slot from the dated default
        // samples (label "Photo, <date>"), whose frames are reliable: their
        // min x is the leftmost column, min y the top row.
        // Dated labels populate lazily (and out of order) in the remote
        // picker; breaking on the first match can anchor on a lower row and
        // pick the wrong photo. Poll until the count stops growing.
        var dated: [CGRect] = []
        var stable = 0
        for _ in 0..<20 {
            let now = cells.matching(NSPredicate(format: "label CONTAINS ','"))
                .allElementsBoundByIndex.map(\.frame)
                .filter { $0.width > 50 }
            stable = (now.count == dated.count && !now.isEmpty) ? stable + 1 : 0
            dated = now
            if stable >= 2 { break }
            Thread.sleep(forTimeInterval: 1.0)
        }
        guard let sample = dated.first else {
            snap("debug-picker")
            XCTFail("no dated photo cells to anchor on")
            return
        }
        let x = dated.map(\.minX).min()! + sample.width / 2
        let y = dated.map(\.minY).min()! + sample.height / 2
        // Remote-picker cells report isHittable == false; coordinate taps
        // bypass XCUITest's hittability gate.
        app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: x, dy: y))
            .tap()
    }
}
