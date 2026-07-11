import CoreGraphics
import UIKit

// Renders a ScreenLayout to a pure black & white UIImage at a panel's exact
// pixel size. Because the output has no grays, the Floyd–Steinberg pass in
// EinkConverter is an identity map — text stays crisp on the device.
enum ScreenRenderer {

    static func render(_ layout: ScreenLayout, for model: DeviceModel,
                       at date: Date = Date()) -> UIImage {
        let size = CGSize(width: model.width, height: model.height)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            for widget in layout.clamped().widgets {
                let rect = widget.frame.cgRect(width: model.width, height: model.height)
                guard rect.width >= 2, rect.height >= 2 else { continue }
                draw(widget, in: rect, ctx: ctx.cgContext, at: date)
            }
        }
    }

    // MARK: - Widget dispatch

    private static func draw(_ widget: ScreenWidget, in rect: CGRect,
                             ctx: CGContext, at date: Date) {
        let p = widget.props
        switch widget.type {
        case .clock:
            drawText(clockString(at: date, props: p), in: rect, ctx: ctx,
                     weight: p.weight ?? .bold, align: p.align ?? .center,
                     monospacedDigits: true)
        case .date:
            drawText(dateString(at: date, props: p), in: rect, ctx: ctx,
                     weight: p.weight ?? .bold, align: p.align ?? .center)
        case .text:
            drawText(p.text ?? "", in: rect, ctx: ctx,
                     weight: p.weight ?? .regular, align: p.align ?? .center,
                     inverted: p.inverted ?? false)
        case .countdown:
            drawCountdown(p, in: rect, ctx: ctx, at: date)
        case .calendarMonth:
            drawCalendarMonth(in: rect, ctx: ctx, at: date)
        case .divider:
            let thickness = max(2, rect.height * 0.04).rounded()
            ctx.setFillColor(UIColor.black.cgColor)
            ctx.fill(CGRect(x: rect.minX, y: rect.midY - thickness / 2,
                            width: rect.width, height: thickness))
        case .box:
            ctx.setStrokeColor(UIColor.black.cgColor)
            ctx.setLineWidth(2)
            ctx.stroke(rect.insetBy(dx: 1, dy: 1))
        }
    }

    // MARK: - Strings

    private static func clockString(at date: Date, props: WidgetProps) -> String {
        let fmt = DateFormatter()
        let seconds = props.style == "hms"
        if props.twentyFourHour == true {
            fmt.dateFormat = seconds ? "HH:mm:ss" : "HH:mm"
        } else {
            fmt.dateFormat = seconds ? "h:mm:ss a" : "h:mm"
        }
        return fmt.string(from: date)
    }

    private static func dateString(at date: Date, props: WidgetProps) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = props.style == "short" ? "EEE, MMM d" : "EEEE, MMMM d"
        return fmt.string(from: date)
    }

    // MARK: - Countdown

    private static func drawCountdown(_ props: WidgetProps, in rect: CGRect,
                                      ctx: CGContext, at date: Date) {
        var days: Int?
        if let target = props.target {
            let fmt = DateFormatter()
            fmt.dateFormat = "yyyy-MM-dd"
            fmt.timeZone = .current
            if let targetDate = fmt.date(from: target) {
                let cal = Calendar.current
                days = cal.dateComponents(
                    [.day],
                    from: cal.startOfDay(for: date),
                    to: cal.startOfDay(for: targetDate)
                ).day
            }
        }

        let number = days.map { $0 >= 0 ? "\($0)" : "+\(-$0)" } ?? "?"
        let caption: String
        if let label = props.label, !label.isEmpty {
            // Labels often already say "days" ("Days to Vacation") — only
            // prepend the unit when the label doesn't mention it.
            if label.range(of: "day", options: .caseInsensitive) != nil {
                caption = label
            } else {
                caption = days.map { $0 == 1 ? "DAY \(label)" : "DAYS \(label)" } ?? label
            }
        } else {
            caption = (days == 1) ? "DAY" : "DAYS"
        }

        // Number takes the top ~70% of the rect, caption the rest.
        let split = rect.height * 0.7
        let numberRect = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: split)
        let captionRect = CGRect(x: rect.minX, y: rect.minY + split,
                                 width: rect.width, height: rect.height - split)
        drawText(number, in: numberRect, ctx: ctx, weight: .bold,
                 align: props.align ?? .center, monospacedDigits: true)
        drawText(caption, in: captionRect, ctx: ctx, weight: .regular,
                 align: props.align ?? .center)
    }

    // MARK: - Calendar

    private static func drawCalendarMonth(in rect: CGRect, ctx: CGContext, at date: Date) {
        let cal = Calendar.current
        let today = cal.component(.day, from: date)
        guard let monthRange = cal.range(of: .day, in: .month, for: date),
              let firstOfMonth = cal.date(from: cal.dateComponents([.year, .month], from: date))
        else { return }
        let daysInMonth = monthRange.count
        // Column of day 1, honoring the user's first-weekday setting.
        let firstColumn = (cal.component(.weekday, from: firstOfMonth)
            - cal.firstWeekday + 7) % 7
        let rows = Int(ceil(Double(firstColumn + daysInMonth) / 7.0))

        // Title strip, weekday header, then the grid.
        let titleH = rect.height * 0.16
        let headerH = rect.height * 0.10
        let gridTop = rect.minY + titleH + headerH
        let cellW = rect.width / 7
        let cellH = (rect.height - titleH - headerH) / CGFloat(max(rows, 5))

        let monthFmt = DateFormatter()
        monthFmt.dateFormat = "MMMM yyyy"
        drawText(monthFmt.string(from: date).uppercased(),
                 in: CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: titleH),
                 ctx: ctx, weight: .bold, align: .center)

        var symbols = cal.veryShortWeekdaySymbols // localized, Sunday-first
        symbols = Array(symbols[(cal.firstWeekday - 1)...] + symbols[..<(cal.firstWeekday - 1)])
        for (i, s) in symbols.enumerated() {
            drawText(s, in: CGRect(x: rect.minX + CGFloat(i) * cellW,
                                   y: rect.minY + titleH,
                                   width: cellW, height: headerH),
                     ctx: ctx, weight: .regular, align: .center)
        }

        for day in 1...daysInMonth {
            let index = firstColumn + day - 1
            let cell = CGRect(x: rect.minX + CGFloat(index % 7) * cellW,
                              y: gridTop + CGFloat(index / 7) * cellH,
                              width: cellW, height: cellH)
            if day == today {
                let r = min(cell.width, cell.height) * 0.44
                ctx.setFillColor(UIColor.black.cgColor)
                ctx.fillEllipse(in: CGRect(x: cell.midX - r, y: cell.midY - r,
                                           width: r * 2, height: r * 2))
                drawText("\(day)", in: cell, ctx: ctx, weight: .bold,
                         align: .center, color: .white,
                         fontFraction: 0.52)
            } else {
                drawText("\(day)", in: cell, ctx: ctx, weight: .regular,
                         align: .center, fontFraction: 0.52)
            }
        }
    }

    // MARK: - Text drawing

    // Draws a single line vertically centered in `rect`, sized to the rect
    // height and shrunk to fit the width. All layout math is in panel pixels.
    private static func drawText(_ string: String, in rect: CGRect, ctx: CGContext,
                                 weight: TextWeight, align: TextAlign,
                                 monospacedDigits: Bool = false,
                                 inverted: Bool = false,
                                 color: UIColor = .black,
                                 fontFraction: CGFloat = 0.72) {
        guard !string.isEmpty else { return }

        if inverted {
            ctx.setFillColor(UIColor.black.cgColor)
            ctx.fill(rect)
        }
        let textColor = inverted ? UIColor.white : color

        var fontSize = max(4, rect.height * fontFraction)
        var font = makeFont(size: fontSize, weight: weight, monospacedDigits: monospacedDigits)
        var attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: textColor]
        var width = (string as NSString).size(withAttributes: attrs).width

        let maxWidth = rect.width * 0.98
        if width > maxWidth {
            fontSize *= maxWidth / width
            font = makeFont(size: fontSize, weight: weight, monospacedDigits: monospacedDigits)
            attrs[.font] = font
            width = (string as NSString).size(withAttributes: attrs).width
        }

        let textHeight = (string as NSString).size(withAttributes: attrs).height
        let x: CGFloat
        switch align {
        case .leading: x = rect.minX
        case .center: x = rect.minX + (rect.width - width) / 2
        case .trailing: x = rect.maxX - width
        }
        let y = rect.minY + (rect.height - textHeight) / 2
        (string as NSString).draw(at: CGPoint(x: x, y: y), withAttributes: attrs)
    }

    private static func makeFont(size: CGFloat, weight: TextWeight,
                                 monospacedDigits: Bool) -> UIFont {
        let uiWeight: UIFont.Weight = weight == .bold ? .bold : .regular
        var font = monospacedDigits
            ? UIFont.monospacedDigitSystemFont(ofSize: size, weight: uiWeight)
            : UIFont.systemFont(ofSize: size, weight: uiWeight)
        // Rounded design reads better at e-ink's hard 1-bit edges.
        if let descriptor = font.fontDescriptor.withDesign(.rounded) {
            font = UIFont(descriptor: descriptor, size: size)
        }
        return font
    }
}
