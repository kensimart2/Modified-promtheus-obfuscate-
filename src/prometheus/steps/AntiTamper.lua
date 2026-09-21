-- This Script is Part of the Prometheus Obfuscator by levno-710
--
-- AntiTamper.lua
--
-- This Script provides an Obfuscation Step, that breaks the script, when someone tries to tamper with it.

local Step = require("prometheus.step")
local RandomStrings = require("prometheus.randomStrings")
local Parser = require("prometheus.parser")
local Enums = require("prometheus.enums")
local logger = require("logger")

local AntiTamper = Step:extend()
AntiTamper.Description = "This Step Breaks your Script when it is modified. This is only effective when using the new VM."
AntiTamper.Name = "Anti Tamper"

AntiTamper.SettingsDescriptor = {
	UseDebug = {
		type = "boolean",
		default = true,
		description = "Use debug library. (Recommended, however scripts will not work without debug library.)",
	},
}

local function generateSanityCheck()
	local sanityCheckAnswers = {}
	local sanityPasses = math.random(1, 10)
	for i = 1, sanityPasses do
		sanityCheckAnswers[i] = (math.random(1, 2 ^ 24) % 2 == 1)
	end
	local primaryCheck = RandomStrings.randomString()
	local codeParts = {}
	local function addCode(fmt, ...)
		table.insert(codeParts, string.format(fmt, ...))
	end

	local function generateAssignment(idx)
		local index = math.min(idx, sanityPasses)
		addCode("            valid = %s;\n", tostring(sanityCheckAnswers[index]))
	end
	local function generateValidation(idx)
		local index = math.min(idx - 1, sanityPasses)
		addCode("            if valid == %s then\n", tostring(sanityCheckAnswers[index]))
		addCode("            else\n")
		addCode("                _trap();\n")
		addCode("            end\n")
	end

	addCode("do local _trap = function() local _k = 0x5f3759df; local _m = {}; _m[_m] = _m; local _f; _f = function(_x) _k = (_k * 1664525 + 1013904223) % 4294967296; return _m[_f](_f(_x + _k)); end; return _f(_k); end; local valid = '%s';", primaryCheck)
	addCode("for i = 0, %d do\n", sanityPasses)
	for i = 0, sanityPasses do
		if i == 0 then
			addCode("        if i == 0 then\n")
			addCode("            if valid ~= '%s' then\n", primaryCheck)
			addCode("                _trap();\n")
			addCode("            end\n")
			addCode("            valid = %s;\n", tostring(sanityCheckAnswers[1]))
		elseif i == 1 then
			addCode("        elseif i == 1 then\n")
			addCode("            if valid == %s then\n", tostring(sanityCheckAnswers[1]))
			addCode("            end\n")
		else
			addCode("        elseif i == %d then\n", i)

			--[[
                Basically, even iterations are used to assign a new sanity check value,
                and odd iterations are used to validate the previous sanity check value.
            ]]
			if i % 2 == 0 then
				generateAssignment(i)
			else
				generateValidation(i)
			end
		end
	end
	addCode("        end\n")
	addCode("    end\n")
	addCode("do valid = true end\n")
	return table.concat(codeParts)
end

function AntiTamper:init(settings) end

