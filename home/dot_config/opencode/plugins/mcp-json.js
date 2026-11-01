// Registers the servers in the project's .mcp.json (Claude Code's format) as opencode MCP servers.
// Servers already defined in opencode's own config win.
//
// ${VAR} references resolve from opencode's own environment first, then from the
// host-only env files below. Without the file step, a server whose header is
// ${CLOUDWAYS_READ_ACCESS_TOKEN} connects only when opencode happened to be
// launched from a shell where direnv had already run — and every such server
// fails with a 401 that looks like bad credentials. Reading the files makes the
// launch path irrelevant; process.env still wins, so direnv, CI and one-off
// overrides keep working.
import { readFile } from "node:fs/promises"
import os from "node:os"
import path from "node:path"

const ENV_REFERENCE = /\$\{([A-Za-z_][A-Za-z0-9_]*)(?::-([^}]*))?\}/g

// The credential env files named by the project's .envrc. Override with a
// colon-separated MCP_JSON_ENV_FILES, or set it to "" to disable file loading.
const DEFAULT_ENV_FILES = ["~/.config/shiprise/env", "~/.config/graceful.dev/env"]

const parseEnvFile = (text) =>
  Object.fromEntries(
    text
      .split("\n")
      .map((line) => line.trim())
      .filter((line) => line && !line.startsWith("#"))
      .map((line) => line.replace(/^export\s+/, ""))
      .map((line) => {
        const match = /^([A-Za-z_][A-Za-z0-9_]*)=(.*)$/.exec(line)
        if (!match) return undefined
        const [, name, raw] = match
        const value = raw.trim().replace(/^(['"])(.*)\1$/, "$2")
        return [name, value]
      })
      .filter(Boolean),
  )

const loadHostEnv = async () => {
  const configured = process.env.MCP_JSON_ENV_FILES ?? DEFAULT_ENV_FILES.join(":")
  const loaded = {}
  for (const file of configured.split(":").filter(Boolean)) {
    try {
      const text = await readFile(file.replace(/^~(?=\/|$)/, os.homedir()), "utf8")
      Object.assign(loaded, parseEnvFile(text))
    } catch {
      // A missing file is normal on a machine that has not been provisioned yet.
    }
  }
  return loaded
}

const makeExpand =
  (fileEnv) =>
  (text) =>
    text.replace(ENV_REFERENCE, (_, name, fallback) => process.env[name] ?? fileEnv[name] ?? fallback ?? "")

const expandValues = (expand, record) =>
  Object.fromEntries(Object.entries(record).map(([key, value]) => [key, expand(value)]))

// opencode's schema rejects explicit undefined, so absent options are left out entirely.
const withoutUndefined = (record) => Object.fromEntries(Object.entries(record).filter(([, value]) => value !== undefined))

const toOpencodeServer = (entry, expand) => {
  if (entry.url) {
    const url = expand(entry.url)
    // opencode aborts the whole transform on one invalid entry, dropping every
    // server after it, so an unexpanded URL is skipped rather than passed on.
    if (!URL.canParse(url)) return undefined
    const headers = entry.headers && expandValues(expand, entry.headers)
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
      environment: entry.env && expandValues(expand, entry.env),
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
    const expand = makeExpand(await loadHostEnv())
    await mcp.transform((editor) => {
      for (const [name, entry] of Object.entries(servers)) {
        const server = toOpencodeServer(entry, expand)
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
