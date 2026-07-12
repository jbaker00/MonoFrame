#!/usr/bin/env node
// MonoFrame screen-designer MCP server.
//
// Lets any MCP-capable assistant (Claude Desktop, Claude Code, …) design
// MonoFrame dashboard screens with guaranteed-valid output: fetch the design
// guide, draft a layout, validate it, hand the user normalized JSON they can
// paste into the app's Create Screen sheet.
//
// Register (Claude Code):
//   claude mcp add monoframe-screens -- node /path/to/MonoFrame/mcp/server.js

import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";
import { PANELS, designGuide, validateLayout } from "./lib/validate.js";

const server = new McpServer({ name: "monoframe-screens", version: "1.0.0" });

const panelEnum = z.enum(Object.keys(PANELS));

server.tool(
  "screen_design_guide",
  "Get the design rules and JSON schema for a MonoFrame e-ink screen. Call this FIRST, before drafting a layout, and target the panel the user owns.",
  { panel: panelEnum.describe("Which e-ink panel the screen is for").optional() },
  async ({ panel }) => ({
    content: [{ type: "text", text: designGuide(panel) }],
  }),
);

server.tool(
  "validate_screen_layout",
  "Validate a drafted MonoFrame screen layout. Returns ok/errors/warnings and a normalized layout. Loop on this until ok=true with no overlap warnings, then give the user ONLY the normalized JSON.",
  {
    layout: z.string().describe("The layout JSON (raw string; fences/prose are tolerated)"),
    panel: panelEnum.describe("Panel the screen targets (affects legibility hints)").optional(),
  },
  async ({ layout }) => {
    const result = validateLayout(layout);
    return {
      content: [{ type: "text", text: JSON.stringify(result, null, 2) }],
      isError: !result.ok,
    };
  },
);

server.tool(
  "list_panels",
  "List the e-ink panels MonoFrame supports, with their pixel sizes.",
  {},
  async () => ({
    content: [{
      type: "text",
      text: JSON.stringify(
        Object.entries(PANELS).map(([id, p]) => ({ id, ...p })), null, 2),
    }],
  }),
);

await server.connect(new StdioServerTransport());
