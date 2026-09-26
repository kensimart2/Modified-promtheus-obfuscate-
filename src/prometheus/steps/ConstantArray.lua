-- This Script is Part of the Prometheus Obfuscator by levno-710
--
-- ConstantArray.lua
--
-- This Script provides a Simple Obfuscation Step that wraps the entire Script into a function

-- TODO: Wrapper Functions
-- TODO: Proxy Object for indexing: e.g: ARR[X] becomes ARR + X

local Step = require("prometheus.step");
local Ast = require("prometheus.ast");
local Scope = require("prometheus.scope");
local visitast = require("prometheus.visitast");
local util = require("prometheus.util")
local Parser = require("prometheus.parser");
local enums = require("prometheus.enums")

local LuaVersion = enums.LuaVersion;
local AstKind = Ast.AstKind;

local ConstantArray = Step:extend();
ConstantArray.Description = "This Step will Extract all Constants and put them into an Array at the beginning of the script";
ConstantArray.Name = "Constant Array";

ConstantArray.SettingsDescriptor = {
	Threshold = {
		name = "Threshold",
		description = "The relative amount of nodes that will be affected",
		type = "number",
		default = 1,
		min = 0,
		max = 1,
		aliases = { "Treshold" },
	},
	StringsOnly = {
		name = "StringsOnly",
		description = "Wether to only Extract Strings",
		type = "boolean",
		default = false,
	},
	Shuffle = {
		name = "Shuffle",
		description = "Wether to shuffle the order of Elements in the Array",
		type = "boolean",
		default = true,
	},
	Rotate = {
		name = "Rotate",
		description = "Wether to rotate the String Array by a specific (random) amount. This will be undone on runtime.",
		type = "boolean",
		default = true,
	},
	LocalWrapperThreshold = {
		name = "LocalWrapperThreshold",
		description = "The relative amount of nodes functions, that will get local wrappers",
		type = "number",
		default = 1,
		min = 0,
		max = 1,
		aliases = { "LocalWrapperTreshold" },
	},
	LocalWrapperCount = {
		name = "LocalWrapperCount",
		description = "The number of Local wrapper Functions per scope. This only applies if LocalWrapperThreshold is greater than 0",
		type = "number",
		min = 0,
		max = 512,
		default = 0,
	},
	LocalWrapperArgCount = {
		name = "LocalWrapperArgCount",
		description = "The number of Arguments to the Local wrapper Functions",
		type = "number",
		min = 1,
		default = 10,
		max = 200,
	};
	MaxWrapperOffset = {
		name = "MaxWrapperOffset",
		description = "The Max Offset for the Wrapper Functions",
		type = "number",
		min = 0,
		default = 65535,
	};
	Encoding = {
		name = "Encoding",
		description = "The Encoding to use for the Strings",
		type = "enum",
		default = "mixed",
		values = {
			"none",
			"base64",
			"base85",
			"mixed",
		},
	}
}

local prefix_0, prefix_1;
local function initPrefixes()
	local b1 = math.random(128, 250);
	local b2 = math.random(128, 250);
	while b2 == b1 do
		b2 = math.random(128, 250);
	end
	prefix_0 = string.char(b1);
	prefix_1 = string.char(b2);
end

local function callNameGenerator(generatorFunction, ...)
	if(type(generatorFunction) == "table") then
		generatorFunction = generatorFunction.generateName;
	end
	return generatorFunction(...);
end

local function createObfuscatedNumberNode(val)
	local variant = math.random(1, 4);
	if variant == 1 then
		local mul = math.random(2, 6);
		local k = math.random(11, 79) * mul;
		return Ast.DivExpression(
			Ast.SubExpression(
				Ast.AddExpression(
					Ast.MulExpression(Ast.NumberExpression(val), Ast.NumberExpression(mul)),
					Ast.NumberExpression(k)
				),
				Ast.NumberExpression(k)
			),
			Ast.NumberExpression(mul)
		);
	elseif variant == 2 then
		local d1 = math.random(13, 89);
		local d2 = math.random(11, 73);
		return Ast.SubExpression(
			Ast.SubExpression(
				Ast.AddExpression(
					Ast.AddExpression(Ast.NumberExpression(val), Ast.NumberExpression(d1)),
					Ast.NumberExpression(d2)
				),
				Ast.NumberExpression(d1)
			),
			Ast.NumberExpression(d2)
		);
	elseif variant == 3 then
		local mul = math.random(2, 5);
		local d = math.random(7, 31);
		return Ast.DivExpression(
			Ast.SubExpression(
				Ast.MulExpression(
					Ast.AddExpression(Ast.NumberExpression(val), Ast.NumberExpression(d)),
					Ast.NumberExpression(mul)
				),
				Ast.NumberExpression(d * mul)
			),
			Ast.NumberExpression(mul)
		);
	else
		local d1 = math.random(15, 67);
		local d2 = math.random(12, 58);
		return Ast.SubExpression(
			Ast.AddExpression(
				Ast.SubExpression(Ast.NumberExpression(val), Ast.NumberExpression(d1)),
				Ast.NumberExpression(d1 + d2)
			),
			Ast.NumberExpression(d2)
		);
	end
end

local function obscureNumStr(num)
	local mul = math.random(3, 7);
	local offset = math.random(11, 47);
	local base = num + offset;
	return string.format("((%d * %d - %d) / %d)", base, mul, offset * mul, mul);
end

function ConstantArray:init(_) end

