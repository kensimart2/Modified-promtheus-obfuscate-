local Step = require("prometheus.step")
local Enums = require("prometheus.enums")
local Unparser = require("prometheus.unparser")

local LuraphStager = Step:extend()
LuraphStager.Description = "Wraps code into a Luraph v15-style polymorphic metatable stager"
LuraphStager.Name = "LuraphStager"

LuraphStager.SettingsDescriptor = {}

function LuraphStager:init(_) end

local function lzssCompress(inputStr)
	local len = #inputStr
	local out = {}
	local i = 1
	local head = {}
	local prev = {}

	local function getHash(idx)
		if idx + 2 > len then return nil end
		local b1, b2, b3 = string.byte(inputStr, idx, idx + 2)
		return (b1 * 65536 + b2 * 256 + b3)
	end

	while i <= len do
		local bestOff = 0
		local bestLen = 0
		local maxLen = math.min(255, len - i + 1)

		if maxLen >= 4 then
			local key = getHash(i)
			if key then
				local p = head[key]
				local chain = 0
				local minPos = math.max(1, i - 4095)
				while p and p >= minPos and chain < 48 do
					local ml = 0
					while ml < maxLen and string.byte(inputStr, p + ml) == string.byte(inputStr, i + ml) do
						ml = ml + 1
					end
					if ml > bestLen then
						bestLen = ml
						bestOff = i - p
						if bestLen == maxLen then break end
					end
					p = prev[p]
					chain = chain + 1
				end
			end
		end

		if bestLen >= 4 then
			local hi = math.floor((bestOff - 1) / 256)
			local lo = (bestOff - 1) % 256
			table.insert(out, string.char(128 + hi, lo, bestLen))
			for k = 0, bestLen - 1 do
				local idx = i + k
				local key = getHash(idx)
				if key then
					prev[idx] = head[key]
					head[key] = idx
				end
			end
			i = i + bestLen
		else
			local litStart = i
			local litLen = 1
			local key = getHash(i)
			if key then
				prev[i] = head[key]
				head[key] = i
			end
			i = i + 1

			while i <= len and litLen < 127 do
				local hasMatch = false
				if (len - i + 1) >= 4 then
					local lk = getHash(i)
					if lk then
						local p = head[lk]
						local minPos = math.max(1, i - 4095)
						if p and p >= minPos then
							local ml = 0
							while ml < 4 and string.byte(inputStr, p + ml) == string.byte(inputStr, i + ml) do
								ml = ml + 1
							end
							if ml >= 4 then
								hasMatch = true
							end
						end
					end
				end

				if hasMatch then
					break
				end

				local chk = getHash(i)
				if chk then
					prev[i] = head[chk]
					head[chk] = i
				end
				litLen = litLen + 1
				i = i + 1
			end

			table.insert(out, string.char(litLen - 1) .. string.sub(inputStr, litStart, litStart + litLen - 1))
		end
	end

	return table.concat(out)
end

-- Cascading 2-seed LCG rolling cipher with dynamic feedback
local function cipherStream(data, key)
	local res = {}
	local h1 = key % 65536
	local h2 = (key * 7 + 13) % 65536
	local prev = 0
	for j = 1, #data do
		h1 = (h1 * 31415 + 27183) % 65536
		h2 = (h2 * 25173 + 13849) % 65536
		local kb = (math.floor(h1 / 256) + math.floor(h2 / 256)) % 256
		local b = string.byte(data, j)
		local shifted = (b + prev) % 256
		local xord = 0
		local m = 1
		local x, y = shifted, kb
		while x > 0 or y > 0 do
			local rx, ry = x % 2, y % 2
			if rx ~= ry then xord = xord + m end
			x, y, m = math.floor(x / 2), math.floor(y / 2), m * 2
		end
		res[j] = string.char(xord)
		prev = xord
	end
	return table.concat(res)
end

local B85_ALPHABET = "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ!#$%&()*+,-./:;<=>?@^_|~"

