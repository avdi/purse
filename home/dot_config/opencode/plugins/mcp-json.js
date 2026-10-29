// Registers the servers in the project's .mcp.json (Claude Code's format) as opencode MCP servers.
// Servers already defined in opencode's own config win.
import { readFile } from "node:fs/promises"
import path from "node:path"

const ENV_REFERENCE = /\$\{([A-Za-z_][A-Za-z0-9_]*)(?::-([^}]*))?\}/g

const expand = (text) => text.replace(ENV_REFERENCE, (_, name, fallback) => process.env[name] ?? fallback ?? "")

const expandValues = (record) => Object.fromEntries(Object.entries(record).map(([key, value]) => [key, expand(value)]))

// opencode's schema rejects explicit undefined, so absent options are left out entirely.
const withoutUndefined = (record) => Object.fromEntries(Object.entries(record).filter(([, value]) => value !== undefined))

const toOpencodeServer = (entry) => {
  if (entry.url) {
    return withoutUndefined({
      type: "remote",
      url: expand(entry.url),
      headers: entry.headers && expandValues(entry.headers),
    })
  }
  if (entry.command) {
    return withoutUndefined({
      type: "local",
      command: [expand(entry.command), ...(entry.args ?? []).map(expand)],
      environment: entry.env && expandValues(entry.env),
    })
  }
}

const readMcpJsonServers = async (directory) => {
  try {
    const text = await readFile(path.join(directory, ".mcp.json"), "utf8")
    return JSON.parse(text).mcpServers ?? {}
  } catch {
    return {}
  }
}

export default {
  id: "mcp-json",
  async setup({ location, mcp }) {
    const servers = await readMcpJsonServers(location.project.directory)
    await mcp.transform((editor) => {
      for (const [name, entry] of Object.entries(servers)) {
        const server = toOpencodeServer(entry)
        if (server && !editor.get(name)) editor.set(name, server)
      }
    })
  },
}
