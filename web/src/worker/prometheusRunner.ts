import glueWasmUrl from "wasmoon/dist/glue.wasm?url"

import luaSources from "virtual:prometheus-lua"
import type { PrometheusLog, PrometheusOptions, PrometheusResult } from "@/lib/prometheusTypes"
import { toLuaLongString } from "./luaString"

type LuaFactoryConstructor = new (
  customWasmUri?: string,
  environmentVariables?: Record<string, string>,
) => {
  createEngine(options?: { openStandardLibs?: boolean }): Promise<{
    doString(luaCode: string): Promise<unknown>
    global: { close(): void }
  }>
}

let luaFactoryCtorPromise: Promise<LuaFactoryConstructor> | null = null

function resolveWasmUri(wasmUrl: string): string {
  if (typeof process !== "undefined" && process.versions?.node) {
    // Vite 7 exposed `/@fs/<abs>` in dev/test; Vite 8 exposes the raw absolute
    // path (which on Windows starts with a `/` before the drive letter, e.g.
    // `/C:/…`). In both cases Node's `fs` needs a plain filesystem path.
    let path = wasmUrl.startsWith("/@fs/") ? wasmUrl.slice("/@fs".length) : wasmUrl

    if (path.startsWith("file://")) {
      try {
        return new URL(path).pathname.replace(/^\/([A-Za-z]:)/, "$1")
      } catch {
        // fall through
      }
    }

    // Strip the leading `/` in front of a Windows drive letter (`/C:/…` → `C:/…`).
    path = path.replace(/^\/([A-Za-z]:)/, "$1")

    return path
  }

  return wasmUrl
}

async function getLuaFactoryConstructor(): Promise<LuaFactoryConstructor> {
  if (luaFactoryCtorPromise) {
    return luaFactoryCtorPromise
  }

  luaFactoryCtorPromise = import("wasmoon/dist/index.js").then((mod) => {
    const globalCandidate = (globalThis as { wasmoon?: { LuaFactory?: unknown } }).wasmoon?.LuaFactory
    const moduleCandidate = (mod as { LuaFactory?: unknown }).LuaFactory
    const defaultCandidate = (mod as { default?: { LuaFactory?: unknown } }).default?.LuaFactory
    const candidate = (globalCandidate ?? moduleCandidate ?? defaultCandidate) as LuaFactoryConstructor | undefined

    if (typeof candidate !== "function") {
      throw new Error("Unable to resolve LuaFactory export from wasmoon.")
    }

    return candidate
  })

  return luaFactoryCtorPromise
}

const bootstrapLua = Object.entries(luaSources)
  .map(([name, source]) => {
    const chunkName = `@/src/${name.split(".").join("/")}.lua`
    return `
package.preload[ ${toLuaLongString(name)} ] = function(...)
  local chunk, err = load(${toLuaLongString(source)}, ${toLuaLongString(chunkName)}, "t")
  if not chunk then
    error(err)
  end
  return chunk(...)
end`
  })
  .join("\n")

export function buildRunLua(options: PrometheusOptions): string {
  return `
_G.arg = _G.arg or {}
${bootstrapLua}

local logs = {}
local unpackFn = table.unpack or unpack
local function pushLog(level, ...)
  local parts = {}
  for i = 1, select("#", ...) do
    parts[#parts + 1] = tostring(select(i, ...))
  end
  if type(_G.__prometheusPushLog) == "function" then
    _G.__prometheusPushLog(level, unpackFn(parts))
  end
  logs[#logs + 1] = { level = level, message = table.concat(parts, " ") }
end

if not math.log10 then
  math.log10 = function(value)
    return math.log(value, 10)
  end
end

local Prometheus = require("prometheus")
Prometheus.Logger.logLevel = Prometheus.Logger.LogLevel.Info
Prometheus.colors.enabled = false
Prometheus.Logger.debugCallback = function(...) pushLog("debug", ...) end
Prometheus.Logger.logCallback = function(...) pushLog("info", ...) end
Prometheus.Logger.warnCallback = function(...) pushLog("warn", ...) end
Prometheus.Logger.errorCallback = function(...)
  pushLog("error", ...)
  error(table.concat((function(...)
    local parts = {}
    for i = 1, select("#", ...) do
      parts[#parts + 1] = tostring(select(i, ...))
    end
    return parts
  end)(...), " "))
end

local ok, outputOrError = xpcall(function()
  local preset = ${toLuaLongString(options.preset)}
  local source = ${toLuaLongString(options.source)}
  local filename = ${toLuaLongString(options.filename)}
  local config = {}
  for key, value in pairs(Prometheus.Presets[preset]) do
    config[key] = value
  end

  config.LuaVersion = ${toLuaLongString(options.luaVersion)}
  config.PrettyPrint = ${options.prettyPrint ? "true" : "false"}
  config.Seed = ${Math.max(1, Math.floor(options.seed))}
  ${options.watermark !== undefined ? `config.Watermark = ${toLuaLongString(options.watermark)}` : `config.Watermark = "ARKA\\nON\\nTOP!"`}

  return Prometheus.Pipeline:fromConfig(config):apply(source, filename)
end, debug.traceback)

return { ok = ok, output = ok and outputOrError or "", error = ok and "" or outputOrError, logs = logs }
`
}

interface LuaScriptOptions {
  source: string
  filename: string
}

