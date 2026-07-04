import CoreGraphics
import Foundation
import UIKit

// Converts a photo into the 1-bit packed buffer a given panel expects.
// Aspect-fill crop into the panel, then Floyd–Steinberg dither so photos
// keep tonal detail on a 2-level display.
enum EinkConverter {

    static func convert(_ image: UIImage, for model: DeviceModel) -> Data? {
        guard let cg = image.cgImage,
              let gray = renderToGrayscale(cg, model) else { return nil }
        let dithered = floydSteinberg(gray, model)
        return pack1Bit(dithered, model)
    }

    // What the panel will actually display, returned as an 8-bit gray CGImage
    // so SwiftUI can show a "this is what you're sending" preview.
    static func previewCGImage(from image: UIImage, for model: DeviceModel) -> CGImage? {
        guard let cg = image.cgImage,
              let gray = renderToGrayscale(cg, model) else { return nil }
        let dithered = floydSteinberg(gray, model)
        let cs = CGColorSpaceCreateDeviceGray()
        let cfData = Data(dithered) as CFData
        guard let provider = CGDataProvider(data: cfData) else { return nil }
        return CGImage(
            width: model.width, height: model.height,
            bitsPerComponent: 8, bitsPerPixel: 8,
            bytesPerRow: model.width,
            space: cs,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
            provider: provider, decode: nil,
            shouldInterpolate: false, intent: .defaultIntent
        )
    }

    private static func renderToGrayscale(_ cg: CGImage, _ model: DeviceModel) -> [UInt8]? {
        let width = model.width
        let height = model.height
        let cs = CGColorSpaceCreateDeviceGray()
        var buf = [UInt8](repeating: 0xFF, count: width * height)
        let ok: Bool = buf.withUnsafeMutableBufferPointer { ptr -> Bool in
            guard let ctx = CGContext(
                data: ptr.baseAddress,
                width: width, height: height,
                bitsPerComponent: 8,
                bytesPerRow: width,
                space: cs,
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else { return false }

            let srcW = CGFloat(cg.width)
            let srcH = CGFloat(cg.height)
            let scale = max(CGFloat(width) / srcW, CGFloat(height) / srcH)
            let dstW = srcW * scale
            let dstH = srcH * scale
            let rect = CGRect(
                x: (CGFloat(width) - dstW) / 2,
                y: (CGFloat(height) - dstH) / 2,
                width: dstW, height: dstH
            )
            ctx.interpolationQuality = .high
            ctx.draw(cg, in: rect)
            return true
        }
        return ok ? buf : nil
    }

    private static func floydSteinberg(_ src: [UInt8], _ model: DeviceModel) -> [UInt8] {
        let width = model.width
        let height = model.height
        var buf = src.map { Int16($0) }
        for y in 0..<height {
            for x in 0..<width {
                let i = y * width + x
                let old = buf[i]
                let new: Int16 = old < 128 ? 0 : 255
                let err = old - new
                buf[i] = new
                if x + 1 < width {
                    buf[i + 1] = clamp(buf[i + 1] + err * 7 / 16)
                }
                if y + 1 < height {
                    if x > 0 {
                        buf[i + width - 1] = clamp(buf[i + width - 1] + err * 3 / 16)
                    }
                    buf[i + width] = clamp(buf[i + width] + err * 5 / 16)
                    if x + 1 < width {
                        buf[i + width + 1] = clamp(buf[i + width + 1] + err * 1 / 16)
                    }
                }
            }
        }
        return buf.map { UInt8($0) }
    }

    @inline(__always)
    private static func clamp(_ v: Int16) -> Int16 {
        v < 0 ? 0 : (v > 255 ? 255 : v)
    }

    // GxEPD2 drawImage convention: 1-bit MSB-first, row-major.
    // Bit=1 -> color (drawn as GxEPD_BLACK), bit=0 -> bg (GxEPD_WHITE).
    private static func pack1Bit(_ src: [UInt8], _ model: DeviceModel) -> Data {
        let width = model.width
        let height = model.height
        var out = Data(count: model.byteCount)
        out.withUnsafeMutableBytes { raw in
            guard let p = raw.bindMemory(to: UInt8.self).baseAddress else { return }
            for y in 0..<height {
                let rowBase = y * width
                for x in 0..<width {
                    if src[rowBase + x] == 0 {
                        p[(rowBase + x) >> 3] |= UInt8(0x80 >> (x & 7))
                    }
                }
            }
        }
        return out
    }
}
