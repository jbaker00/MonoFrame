// Screen-layout validation shared by the MCP tools. Mirrors the Swift-side
// rules in Sources/MonoFrame/ScreenLayout.swift / ScreenGenerator.swift:
// repair common LLM/chat JSON damage, drop unknown widget types, clamp
// frames to the unit canvas — and report everything that was fixed so the
// calling LLM can self-correct.

export const PANELS = {
  "crowpanel-4.2": { width: 400, height: 300, name: 'CrowPanel 4.2"' },
  "crowpanel-5.79": { width: 792, height: 272, name: 'CrowPanel 5.79"' },
  "reterminal-e1001": { width: 800, height: 480, name: 'reTerminal E1001 7.5"' },
};

const WIDGET_TYPES = new Set([
  "clock", "date", "text", "countdown", "calendarMonth", "divider", "box",
]);

export function designGuide(panel = "crowpanel-4.2") {
  const p = PANELS[panel] ?? PANELS["crowpanel-4.2"];
  return `You design screens for a black & white e-ink display, ${p.width}x${p.height} pixels, 1-bit (pure black on white, no grays).

Output one JSON object matching this schema exactly:
{"version":1,"name":"Short Name","description":"one sentence","widgets":[
  {"type":"<type>","frame":{"x":0.0,"y":0.0,"w":1.0,"h":1.0},"props":{...}}]}

frame values are FRACTIONS of the screen (0.0-1.0); x,y is the top-left corner.
The ONLY valid widget types and their props (all props optional unless noted):
- "text": props.text (required), props.weight "regular"|"bold", props.align "leading"|"center"|"trailing", props.inverted true = white-on-black banner
- "date": today's date. props.style "long"|"short"
- "clock": time of render. props.twentyFourHour, props.style "hm"|"hms"
- "countdown": days until props.target "YYYY-MM-DD" (required), props.label caption
- "calendarMonth": this month's grid, today circled. Needs w>=0.4 and h>=0.5 to be legible.
- "divider": horizontal line
- "box": outline rectangle for grouping

Rules:
- Strict JSON only: straight double quotes, no trailing commas, no comments.
- Do not invent widget types — anything not in the list above is dropped.
- The screen is sent as a static picture: prefer date-stable content (calendar, countdown, text). Use "clock" only if the user asks for one.
- Text height comes from frame.h — a hero line wants h 0.2-0.4, a caption 0.08-0.12.
- Don't overlap text widgets; leave 0.02-0.04 gaps. 3-6 widgets is usually right.
- Keep name under 24 characters.

After drafting, call the validate_screen_layout tool and fix anything it reports until ok=true, then give the user ONLY the normalized JSON it returns.`;
}

function repair(json) {
  return json
    .replace(/[“”„]/g, '"')
    .replace(/[‘’]/g, "'")
    .replace(/,\s*([}\]])/g, "$1");
}

