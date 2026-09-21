-- This Script is Part of the Prometheus Obfuscator
-- watermark_banner.lua
-- Generates formatted ASCII banners for script watermarking

local WatermarkBanner = {}

local ARKA_ON_TOP_BANNER = [[
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@                                                        @@
@@        @@@@@   @@@@@@@@  @@@   @@@   @@@@@             @@
@@       @@@ @@@  @@@   @@@ @@@  @@@   @@@ @@@            @@
@@      @@@   @@@ @@@@@@@@  @@@@@@    @@@   @@@           @@
@@      @@@@@@@@@ @@@ @@@   @@@  @@@  @@@@@@@@@           @@
@@      @@@   @@@ @@@  @@@  @@@   @@@ @@@   @@@           @@
@@      @@@   @@@ @@@   @@@ @@@    @@@@@@   @@@           @@
@@                                                        @@
@@                  @@@@@@   @@@   @@@                    @@
@@                 @@@  @@@  @@@@  @@@                    @@
@@                 @@@  @@@  @@@@@ @@@                    @@
@@                 @@@  @@@  @@@ @@@@@                    @@
@@                 @@@  @@@  @@@  @@@@                    @@
@@                  @@@@@@   @@@   @@@                    @@
@@                                                        @@
@@             @@@@@@@@@  @@@@@@   @@@@@@@@   @@@         @@
@@                @@@    @@@  @@@  @@@   @@@  @@@         @@
@@                @@@    @@@  @@@  @@@@@@@@   @@@         @@
@@                @@@    @@@  @@@  @@@        @@@         @@
@@                @@@    @@@  @@@  @@@                    @@
@@                @@@     @@@@@@   @@@        @@@         @@
@@                                                        @@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@]]

function WatermarkBanner.formatBanner(text)
	if not text or text == "" or text == false then
		return nil
	end

	if type(text) ~= "string" then
		text = tostring(text)
	end

	local clean = text:gsub("\r", "")
	local upper = clean:upper()
	if (upper:find("ARKA") and upper:find("TOP")) or upper:find("ARKA") then
		return ARKA_ON_TOP_BANNER:gsub("^\n+", ""):gsub("\n+$", "")
	end

	-- Generic multi-line text framed with @ border of width 60
	local lines = {}
	for line in clean:gmatch("([^\n]+)") do
		table.insert(lines, line)
	end
	if #lines == 0 then
		lines = { clean }
	end

	local bannerWidth = 60
	local innerWidth = bannerWidth - 4 -- 2 chars for '@@' on each side

	local out = { string.rep("@", bannerWidth), "@@" .. string.rep(" ", innerWidth) .. "@@" }
	for _, l in ipairs(lines) do
		local trimmed = l:sub(1, innerWidth)
		local pad = math.max(0, math.floor((innerWidth - #trimmed) / 2))
		local rightPad = math.max(0, innerWidth - #trimmed - pad)
		local lineFormatted = "@@" .. string.rep(" ", pad) .. trimmed .. string.rep(" ", rightPad) .. "@@"
		table.insert(out, lineFormatted)
	end
	table.insert(out, "@@" .. string.rep(" ", innerWidth) .. "@@")
	table.insert(out, string.rep("@", bannerWidth))

	return table.concat(out, "\n")
end

return WatermarkBanner