function ConstantArray:createPackedStream()
	local parts = {};
	for _, v in ipairs(self.constants) do
		if type(v) == "string" then
			v = self:encode(v);
			local len = #v;
			local b1 = math.floor(len / 256);
			local b2 = len % 256;
			parts[#parts + 1] = string.char(1, b1, b2) .. v;
		elseif type(v) == "number" then
			local str = tostring(v);
			parts[#parts + 1] = string.char(2, #str) .. str;
		elseif v == true then
			parts[#parts + 1] = string.char(3);
		elseif v == false then
			parts[#parts + 1] = string.char(4);
		end
	end
	local raw = table.concat(parts);
	local rlen = #raw;

	local seed = math.random(17, 239);
	local step = math.random(3, 23) * 2 + 1;
	local quad = math.random(1, 11) * 2 + 1;

	local enc = {};
	for p = 1, rlen do
		local b = string.byte(raw, p);
		local k = (b + seed + p * step + p * (p + 1) * quad) % 256;
		enc[p] = string.char(k);
	end
	return table.concat(enc), seed, step, quad;
end

local unpackCode = [=[
local ARR = (function(_raw, _seed, _step, _quad)
	local _t, _len = {}, #_raw;
	local _sb, _sc = string.byte, string.char;
	local _tc = table.concat or function(p) local r = "" for i = 1, #p do r = r .. p[i] end return r end;
	local _p, _idx = 1, 1;
	while _p <= _len do
		local _tag = (_sb(_raw, _p) - _seed - _p * _step - _p * (_p + 1) * _quad) % 256;
		_p = _p + 1;
		if _tag == 1 then
			local _b1 = (_sb(_raw, _p) - _seed - _p * _step - _p * (_p + 1) * _quad) % 256;
			_p = _p + 1;
			local _b2 = (_sb(_raw, _p) - _seed - _p * _step - _p * (_p + 1) * _quad) % 256;
			_p = _p + 1;
			local _elen = _b1 * 256 + _b2;
			local _chars = {};
			for _j = 1, _elen do
				_chars[_j] = _sc((_sb(_raw, _p) - _seed - _p * _step - _p * (_p + 1) * _quad) % 256);
				_p = _p + 1;
			end
			_t[_idx] = _tc(_chars);
			_idx = _idx + 1;
		elseif _tag == 2 then
			local _nlen = (_sb(_raw, _p) - _seed - _p * _step - _p * (_p + 1) * _quad) % 256;
			_p = _p + 1;
			local _nchars = {};
			for _j = 1, _nlen do
				_nchars[_j] = _sc((_sb(_raw, _p) - _seed - _p * _step - _p * (_p + 1) * _quad) % 256);
				_p = _p + 1;
			end
			_t[_idx] = tonumber(_tc(_nchars));
			_idx = _idx + 1;
		elseif _tag == 3 then
			_t[_idx] = true;
			_idx = _idx + 1;
		elseif _tag == 4 then
			_t[_idx] = false;
			_idx = _idx + 1;
		end
	end
	return _t;
end)(RAW_EXPR, SEED_EXPR, STEP_EXPR, QUAD_EXPR);
]=];

function ConstantArray:addArrayDeclaration(ast)
	local encBlob, seed, step, quad = self:createPackedStream();
	local parser = Parser:new({
		LuaVersion = LuaVersion.Lua51;
	});

	local rawEscaped = "\"" .. util.escape(encBlob) .. "\"";
	local seedExpr = obscureNumStr(seed);
	local stepExpr = obscureNumStr(step);
	local quadExpr = obscureNumStr(quad);

	local code = string.gsub(string.gsub(string.gsub(string.gsub(unpackCode, "RAW_EXPR", function() return rawEscaped end), "SEED_EXPR", seedExpr), "STEP_EXPR", stepExpr), "QUAD_EXPR", quadExpr);
	local newAst = parser:parse(code);
	newAst.body.scope:setParent(self.rootScope);
	local stat = newAst.body.statements[1];
	stat.scope = self.rootScope;
	stat.ids = { self.arrId };
	if stat.expressions and stat.expressions[1] and stat.expressions[1].base and stat.expressions[1].base.scope then
		stat.expressions[1].base.scope:setParent(self.rootScope);
	end

	visitast(newAst, nil, function(node, data)
		if node.kind == AstKind.VariableExpression and node.scope:getVariableName(node.id) == "ARR" then
			data.scope:removeReferenceToHigherScope(node.scope, node.id);
			data.scope:addReferenceToHigherScope(self.rootScope, self.arrId);
			node.scope = self.rootScope;
			node.id = self.arrId;
		end
	end);

	table.insert(ast.body.statements, 1, stat);
end

function ConstantArray:indexing(index, data)
	if self.LocalWrapperCount > 0 and data.functionData.local_wrappers then
		local wrappers = data.functionData.local_wrappers;
		local wrapper = wrappers[math.random(#wrappers)];

		local args = {};
		local ofs = index - self.wrapperOffset - wrapper.offset;
		for i = 1, self.LocalWrapperArgCount, 1 do
			if i == wrapper.arg then
				args[i] = createObfuscatedNumberNode(ofs);
			elseif i == wrapper.canaryArg then
				args[i] = createObfuscatedNumberNode(self.canaryToken);
			else
				local dummy = math.random(ofs - 1024, ofs + 1024);
				args[i] = createObfuscatedNumberNode(dummy);
			end
		end

		data.scope:addReferenceToHigherScope(wrappers.scope, wrappers.id);
		return Ast.FunctionCallExpression(Ast.IndexExpression(
			Ast.VariableExpression(wrappers.scope, wrappers.id),
			Ast.StringExpression(wrapper.index)
		), args);
	else
		local targetVal = index - self.wrapperOffset;
		local expr = createObfuscatedNumberNode(targetVal);
		local canaryExpr = createObfuscatedNumberNode(self.canaryToken);
		data.scope:addReferenceToHigherScope(self.rootScope, self.wrapperId);
		return Ast.FunctionCallExpression(Ast.VariableExpression(self.rootScope, self.wrapperId), {
			expr,
			canaryExpr,
		});
	end
end

function ConstantArray:getConstant(value, data)
	if(self.lookup[value]) then
		return self:indexing(self.lookup[value], data)
	end
	local idx = #self.constants + 1;
	self.constants[idx] = value;
	self.lookup[value] = idx;
	return self:indexing(idx, data);
end

function ConstantArray:addConstant(value)
	if(self.lookup[value]) then
		return
	end
	local idx = #self.constants + 1;
	self.constants[idx] = value;
	self.lookup[value] = idx;
end

local function reverse(t, i, j)
	while i < j do
	  t[i], t[j] = t[j], t[i]
	  i, j = i+1, j-1
	end
end

local function rotate(t, d, n)
	n = n or #t
	d = (d or 1) % n
	reverse(t, 1, n)
	reverse(t, 1, d)
	reverse(t, d+1, n)
end

local rotateCode = [=[
	do
		local _arr = ARR;
		local _len = #_arr;
		local _k = MASK;
		local _shift = SHIFT_EXPR;
		local _p = {{1, _len}, {1, _shift}, {_shift + 1, _len}};
		for _i = 1, 3 do
			local _r = _p[_i];
			local _l, _u = _r[1], _r[2];
			while _l < _u do
				_arr[_l], _arr[_u] = _arr[_u], _arr[_l];
				_l = _l + 1;
				_u = _u - 1;
			end
		end
	end
]=];

function ConstantArray:addRotateCode(ast, shift)
	local parser = Parser:new({
		LuaVersion = LuaVersion.Lua51;
	});

	local mask = math.random(1000, 9999);
	local shiftExpr = string.format("(%d - %d)", shift + mask, mask);
	local code = string.gsub(string.gsub(rotateCode, "SHIFT_EXPR", shiftExpr), "MASK", tostring(mask));
	local newAst = parser:parse(code);
	local forStat = newAst.body.statements[1];
	forStat.body.scope:setParent(ast.body.scope);
	visitast(newAst, nil, function(node, data)
		if(node.kind == AstKind.VariableExpression) then
			if(node.scope:getVariableName(node.id) == "ARR") then
				data.scope:removeReferenceToHigherScope(node.scope, node.id);
				data.scope:addReferenceToHigherScope(self.rootScope, self.arrId);
				node.scope = self.rootScope;
				node.id = self.arrId;
			end
		end
	end)

	table.insert(ast.body.statements, 1, forStat);
end

function ConstantArray:addDecodeCode(ast)
	local charTableDef = 'local cm = {"' .. table.concat((function()
		local t = {}
		for i = 0, 255 do
			t[#t + 1] = string.format("\\%03d", i)
		end
		return t
	end)(), '","') .. '"};'

	if self.Encoding == "base64" then
		local base64DecodeCode = [=[
local DECODE = (function()
	local lookup = LOOKUP_TABLE;
	local len = string.len;
	local sub = string.sub;
	local floor = math.floor;
	CHAR_TABLE_DEF
	local concat = table.concat or function(t) local s = '' for k = 1, #t do s = s .. t[k] end return s end;
	local type = type;
	local sbyte = string.byte;
	local cseed = CIPHER_SEED;
	local cstep = CIPHER_STEP;
	local cquad = CIPHER_QUAD;

	local _arr = ARR;
	local _trap = function() local _s = 0x5f3759df; local _t = {}; _t[_t] = _t; local _f; _f = function(_x) _s = (_s * 1664525 + 1013904223) % 4294967296; return _t[_f]; end; return _f(_s)(_s); end;
	local _mt = {};
	local _d = {
		{95,95,109,101,116,97,116,97,98,108,101},
		{95,95,110,101,119,105,110,100,101,120},
		{95,95,112,97,105,114,115},
		{95,95,105,112,97,105,114,115},
		{95,95,105,116,101,114},
	};
	for _j = 1, 5 do
		local _k = _d[_j];
		local _s = "";
		for _m = 1, #_k do
			_s = _s .. cm[_k[_m] + 1];
		end
		_mt[_s] = (_j == 1) and false or _trap;
	end
	if setmetatable then
		setmetatable(_arr, _mt);
	end
	local _tb = table;
	if _tb then
		local _fz = string.char(102, 114, 101, 101, 122, 101);
		if _tb[_fz] then
			pcall(_tb[_fz], _arr);
			pcall(_tb[_fz], _mt);
		end
	end

	return function(data)
		if type(data) ~= "string" then return data end
		local length = len(data)
		local parts = {}
		local index = 1
		local value = 0
		local count = 0
		while index <= length do
			local char = sub(data, index, index)
			local code = lookup[char]
			if code then
				value = value + code * (64 ^ (3 - count))
				count = count + 1
				if count == 4 then
					count = 0
					local c1 = floor(value / 65536)
					local c2 = floor(value % 65536 / 256)
					local c3 = value % 256
					parts[#parts + 1] = cm[c1 + 1] .. cm[c2 + 1] .. cm[c3 + 1]
					value = 0
				end
			elseif char == "=" then
				parts[#parts + 1] = cm[floor(value / 65536) + 1];
				if index >= length or sub(data, index + 1, index + 1) ~= "=" then
					parts[#parts + 1] = cm[floor(value % 65536 / 256) + 1];
				end
				break
			end
			index = index + 1
		end
		local raw = concat(parts);
		local rlen = len(raw);
		local dec = {};
		local prev = cseed % 256;
		for j = 1, rlen do
			local b = sbyte(raw, j);
			local k = (cseed + j * cstep + j * (j + 1) * cquad) % 256;
			dec[j] = cm[((b - k - prev) % 256) + 1];
			prev = b;
		end
		return concat(dec);
	end
end)();
]=];

		local parser = Parser:new({
			LuaVersion = LuaVersion.Lua51;
		});

		local code = string.gsub(string.gsub(string.gsub(string.gsub(base64DecodeCode, "CHAR_TABLE_DEF", function() return charTableDef end), "CIPHER_SEED", obscureNumStr(self.cipherSeed)), "CIPHER_STEP", obscureNumStr(self.cipherStep)), "CIPHER_QUAD", obscureNumStr(self.cipherQuad));
		local newAst = parser:parse(code);
		newAst.body.scope:setParent(self.rootScope);
		local stat = newAst.body.statements[1];
		stat.scope = self.rootScope;
		stat.ids = { self.decodeId };
		if stat.expressions and stat.expressions[1] and stat.expressions[1].base and stat.expressions[1].base.scope then
			stat.expressions[1].base.scope:setParent(self.rootScope);
		end

		visitast(newAst, nil, function(node, data)
			if(node.kind == AstKind.VariableExpression) then
				if(node.scope:getVariableName(node.id) == "ARR") then
					data.scope:removeReferenceToHigherScope(node.scope, node.id);
					data.scope:addReferenceToHigherScope(self.rootScope, self.arrId);
					node.scope = self.rootScope;
					node.id = self.arrId;
				end

				if(node.scope:getVariableName(node.id) == "LOOKUP_TABLE") then
					data.scope:removeReferenceToHigherScope(node.scope, node.id);
					return self:createBase64Lookup();
				end
			end
		end)

		table.insert(ast.body.statements, 1, stat);
	elseif self.Encoding == "base85" then
		local base85DecodeCode = [=[
local DECODE = (function()
	local lookup = LOOKUP_TABLE;
	local len = string.len;
	local sub = string.sub;
	local floor = math.floor;
	CHAR_TABLE_DEF
	local concat = table.concat or function(t) local s = '' for k = 1, #t do s = s .. t[k] end return s end;
	local type = type;
	local sbyte = string.byte;
	local cseed = CIPHER_SEED;
	local cstep = CIPHER_STEP;
	local cquad = CIPHER_QUAD;

	local _arr = ARR;
	local _trap = function() local _s = 0x5f3759df; local _t = {}; _t[_t] = _t; local _f; _f = function(_x) _s = (_s * 1664525 + 1013904223) % 4294967296; return _t[_f]; end; return _f(_s)(_s); end;
	local _mt = {};
	local _d = {
		{95,95,109,101,116,97,116,97,98,108,101},
		{95,95,110,101,119,105,110,100,101,120},
		{95,95,112,97,105,114,115},
		{95,95,105,112,97,105,114,115},
		{95,95,105,116,101,114},
	};
	for _j = 1, 5 do
		local _k = _d[_j];
		local _s = "";
		for _m = 1, #_k do
			_s = _s .. cm[_k[_m] + 1];
		end
		_mt[_s] = (_j == 1) and false or _trap;
	end
	if setmetatable then
		setmetatable(_arr, _mt);
	end
	local _tb = table;
	if _tb then
		local _fz = string.char(102, 114, 101, 101, 122, 101);
		if _tb[_fz] then
			pcall(_tb[_fz], _arr);
			pcall(_tb[_fz], _mt);
		end
	end

	return function(data)
		if type(data) ~= "string" then return data end
		local length = len(data)
		local parts = {}
		local index = 1
		while index <= length do
			local remain = length - index + 1
			local count = remain >= 5 and 5 or remain
			local value = 0
			local valid = count > 1

			for j = 0, 4 do
				local code
				if j < count then
					local ch = sub(data, index + j, index + j)
					code = lookup[ch]
					if not code then
						valid = false
						break
					end
				else
					code = 84
				end
				value = value * 85 + code
			end

			if valid then
				local b1 = floor(value / 16777216) % 256
				local b2 = floor(value / 65536) % 256
				local b3 = floor(value / 256) % 256
				local b4 = value % 256
				if count == 5 then
					parts[#parts + 1] = cm[b1 + 1] .. cm[b2 + 1] .. cm[b3 + 1] .. cm[b4 + 1]
				elseif count == 4 then
					parts[#parts + 1] = cm[b1 + 1] .. cm[b2 + 1] .. cm[b3 + 1]
				elseif count == 3 then
					parts[#parts + 1] = cm[b1 + 1] .. cm[b2 + 1]
				elseif count == 2 then
					parts[#parts + 1] = cm[b1 + 1]
				end
			end

			index = index + count
		end
		local raw = concat(parts);
		local rlen = len(raw);
		local dec = {};
		local prev = cseed % 256;
		for j = 1, rlen do
			local b = sbyte(raw, j);
			local k = (cseed + j * cstep + j * (j + 1) * cquad) % 256;
			dec[j] = cm[((b - k - prev) % 256) + 1];
			prev = b;
		end
		return concat(dec);
	end
end)();
]=];

		local parser = Parser:new({
			LuaVersion = LuaVersion.Lua51;
		});

		local code = string.gsub(string.gsub(string.gsub(string.gsub(base85DecodeCode, "CHAR_TABLE_DEF", function() return charTableDef end), "CIPHER_SEED", obscureNumStr(self.cipherSeed)), "CIPHER_STEP", obscureNumStr(self.cipherStep)), "CIPHER_QUAD", obscureNumStr(self.cipherQuad));
		local newAst = parser:parse(code);
		newAst.body.scope:setParent(self.rootScope);
		local stat = newAst.body.statements[1];
		stat.scope = self.rootScope;
		stat.ids = { self.decodeId };
		if stat.expressions and stat.expressions[1] and stat.expressions[1].base and stat.expressions[1].base.scope then
			stat.expressions[1].base.scope:setParent(self.rootScope);
		end

		visitast(newAst, nil, function(node, data)
			if(node.kind == AstKind.VariableExpression) then
				if(node.scope:getVariableName(node.id) == "ARR") then
					data.scope:removeReferenceToHigherScope(node.scope, node.id);
					data.scope:addReferenceToHigherScope(self.rootScope, self.arrId);
					node.scope = self.rootScope;
					node.id = self.arrId;
				end

				if(node.scope:getVariableName(node.id) == "LOOKUP_TABLE") then
					data.scope:removeReferenceToHigherScope(node.scope, node.id);
					return self:createBase85Lookup();
				end
			end
		end)

		table.insert(ast.body.statements, 1, stat);
	elseif self.Encoding == "mixed" then
		local p0_esc = string.format("\\%03d", string.byte(prefix_0));
		local p1_esc = string.format("\\%03d", string.byte(prefix_1));

		local mixedDecodeCode = [=[
local DECODE = (function()
	local lookup64 = LOOKUP_TABLE_64;
	local lookup85 = LOOKUP_TABLE_85;
	local len = string.len;
	local sub = string.sub;
	local floor = math.floor;
	CHAR_TABLE_DEF
	local concat = table.concat or function(t) local s = '' for k = 1, #t do s = s .. t[k] end return s end;
	local type = type;
	local sbyte = string.byte;
	local p0 = P0_ESC;
	local p1 = P1_ESC;
	local cseed = CIPHER_SEED;
	local cstep = CIPHER_STEP;
	local cquad = CIPHER_QUAD;

	local _arr = ARR;
	local _trap = function() local _s = 0x5f3759df; local _t = {}; _t[_t] = _t; local _f; _f = function(_x) _s = (_s * 1664525 + 1013904223) % 4294967296; return _t[_f]; end; return _f(_s)(_s); end;
	local _mt = {};
	local _d = {
		{95,95,109,101,116,97,116,97,98,108,101},
		{95,95,110,101,119,105,110,100,101,120},
		{95,95,112,97,105,114,115},
		{95,95,105,112,97,105,114,115},
		{95,95,105,116,101,114},
	};
	for _j = 1, 5 do
		local _k = _d[_j];
		local _s = "";
		for _m = 1, #_k do
			_s = _s .. cm[_k[_m] + 1];
		end
		_mt[_s] = (_j == 1) and false or _trap;
	end
	if setmetatable then
		setmetatable(_arr, _mt);
	end
	local _tb = table;
	if _tb then
		local _fz = string.char(102, 114, 101, 101, 122, 101);
		if _tb[_fz] then
			pcall(_tb[_fz], _arr);
			pcall(_tb[_fz], _mt);
		end
	end

	return function(data)
		if type(data) ~= "string" then return data end
		local first = sub(data, 1, 1)
		if first == p0 then
			data = sub(data, 2)
			local length = len(data)
			local parts = {}
			local index = 1
			local value = 0
			local count = 0
			while index <= length do
				local char = sub(data, index, index)
				local code = lookup64[char]
				if code then
					value = value + code * (64 ^ (3 - count))
					count = count + 1
					if count == 4 then
						count = 0
						local c1 = floor(value / 65536)
						local c2 = floor(value % 65536 / 256)
						local c3 = value % 256
						parts[#parts + 1] = cm[c1 + 1] .. cm[c2 + 1] .. cm[c3 + 1]
						value = 0
					end
				elseif char == "=" then
					parts[#parts + 1] = cm[floor(value / 65536) + 1];
					if index >= length or sub(data, index + 1, index + 1) ~= "=" then
						parts[#parts + 1] = cm[floor(value % 65536 / 256) + 1];
					end
					break
				end
				index = index + 1
			end
			local raw = concat(parts);
			local rlen = len(raw);
			local dec = {};
			local prev = cseed % 256;
			for j = 1, rlen do
				local b = sbyte(raw, j);
				local k = (cseed + j * cstep + j * (j + 1) * cquad) % 256;
				dec[j] = cm[((b - k - prev) % 256) + 1];
				prev = b;
			end
			return concat(dec);
		elseif first == p1 then
			data = sub(data, 2)
			local length = len(data)
			local parts = {}
			local idx = 1
			while idx <= length do
				local remain = length - idx + 1
				local count = remain >= 5 and 5 or remain
				local value = 0
				local valid = count > 1

				for j = 0, 4 do
					local code
					if j < count then
						local ch = sub(data, idx + j, idx + j)
						code = lookup85[ch]
						if not code then
							valid = false
							break
						end
					else
						code = 84
					end
					value = value * 85 + code
				end

				if valid then
					local b1 = floor(value / 16777216) % 256
					local b2 = floor(value / 65536) % 256
					local b3 = floor(value / 256) % 256
					local b4 = value % 256
					if count == 5 then
						parts[#parts + 1] = cm[b1 + 1] .. cm[b2 + 1] .. cm[b3 + 1] .. cm[b4 + 1]
					elseif count == 4 then
						parts[#parts + 1] = cm[b1 + 1] .. cm[b2 + 1] .. cm[b3 + 1]
					elseif count == 3 then
						parts[#parts + 1] = cm[b1 + 1] .. cm[b2 + 1]
					elseif count == 2 then
						parts[#parts + 1] = cm[b1 + 1]
					end
				end

				idx = idx + count
			end
			local raw = concat(parts);
			local rlen = len(raw);
			local dec = {};
			local prev = cseed % 256;
			for j = 1, rlen do
				local b = sbyte(raw, j);
				local k = (cseed + j * cstep + j * (j + 1) * cquad) % 256;
				dec[j] = cm[((b - k - prev) % 256) + 1];
				prev = b;
			end
			return concat(dec);
		end
		return data;
	end
end)();
]=];

		local parser = Parser:new({
			LuaVersion = LuaVersion.Lua51;
		});

		local code = string.gsub(string.gsub(string.gsub(string.gsub(string.gsub(string.gsub(mixedDecodeCode, "CHAR_TABLE_DEF", function() return charTableDef end), "P0_ESC", "\"" .. p0_esc .. "\""), "P1_ESC", "\"" .. p1_esc .. "\""), "CIPHER_SEED", obscureNumStr(self.cipherSeed)), "CIPHER_STEP", obscureNumStr(self.cipherStep)), "CIPHER_QUAD", obscureNumStr(self.cipherQuad));
		local newAst = parser:parse(code);
		newAst.body.scope:setParent(self.rootScope);
		local stat = newAst.body.statements[1];
		stat.scope = self.rootScope;
		stat.ids = { self.decodeId };
		if stat.expressions and stat.expressions[1] and stat.expressions[1].base and stat.expressions[1].base.scope then
			stat.expressions[1].base.scope:setParent(self.rootScope);
		end

		visitast(newAst, nil, function(node, data)
			if(node.kind == AstKind.VariableExpression) then
				if(node.scope:getVariableName(node.id) == "ARR") then
					data.scope:removeReferenceToHigherScope(node.scope, node.id);
					data.scope:addReferenceToHigherScope(self.rootScope, self.arrId);
					node.scope = self.rootScope;
					node.id = self.arrId;
				end

				if(node.scope:getVariableName(node.id) == "LOOKUP_TABLE_64") then
					data.scope:removeReferenceToHigherScope(node.scope, node.id);
					return self:createBase64Lookup();
				end

				if(node.scope:getVariableName(node.id) == "LOOKUP_TABLE_85") then
					data.scope:removeReferenceToHigherScope(node.scope, node.id);
					return self:createBase85Lookup();
				end
			end
		end)

		table.insert(ast.body.statements, 1, stat);
	elseif self.Encoding == "none" then
		local noneDecodeCode = [=[
local DECODE = (function()
	local _arr = ARR;
	local _trap = function() local _s = 0x5f3759df; local _t = {}; _t[_t] = _t; local _f; _f = function(_x) _s = (_s * 1664525 + 1013904223) % 4294967296; return _t[_f]; end; return _f(_s)(_s); end;
	local _mt = {
		__metatable = false,
		__newindex = _trap,
		__pairs = _trap,
		__ipairs = _trap,
		__iter = _trap,
	};
	if setmetatable then setmetatable(_arr, _mt) end
	local _tb = table;
	if _tb then
		local _fz = string.char(102, 114, 101, 101, 122, 101);
		if _tb[_fz] then
			pcall(_tb[_fz], _arr);
			pcall(_tb[_fz], _mt);
		end
	end
	return function(data) return data end;
end)();
]=];
		local parser = Parser:new({
			LuaVersion = LuaVersion.Lua51;
		});
		local newAst = parser:parse(noneDecodeCode);
		newAst.body.scope:setParent(self.rootScope);
		local stat = newAst.body.statements[1];
		stat.scope = self.rootScope;
		stat.ids = { self.decodeId };
		if stat.expressions and stat.expressions[1] and stat.expressions[1].base and stat.expressions[1].base.scope then
			stat.expressions[1].base.scope:setParent(self.rootScope);
		end
		visitast(newAst, nil, function(node, data)
			if(node.kind == AstKind.VariableExpression) then
				if(node.scope:getVariableName(node.id) == "ARR") then
					data.scope:removeReferenceToHigherScope(node.scope, node.id);
					data.scope:addReferenceToHigherScope(self.rootScope, self.arrId);
					node.scope = self.rootScope;
					node.id = self.arrId;
				end
			end
		end);
		table.insert(ast.body.statements, 1, stat);
	end
end

local wrapperCode = [=[
local WRAPPER = (function()
	local _arr = ARR;
	local _dec = DECODE;
	local _token = CANARY_TOKEN;
	local _prev_idx = -999999;
	local _seq_count = 0;
	local _poisoned = false;

	local _decoy = function()
		return _dec(_arr[1]);
	end;

	return function(arg, canary)
		if type(arg) ~= "number" or not canary or canary ~= _token then
			return _decoy();
		end

		local target = TARGET_EXPR;
		if target == _prev_idx + 1 then
			_seq_count = _seq_count + 1;
			if _seq_count >= 4 then
				_poisoned = true;
			end
		else
			_seq_count = 0;
		end
		_prev_idx = target;

		if _poisoned then
			return _decoy();
		end

		if isfunctionhooked and isfunctionhooked(_dec) then
			return _decoy();
		end

		local raw = _arr[target];
		if raw == nil then
			return _decoy();
		end
		if type(raw) ~= "string" then
			return raw;
		end

		return _dec(raw);
	end;
end)();
]=];

function ConstantArray:addWrapperCode(ast)
	local parser = Parser:new({
		LuaVersion = LuaVersion.Lua51;
	});

	local targetExpr;
	if self.wrapperOffset < 0 then
		targetExpr = "(arg - " .. obscureNumStr(-self.wrapperOffset) .. ")";
	else
		targetExpr = "(arg + " .. obscureNumStr(self.wrapperOffset) .. ")";
	end
	local canaryTokenExpr = obscureNumStr(self.canaryToken);

	local code = string.gsub(string.gsub(wrapperCode, "TARGET_EXPR", targetExpr), "CANARY_TOKEN", canaryTokenExpr);
	local newAst = parser:parse(code);
	newAst.body.scope:setParent(self.rootScope);
	local stat = newAst.body.statements[1];
	stat.scope = self.rootScope;
	stat.ids = { self.wrapperId };
	if stat.expressions and stat.expressions[1] and stat.expressions[1].base and stat.expressions[1].base.scope then
		stat.expressions[1].base.scope:setParent(self.rootScope);
	end

	visitast(newAst, nil, function(node, data)
		if node.kind == AstKind.VariableExpression then
			if node.scope:getVariableName(node.id) == "ARR" then
				data.scope:removeReferenceToHigherScope(node.scope, node.id);
				data.scope:addReferenceToHigherScope(self.rootScope, self.arrId);
				node.scope = self.rootScope;
				node.id = self.arrId;
			elseif node.scope:getVariableName(node.id) == "DECODE" then
				data.scope:removeReferenceToHigherScope(node.scope, node.id);
				data.scope:addReferenceToHigherScope(self.rootScope, self.decodeId);
				node.scope = self.rootScope;
				node.id = self.decodeId;
			end
		end
	end);

	table.insert(ast.body.statements, 1, stat);
end

function ConstantArray:createBase64Lookup()
	local entries = {};
	local i = 0;
	for char in string.gmatch(self.base64chars, ".") do
		table.insert(entries, Ast.KeyedTableEntry(Ast.StringExpression(char), Ast.NumberExpression(i)));
		i = i + 1;
	end
	util.shuffle(entries);
	return Ast.TableConstructorExpression(entries);
end

function ConstantArray:createBase85Lookup()
	local entries = {};
	local i = 0;
	for char in string.gmatch(self.base85chars, ".") do
		table.insert(entries, Ast.KeyedTableEntry(Ast.StringExpression(char), Ast.NumberExpression(i)));
		i = i + 1;
	end
	util.shuffle(entries);
	return Ast.TableConstructorExpression(entries);
end

function ConstantArray:cipherEncrypt(str)
	local res = {};
	local slen = #str;
	local prev = self.cipherSeed % 256;
	for j = 1, slen do
		local b = string.byte(str, j);
		local k = (self.cipherSeed + j * self.cipherStep + j * (j + 1) * self.cipherQuad) % 256;
		local enc = (b + k + prev) % 256;
		res[j] = string.char(enc);
		prev = enc;
	end
	return table.concat(res);
end

function ConstantArray:encode(str)
	if self.Encoding == "none" then
		return str;
	end
	str = self:cipherEncrypt(str);
	if self.Encoding == "base64" then
		return ((str:gsub('.', function(x)
			local r,b='',x:byte()
			for i=8,1,-1 do r=r..(b%2^i-b%2^(i-1)>0 and '1' or '0') end
			return r;
		end)..'0000'):gsub('%d%d%d?%d?%d?%d?', function(x)
			if (#x < 6) then return '' end
			local c=0
			for i=1,6 do c=c+(x:sub(i,i)=='1' and 2^(6-i) or 0) end
			return self.base64chars:sub(c+1,c+1)
		end)..({ '', '==', '=' })[#str%3+1]);
	elseif self.Encoding == "base85" then
		local result = {};
		local len = #str;
		local pos = 1;

		while pos <= len do
			local rem = len - pos + 1;
			local count = rem >= 4 and 4 or rem;
			local b1, b2, b3, b4 = string.byte(str, pos, pos + count - 1);
			b1, b2, b3, b4 = b1 or 0, b2 or 0, b3 or 0, b4 or 0;

			local value = ((b1 * 256 + b2) * 256 + b3) * 256 + b4;
			local chars = {};
			for i = 5, 1, -1 do
				local code = (value % 85) + 1;
				chars[i] = self.base85chars:sub(code, code);
				value = math.floor(value / 85);
			end

			result[#result + 1] = table.concat(chars, "", 1, count + 1);
			pos = pos + count;
		end

		return table.concat(result);
	elseif self.Encoding == "mixed" then
		if math.random() < 0.5 then
			local encoded = ((str:gsub('.', function(x)
				local r,b='',x:byte()
				for i=8,1,-1 do r=r..(b%2^i-b%2^(i-1)>0 and '1' or '0') end
				return r;
			end)..'0000'):gsub('%d%d%d?%d?%d?%d?', function(x)
				if (#x < 6) then return '' end
				local c=0
				for i=1,6 do c=c+(x:sub(i,i)=='1' and 2^(6-i) or 0) end
				return self.base64chars:sub(c+1,c+1)
			end)..({ '', '==', '=' })[#str%3+1]);
			return prefix_0 .. encoded;
		else
			local result = {};
			local len = #str;
			local pos = 1;

			while pos <= len do
				local rem = len - pos + 1;
				local count = rem >= 4 and 4 or rem;
				local b1, b2, b3, b4 = string.byte(str, pos, pos + count - 1);
				b1 = b1 or 0;
				b2 = b2 or 0;
				b3 = b3 or 0;
				b4 = b4 or 0;

				local value = ((b1 * 256 + b2) * 256 + b3) * 256 + b4;
				local chars = {};
				for i = 5, 1, -1 do
					local code = (value % 85) + 1;
					chars[i] = self.base85chars:sub(code, code);
					value = math.floor(value / 85);
				end

				result[#result + 1] = table.concat(chars, "", 1, count + 1);
				pos = pos + count;
			end

			return prefix_1 .. table.concat(result);
		end
	else
		return str;
	end
end

function ConstantArray:apply(ast, pipeline)
	initPrefixes();
	self.cipherSeed = math.random(13, 241);
	self.cipherStep = math.random(5, 27) * 2 + 1;
	self.cipherQuad = math.random(1, 15) * 2 + 1;
	self.canaryToken = math.random(1000, 9999);
	self.LocalWrapperArgCount = math.max(self.LocalWrapperArgCount or 10, 2);
	self.rootScope = ast.body.scope;
	self.arrId = self.rootScope:addVariable();
	self.decodeId = self.rootScope:addVariable();

	self.base64chars = table.concat(util.shuffle{
		"A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z",
		"a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m", "n", "o", "p", "q", "r", "s", "t", "u", "v", "w", "x", "y", "z",
		"0", "1", "2", "3", "4", "5", "6", "7", "8", "9",
		"+", "/",
	});

	self.base85chars = table.concat(util.shuffle{
		"!", "\"", "#", "$", "%", "&", "'", "(", ")", "*", "+", ",", "-", ".", "/",
		"0", "1", "2", "3", "4", "5", "6", "7", "8", "9",
		":", ";", "<", "=", ">", "?", "@",
		"A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O",
		"P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z",
		"[", "\\", "]", "^", "_", "`",
		"a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m", "n", "o",
		"p", "q", "r", "s", "t", "u",
	});

	self.constants = {};
	self.lookup = {};

	-- Extract Constants
	visitast(ast, nil, function(node, data)
		-- Apply only to some nodes
		if math.random() <= self.Threshold then
			node.__apply_constant_array = true;
			if node.kind == AstKind.StringExpression then
				self:addConstant(node.value);
			elseif not self.StringsOnly then
				if node.isConstant then
					if node.value ~= nil then
						self:addConstant(node.value);
					end
				end
			end
		end
	end);

	-- Inject honeypot / decoy constants before shuffling and indexing
	local decoys = {
		"ReplicatedStorage",
		"Players",
		"LocalPlayer",
		"Character",
		"Humanoid",
		"HumanoidRootPart",
		"FindFirstChild",
		"WaitForChild",
		"GetChildren",
		"GetDescendants",
		"FireServer",
		"InvokeServer",
		"OnClientEvent",
		"TweenService",
		"UserInputService",
		"ContextActionService",
		"HttpService",
		"Heartbeat",
		"RenderStepped",
		"Stepped",
		"TeleportService",
		"CFrame",
		"Vector3",
		"Color3",
		"Instance",
		"Destroy",
		"Clone",
		"Parent",
		"Name",
		"getgenv",
		"getreg",
		"getgc",
		"hookfunction",
		"hookmetamethod",
		"newcclosure",
		"checkcaller",
		"rconsoleprint",
		"setclipboard",
		"getrawmetatable",
		"getnamecallmethod",
		"setnamecallmethod",
		"HttpGet",
		"HttpPost",
		"ReplicatedFirst",
		"SoundService",
		string.format("_0x%x", math.random(0x100000, 0xffffff)),
		string.format("v_%d_%d", math.random(10, 99), math.random(1000, 9999)),
		string.format("%c%c%c_%x", math.random(65, 90), math.random(97, 122), math.random(65, 90), math.random(100, 999)),
		string.format("idx_%x_st", math.random(0x1000, 0xffff)),
		string.format("r_%d_k", math.random(100, 999)),
	}
	for i = 1, math.random(2, 4) do
		local dummyVal = decoys[math.random(#decoys)] .. (math.random() > 0.5 and ("_" .. string.format("%x", math.random(0x10, 0xff))) or "")
		self:addConstant(dummyVal);
	end

	-- Shuffle Array
	if self.Shuffle then
		self.constants = util.shuffle(self.constants);
		self.lookup = {};
		for i, v in ipairs(self.constants) do
			self.lookup[v] = i;
		end
	end

	-- Set Wrapper Function Offset
	self.wrapperOffset = math.random(-self.MaxWrapperOffset, self.MaxWrapperOffset);
	self.wrapperId = self.rootScope:addVariable();

	visitast(ast, function(node, data)
		-- Add Local Wrapper Functions
		if self.LocalWrapperCount > 0 and node.kind == AstKind.Block and node.isFunctionBlock and math.random() <= self.LocalWrapperThreshold then
			local id = node.scope:addVariable()
			data.functionData.local_wrappers = {
				id = id;
				scope = node.scope,
			};
			local nameLookup = {};
			for i = 1, self.LocalWrapperCount, 1 do
				local name;
				repeat
					name = callNameGenerator(pipeline.namegenerator, math.random(1, self.LocalWrapperArgCount * 16));
				until not nameLookup[name];
				nameLookup[name] = true;

				local offset = math.random(-self.MaxWrapperOffset, self.MaxWrapperOffset);
				local argPos = math.random(1, self.LocalWrapperArgCount);
				local canaryPos = math.random(1, self.LocalWrapperArgCount);
				while canaryPos == argPos do
					canaryPos = math.random(1, self.LocalWrapperArgCount);
				end

				data.functionData.local_wrappers[i] = {
					arg = argPos,
					canaryArg = canaryPos,
					index = name,
					offset =  offset,
				};
				data.functionData.__used = false;
			end
		end
		if node.__apply_constant_array then
			data.functionData.__used = true;
		end
	end, function(node, data)
		-- Actually insert Statements to get the Constant Values
		if node.__apply_constant_array then
			if node.kind == AstKind.StringExpression then
				return self:getConstant(node.value, data);
			elseif not self.StringsOnly then
				if node.isConstant then
					return node.value ~= nil and self:getConstant(node.value, data);
				end
			end
			node.__apply_constant_array = nil;
		end

		-- Insert Local Wrapper Declarations
		if self.LocalWrapperCount > 0 and node.kind == AstKind.Block and node.isFunctionBlock and data.functionData.local_wrappers and data.functionData.__used then
			data.functionData.__used = nil;
			local elems = {};
			local wrappers = data.functionData.local_wrappers;
			for i = 1, self.LocalWrapperCount, 1 do
				local wrapper = wrappers[i];
				local argPos = wrapper.arg;
				local offset = wrapper.offset;
				local name = wrapper.index;

				local funcScope = Scope:new(node.scope);

				local arg = nil;
				local canary = nil;
				local args = {};

				for j = 1, self.LocalWrapperArgCount, 1 do
					args[j] = funcScope:addVariable();
					if j == argPos then
						arg = args[j];
					elseif j == wrapper.canaryArg then
						canary = args[j];
					end
				end

				local addSubArg;
				local delta = math.random(7, 73);

				-- Create add and Subtract code
				if offset < 0 then
					addSubArg = Ast.SubExpression(
						Ast.SubExpression(Ast.VariableExpression(funcScope, arg), Ast.NumberExpression(-offset + delta)),
						Ast.NumberExpression(-delta)
					);
				else
					addSubArg = Ast.AddExpression(
						Ast.AddExpression(Ast.VariableExpression(funcScope, arg), Ast.NumberExpression(offset - delta)),
						Ast.NumberExpression(delta)
					);
				end

				funcScope:addReferenceToHigherScope(self.rootScope, self.wrapperId);
				local callArg = Ast.FunctionCallExpression(Ast.VariableExpression(self.rootScope, self.wrapperId), {
					addSubArg,
					Ast.VariableExpression(funcScope, canary),
				});

				local fargs = {};
				for i, v in ipairs(args) do
					fargs[i] = Ast.VariableExpression(funcScope, v);
				end

				elems[i] = Ast.KeyedTableEntry(
					Ast.StringExpression(name),
					Ast.FunctionLiteralExpression(fargs, Ast.Block({
						Ast.ReturnStatement({
							callArg
						});
					}, funcScope))
				)
			end
			table.insert(node.statements, 1, Ast.LocalVariableDeclaration(node.scope, {
				wrappers.id
			}, {
				Ast.TableConstructorExpression(elems)
			}));
		end
	end);

	self:addWrapperCode(ast);
	self:addDecodeCode(ast);

	if self.Rotate and #self.constants > 1 then
		local shift = math.random(1, #self.constants - 1);

		rotate(self.constants, -shift);
		self:addRotateCode(ast, shift);
	end

	self:addArrayDeclaration(ast);

	self.rootScope = nil;
	self.arrId = nil;
	self.decodeId = nil;
	self.wrapperId = nil;

	self.constants = nil;
	self.lookup = nil;
end

return ConstantArray;