export function validateLayout(input) {
  const errors = [];
  const warnings = [];

  // Accept an object, or a string with prose/fences around the JSON.
  let layout = input;
  if (typeof input === "string") {
    const start = input.indexOf("{");
    const end = input.lastIndexOf("}");
    if (start < 0 || end <= start) {
      return { ok: false, errors: ["no JSON object found in the input"], warnings, layout: null };
    }
    const raw = input.slice(start, end + 1);
    try {
      layout = JSON.parse(raw);
    } catch {
      try {
        layout = JSON.parse(repair(raw));
        warnings.push("repaired smart quotes and/or trailing commas — emit strict JSON");
      } catch (e2) {
        return { ok: false, errors: [`JSON does not parse: ${e2.message}`], warnings, layout: null };
      }
    }
  }

  if (typeof layout !== "object" || layout === null || Array.isArray(layout)) {
    return { ok: false, errors: ["top level must be a JSON object"], warnings, layout: null };
  }

  const out = { version: 1, name: "", widgets: [] };

  if (typeof layout.version === "number") out.version = layout.version;
  if (typeof layout.name === "string" && layout.name.trim()) {
    out.name = layout.name.trim();
    if (out.name.length > 24) {
      out.name = out.name.slice(0, 24).trim();
      warnings.push('"name" was over 24 characters — truncated');
    }
  } else {
    errors.push('missing "name" (short string, under 24 characters)');
  }
  if (typeof layout.description === "string" && layout.description.trim()) {
    out.description = layout.description.trim();
  }

  if (!Array.isArray(layout.widgets) || layout.widgets.length === 0) {
    errors.push('"widgets" must be a non-empty array');
    return { ok: false, errors, warnings, layout: null };
  }

  for (const [i, w] of layout.widgets.entries()) {
    const where = `widgets[${i}]`;
    if (typeof w !== "object" || w === null) {
      warnings.push(`${where} is not an object — dropped`);
      continue;
    }
    if (!WIDGET_TYPES.has(w.type)) {
      warnings.push(`${where} has unknown type "${w.type}" — dropped (valid: ${[...WIDGET_TYPES].join(", ")})`);
      continue;
    }
    const f = w.frame ?? {};
    const nums = ["x", "y", "w", "h"].map((k) => Number(f[k]));
    if (nums.some((n) => !Number.isFinite(n))) {
      warnings.push(`${where} frame needs numeric x, y, w, h — dropped`);
      continue;
    }
    let [x, y, wd, h] = nums;
    const cx = Math.min(Math.max(x, 0), 1);
    const cy = Math.min(Math.max(y, 0), 1);
    const cw = Math.min(Math.max(wd, 0), 1 - cx);
    const ch = Math.min(Math.max(h, 0), 1 - cy);
    if (cx !== x || cy !== y || cw !== wd || ch !== h) {
      warnings.push(`${where} frame was outside the 0-1 canvas — clamped`);
    }
    if (cw < 0.005 || ch < 0.005) {
      warnings.push(`${where} has a zero-size frame after clamping — dropped`);
      continue;
    }

    const widget = { type: w.type, frame: { x: cx, y: cy, w: cw, h: ch } };
    const props = typeof w.props === "object" && w.props !== null ? w.props : {};

    if (w.type === "text" && !(typeof props.text === "string" && props.text.trim())) {
      warnings.push(`${where} text widget has no props.text — dropped`);
      continue;
    }
    if (w.type === "countdown" &&
        !(typeof props.target === "string" && /^\d{4}-\d{2}-\d{2}$/.test(props.target))) {
      errors.push(`${where} countdown needs props.target as "YYYY-MM-DD"`);
      continue;
    }
    if (w.type === "calendarMonth" && (cw < 0.4 || ch < 0.5)) {
      warnings.push(`${where} calendarMonth is small (needs w>=0.4, h>=0.5 to be legible)`);
    }
    if (Object.keys(props).length) widget.props = props;
    out.widgets.push(widget);
  }

  if (out.widgets.length === 0) {
    errors.push("no usable widgets remained after validation");
  }

  // Overlap check between text-bearing widgets — the most common layout bug.
  const texty = out.widgets.filter((w) =>
    ["text", "date", "clock", "countdown"].includes(w.type));
  for (let a = 0; a < texty.length; a++) {
    for (let b = a + 1; b < texty.length; b++) {
      const A = texty[a].frame;
      const B = texty[b].frame;
      const overlapX = Math.min(A.x + A.w, B.x + B.w) - Math.max(A.x, B.x);
      const overlapY = Math.min(A.y + A.h, B.y + B.h) - Math.max(A.y, B.y);
      if (overlapX > 0.01 && overlapY > 0.01) {
        warnings.push(`"${texty[a].type}" and "${texty[b].type}" widgets overlap — text will collide`);
      }
    }
  }

  const ok = errors.length === 0;
  return { ok, errors, warnings, layout: ok ? out : null };
}
