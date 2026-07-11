// node test/validate.test.js — plain asserts, no framework.
import assert from "node:assert/strict";
import { validateLayout, designGuide, PANELS } from "../lib/validate.js";

// Clean layout passes.
{
  const r = validateLayout(JSON.stringify({
    version: 1, name: "Test", widgets: [
      { type: "text", frame: { x: 0.1, y: 0.1, w: 0.8, h: 0.3 }, props: { text: "HI" } },
    ],
  }));
  assert.equal(r.ok, true);
  assert.equal(r.layout.widgets.length, 1);
}

// Chat-app damage: prose + fence + trailing comma + smart quotes.
{
  const r = validateLayout(`Here you go!\n\`\`\`json\n{
    “version”: 1, “name”: “Damaged”,
    “widgets”: [
      {“type”: “text”, “frame”: {“x”: 0, “y”: 0.1, “w”: 1, “h”: 0.3}, “props”: {“text”: “OK”}},
    ]
  }\n\`\`\`\nAnything else?`);
  assert.equal(r.ok, true, JSON.stringify(r.errors));
  assert.ok(r.warnings.some((w) => w.includes("repaired")));
}

// Unknown types drop with a warning; countdown without target is an error.
{
  const r = validateLayout(JSON.stringify({
    name: "Mixed", widgets: [
      { type: "stockTicker", frame: { x: 0, y: 0, w: 1, h: 0.3 } },
      { type: "countdown", frame: { x: 0, y: 0.4, w: 1, h: 0.3 }, props: { label: "oops" } },
      { type: "date", frame: { x: 0, y: 0.8, w: 1, h: 0.15 } },
    ],
  }));
  assert.equal(r.ok, false);
  assert.ok(r.warnings.some((w) => w.includes("stockTicker")));
  assert.ok(r.errors.some((e) => e.includes("YYYY-MM-DD")));
}

// Frames clamp; overlapping text widgets warn.
{
  const r = validateLayout(JSON.stringify({
    name: "Overlap", widgets: [
      { type: "text", frame: { x: -0.2, y: 0.1, w: 2, h: 0.4 }, props: { text: "A" } },
      { type: "text", frame: { x: 0.1, y: 0.2, w: 0.5, h: 0.4 }, props: { text: "B" } },
    ],
  }));
  assert.equal(r.ok, true);
  assert.ok(r.warnings.some((w) => w.includes("clamped")));
  assert.ok(r.warnings.some((w) => w.includes("overlap")));
  assert.equal(r.layout.widgets[0].frame.x, 0);
}

// No JSON at all.
{
  const r = validateLayout("sorry, I can't help with that");
  assert.equal(r.ok, false);
}

// Guide mentions the right panel size.
assert.ok(designGuide("reterminal-e1001").includes("800x480"));
assert.equal(Object.keys(PANELS).length, 3);

console.log("all validate tests passed");
