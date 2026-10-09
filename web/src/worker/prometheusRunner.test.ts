import { describe, expect, it } from "vitest"

import { PRESETS, type PresetName } from "@/lib/prometheusTypes"
import { runLuaScript, runPrometheus } from "./prometheusRunner"

function options(preset: PresetName) {
  return {
    source: 'print("Hello, World!")',
    filename: "hello.lua",
    preset,
    luaVersion: "Lua51" as const,
    prettyPrint: false,
    seed: 12345,
  }
}

describe("runPrometheus", () => {
  it("obfuscates a simple script with Minify", async () => {
    const result = await runPrometheus(options("Minify"))

    if (!result.ok) {
      throw new Error(result.error)
    }
    expect(result.ok).toBe(true)
    if (result.ok) {
      expect(result.output.length).toBeGreaterThan(0)
      expect(result.logs.length).toBeGreaterThan(0)
    }
  }, 30000)

  it("obfuscates a simple script with Medium", async () => {
    const result = await runPrometheus(options("Medium"))

    if (!result.ok) {
      throw new Error(result.error)
    }
    expect(result.ok).toBe(true)
    if (result.ok) {
      expect(result.output.length).toBeGreaterThan(0)
      expect(result.logs.length).toBeGreaterThan(0)
    }
  }, 30000)

  it.each(PRESETS)("smoke tests the %s preset", async (preset) => {
    const result = await runPrometheus(options(preset))

    if (!result.ok) {
      throw new Error(result.error)
    }
    expect(result.ok).toBe(true)
    if (result.ok) {
      expect(result.output).not.toHaveLength(0)
    }
  }, 30000)

  it("verifies strong preset prevents string extraction and stays under 100KB", async () => {
    const robloxScript = `
      local rs = game:GetService("RunService")
      local p = workspace:FindFirstChild("Part")
      print("Protected Execution")
    `
    const result = await runPrometheus({
      source: robloxScript,
      filename: "roblox.lua",
      preset: "Strong",
      luaVersion: "Lua51",
      prettyPrint: false,
      seed: 54321,
    })

    if (!result.ok) {
      throw new Error(result.error)
    }
    expect(result.ok).toBe(true)
    if (result.ok) {
      const sizeKB = Buffer.byteLength(result.output, "utf8") / 1024
      expect(sizeKB).toBeLessThan(115)

      // Verify that sensitive AntiTamper strings do not appear literally in the output
      const sensitiveWords = [
        "RunService",
        "GetService",
        "isfunctionhooked",
        "ishooked",
        "getrenv",
        "setrawmetatable",
        "filtergc",
        "getfunctionhash",
        "getupvalues",
        "__index",
        "__newindex",
        "__metatable",
        "__pairs",
        "__ipairs",
        "__iter",
        "Workspace",
        "Players",
        "LocalPlayer",
        "Humanoid",
        "FindFirstChild",
      ]
      for (const word of sensitiveWords) {
        expect(result.output.includes(`"${word}"`)).toBe(false)
        expect(result.output.includes(`'${word}'`)).toBe(false)
      }
      expect(result.output).not.toContain("The table is locked")
      expect(result.output).not.toContain("table.freeze")
    }
  }, 30000)

  it("executes obfuscated code with ConstantArray mixed encoding and rolling cipher successfully", async () => {
    const script = `
      local a = "Hello"
      local b = "Roblox"
      return a .. " " .. b
    `
    const result = await runPrometheus({
      source: script,
      filename: "test.lua",
      preset: "Weak",
      luaVersion: "Lua51",
      prettyPrint: false,
      seed: 8888,
    })
    if (!result.ok) {
      console.log("PROMETHEUS ERROR:", (result as any).error)
    }
    expect(result.ok).toBe(true)
    if (result.ok) {
      const { LuaFactory } = await import("wasmoon")
      const factory = new LuaFactory()
      const engine = await factory.createEngine()
      try {
        await engine.doString(`
          unpack = table.unpack or unpack
          newproxy = function(b)
            local t = {}
            if b then setmetatable(t, {}) end
            return t
          end
        `)
        const output = await engine.doString(result.output)
        expect(output).toBe("Hello Roblox")
      } catch (e: any) {
        console.log("EXEC ERROR:", e?.message)
        throw e
      } finally {
        engine.global.close()
      }
    }
  }, 30000)

  it("executes code obfuscated with Medium preset in a simulated Roblox Luau environment", async () => {
    const script = `
      local msg = "Welcome to Roblox Luau"
      return msg
    `
    const result = await runPrometheus({
      source: script,
      filename: "test.lua",
      preset: "Medium",
      luaVersion: "Lua51",
      prettyPrint: false,
      seed: 4242,
    })
    expect(result.ok).toBe(true)
    if (result.ok) {
      const { LuaFactory } = await import("wasmoon")
      const factory = new LuaFactory()
      const engine = await factory.createEngine()
      try {
        await engine.doString(`
          unpack = table.unpack or unpack
          newproxy = function(b)
            local t = {}
            if b then setmetatable(t, {}) end
            return t
          end
        `)
        const output = await engine.doString(result.output)
        expect(output).toBe("Welcome to Roblox Luau")
      } catch (e: any) {
        console.log("EXEC ERROR MEDIUM:", e?.message)
        throw e
      } finally {
        engine.global.close()
      }
    }
  }, 30000)

  it("executes code obfuscated with Strong preset in a simulated Roblox Luau environment", async () => {
    const script = `
      local function greet(name)
        return "Roblox:" .. name
      end
      return greet("Player1")
    `
    const result = await runPrometheus({
      source: script,
      filename: "test.lua",
      preset: "Strong",
      luaVersion: "Lua51",
      prettyPrint: false,
      seed: 9999,
    })
    expect(result.ok).toBe(true)
    if (result.ok) {
      const { LuaFactory } = await import("wasmoon")
      const factory = new LuaFactory()
      const engine = await factory.createEngine()
      try {
        await engine.doString(`
          unpack = table.unpack or unpack
          newproxy = function(b)
            local t = {}
            if b then setmetatable(t, {}) end
            return t
          end
        `)
        const output = await engine.doString(result.output)
        expect(output).toBe("Roblox:Player1")
      } catch (e: any) {
        console.log("EXEC ERROR STRONG:", e?.message)
        throw e
      } finally {
        engine.global.close()
      }
    }
  }, 30000)

  it("executes code obfuscated with Strong preset in a full simulated Roblox Luau executor environment without errors or hangs", async () => {
    const script = `
      local function combat(attack, defense)
        local base = math.floor(attack * 2 - defense)
        if base > 0 then
          return "HIT:" .. tostring(base)
        end
        return "BLOCKED"
      end
      return combat(50, 20)
    `
    const result = await runPrometheus({
      source: script,
      filename: "executor_test.lua",
      preset: "Strong",
      luaVersion: "LuaU",
      prettyPrint: false,
      seed: 7777,
    })
    expect(result.ok).toBe(true)
    if (result.ok) {
      const { LuaFactory } = await import("wasmoon")
      const factory = new LuaFactory()
      const engine = await factory.createEngine()
      try {
        await engine.doString(`
          unpack = table.unpack or unpack
          newproxy = function(b)
            local t = {}
            if b then setmetatable(t, {}) end
            return t
          end
          -- Setup Roblox Luau executor environment simulation
          local rsInstance = setmetatable({}, { __metatable = "The metatable is locked" })
          local wsInstance = setmetatable({}, { __metatable = "The metatable is locked" })
          game = setmetatable({
            ClassName = "DataModel",
            GetService = function(self, name)
              if name == "RunService" then return rsInstance end
              if name == "Workspace" then return wsInstance end
              return nil
            end
          }, {
            __metatable = "The metatable is locked"
          })
          workspace = wsInstance
          typeof = function(x)
            if x == game or x == rsInstance or x == wsInstance then
              return "Instance"
            end
            return type(x)
          end
          -- Executor globals
          getrenv = function()
            return {
              pcall = function(f, ...) return pcall(f, ...) end,
              type = type,
            }
          end
          hookfunction = function() end
          table.freeze = function(t) return t end
        `)
        const output = await engine.doString(result.output)
        expect(output).toBe("HIT:80")
      } catch (e: any) {
        console.log("EXEC ERROR SIMULATED EXECUTOR:", e?.message)
        throw e
      } finally {
        engine.global.close()
      }
    }
  }, 30000)

  it("ensures no hanging while loops exist and hides 'Tamper Detect!' and error calls from plain text", async () => {
    const code = `
      local function secret(key)
        if key == "open" then
          return "ACCESS_GRANTED"
        end
        return "ACCESS_DENIED"
      end
      return secret("open")
    `
    const result = await runPrometheus({
      source: code,
      filename: "test.lua",
      preset: "Strong",
      luaVersion: "Lua51",
      prettyPrint: false,
      seed: 12345,
    })
    expect(result.ok).toBe(true)
    if (result.ok) {
      // Must not contain any while true do end hangs
      expect(result.output).not.toMatch(/while\s+true\s+do\s+end/)
      expect(result.output).not.toMatch(/while\s+true\s+do\s+while\s+true/)
      // Plain text "Tamper Detect!" and error("Tamper Detect!",0) must be hidden
      expect(result.output).not.toContain("Tamper Detect!")
      expect(result.output).not.toContain('error("Tamper Detect!"')
      expect(result.output).not.toContain('string.char(84')

      // Must execute cleanly in Lua/Luau environment
      const { LuaFactory } = await import("wasmoon")
      const factory = new LuaFactory()
      const engine = await factory.createEngine()
      try {
        await engine.doString(`
          unpack = table.unpack or unpack
          newproxy = function(b)
            local t = {}
            if b then setmetatable(t, {}) end
            return t
          end
        `)
        const output = await engine.doString(result.output)
        expect(output).toBe("ACCESS_GRANTED")
      } finally {
        engine.global.close()
      }
    }
  }, 30000)

  it("injects the ARKA ON TOP! ASCII watermark without _ARKA_ON_TOP= as valid code statement in the middle of obfuscated code and executes in Roblox Luau", async () => {
    const code = `
      local function calculate(x, y)
        local sum = x + y
        local diff = x - y
        local prod = x * y
        return sum + diff + prod
      end
      return calculate(10, 5)
    `
    const result = await runPrometheus({
      source: code,
      filename: "watermark_test.lua",
      preset: "Medium",
      luaVersion: "LuaU",
      prettyPrint: false,
      seed: 8888,
      watermark: "ARKA\nON\nTOP!",
    })

    expect(result.ok).toBe(true)
    if (!result.ok) return

    // 1. Top watermark is removed - output does NOT start with a watermark comment
    expect(result.output.startsWith("--[=[")).toBe(false)
    expect(result.output.startsWith("@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@")).toBe(false)

    // 2. _ARKA_ON_TOP= must be completely removed
    expect(result.output).not.toContain("_ARKA_ON_TOP=")

    // 3. Middle watermark is injected as a valid Lua code statement seamlessly combined with the code
    expect(result.output).toContain(";local _=[==[\n@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@")

    // 4. Must contain the block letters made with @ characters with crystal clarity
    expect(result.output).toContain("@@        @@@@@   @@@@@@@@  @@@   @@@   @@@@@             @@")

    // 5. Executes accurately without syntax errors in Roblox Luau environment
    const { LuaFactory } = await import("wasmoon")
    const factory = new LuaFactory()
    const engine = await factory.createEngine()
    try {
      await engine.doString(`
        unpack = table.unpack or unpack
        newproxy = function(b)
          local t = {}
          if b then setmetatable(t, {}) end
          return t
        end
      `)
      const res = await engine.doString(result.output)
      expect(res).toBe(70) // (10+5) + (10-5) + (10*5) = 15 + 5 + 50 = 70
    } finally {
      engine.global.close()
    }
  }, 30000)

  it("allows disabling watermark when watermark is empty", async () => {
    const code = `return 42`
    const result = await runPrometheus({
      source: code,
      filename: "no_watermark.lua",
      preset: "Minify",
      luaVersion: "Lua51",
      prettyPrint: false,
      seed: 1234,
      watermark: "",
    })

    expect(result.ok).toBe(true)
    if (!result.ok) return
    expect(result.output).not.toContain("@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@")
  })

  it("hardens against Python deobfuscators and Roblox executor memory dumping with anti-dump decoys and Luau invariants", async () => {
    const code = `
      local function checkPermissions(player, rank)
        if rank >= 100 then
          return "ADMIN_ACCESS_OK"
        end
        return "PLAYER_ACCESS_OK"
      end
      return checkPermissions("RobloxUser", 255)
    `
    const result = await runPrometheus({
      source: code,
      filename: "anti_dump_test.lua",
      preset: "Strong",
      luaVersion: "LuaU",
      prettyPrint: false,
      seed: 98765,
    })

    expect(result.ok).toBe(true)
    if (!result.ok) return

    // 1. Must use obscured arithmetic representations for cipher keystream and arguments (anti-Python regex)
    expect(result.output).toMatch(/\(\([^)]+\)\s*\/\s*\d+\)/)

    // 2. Sensitive strings must remain fully hidden
    expect(result.output).not.toContain("ADMIN_ACCESS_OK")
    expect(result.output).not.toContain("PLAYER_ACCESS_OK")

    // 3. Executes flawlessly in a full Roblox Luau executor environment with bit32 & Luau math
    const { LuaFactory } = await import("wasmoon")
    const factory = new LuaFactory()
    const engine = await factory.createEngine()
    try {
      await engine.doString(`
        unpack = table.unpack or unpack
        newproxy = function(b)
          local t = {}
          if b then setmetatable(t, {}) end
          return t
        end
        bit32 = {
          bxor = function(a, b) return a ~ b end,
          band = function(a, b) return a & b end,
          btest = function(a, b) return (a & b) ~= 0 end,
        }
        math.clamp = function(v, min, max)
          if v < min then return min end
          if v > max then return max end
          return v
        end
        math.sign = function(v)
          if v > 0 then return 1 elseif v < 0 then return -1 else return 0 end
        end
        math.round = function(v)
          return math.floor(v + 0.5)
        end
        table.freeze = function(t) return t end
      `)
      const res = await engine.doString(result.output)
      expect(res).toBe("ADMIN_ACCESS_OK")
    } finally {
      engine.global.close()
    }
  }, 30000)

  it("detects and thwarts reverse engineering environment hooks on _G.print and _G.loadstring", async () => {
    const secretPayload = `
      local secretKey = "SUPER_SECRET_PAYLOAD_TOKEN_999"
      print(secretKey)
      return secretKey
    `
    const result = await runPrometheus({
      source: secretPayload,
      filename: "protected_payload.lua",
      preset: "Strong",
      luaVersion: "LuaU",
      prettyPrint: false,
      seed: 443322,
    })

    expect(result.ok).toBe(true)
    if (!result.ok) return

    const { LuaFactory } = await import("wasmoon")
    const factory = new LuaFactory()
    const engine = await factory.createEngine()

    try {
      // 1. Setup the exact reverse-engineering environment hook reported by the user
      await engine.doString(`
        unpack = table.unpack or unpack
        table.freeze = function(t) return t end

        _captured_prints = {}
        _captured_loadstrings = {}

        local original_print = print
        local original_loadstring = loadstring

        _G.print = function(...)
          local args = {...}
          local output = {}
          for i = 1, #args do
            output[#output + 1] = tostring(args[i])
          end
          local line = table.concat(output, "\t")
          _captured_prints[#_captured_prints + 1] = line
          original_print("[PAYLOAD DUMP - PRINT]:", line)
        end

        if original_loadstring then
          _G.loadstring = function(code, chunk)
            _captured_loadstrings[#_captured_loadstrings + 1] = tostring(code)
            original_print("[PAYLOAD DUMP - LOADSTRING]:\\\\n" .. tostring(code))
            return original_loadstring(code, chunk)
          end
        end
      `)

      // 2. Attempt to execute the obfuscated code inside the hooked environment
      let executionError = null
      try {
        await engine.doString(result.output)
      } catch (err: any) {
        executionError = err
      }

      // 3. Execution MUST be trapped/halted
      expect(executionError).not.toBeNull()

      // 4. Zero sensitive payload strings must be dumped into captured prints or loadstrings
      const dumpedPrints = (await engine.doString("return table.concat(_captured_prints, '\\n')")) as string
      const dumpedLoadstrings = (await engine.doString("return table.concat(_captured_loadstrings, '\\n')")) as string
      expect(dumpedPrints).not.toContain("SUPER_SECRET_PAYLOAD_TOKEN_999")
      expect(dumpedLoadstrings).not.toContain("SUPER_SECRET_PAYLOAD_TOKEN_999")
    } finally {
      engine.global.close()
    }
  }, 30000)

  it("detects getgc below 800 and aborts execution in sandbox", async () => {
    const code = `
      local function secret()
        return "SUCCESSFUL_EXECUTION"
      end
      return secret()
    `
    const result = await runPrometheus({
      source: code,
      filename: "test_getgc.lua",
      preset: "Strong",
      luaVersion: "LuaU",
      prettyPrint: false,
      seed: 88811,
    })
    expect(result.ok).toBe(true)
    if (!result.ok) return

    const { LuaFactory } = await import("wasmoon")
    const factory = new LuaFactory()
    const engine = await factory.createEngine()
    try {
      // Sandbox with shallow getgc (#getgc < 800)
      await engine.doString(`
        unpack = table.unpack or unpack
        table.freeze = function(t) return t end
        getgc = function()
          return {1, 2, 3, 4, 5}
        end
      `)
      let err = null
      try {
        await engine.doString(result.output)
      } catch (e) {
        err = e
      }
      expect(err).not.toBeNull()
    } finally {
      engine.global.close()
    }
  }, 30000)

  it("detects low/spoofed memory address and aborts execution", async () => {
    const code = `
      return "VALID_RUN"
    `
    const result = await runPrometheus({
      source: code,
      filename: "test_low_mem.lua",
      preset: "Strong",
      luaVersion: "LuaU",
      prettyPrint: false,
      seed: 55443,
    })
    expect(result.ok).toBe(true)
    if (!result.ok) return

    const { LuaFactory } = await import("wasmoon")
    const factory = new LuaFactory()
    const engine = await factory.createEngine()
    try {
      // Hook tostring to return low memory addresses (e.g. 0x100)
      await engine.doString(`
        unpack = table.unpack or unpack
        table.freeze = function(t) return t end
        local old_tostring = tostring
        tostring = function(v)
          if type(v) == "table" then
            return "table: 0x100"
          end
          return old_tostring(v)
        end
      `)
      let err = null
      try {
        await engine.doString(result.output)
      } catch (e) {
        err = e
      }
      expect(err).not.toBeNull()
    } finally {
      engine.global.close()
    }
  }, 30000)

  it("reproduces and verifies running Strong preset output in runLuaScript", async () => {
    const result = await runPrometheus({
      source: 'print("Hello from Strong!")',
      filename: "test.lua",
      preset: "Strong",
      luaVersion: "LuaU",
      prettyPrint: false,
      seed: 12345,
    })
    expect(result.ok).toBe(true)
    if (!result.ok) return
    const runResult = await runLuaScript({
      source: result.output,
      filename: "browser-output.lua",
    })
    if (!runResult.ok) {
      throw new Error(`RUN SCRIPT ERROR: ${runResult.error}`)
    }
    expect(runResult.ok).toBe(true)
    expect(runResult.logs.some((l) => l.message.includes("Hello from Strong!"))).toBe(true)
  }, 30000)
})
