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

function ConstantArray:init(_) end

function ConstantArray:createArray()
	local entries = {};
	for i, v in ipairs(self.constants) do
		if type(v) == "string" then
			v = self:encode(v);
		end
		entries[i] = Ast.TableEntry(Ast.ConstantNode(v));
	end
	return Ast.TableConstructorExpression(entries);
end

function ConstantArray:indexing(index, data)
	if self.LocalWrapperCount > 0 and data.functionData.local_wrappers then
		local wrappers = data.functionData.local_wrappers;
		local wrapper = wrappers[math.random(#wrappers)];

		local args = {};
		local ofs = index - self.wrapperOffset - wrapper.offset;
		for i = 1, self.LocalWrapperArgCount, 1 do
			if i == wrapper.arg then
				args[i] = Ast.NumberExpression(ofs);
			else
				args[i] = Ast.NumberExpression(math.random(ofs - 1024, ofs + 1024));
			end
		end

		data.scope:addReferenceToHigherScope(wrappers.scope, wrappers.id);
		return Ast.FunctionCallExpression(Ast.IndexExpression(
			Ast.VariableExpression(wrappers.scope, wrappers.id),
			Ast.StringExpression(wrapper.index)
		), args);
	else
		data.scope:addReferenceToHigherScope(self.rootScope, self.wrapperId);
		return Ast.FunctionCallExpression(Ast.VariableExpression(self.rootScope, self.wrapperId), {
			Ast.NumberExpression(index - self.wrapperOffset);
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
	if self.Encoding == "base64" then
		local charTableDef = 'local cm = {"' .. table.concat((function()
			local t = {}
			for i = 0, 255 do
				t[#t + 1] = string.format("\\%03d", i)
			end
			return t
		end)(), '","') .. '"};'

		local base64DecodeCode = [[
	do ]] .. table.concat(util.shuffle{
		"local lookup = LOOKUP_TABLE;",
		"local len = string.len;",
		"local sub = string.sub;",
		"local floor = math.floor;",
		charTableDef,
		"local concat = function(t) local s = '' for k = 1, #t do s = s .. t[k] end return s end;",
		"local type = type;",
		"local sbyte = string.byte;",
		"local arr = ARR;",
	}) .. [[
		for i = 1, #arr do
			local data = arr[i];
			if type(data) == "string" then
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
				for j = 1, rlen do
					local b = sbyte(raw, j);
					local k = (CIPHER_SEED + j * CIPHER_STEP + j * (j + 1) * CIPHER_QUAD) % 256;
					dec[j] = cm[((b - k) % 256) + 1];
				end
				arr[i] = concat(dec);
			end
		end
		local _s_mt = setmetatable;
		local _trap = function() (error or print)(string.char(84, 97, 109, 112, 101, 114, 32, 68, 101, 116, 101, 99, 116, 33), 0) end;
		local _arr_mt = {
			__metatable = "The table is locked.",
			__newindex = _trap,
			__pairs = _trap,
			__ipairs = _trap,
		};
		_s_mt(arr, _arr_mt);
		if table and table.freeze then
			pcall(table.freeze, arr);
			pcall(table.freeze, _arr_mt);
		end
	end
]];

		local parser = Parser:new({
			LuaVersion = LuaVersion.Lua51;
		});

		local code = string.gsub(string.gsub(string.gsub(base64DecodeCode, "CIPHER_SEED", tostring(self.cipherSeed)), "CIPHER_STEP", tostring(self.cipherStep)), "CIPHER_QUAD", tostring(self.cipherQuad));
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

				if(node.scope:getVariableName(node.id) == "LOOKUP_TABLE") then
					data.scope:removeReferenceToHigherScope(node.scope, node.id);
					return self:createBase64Lookup();
				end
			end
		end)

		table.insert(ast.body.statements, 1, forStat);
	elseif self.Encoding == "base85" then
		local charTableDef = 'local cm = {"' .. table.concat((function()
			local t = {}
			for i = 0, 255 do
				t[#t + 1] = string.format("\\%03d", i)
			end
			return t
		end)(), '","') .. '"};'

		local base85DecodeCode = [[
	do ]] .. table.concat(util.shuffle{
		"local lookup = LOOKUP_TABLE;",
		"local len = string.len;",
		"local sub = string.sub;",
		"local floor = math.floor;",
		charTableDef,
		"local concat = function(t) local s = '' for k = 1, #t do s = s .. t[k] end return s end;",
		"local type = type;",
		"local sbyte = string.byte;",
		"local arr = ARR;",
	}) .. [[
		for i = 1, #arr do
			local data = arr[i];
			if type(data) == "string" then
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
				for j = 1, rlen do
					local b = sbyte(raw, j);
					local k = (CIPHER_SEED + j * CIPHER_STEP + j * (j + 1) * CIPHER_QUAD) % 256;
					dec[j] = cm[((b - k) % 256) + 1];
				end
				arr[i] = concat(dec);
			end
		end
		local _s_mt = setmetatable;
		local _trap = function() (error or print)(string.char(84, 97, 109, 112, 101, 114, 32, 68, 101, 116, 101, 99, 116, 33), 0) end;
		local _arr_mt = {
			__metatable = "The table is locked.",
			__newindex = _trap,
			__pairs = _trap,
			__ipairs = _trap,
		};
		_s_mt(arr, _arr_mt);
		if table and table.freeze then
			pcall(table.freeze, arr);
			pcall(table.freeze, _arr_mt);
		end
	end
]];

		local parser = Parser:new({
			LuaVersion = LuaVersion.Lua51;
		});

		local code = string.gsub(string.gsub(string.gsub(base85DecodeCode, "CIPHER_SEED", tostring(self.cipherSeed)), "CIPHER_STEP", tostring(self.cipherStep)), "CIPHER_QUAD", tostring(self.cipherQuad));
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

				if(node.scope:getVariableName(node.id) == "LOOKUP_TABLE") then
					data.scope:removeReferenceToHigherScope(node.scope, node.id);
					return self:createBase85Lookup();
				end
			end
		end)

		table.insert(ast.body.statements, 1, forStat);
	elseif self.Encoding == "mixed" then
		local charTableDef = 'local cm = {"' .. table.concat((function()
			local t = {}
			for i = 0, 255 do
				t[#t + 1] = string.format("\\%03d", i)
			end
			return t
		end)(), '","') .. '"};'

		local p0_esc = string.format("\\%03d", string.byte(prefix_0));
		local p1_esc = string.format("\\%03d", string.byte(prefix_1));

		local mixedDecodeCode = [[
	do ]] .. table.concat(util.shuffle{
		"local lookup64 = LOOKUP_TABLE_64;",
		"local lookup85 = LOOKUP_TABLE_85;",
		"local len = string.len;",
		"local sub = string.sub;",
		"local floor = math.floor;",
		charTableDef,
		"local concat = function(t) local s = '' for k = 1, #t do s = s .. t[k] end return s end;",
		"local type = type;",
		"local sbyte = string.byte;",
		"local arr = ARR;",
	}) .. [[
		for i = 1, #arr do
			local data = arr[i];
			if type(data) == "string" then
				local first = sub(data, 1, 1)
				if first == "]]..p0_esc..[[" then
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
					for j = 1, rlen do
						local b = sbyte(raw, j);
						local k = (CIPHER_SEED + j * CIPHER_STEP + j * (j + 1) * CIPHER_QUAD) % 256;
						dec[j] = cm[((b - k) % 256) + 1];
					end
					arr[i] = concat(dec);
				elseif first == "]]..p1_esc..[[" then
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
					for j = 1, rlen do
						local b = sbyte(raw, j);
						local k = (CIPHER_SEED + j * CIPHER_STEP + j * (j + 1) * CIPHER_QUAD) % 256;
						dec[j] = cm[((b - k) % 256) + 1];
					end
					arr[i] = concat(dec);
				end
			end
		end
		local _s_mt = setmetatable;
		local _trap = function() (error or print)(string.char(84, 97, 109, 112, 101, 114, 32, 68, 101, 116, 101, 99, 116, 33), 0) end;
		local _arr_mt = {
			__metatable = "The table is locked.",
			__newindex = _trap,
			__pairs = _trap,
			__ipairs = _trap,
		};
		_s_mt(arr, _arr_mt);
		if table and table.freeze then
			pcall(table.freeze, arr);
			pcall(table.freeze, _arr_mt);
		end
	end
]];

		local parser = Parser:new({
			LuaVersion = LuaVersion.Lua51;
		});

		local code = string.gsub(string.gsub(string.gsub(mixedDecodeCode, "CIPHER_SEED", tostring(self.cipherSeed)), "CIPHER_STEP", tostring(self.cipherStep)), "CIPHER_QUAD", tostring(self.cipherQuad));
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

		table.insert(ast.body.statements, 1, forStat);
	end
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
	for j = 1, slen do
		local b = string.byte(str, j);
		local k = (self.cipherSeed + j * self.cipherStep + j * (j + 1) * self.cipherQuad) % 256;
		res[j] = string.char((b + k) % 256);
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
	self.rootScope = ast.body.scope;
	self.arrId = self.rootScope:addVariable();

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
		string.format("_0x%x", math.random(0x100000, 0xffffff)),
		string.format("v_%d_%d", math.random(10, 99), math.random(1000, 9999)),
		string.format("%c%c%c_%x", math.random(65, 90), math.random(97, 122), math.random(65, 90), math.random(100, 999)),
		string.format("idx_%x_st", math.random(0x1000, 0xffff)),
		string.format("r_%d_k", math.random(100, 999)),
	}
	for i = 1, math.random(14, 22) do
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

				data.functionData.local_wrappers[i] = {
					arg = argPos,
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
				local args = {};

				for i = 1, self.LocalWrapperArgCount, 1 do
					args[i] = funcScope:addVariable();
					if i == argPos then
						arg = args[i];
					end
				end

				local addSubArg;

				-- Create add and Subtract code
				if offset < 0 then
					addSubArg = Ast.SubExpression(Ast.VariableExpression(funcScope, arg), Ast.NumberExpression(-offset));
				else
					addSubArg = Ast.AddExpression(Ast.VariableExpression(funcScope, arg), Ast.NumberExpression(offset));
				end

				funcScope:addReferenceToHigherScope(self.rootScope, self.wrapperId);
				local callArg = Ast.FunctionCallExpression(Ast.VariableExpression(self.rootScope, self.wrapperId), {
					addSubArg
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

	self:addDecodeCode(ast);

	local steps = util.shuffle({
		-- Add Wrapper Function Code
		function()
			local funcScope = Scope:new(self.rootScope);
			-- Add Reference to Array
			funcScope:addReferenceToHigherScope(self.rootScope, self.arrId);

			local arg = funcScope:addVariable();
			local addSubArg;

			-- Create add and Subtract code
			if self.wrapperOffset < 0 then
				addSubArg = Ast.SubExpression(Ast.VariableExpression(funcScope, arg), Ast.NumberExpression(-self.wrapperOffset));
			else
				addSubArg = Ast.AddExpression(Ast.VariableExpression(funcScope, arg), Ast.NumberExpression(self.wrapperOffset));
			end

			local dummyArg = funcScope:addVariable();
			local canaryStat = Ast.IfStatement(
				Ast.AndExpression(
					Ast.VariableExpression(funcScope, dummyArg),
					Ast.EqualsExpression(Ast.VariableExpression(funcScope, dummyArg), Ast.NumberExpression(0))
				),
				Ast.Block({
					Ast.FunctionCallStatement(
						Ast.VariableExpression(funcScope:resolveGlobal("error")),
						{
							Ast.FunctionCallExpression(
								Ast.IndexExpression(
									Ast.VariableExpression(funcScope:resolveGlobal("string")),
									Ast.StringExpression("char")
								),
								{
									Ast.NumberExpression(84),
									Ast.NumberExpression(97),
									Ast.NumberExpression(109),
									Ast.NumberExpression(112),
									Ast.NumberExpression(101),
									Ast.NumberExpression(114),
									Ast.NumberExpression(32),
									Ast.NumberExpression(68),
									Ast.NumberExpression(101),
									Ast.NumberExpression(116),
									Ast.NumberExpression(101),
									Ast.NumberExpression(99),
									Ast.NumberExpression(116),
									Ast.NumberExpression(33),
								}
							),
							Ast.NumberExpression(0),
						}
					)
				}, funcScope),
				{},
				nil
			);

			-- Create and Add the Function Declaration
			table.insert(ast.body.statements, 1, Ast.LocalFunctionDeclaration(self.rootScope, self.wrapperId, {
				Ast.VariableExpression(funcScope, arg),
				Ast.VariableExpression(funcScope, dummyArg),
			}, Ast.Block({
				canaryStat,
				Ast.ReturnStatement({
					Ast.IndexExpression(
						Ast.VariableExpression(self.rootScope, self.arrId),
						addSubArg
					)
				});
			}, funcScope)));

			-- Resulting Code:
			-- function xy(a)
			-- 		return ARR[a - 10]
			-- end
		end,
		-- Rotate Array and Add unrotate code
		function()
			if self.Rotate and #self.constants > 1 then
				local shift = math.random(1, #self.constants - 1);

				rotate(self.constants, -shift);
				self:addRotateCode(ast, shift);
			end
		end,
	});

	for i, f in ipairs(steps) do
		f();
	end

	-- Add the Array Declaration
	table.insert(ast.body.statements, 1, Ast.LocalVariableDeclaration(self.rootScope, {self.arrId}, {self:createArray()}));

	self.rootScope = nil;
	self.arrId = nil;

	self.constants = nil;
	self.lookup = nil;
end

return ConstantArray;
