import XCTest
@testable import MonoFrame

final class ScreenRenderTests: XCTestCase {

    // Every bundled sample must decode — a typo in SampleScreens JSON would
    // otherwise silently drop the screen from the picker (compactMap).
    func testAllSamplesDecode() {
        XCTAssertEqual(SampleScreens.all.count, 5)
    }

    func testRendersAtExactPanelSize() {
        for layout in SampleScreens.all {
            for model in DeviceModel.allCases {
                let image = ScreenRenderer.render(layout, for: model)
                XCTAssertEqual(Int(image.size.width), model.width, layout.name)
                XCTAssertEqual(Int(image.size.height), model.height, layout.name)
            }
        }
    }

    // Rendered screens must survive the photo pipeline into a device payload.
    func testConvertsTo1BitPayload() {
        for layout in SampleScreens.all {
            for model in DeviceModel.allCases {
                let image = ScreenRenderer.render(layout, for: model)
                let blob = EinkConverter.convert(image, for: model)
                XCTAssertEqual(blob?.count, model.byteCount, layout.name)
            }
        }
    }

    // Not an assertion — writes PNGs so a human can eyeball every sample on
    // every panel. Simulator tests can write to the host's /tmp.
    func testWritePreviewPNGs() throws {
        let outDir = URL(fileURLWithPath: "/tmp/monoframe-screens")
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        for layout in SampleScreens.all {
            for model in [DeviceModel.reTerminalE1001, .crowPanel42] {
                let image = ScreenRenderer.render(layout, for: model)
                let name = layout.name.replacingOccurrences(of: " ", with: "-")
                let url = outDir.appendingPathComponent("\(name)_\(model.rawValue).png")
                try XCTUnwrap(image.pngData()).write(to: url)
            }
        }
    }
}
