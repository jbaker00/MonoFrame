# monoframe-screens-mcp

MCP server for designing **[MonoFrame](https://github.com/jbaker00/MonoFrame)**
e-ink dashboard screens with an AI assistant — with output validation, so the
JSON you get is guaranteed to paste cleanly into the MonoFrame iOS app.

MonoFrame is an open-source (MIT) e-ink picture frame: an iOS app + Firebase
backend + ESP32 firmware for panels like the CrowPanel 4.2"/5.79" and Seeed
reTerminal E1001. Besides photos, frames can show *screens* — clock,
calendar, countdowns, notes — described in a small widget-layout JSON schema.
This server teaches that schema to any MCP-capable assistant and validates
drafts until they're clean.

## Install

Claude Code:

```bash
claude mcp add monoframe-screens -- npx -y monoframe-screens-mcp
```

Claude Desktop (`claude_desktop_config.json`):

```json
{
  "mcpServers": {
    "monoframe-screens": {
      "command": "npx",
      "args": ["-y", "monoframe-screens-mcp"]
    }
  }
}
```

Any other MCP client: it's a standard stdio server — run `npx -y monoframe-screens-mcp`.

## Tools

| Tool | What it does |
|------|--------------|
| `screen_design_guide` | Returns the design rules + JSON schema for a given panel (call first) |
| `validate_screen_layout` | Validates a draft; returns `ok`/`errors`/`warnings` + normalized JSON. Repairs smart quotes and trailing commas, drops invented widget types, clamps frames, flags overlapping text |
| `list_panels` | Supported panels with pixel sizes |

## Typical flow

> **You:** design a screen for my reTerminal counting down to our Hawaii trip on Aug 20
>
> **Assistant:** *(calls `screen_design_guide`, drafts, calls
> `validate_screen_layout`, fixes warnings, repeats until `ok: true`)*
> Here's your validated layout: `{...}`

Paste that JSON into the MonoFrame app: **Screens → Create New Screen →
Paste the AI's reply → Build Screen**, preview, and send it to your frame.

## License

MIT
