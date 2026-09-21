import { describe, expect, it } from "vitest"

import { PRESETS, type PresetName } from "@/lib/prometheusTypes"
import { runPrometheus } from "./prometheusRunner"

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
      expect(sizeKB).toBeLessThan(100)

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
      ]
      for (const word of sensitiveWords) {
        expect(result.output.includes(`"${word}"`)).toBe(false)
        expect(result.output.includes(`'${word}'`)).toBe(false)
      }
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
})
