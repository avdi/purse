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
    const url = expand(entry.url)
    // opencode aborts the whole transform on one invalid entry, dropping every
    // server after it, so an unexpanded URL is skipped rather than passed on.
    if (!URL.canParse(url)) return undefined
    const headers = entry.headers && expandValues(entry.headers)
    return withoutUndefined({
      type: "remote",
      url,
      headers,
      // A server authenticated by header has no OAuth flow to offer; without this
      // opencode answers its 401 with an "authenticate" prompt that cannot succeed.
      oauth: headers ? false : undefined,
    })
  }
  if (entry.command) {
    const command = [expand(entry.command), ...(entry.args ?? []).map(expand)]
    if (command.some((part) => part === "")) return undefined
    return withoutUndefined({
      type: "local",
      command,
      environment: entry.env && expandValues(entry.env),
      // A cold `npx -y`/`uv run` install outlasts opencode's 30s default.
      timeout: { startup: 60000 },
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

let reloaded = false

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
    // A registered transform only reaches the config build after it. Without this
    // rebuild the servers appear on a fresh start and then vanish on `reload`.
    if (!reloaded) {
      reloaded = true
      await mcp.reload()
    }
  },
}
