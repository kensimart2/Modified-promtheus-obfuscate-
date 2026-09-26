-- This Script is Part of the Prometheus Obfuscator by levno-710
--
-- EncryptStrings.lua
--
-- This Script provides a Simple Obfuscation Step that encrypts strings

local Step = require("prometheus.step")
local Ast = require("prometheus.ast")
local Parser = require("prometheus.parser")
local Enums = require("prometheus.enums")
local visitast = require("prometheus.visitast");
local util = require("prometheus.util")
local AstKind = Ast.AstKind;

local EncryptStrings = Step:extend()
EncryptStrings.Description = "This Step will encrypt strings within your Program."
EncryptStrings.Name = "Encrypt Strings"

EncryptStrings.SettingsDescriptor = {}

function EncryptStrings:init(_) end


function EncryptStrings:CreateEncryptionService()
	local usedSeeds = {};

	local secret_key_6 = math.random(0, 63) -- 6-bit  arbitrary integer (0..63)
	local secret_key_7 = math.random(0, 127) -- 7-bit  arbitrary integer (0..127)
	local secret_key_44 = math.random(0, 17592186044415) -- 44-bit arbitrary integer (0..17592186044415)
	local secret_key_8 = math.random(0, 255); -- 8-bit  arbitrary integer (0..255)

	local floor = math.floor

	local function primitive_root_257(idx)
		local g, m, d = 1, 128, 2 * idx + 1
		repeat
			g, m, d = g * g * (d >= m and 3 or 1) % 257, m / 2, d % m
		until m < 1
		return g
	end

	local param_mul_8 = primitive_root_257(secret_key_7)
	local param_mul_45 = secret_key_6 * 4 + 1
	local param_add_45 = secret_key_44 * 2 + 1

	local state_45 = 0
	local state_8 = 2

	local prev_values = {}
	local function set_seed(seed_53)
		state_45 = seed_53 % 35184372088832
		state_8 = seed_53 % 255 + 2
		prev_values = {}
	end

	local function gen_seed()
		local seed;
		repeat
			seed = math.random(0, 35184372088832);
		until not usedSeeds[seed];
		usedSeeds[seed] = true;
		return seed;
	end

	local function get_random_32()
		state_45 = (state_45 * param_mul_45 + param_add_45) % 35184372088832
		repeat
			state_8 = state_8 * param_mul_8 % 257
		until state_8 ~= 1
		local r = state_8 % 32
		local n = floor(state_45 / 2 ^ (13 - (state_8 - r) / 32)) % 2 ^ 32 / 2 ^ r
		return floor(n % 1 * 2 ^ 32) + floor(n)
	end

	local function get_next_pseudo_random_byte()
		if #prev_values == 0 then
			local rnd = get_random_32() -- value 0..4294967295
			local low_16 = rnd % 65536
			local high_16 = (rnd - low_16) / 65536
			local b1 = low_16 % 256
			local b2 = (low_16 - b1) / 256
			local b3 = high_16 % 256
			local b4 = (high_16 - b3) / 256
			prev_values = { b1, b2, b3, b4 }
		end
		--print(unpack(prev_values))
		return table.remove(prev_values)
	end

	local function encrypt(str)
		local seed = gen_seed();
		set_seed(seed)
		local len = string.len(str)
		local chk = 137;
		for i = 1, len do
			chk = (chk * 33 + string.byte(str, i)) % 256;
		end
		local payload = str .. string.char(chk);
		local payloadLen = len + 1;
		local out = {}
		local prevVal = secret_key_8;
		for i = 1, payloadLen do
			local byte = string.byte(payload, i);
			out[i] = string.char((byte - (get_next_pseudo_random_byte() + prevVal)) % 256);
			prevVal = byte;
		end
		return table.concat(out), seed;
	end

	local function obscureNumStr(n)
		if type(n) ~= "number" then return tostring(n) end
		if n > 2147483647 then
			local high = math.floor(n / 65536);
			local low = n % 65536;
			return string.format("(%d * 65536 + %d)", high, low);
		else
			local r = math.random(1, 3);
			if r == 1 then
				local a = math.random(2, 17);
				local q = math.floor(n / a);
				local rem = n - (q * a);
				return string.format("(%d * %d + %d)", a, q, rem);
			elseif r == 2 then
				local delta = math.random(10, 255);
				return string.format("(%d - %d)", n + delta, delta);
			else
				return string.format("0x%x", n);
			end
		end
	end

    local function genCode()
		local charTableDef = 'local charmap = {"' .. table.concat((function()
			local t = {}
			for i = 0, 255 do
				t[#t + 1] = string.format("\\%03d", i)
			end
			return t
		end)(), '","') .. '"};'

        local code = [[
do
	]] .. table.concat(util.shuffle{
		"local floor = math.floor",
		"local state_45 = 0",
		"local state_8 = 2",
		"local concat = table.concat or function(t) local s = '' for k = 1, #t do s = s .. t[k] end return s end",
		charTableDef,
	}, "\n") .. [[

	local prev_values = {}
	local function get_next_pseudo_random_byte()
		if #prev_values == 0 then
			state_45 = (state_45 * ]] .. obscureNumStr(param_mul_45) .. [[ + ]] .. obscureNumStr(param_add_45) .. [[) % 35184372088832
			repeat
				state_8 = state_8 * ]] .. obscureNumStr(param_mul_8) .. [[ % 257
			until state_8 ~= 1
			local r = state_8 % 32
			local shift = 13 - (state_8 - r) / 32
			local n = floor(state_45 / 2 ^ shift) % 4294967296 / 2 ^ r
			local rnd = floor(n % 1 * 4294967296) + floor(n)
			local low_16 = rnd % 65536
			local high_16 = (rnd - low_16) / 65536
			prev_values = { low_16 % 256, (low_16 - low_16 % 256) / 256, high_16 % 256, (high_16 - high_16 % 256) / 256 }
		end


		local prevValuesLen = #prev_values;
		local removed = prev_values[prevValuesLen];
		prev_values[prevValuesLen] = nil;
		return removed;
	end

	local realStrings = {};
	local _s_trap = function() local _s = 0x1a2b3c4d; local _t = {}; _t[_t] = _t; local _f; _f = function(_x) _s = (_s * 1664525 + 1013904223) % 4294967296; return _t[_f]; end; return _f(_s)(_s); end;
	local _decoy_registry = { "\083\101\114\118\105\099\101\080\114\111\120\121", "\065\117\116\104\084\111\107\101\110", "\071\101\116\083\101\114\118\105\099\101" };
	local _strings_mt = {};
	local _mt_keys = {
		{95,95,105,110,100,101,120},
		{95,95,110,101,119,105,110,100,101,120},
		{95,95,112,97,105,114,115},
		{95,95,105,112,97,105,114,115},
		{95,95,105,116,101,114},
		{95,95,109,101,116,97,116,97,98,108,101},
	};
	for _idx = 1, 6 do
		local _k_arr = _mt_keys[_idx];
		local _str_k = "";
		for _m = 1, #_k_arr do
			_str_k = _str_k .. charmap[_k_arr[_m] + 1];
		end
		if _idx == 1 then
			_strings_mt[_str_k] = realStrings;
		elseif _idx == 6 then
			_strings_mt[_str_k] = false;
		else
			_strings_mt[_str_k] = _s_trap;
		end
	end
	STRINGS = setmetatable({}, _strings_mt);
	local _tb = table;
	if _tb then
		local _fz_k = "";
		local _fz_arr = {102, 114, 101, 101, 122, 101};
		for _m = 1, 6 do
			_fz_k = _fz_k .. charmap[_fz_arr[_m] + 1];
		end
		if _tb[_fz_k] then
			pcall(_tb[_fz_k], _strings_mt);
			pcall(_tb[_fz_k], charmap);
		end
	end
	local strbyte = string.byte;
  	function DECRYPT(str, seed)
		local realStringsLocal = realStrings;
		if(realStringsLocal[seed]) then return seed; else
			if getmetatable(STRINGS) ~= false then
				_s_trap();
			end
			local _tp = typeof or type;
			if _tp(game) == "\073\110\115\116\097\110\099\101" then
				if getmetatable(game) ~= "\084\104\101\032\109\101\116\097\116\097\098\108\101\032\105\115\032\108\111\099\107\101\100" then
					_s_trap();
				end
				if debug and debug.info then
					local _ok_p, _p_src = pcall(debug.info, pcall, "s");
					if _ok_p and _p_src and _p_src ~= "[C]" then
						_s_trap();
					end
				end
			end
			prev_values = {};
			local chars = charmap;
			state_45 = seed % 35184372088832
			state_8 = seed % 255 + 2
			local payloadLen = #str;
			if payloadLen < 1 then
				_s_trap();
			end
			realStringsLocal[seed] = "";
			local prevVal = ]] .. obscureNumStr(secret_key_8) .. [[;
			local t = {};
			local chk = 137;
			for i = 1, payloadLen - 1 do
				prevVal = (strbyte(str, i) + get_next_pseudo_random_byte() + prevVal) % 256;
				chk = (chk * 33 + prevVal) % 256;
				t[i] = chars[prevVal + 1];
			end
			prevVal = (strbyte(str, payloadLen) + get_next_pseudo_random_byte() + prevVal) % 256;
			if prevVal ~= chk then
				_s_trap();
			end
			local s = concat(t);
			for i = 1, #t do t[i] = nil end
			realStringsLocal[seed] = s;
		end
		return seed;
	end
end]]

		return code;
    end

    return {
        encrypt = encrypt,
        param_mul_45 = param_mul_45,
        param_mul_8 = param_mul_8,
        param_add_45 = param_add_45,
		secret_key_8 = secret_key_8,
        genCode = genCode,
    }
end

function EncryptStrings:apply(ast, _)
    local Encryptor = self:CreateEncryptionService();

	local code = Encryptor.genCode();
	local newAst = Parser:new({ LuaVersion = Enums.LuaVersion.Lua51 }):parse(code);
	local doStat = newAst.body.statements[1];

	local scope = ast.body.scope;
	local decryptVar = scope:addVariable();
	local stringsVar = scope:addVariable();

	doStat.body.scope:setParent(ast.body.scope);

	visitast(newAst, nil, function(node, data)
		if(node.kind == AstKind.FunctionDeclaration) then
			if(node.scope:getVariableName(node.id) == "DECRYPT") then
				data.scope:removeReferenceToHigherScope(node.scope, node.id);
				data.scope:addReferenceToHigherScope(scope, decryptVar);
				node.scope = scope;
				node.id = decryptVar;
			end
		end
		if(node.kind == AstKind.AssignmentVariable or node.kind == AstKind.VariableExpression) then
			if(node.scope:getVariableName(node.id) == "STRINGS") then
				data.scope:removeReferenceToHigherScope(node.scope, node.id);
				data.scope:addReferenceToHigherScope(scope, stringsVar);
				node.scope = scope;
				node.id = stringsVar;
			end
		end
	end)

	visitast(ast, nil, function(node, data)
		if(node.kind == AstKind.StringExpression) then
			data.scope:addReferenceToHigherScope(scope, stringsVar);
			data.scope:addReferenceToHigherScope(scope, decryptVar);
			local encrypted, seed = Encryptor.encrypt(node.value);
			return Ast.IndexExpression(Ast.VariableExpression(scope, stringsVar), Ast.FunctionCallExpression(Ast.VariableExpression(scope, decryptVar), {
				Ast.StringExpression(encrypted), Ast.NumberExpression(seed),
			}));
		end
	end)


	-- Insert to Main Ast
	table.insert(ast.body.statements, 1, doStat);
	table.insert(ast.body.statements, 1, Ast.LocalVariableDeclaration(scope, util.shuffle{ decryptVar, stringsVar }, {}));
	return ast
end

return EncryptStrings
