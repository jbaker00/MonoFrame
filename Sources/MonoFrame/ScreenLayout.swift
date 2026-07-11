import Foundation

// A dashboard screen definition: widgets placed on a unit canvas. Layouts are
// plain JSON so they can come from bundled samples today and from a designer
// UI or LLM generator later — the schema is the contract, not Swift code.
//
// Coordinates are fractions of the panel (0…1 for x/y/w/h), so one layout
// renders on any DeviceModel. Widgets size their own type to the rect given.
struct ScreenLayout: Codable, Identifiable, Hashable {
    var version: Int
    var name: String
    var description: String?
    var widgets: [ScreenWidget]

    var id: String { name }

    static func decode(fromJSON json: String) throws -> ScreenLayout {
        let layout = try JSONDecoder().decode(ScreenLayout.self, from: Data(json.utf8))
        return layout.clamped()
    }

    // Out-of-range rects (hand-written or LLM-generated) are clamped rather
    // than rejected — a slightly-off screen beats an error.
    func clamped() -> ScreenLayout {
        var copy = self
        copy.widgets = widgets.map { widget in
            var w = widget
            w.frame = w.frame.clampedToUnit()
            return w
        }
        return copy
    }
}

struct ScreenWidget: Codable, Hashable {
    var type: WidgetType
    var frame: UnitRect
    var props: WidgetProps

    init(type: WidgetType, frame: UnitRect, props: WidgetProps = WidgetProps()) {
        self.type = type
        self.frame = frame
        self.props = props
    }

    // `props` may be omitted entirely in JSON.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        type = try c.decode(WidgetType.self, forKey: .type)
        frame = try c.decode(UnitRect.self, forKey: .frame)
        props = try c.decodeIfPresent(WidgetProps.self, forKey: .props) ?? WidgetProps()
    }
}

enum WidgetType: String, Codable {
    case clock          // current time (frozen at render time until live rendering ships)
    case date           // weekday + date
    case text           // static label
    case countdown      // days until props.target (ISO date)
    case calendarMonth  // month grid, today inverted
    case divider        // horizontal rule centered in the rect
    case box            // outline rectangle (decoration/grouping)
}

// Flat superset of every widget's options — all optional, each widget reads
// what it understands. Flat beats per-type polymorphism here: trivial to
// decode, trivial for an LLM to emit, unknown keys are simply ignored.
struct WidgetProps: Codable, Hashable {
    var text: String?           // text
    var label: String?          // countdown: caption under the number
    var target: String?         // countdown: "YYYY-MM-DD"
    var align: TextAlign?       // text/date/clock/countdown (default center)
    var weight: TextWeight?     // default bold for hero-ish widgets, regular for text
    var style: String?          // date: "long"|"short"; clock: "hm"|"hms"
    var twentyFourHour: Bool?   // clock
    var inverted: Bool?         // text: white-on-black banner

    init() {}
}

enum TextAlign: String, Codable {
    case leading, center, trailing
}

enum TextWeight: String, Codable {
    case regular, bold
}

struct UnitRect: Codable, Hashable {
    var x: Double
    var y: Double
    var w: Double
    var h: Double

    func clampedToUnit() -> UnitRect {
        let cx = min(max(x, 0), 1)
        let cy = min(max(y, 0), 1)
        return UnitRect(
            x: cx,
            y: cy,
            w: min(max(w, 0), 1 - cx),
            h: min(max(h, 0), 1 - cy)
        )
    }

    func cgRect(width: Int, height: Int) -> CGRect {
        CGRect(
            x: x * Double(width),
            y: y * Double(height),
            width: w * Double(width),
            height: h * Double(height)
        )
    }
}