export function buildScriptRunLua(options: LuaScriptOptions): string {
  return `
local logs = {}
local unpackFn = table.unpack or unpack
local function pushLog(level, ...)
  local parts = {}
  for i = 1, select("#", ...) do
    parts[#parts + 1] = tostring(select(i, ...))
  end
  if type(_G.__prometheusPushLog) == "function" then
    _G.__prometheusPushLog(level, unpackFn(parts))
  end
  logs[#logs + 1] = { level = level, message = table.concat(parts, " ") }
end

print = function(...)
  pushLog("info", ...)
end
warn = function(...)
  pushLog("warn", ...)
end

unpack = table.unpack or unpack
newproxy = newproxy or function(b)
  local t = {}
  if b then setmetatable(t, {}) end
  return t
end
if not bit32 then
  bit32 = {
    bxor = function(a, b)
      local r, m = 0, 1
      while a > 0 or b > 0 do
        local ra, rb = a % 2, b % 2
        if ra ~= rb then r = r + m end
        a, b, m = math.floor(a / 2), math.floor(b / 2), m * 2
      end
      return r
    end,
    band = function(a, b)
      local r, m = 0, 1
      while a > 0 and b > 0 do
        if a % 2 == 1 and b % 2 == 1 then r = r + m end
        a, b, m = math.floor(a / 2), math.floor(b / 2), m * 2
      end
      return r
    end,
    btest = function(a, b)
      while a > 0 and b > 0 do
        if a % 2 == 1 and b % 2 == 1 then return true end
        a, b = math.floor(a / 2), math.floor(b / 2)
      end
      return false
    end,
  }
end
math.clamp = math.clamp or function(v, min, max)
  if v < min then return min end
  if v > max then return max end
  return v
end
math.sign = math.sign or function(v)
  if v > 0 then return 1 elseif v < 0 then return -1 else return 0 end
end
math.round = math.round or function(v)
  return math.floor(v + 0.5)
end

local ok, err = xpcall(function()
  local chunk, loadErr = load(${toLuaLongString(options.source)}, ${toLuaLongString(options.filename)}, "t")
  if not chunk then
    error(loadErr)
  end
  chunk()
end, debug.traceback)

if not ok then
  pushLog("error", err)
end

return { ok = ok, output = "", error = ok and "" or err, logs = logs }
`
}

function normalizeLogs(logs: unknown): PrometheusLog[] {
  if (!Array.isArray(logs)) {
    return []
  }

  return logs.map((entry) => {
    const candidate = entry as { level?: unknown; message?: unknown }
    return {
      level: candidate.level === "warn" || candidate.level === "error" || candidate.level === "debug" ? candidate.level : "info",
      message: String(candidate.message ?? ""),
    }
  })
}

export async function runPrometheus(options: PrometheusOptions): Promise<PrometheusResult> {
  const logs: PrometheusLog[] = []
  let lua: Awaited<ReturnType<InstanceType<LuaFactoryConstructor>["createEngine"]>> | null = null

  try {
    // Force a local Vite-managed Wasm URL so dev/preview behave the same and
    // we don't depend on wasmoon's default CDN URL resolution in workers.
    const LuaFactory = await getLuaFactoryConstructor()
    lua = await new LuaFactory(resolveWasmUri(glueWasmUrl)).createEngine({ openStandardLibs: true })

    const result = (await lua.doString(buildRunLua(options))) as {
      ok?: unknown
      output?: unknown
      error?: unknown
      logs?: unknown
    }
    const isOk = result.ok !== false
    const outputVal = String(result.output ?? "")
    const errorVal = String(result.error ?? "Prometheus failed")
    const logsVal = normalizeLogs(result.logs)

    if (!isOk) {
      return {
        ok: false,
        error: errorVal,
        logs: logsVal,
      }
    }

    return { ok: true, output: outputVal, logs: logsVal }
  } catch (error) {
    return {
      ok: false,
      error: error instanceof Error ? error.message : String(error),
      logs,
    }
  } finally {
    lua?.global.close()
  }
}

export async function runLuaScript(
  options: LuaScriptOptions,
  onLog?: (log: PrometheusLog) => void,
): Promise<PrometheusResult> {
  let lua: Awaited<ReturnType<InstanceType<LuaFactoryConstructor>["createEngine"]>> | null = null

  try {
    const LuaFactory = await getLuaFactoryConstructor()
    lua = await new LuaFactory(resolveWasmUri(glueWasmUrl)).createEngine({ openStandardLibs: true })
    const luaGlobal = lua.global as unknown as {
      set?: (name: string, value: (...args: unknown[]) => void) => void
    }
    luaGlobal.set?.("__prometheusPushLog", (level: unknown, ...parts: unknown[]) => {
      const normalized: PrometheusLog = {
        level: level === "warn" || level === "error" || level === "debug" ? level : "info",
        message: parts.map((part) => String(part)).join(" "),
      }
      onLog?.(normalized)
    })

    const result = (await lua.doString(buildScriptRunLua(options))) as {
      ok?: unknown
      output?: unknown
      error?: unknown
      logs?: unknown
    }
    const isOk = result.ok !== false
    const outputVal = String(result.output ?? "")
    const errorVal = String(result.error ?? "Script execution failed")
    const logsVal = normalizeLogs(result.logs)

    if (!isOk) {
      return {
        ok: false,
        error: errorVal,
        logs: logsVal,
      }
    }

    return { ok: true, output: outputVal, logs: logsVal }
  } catch (error) {
    return {
      ok: false,
      error: error instanceof Error ? error.message : String(error),
      logs: [],
    }
  } finally {
    lua?.global.close()
  }
}
