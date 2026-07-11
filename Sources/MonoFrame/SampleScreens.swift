import Foundation

// Bundled screen layouts, stored as the same JSON a future designer UI or
// screen generator would produce — the samples double as schema fixtures.
//
// Until frames re-render server-side, a sent screen is a static picture, so
// every sample is built from day-stable widgets (calendar, date, countdown,
// text). A live clock would freeze at whatever time you pressed Send.
enum SampleScreens {

    static let all: [ScreenLayout] = {
        rawLayouts.compactMap { try? ScreenLayout.decode(fromJSON: $0) }
    }()

    private static let rawLayouts: [String] = [
        // Month at a glance — the whole panel is one calendar.
        """
        {
          "version": 1,
          "name": "Month at a Glance",
          "description": "A full-screen calendar for this month with today circled.",
          "widgets": [
            {"type": "calendarMonth", "frame": {"x": 0.04, "y": 0.04, "w": 0.92, "h": 0.92}}
          ]
        }
        """,

        // Today — big date on top, this month's calendar below.
        """
        {
          "version": 1,
          "name": "Today",
          "description": "Today's date in large type over a mini month calendar.",
          "widgets": [
            {"type": "date", "frame": {"x": 0.04, "y": 0.03, "w": 0.92, "h": 0.20}},
            {"type": "divider", "frame": {"x": 0.10, "y": 0.24, "w": 0.80, "h": 0.03}},
            {"type": "calendarMonth", "frame": {"x": 0.16, "y": 0.30, "w": 0.68, "h": 0.66}}
          ]
        }
        """,

        // Countdown — giant days-remaining number.
        """
        {
          "version": 1,
          "name": "New Year Countdown",
          "description": "Days remaining until January 1st, in numbers you can read from the couch.",
          "widgets": [
            {"type": "countdown", "frame": {"x": 0.05, "y": 0.10, "w": 0.90, "h": 0.62},
             "props": {"target": "2027-01-01", "label": "UNTIL 2027"}},
            {"type": "divider", "frame": {"x": 0.20, "y": 0.78, "w": 0.60, "h": 0.03}},
            {"type": "date", "frame": {"x": 0.10, "y": 0.83, "w": 0.80, "h": 0.12},
             "props": {"style": "short", "weight": "regular"}}
          ]
        }
        """,

        // Kitchen note — a banner headline with room for a message.
        """
        {
          "version": 1,
          "name": "Family Note",
          "description": "A bold banner and message — edit the text to leave a note on the fridge frame.",
          "widgets": [
            {"type": "text", "frame": {"x": 0.0, "y": 0.06, "w": 1.0, "h": 0.20},
             "props": {"text": "DON'T FORGET", "weight": "bold", "inverted": true}},
            {"type": "text", "frame": {"x": 0.06, "y": 0.34, "w": 0.88, "h": 0.30},
             "props": {"text": "Trash night is tonight", "weight": "bold"}},
            {"type": "text", "frame": {"x": 0.06, "y": 0.66, "w": 0.88, "h": 0.14},
             "props": {"text": "bins out by 8 PM", "weight": "regular"}},
            {"type": "date", "frame": {"x": 0.06, "y": 0.85, "w": 0.88, "h": 0.10},
             "props": {"style": "short", "weight": "regular"}}
          ]
        }
        """,

        // Focus — one framed word for the desk.
        """
        {
          "version": 1,
          "name": "Daily Focus",
          "description": "One framed word front and center. Change it to whatever this week is about.",
          "widgets": [
            {"type": "box", "frame": {"x": 0.06, "y": 0.12, "w": 0.88, "h": 0.76}},
            {"type": "text", "frame": {"x": 0.10, "y": 0.28, "w": 0.80, "h": 0.34},
             "props": {"text": "FOCUS", "weight": "bold"}},
            {"type": "text", "frame": {"x": 0.10, "y": 0.62, "w": 0.80, "h": 0.12},
             "props": {"text": "one thing at a time", "weight": "regular"}}
          ]
        }
        """
    ]
}