function AntiTamper:apply(ast, pipeline)
	if pipeline.PrettyPrint then
		logger:warn(string.format('"%s" cannot be used with PrettyPrint, ignoring "%s"', self.Name, self.Name))
		return ast
	end
	local code = generateSanityCheck()
	if self.UseDebug then
		local string = RandomStrings.randomString()
		code = code
			.. [[
			local sethook = debug and debug.sethook or function() end;
			local allowedLine = nil;
			local called = 0;
			if debug and debug.sethook then
				sethook(function(s, line)
					if not line then
						return
					end
					called = called + 1;
					if allowedLine then
						if allowedLine ~= line then
							sethook(error, "l", 5);
						end
					else
						allowedLine = line;
					end
				end, "l", 5);
				(function() end)();
				(function() end)();
				sethook();
				if called < 2 then
					valid = false;
				end
			end

            local funcs = {pcall, xpcall, type, print, io and io.write, table.concat, table.insert, string.byte, string.sub, setmetatable, rawget, rawset, debug and debug.getinfo, string.dump}
            for i = 1, #funcs do
                if funcs[i] then
                    if debug and debug.getinfo then
                        local info = debug.getinfo(funcs[i])
                        if info and info.what ~= "C" then
                            valid = false;
                        end
                    end

                    if debug and debug.getupvalue and debug.getupvalue(funcs[i], 1) then
                        valid = false;
                    end

                     if pcall(string.dump, funcs[i]) then
                        valid = false;
                    end
                end
            end

            local function getTraceback()
                local str = (function(arg)
                    return (debug and debug.traceback) and debug.traceback(arg) or tostring(arg);
                end)("]] .. string .. [[");
                return str;
            end

            local traceback = getTraceback();
            local nl = traceback:find("\n")
            valid = valid and traceback:sub(1, nl and (nl - 1) or #traceback) == "]] .. string .. [[";
            local iter = traceback:gmatch(":(%d*):");
            local v = iter();
            if v then
                local c = 1;
                for i in iter do
                    valid = valid and i == v;
                    c = c + 1;
                end
                valid = valid and c >= 2;
            end
        ]]
    end
    code = code .. [[
    local gmatch = string.gmatch;
    local err = function() local _k = 0x5f3759df; local _m = {}; _m[_m] = _m; local _f; _f = function(_x) _k = (_k * 1664525 + 1013904223) % 4294967296; return _m[_f](_f(_x + _k)); end; return _f(_k); end;

    do
        local _tp = typeof or type;
        local _f_pcall = pcall;
        local _f_type = type;
        local _f_setmt = setmetatable;
        local _f_sbyte = string.byte;
        local _f_tconcat = table.concat;
        local _f_rawget = rawget;
        local _f_rawset = rawset;

        local _k_Inst = "Instance";
        local _k_DM = "DataModel";
        local _k_MTL = "The metatable is locked";
        local _k_RS = "RunService";
        local _k_fn = "function";
        local _k_tbl = "table";
        local _k_C = "[C]";
        local _k_run = "running";
        local _k_lck = "locked";
        local _k_ign = "IgnoreExecutor";
        local _k_hsh = "Hash";
        local _k_idx = "__index";
        local _k_nidx = "__newindex";
        local _k_mt = "__metatable";

        if _tp(game) == _k_Inst then
            local _s1, _cn = _f_pcall(function() return game.ClassName end);
            if not _s1 or _cn ~= _k_DM then
                valid = false;
            end
            local _s_mt = getmetatable(game);
            if _s_mt ~= _k_MTL then
                valid = false;
            end
            local _s2 = _f_pcall(function() return game["\0\255_test_\0"] end);
            if _s2 then
                valid = false;
            end
            local _s3, _svc = _f_pcall(game.GetService, game, _k_RS);
            if not _s3 or _tp(_svc) ~= _k_Inst then
                valid = false;
            end
            local _s_ws_ok, _ws_svc = _f_pcall(game.GetService, game, "Workspace");
            if not _s_ws_ok or _tp(_ws_svc) ~= _k_Inst or _svc == _ws_svc then
                valid = false;
            end
            local _s4 = _f_pcall(function() return game:GetService("\0_inv_\0") end);
            if _s4 then
                valid = false;
            end
            if _tp(workspace) == _k_Inst then
                local _ws_mt = getmetatable(workspace);
                if _ws_mt ~= _k_MTL then
                    valid = false;
                end
            end
        end

        if _tp(getrenv) == _k_fn then
            local _ok_renv, _renv = _f_pcall(getrenv);
            if _ok_renv and _tp(_renv) == _k_tbl then
                if _renv.pcall and _renv.pcall ~= _f_pcall then
                    valid = false;
                end
                if _renv.type and _renv.type ~= _f_type then
                    valid = false;
                end
                if _renv.setmetatable and _renv.setmetatable ~= _f_setmt then
                    valid = false;
                end
                if _renv.getmetatable and _renv.getmetatable ~= getmetatable then
                    valid = false;
                end
                if _renv.rawget and _renv.rawget ~= _f_rawget then
                    valid = false;
                end
                if _renv.rawset and _renv.rawset ~= _f_rawset then
                    valid = false;
                end
            end
        end

        if _tp(isfunctionhooked) == _k_fn then
            if isfunctionhooked(_f_pcall) or isfunctionhooked(_f_type) or isfunctionhooked(_f_setmt) or isfunctionhooked(_f_sbyte) or isfunctionhooked(_f_tconcat) then
                valid = false;
            end
        end
        if _tp(ishooked) == _k_fn then
            if ishooked(_f_pcall) or ishooked(_f_type) or ishooked(_f_setmt) or ishooked(_f_sbyte) or ishooked(_f_tconcat) then
                valid = false;
            end
        end
        if _tp(islclosure) == _k_fn then
            if islclosure(_f_pcall) or islclosure(_f_type) or islclosure(_f_setmt) or islclosure(_f_sbyte) or islclosure(_f_schar) or islclosure(_f_tconcat) or islclosure(_f_rawget) or islclosure(_f_rawset) then
                valid = false;
            end
        end

        if debug and _tp(debug.info) == _k_fn then
            local _w = debug.info(_f_pcall, _s(115));
            if _w and _w ~= _k_C then
                valid = false;
            end
            local _w2 = debug.info(_f_type, _s(115));
            if _w2 and _w2 ~= _k_C then
                valid = false;
            end
            local _w3 = debug.info(_f_sbyte, _s(115));
            if _w3 and _w3 ~= _k_C then
                valid = false;
            end
            local _w4 = debug.info(_f_setmt, _s(115));
            if _w4 and _w4 ~= _k_C then
                valid = false;
            end
        elseif debug and _tp(debug.getinfo) == _k_fn then
            local _gi = debug.getinfo(_f_pcall);
            if _gi and _gi.what ~= _s(67) then
                valid = false;
            end
        end

        if debug and _tp(debug.getupvalues) == _k_fn then
            local _up = debug.getupvalues(_f_pcall);
            if _tp(_up) == _k_tbl and #_up > 0 then
                valid = false;
            end
            local _up2 = debug.getupvalues(_f_sbyte);
            if _tp(_up2) == _k_tbl and #_up2 > 0 then
                valid = false;
            end
        elseif debug and _tp(debug.getupvalue) == _k_fn then
            if debug.getupvalue(_f_pcall, 1) ~= nil or debug.getupvalue(_f_sbyte, 1) ~= nil then
                valid = false;
            end
        end

        if _f_pcall(string.dump, _f_pcall) or _f_pcall(string.dump, _f_type) then
            valid = false;
        end

        local _f_cowrap = coroutine.wrap;
        local _f_costatus = coroutine.status;
        local _f_corunning = coroutine.running;
        local _co_ok = _f_pcall(function()
            local _th = _f_corunning();
            if _th and _f_costatus(_th) ~= _k_run then
                valid = false;
            end
            local _sync = false;
            local _c = _f_cowrap(function()
                _sync = true;
                return 42;
            end);
            local _ret = _c();
            if not _sync or _ret ~= 42 then
                valid = false;
            end
        end);
        if not _co_ok then
            valid = false;
        end

        if _tp(filtergc) == _k_fn and _tp(getfunctionhash) == _k_fn then
            local function _p() end
            local _h = getfunctionhash(_p);
            local _r = filtergc(_k_fn, {
                [_k_ign] = false,
                [_k_hsh] = _h,
            }, true);
            if _tp(_r) ~= _k_fn or getfunctionhash(_r) ~= _h then
                valid = false;
            end
        end

        local _tb_mt = {};
        _tb_mt[_k_mt] = _k_lck;
        _tb_mt[_k_idx] = function() end;
        local _tb = _f_setmt({}, _tb_mt);
        local _ok, _ = _f_pcall(_f_setmt, _tb, {});
        if _ok or getmetatable(_tb) ~= _k_lck then
            valid = false;
        end
        if _tp(setrawmetatable) == _k_fn then
            local _ok2, _m = _f_pcall(setrawmetatable, _tb, {});
            if not _ok2 or _tp(_m) ~= _k_tbl or getmetatable(_tb) ~= _m then
                valid = false;
            end
        end

        local _k_hkfn = _s(104, 111, 111, 107, 102, 117, 110, 99, 116, 105, 111, 110);
        local _k_hkmt = _s(104, 111, 111, 107, 109, 101, 116, 97, 109, 101, 116, 104, 111, 100);
        local _k_nc = _s(95, 95, 110, 97, 109, 101, 99, 97, 108, 108);

        if _tp(hookfunction) == _k_fn or _tp(replaceclosure) == _k_fn then
            local _target_tbl = _f_setmt({}, {
                [_k_idx] = function(t, k) return k end,
                [_k_nc] = function(t, ...) return ... end,
            });
            local _res_idx = _target_tbl[_k_Inst];
            if _res_idx ~= _k_Inst then
                valid = false;
            end
        end

        local _test_str = "abc";
        local _str_mt = debug and _tp(debug.getmetatable) == _k_fn and debug.getmetatable(_test_str) or getmetatable(_test_str);
        if _tp(_str_mt) == _k_tbl and _str_mt[_k_idx] and _tp(_str_mt[_k_idx]) ~= _k_tbl then
            if _str_mt[_k_idx] ~= string then
                valid = false;
            end
        end

        if _f_sbyte("A") ~= 65 or _f_schar(65) ~= "A" or ("Lua"):sub(1, 2) ~= "Lu" or ("123"):len() ~= 3 or _f_tconcat({"a", "b"}) ~= "ab" then
            valid = false;
        end

        local _op_x = math.random(11, 9999);
        local _op_tautology1 = (_op_x * (_op_x + 1)) % 2;
        if _op_tautology1 ~= 0 then
            err();
        end
        local _op_tautology2 = (_op_x ^ 2 + _op_x) % 2;
        if _op_tautology2 ~= 0 then
            err();
        end
        local _op_qr = (_op_x * _op_x) % 4;
        if _op_qr > 1 then
            err();
        end
        local _op_six = (_op_x * (_op_x + 1) * (_op_x + 2)) % 6;
        if _op_six ~= 0 then
            err();
        end

        local _trap_fired = false;
        local _honey_mt = {};
        _honey_mt[_k_mt] = _k_lck;
        _honey_mt[_k_idx] = function()
            _trap_fired = true;
            err();
        end;
        _honey_mt[_k_nidx] = function()
            _trap_fired = true;
            err();
        end;
        local _honey = _f_setmt({}, _honey_mt);
        if _trap_fired then
            valid = false;
        end
    end

    local pcallIntact2 = false;
    local pcallIntact = pcall(function()
        pcallIntact2 = true;
    end) and pcallIntact2;

    local random = math.random;
    local tblconcat = table.concat;
    local unpkg = table and table.unpack or unpack;
    local n = random(3, 65);
    local acc1 = 0;
    local acc2 = 0;
    local pcallRet = {pcall(function() local a = ]] .. tostring(math.random(1, 2^24)) .. [[ - "]] .. RandomStrings.randomString() .. [[" ^ ]] .. tostring(math.random(1, 2^24)) .. [[ return "]] .. RandomStrings.randomString() .. [[" / a; end)};
    local origMsg = pcallRet[2];
    local line = tonumber(gmatch(tostring(origMsg), ':(%d*):')());
    for i = 1, n do
        local len = math.random(1, 100);
        local n2 = random(0, 255);
        local pos = random(1, len);
        local shouldErr = random(1, 2) == 1;
        local msg = origMsg:gsub(':(%d*):', ':' .. tostring(random(0, 10000)) .. ':');
        local arr = {pcall(function()
            if random(1, 2) == 1 or i == n then
                local line2 = tonumber(gmatch(tostring(({pcall(function() local a = ]] .. tostring(math.random(1, 2^24)) .. [[ - "]] .. RandomStrings.randomString() .. [[" ^ ]] .. tostring(math.random(1, 2^24)) .. [[ return "]] .. RandomStrings.randomString() .. [[" / a; end)})[2]), ':(%d*):')());
                valid = valid and line == line2;
            end
            if shouldErr then
                error(msg, 0);
            end
            local arr = {};
            for i = 1, len do
                arr[i] = random(0, 255);
            end
            arr[pos] = n2;
            return unpkg(arr);
        end)};
        if shouldErr then
            valid = valid and arr[1] == false and arr[2] == msg;
        else
            valid = valid and arr[1];
            acc1 = (acc1 + arr[pos + 1]) % 256;
            acc2 = (acc2 + n2) % 256;
        end
    end
    valid = valid and acc1 == acc2;

    if not valid then
        err();
    end
end

    local obj = setmetatable({}, {
        __tostring = err,
    });
    obj[math.random(1, 100)] = obj;
    (function() end)(obj);

    if not valid then
        err();
    end
    ]]

    local parsed = Parser:new({LuaVersion = Enums.LuaVersion.Lua51}):parse(code);
    local doStat = parsed.body.statements[1];
    doStat.body.scope:setParent(ast.body.scope);
    table.insert(ast.body.statements, 1, doStat);

    return ast;
end

return AntiTamper;