local function base85Encode(data)
	local origLen = #data
	local lenHeader = string.char(
		math.floor(origLen / 16777216) % 256,
		math.floor(origLen / 65536) % 256,
		math.floor(origLen / 256) % 256,
		origLen % 256
	)
	local fullData = lenHeader .. data
	local pad = (4 - (#fullData % 4)) % 4
	if pad > 0 then
		fullData = fullData .. string.rep("\0", pad)
	end

	local alphaBytes = { string.byte(B85_ALPHABET, 1, #B85_ALPHABET) }
	local out = {}
	for i = 1, #fullData, 4 do
		local b1, b2, b3, b4 = string.byte(fullData, i, i + 3)
		local num = b1 * 16777216 + b2 * 65536 + b3 * 256 + b4
		local c5 = num % 85; num = math.floor(num / 85)
		local c4 = num % 85; num = math.floor(num / 85)
		local c3 = num % 85; num = math.floor(num / 85)
		local c2 = num % 85; num = math.floor(num / 85)
		local c1 = num % 85
		table.insert(out, string.char(alphaBytes[c1 + 1], alphaBytes[c2 + 1], alphaBytes[c3 + 1], alphaBytes[c4 + 1], alphaBytes[c5 + 1]))
	end
	return table.concat(out)
end

local function escapeLuaPattern(s)
	return s:gsub("[%(%)%.%%%+%-%*%?%[%]%^%$]", "%%%1")
end

function LuraphStager:apply(ast, pipeline)
	-- Ensure AST variable names are generated before unparsing
	pipeline:renameVariables(ast)

	local innerUnparser = Unparser:new({
		LuaVersion = pipeline.LuaVersion or Enums.LuaVersion.LuaU,
		PrettyPrint = false,
		Watermark = pipeline.Watermark,
	})
	local innerCode = innerUnparser:unparse(ast)

	local compressed = lzssCompress(innerCode)
	local key = math.random(10000, 60000)
	local ciphered = cipherStream(compressed, key)
	local b85String = base85Encode(ciphered)

	local counts = {}
	local slen = #b85String
	for i = 1, slen - 7, 4 do
		local chunk = string.sub(b85String, i, i + 3)
		counts[chunk] = (counts[chunk] or 0) + 1
	end

	local sorted = {}
	for seq, cnt in pairs(counts) do
		if cnt >= 3 then
			table.insert(sorted, { seq = seq, cnt = cnt })
		end
	end
	table.sort(sorted, function(a, b) return a.cnt > b.cnt end)

	local markerChars = { "{", "}" }
	local finalPayload = b85String
	local dictEntries = {}
	for idx = 1, math.min(#markerChars, #sorted) do
		local marker = markerChars[idx]
		local seq = sorted[idx].seq
		local replaced = string.gsub(finalPayload, escapeLuaPattern(seq), marker)
		finalPayload = replaced
		table.insert(dictEntries, string.format("[%q] = %q", marker, seq))
	end

	local kHTableCode = "{" .. table.concat(dictEntries, ", ") .. "}"
	local dHRegex = "[{}]"

	local isPretty = pipeline.PrettyPrint == true
	local nl = isPretty and "\n" or ""
	local tab = isPretty and "\t" or ""
	local sep = isPretty and (",\n" .. tab) or ","

	local entries = {
		"[43]=bit32 and bit32.bxor or function(a,b)local r,m=0,1;while a>0 or b>0 do local ra,rb=a%2,b%2;if ra~=rb then r=r+m end;a,b,m=math.floor(a/2),math.floor(b/2),m*2 end;return r end",
		"[39]=string.gsub",
		"[46]=bit32 and bit32.countrz or function(x)local c=0;while x>0 and x%2==0 do c=c+1;x=math.floor(x/2) end;return c end",
		"tH=function(R,F,Y,d,L,O,k,v)if d<=1 then if d<=0 then return 128>Y and 10 or 32,O,Y,v else return 3,O,Y,v end elseif d<=2 then return 24,3+O,F,v else return 19,L,Y,v end end",
		"C={39314,3019592665,268586211,427097616,1235795541,4165977883,4144480640,2497155359,1130321932}",
		"[94]=pcall",
		"[126]=buffer and buffer.readstring or function(b,o,l)return\"\"end",
		"O=function(R,F,Y,d,L,O,k,v,y,K,c)if k then if O<=147 then return 155,F,L,v,c,d,1+y else return 24,F,L,k,c,d,y end elseif O<=149 then return 49,F,L,v,c,d,k elseif O<=150 then return 153,F,L+4,v,c,Y,y else return 99,{1-v,Y+0,nil,F,v},L,O,k,d,y end end",
		"Q=function(R,F,Y,d,L,O,k)if k<=1 then if k<=0 then return 81,d,F,L,v else return 115,d,v,L,O end elseif k<=2 then return 89,d,F,L+1,O elseif k<=3 then return 132,d,F,L+4,O else return 156,1+L,F,L,O end end",
		"[12]=string.match",
		"[102]=buffer and buffer.readu16 or function()return 0 end",
		"[115]=buffer and buffer.writef64 or function()end",
		"qH=function(R,F,Y,d,L,O,k,v)if k<=29 then return 12,Y,L elseif k<=30 then return 15,Y,L else return 40,Y,d end end",
		"D=function(R,F,Y,d,L,O,k,v,y,K)if Y<=82 then if Y<=81 then return 31,F,L+1,v,O,y,K else return 162,F,s,v,O,y,K end elseif Y<=83 then return 135,F,L,v,O,y,K elseif Y<=84 then return 28,F,L,v,O,y,Y else return 82,F,L,O+128*(v-128),2,y,K end end",
		"f=function(R,F,Y,d,L,O,k,v,y,K,c,s)if O<=123 then if O<=122 then return 117,v,2+d,k,s,r,K,y else return 121,{nil,Y+0,v,r,M},Y,k,s,L,G,N end elseif O<=124 then return 132,v,2+d,k,Y,L,K,y elseif O<=125 then return 35,v[4],d,k,s,L,K,y else return 37,v,d,F,s,L,K,y end end",
		"[16]=coroutine.status",
		"EH=function(R,F,Y,d,L,O,k,v)if O<=5 then return 24,3+k,d,v else return 2,k,L,F end end",
		"[33]=string.format",
		"S=function(R,F,Y,d,L,O,k,v,y)if d<=50 then return 3,y,L,R+v else return 156,128*(y-128)+L,O+2,F end end",
		"JH=function(R,F,Y,d,L,O,k,v,y,K,c)if L<=7 then return 14,O,K,v,y elseif L<=8 then return 1,O,K,F else return 26,O,c,F end end",
		"[22]=typeof and typeof==\"function\" and Vector3 and Vector3.new or function()return nil end",
		"RH=function(R,F,Y,d,L,O,k,v,y,K,c,s)if s<=5 then return 11,c,v,d elseif s<=6 then return 24,c,v,d+2 elseif s<=7 then return 16,c,s,r else return 26,c,Y,d end end",
		"vH=function(R,F,Y,d,L,O,k,v,y,K,c)if K<=33 then return 35,F,Y elseif K<=34 then return 6,c,O,Y else return 33,c,F,O end end",
		"[125]=loadstring or load",
		"[24]=bit32 and bit32.lshift or function(a,b)return a*(2^b)end",
		"[93]=bit32 and bit32.bor or function(a,b)return a+b end",
		"[60]=buffer and buffer.writeu8 or function()end",
		"[48]=buffer and buffer.writeu32 or function()end",
		"[18]=buffer and buffer.copy or function()end",
		"[76]=bit32 and bit32.band or function(a,b)return a%b end",
		"[50]=table.pack or function(...)return{n=select(\"#\",...),...}end",
		"[53]=string.byte",
		"[108]=string.char",
		"[73]=string.sub",
		"[30]=table.concat",
		"_K=" .. tostring(key),
		"DH=" .. string.format("%q", dHRegex),
		"kH=" .. kHTableCode,
		"XH=[=[LPH+" .. finalPayload .. "]=]",
		"rH=function(self,...)local S=self[73];local G=self[39];local C=self[108];local B=self[53];local T=self[30];local L=self[125];local X=self[43];local A=" .. string.format("%q", B85_ALPHABET) .. ";local M={};for i=1,85 do M[B(A,i)]=i-1 end;local _src=G(S(self.XH,5),self.DH,self.kH);local _dec={};local _slen=#_src;local _p=1;while _p+4<=_slen do local n=(M[B(_src,_p)] or 0)*52200625 + (M[B(_src,_p+1)] or 0)*614125 + (M[B(_src,_p+2)] or 0)*7225 + (M[B(_src,_p+3)] or 0)*85 + (M[B(_src,_p+4)] or 0);_p=_p+5;local b4=n%256;n=math.floor(n/256);local b3=n%256;n=math.floor(n/256);local b2=n%256;n=math.floor(n/256);local b1=n%256;_dec[#_dec+1]=C(b1,b2,b3,b4) end;local _raw=T(_dec);local _origLen=B(_raw,1)*16777216+B(_raw,2)*65536+B(_raw,3)*256+B(_raw,4);_raw=S(_raw,5,4+_origLen);local P=self[94];local D=string and string.dump;local _chk=false;local _g=rawget(_G and _G or {},1) or _G;local _g_lds=_g and (_g.loadstring or _g.load) or (loadstring or load);if P and D and (P(D,L) or (print and P(D,print)) or (_g_lds and P(D,_g_lds)) or (load and P(D,load)) or (loadstring and P(D,loadstring))) then _chk=true end;if debug and debug.gethook and debug.gethook() then _chk=true end;local _ih=isfunctionhooked or ishooked;if _ih and (_ih(L) or (_g_lds and _ih(_g_lds))) then _chk=true end;local _h1=self._K%65536;local _h2=(self._K*7+13)%65536;if _chk then _h1=(_h1+41235)%65536;_h2=(_h2+58321)%65536 end;local _pbytes={};local _prev=0;for i=1,#_raw do _h1=(_h1*31415+27183)%65536;_h2=(_h2*25173+13849)%65536;local kb=(math.floor(_h1/256)+math.floor(_h2/256))%256;local x=B(_raw,i);local b=((X(x,kb)-_prev+256)%256);_pbytes[i]=C(b);_prev=x end;local _cmp=T(_pbytes);local _pos=1;local _res={};local _clen=#_cmp;while _pos<=_clen do local _tag=B(_cmp,_pos);_pos=_pos+1;if _tag<128 then local _run=_tag+1;for j=0,_run-1 do _res[#_res+1]=S(_cmp,_pos+j,_pos+j) end;_pos=_pos+_run else local _hi=_tag-128;local _lo=B(_cmp,_pos);local _mlen=B(_cmp,_pos+1);_pos=_pos+2;local _off=_hi*256+_lo+1;local _st=#_res-_off+1;for j=0,_mlen-1 do _res[#_res+1]=_res[_st+j] end end end;local _payload=T(_res);if _chk then return nil end;local _fn=L(_payload);if not _fn then return nil end;return _fn(...)end"
	}

	local header = isPretty and "-- This file was protected using Luraph Obfuscator v15.1 [https://lura.ph/]\n\n" or ""
	local body = table.concat(entries, sep)
	local stagerCode = header .. "return setmetatable({" .. (isPretty and ("\n" .. tab) or "") .. body .. (isPretty and "\n" or "") .. "},{}):rH(...)"

	pipeline.finalCode = stagerCode

	return ast
end

return LuraphStager
