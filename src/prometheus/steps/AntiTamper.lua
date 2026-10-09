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
	local sanityPasses = math.random(2, 4)
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

	addCode("do local _trap = function() local _s = 0x5f3759df; local _t = {}; _t[_t] = _t; local _f; _f = function(_x) _s = (_s * 1664525 + 1013904223) %% 4294967296; return _t[_f]; end; return _f(_s)(_s); end; local valid = '%s';", primaryCheck)
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
    local err = function() local _s = 0x5f3759df; local _t = {}; _t[_t] = _t; local _f; _f = function(_x) _s = (_s * 1664525 + 1013904223) % 4294967296; return _t[_f]; end; return _f(_s)(_s); end;

    do
        local _tp = typeof or type;
        local _f_pcall = pcall;
        local _f_type = type;
        local _f_setmt = setmetatable;
        local _f_sbyte = string.byte;
        local _f_tconcat = table.concat;
        local _f_rawget = rawget;
        local _f_rawset = rawset;

        local _k_Inst = "\073\110\115\116\097\110\099\101";
        local _k_DM = "\068\097\116\097\077\111\100\101\108";
        local _k_MTL = "\084\104\101\032\109\101\116\097\116\097\098\108\101\032\105\115\032\108\111\099\107\101\100";
        local _k_RS = "\082\117\110\083\101\114\118\105\099\101";
        local _k_fn = "\102\117\110\099\116\105\111\110";
        local _k_tbl = "\116\097\098\108\101";
        local _k_run = "\114\117\110\110\105\110\103";
        local _k_lck = "\108\111\099\107\101\100";
        local _k_idx = "\095\095\105\110\100\101\120";
        local _k_nidx = "\095\095\110\101\119\105\110\100\101\120";
        local _k_mt = "\095\095\109\101\116\097\116\097\098\108\101";

        if _tp(game) == _k_Inst then
            local _s1, _cn = _f_pcall(function() return game.ClassName end);
            if not _s1 or _cn ~= _k_DM then
                valid = false;
            end
            local _s_mt = getmetatable(game);
            if _s_mt ~= _k_MTL then
                valid = false;
            end
            local _s3, _svc = _f_pcall(game.GetService, game, _k_RS);
            if not _s3 or _tp(_svc) ~= _k_Inst then
                valid = false;
            end
            local _s_ws_ok, _ws_svc = _f_pcall(game.GetService, game, "\087\111\114\107\115\112\097\099\101");
            if not _s_ws_ok or _tp(_ws_svc) ~= _k_Inst or _svc == _ws_svc then
                valid = false;
            end
            if _tp(workspace) == _k_Inst then
                local _ws_mt = getmetatable(workspace);
                if _ws_mt ~= _k_MTL then
                    valid = false;
                end
            end
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

        local _tb_mt = {};
        _tb_mt[_k_mt] = _k_lck;
        _tb_mt[_k_idx] = function() end;
        local _tb = _f_setmt({}, _tb_mt);
        local _ok, _ = _f_pcall(_f_setmt, _tb, {});
        if _ok or getmetatable(_tb) ~= _k_lck then
            valid = false;
        end

        local _test_str = "abc";
        local _str_mt = debug and _tp(debug.getmetatable) == _k_fn and debug.getmetatable(_test_str) or getmetatable(_test_str);
        if _tp(_str_mt) == _k_tbl and _str_mt[_k_idx] and _tp(_str_mt[_k_idx]) ~= _k_tbl then
            if _str_mt[_k_idx] ~= string then
                valid = false;
            end
        end

        if _f_sbyte("A") ~= 65 or ("Lua"):sub(1, 2) ~= "Lu" or ("123"):len() ~= 3 or _f_tconcat({"a", "b"}) ~= "ab" then
            valid = false;
        end

        local _op_x = math.random(11, 9999);
        local _op_y = math.random(7, 31) * 2 + 1;
        if (_op_x * (_op_x + 1)) % 2 ~= 0 or (_op_x * (_op_x + 1) * (_op_x + 2)) % 6 ~= 0 or (_op_y * _op_y) % 8 ~= 1 or ((_op_x * _op_x + _op_y * _op_y) % 4) == 3 or (_op_y ^ 4) % 16 ~= 1 then
            err();
        end

        if bit32 and bit32.bxor then
            if bit32.bxor(255, 255) ~= 0 or bit32.band(255, 15) ~= 15 or bit32.btest(1, 2) ~= false then
                valid = false;
            end
        end
        if table and table.freeze and table.isfrozen then
            local _fz = { 1, 2 };
            if _f_pcall(table.freeze, _fz) and table.isfrozen(_fz) then
                if _f_pcall(function() _fz[1] = 9; end) and _fz[1] == 9 then
                    valid = false;
                end
            end
        end
        if math.clamp and (math.clamp(15, 0, 10) ~= 10 or math.clamp(-5, 0, 10) ~= 0) then
            valid = false;
        end
        if math.sign and (math.sign(-100) ~= -1 or math.sign(50) ~= 1 or math.sign(0) ~= 0) then
            valid = false;
        end
        if math.round and (math.round(3.6) ~= 4 or math.round(3.2) ~= 3) then
            valid = false;
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
        _honey_mt["\095\095\105\116\101\114"] = function()
            _trap_fired = true;
            err();
        end;
        local _honey = _f_setmt({}, _honey_mt);
        if _trap_fired then
            valid = false;
        end

        local _seed_val = math.random(1000, 9999);
        local _hash_acc = 137;
        local _sample = "\080\045\082\045\079\045\077";
        for _j = 1, #_sample do
            _hash_acc = (_hash_acc * 31 + _f_sbyte(_sample, _j) + _seed_val) % 65536;
        end
        if _hash_acc < 0 or _hash_acc >= 65536 then
            valid = false;
        end

        local _chk_ptr = function(_o)
            local _s = tostring(_o);
            local _h = _s:match("0x([%da-fA-F]+)") or _s:match(": ([%da-fA-F]+)");
            if _h then
                if #_h <= 3 then return true; end
                local _v = tonumber(_h:sub(-8), 16);
                if _v and _v < 4096 then return true; end
            end
            return false;
        end;
        local _t1, _t2, _t3 = {}, {}, {};
        local _s1, _s2, _s3 = tostring(_t1), tostring(_t2), tostring(_t3);
        if _s1 == _s2 or _s2 == _s3 or _s1 == _s3 or _chk_ptr(_t1) or _chk_ptr(function() end) then
            valid = false;
        end

        local _g_env = _G or (getgenv and getgenv()) or (getfenv and getfenv(0)) or {};
        local _k_prn = "\112\114\105\110\116";
        local _k_wrn = "\119\097\114\110";
        local _k_lds = "\108\111\097\100\115\116\114\105\110\103";
        local _k_getgc = "\103\101\116\103\099";
        local _is_internal_runner = (_G and _G.__prometheusPushLog ~= nil) or (_g_env and _g_env.__prometheusPushLog ~= nil);

        local _chk_hook = function(fn, name)
            if not fn or _f_type(fn) ~= _k_fn then return false; end
            if _is_internal_runner and (name == _k_prn or name == _k_wrn) then return false; end
            if debug and debug.info then
                local _ok_s, _src = _f_pcall(debug.info, fn, "s");
                if _ok_s and _src and _src ~= "[C]" then return true; end
                local _ok_l, _ln = _f_pcall(debug.info, fn, "l");
                if _ok_l and _ln and _ln > 0 then return true; end
                local _ok_a, _numparams = _f_pcall(debug.info, fn, "a");
                if _ok_a and _numparams and _numparams < 0 then return true; end
            end
            if debug and debug.getinfo then
                local _ok_i, _inf = _f_pcall(debug.getinfo, fn, "S");
                if _ok_i and _inf and _inf.what and _inf.what ~= "C" then return true; end
            end
            if string and string.dump and _f_pcall(string.dump, fn) then return true; end
            if debug and debug.getupvalue then
                local _ok_u, _u1 = _f_pcall(debug.getupvalue, fn, 1);
                if _ok_u and _u1 ~= nil then return true; end
            end
            local _fn_is_hooked = isfunctionhooked or (_g_env and _g_env.isfunctionhooked);
            if _fn_is_hooked and _f_pcall(_fn_is_hooked, fn) and _fn_is_hooked(fn) then return true; end
            local _fn_ishooked = ishooked or (_g_env and _g_env.ishooked);
            if _fn_ishooked and _f_pcall(_fn_ishooked, fn) and _fn_ishooked(fn) then return true; end
            local _fn_islclosure = islclosure or (_g_env and _g_env.islclosure);
            if _fn_islclosure and _f_pcall(_fn_islclosure, fn) and _fn_islclosure(fn) then return true; end
            local _fn_iscclosure = iscclosure or (_g_env and _g_env.iscclosure);
            if _fn_iscclosure and _f_pcall(_fn_iscclosure, fn) and not _fn_iscclosure(fn) then return true; end
            local _fn_getupvalues = getupvalues or (_g_env and _g_env.getupvalues);
            if _fn_getupvalues and _f_pcall(_fn_getupvalues, fn) then
                local _ups = _fn_getupvalues(fn);
                if _f_type(_ups) == _k_tbl and #_ups > 0 then return true; end
            end
            return false;
        end;

        local _fn_getgc = getgc or (_g_env and _g_env[_k_getgc]);
        if _fn_getgc and _f_type(_fn_getgc) == _k_fn then
            local _ok_gc, _gc_arr = _f_pcall(_fn_getgc, true);
            if not _ok_gc or _f_type(_gc_arr) ~= _k_tbl then
                _ok_gc, _gc_arr = _f_pcall(_fn_getgc);
            end
            if _ok_gc and _f_type(_gc_arr) == _k_tbl and #_gc_arr < 800 then
                valid = false;
            end
        end

        if _g_env and (_g_env["\095\099\097\112\116\117\114\101\100\095\112\114\105\110\116\115"] or _g_env["\095\099\097\112\116\117\114\101\100\095\108\111\097\100\115\116\114\105\110\103\115"] or _g_env["\095\095\100\101\111\098\102\117\115\099\097\116\111\114"] or _g_env["\095\095\097\115\116\114\097\095\116\114\097\099\101"] or _g_env["\095\095\097\115\116\114\097\095\101\110\118"] or _g_env["\095\095\097\115\116\114\097\095\100\117\109\112"] or _g_env["\095\095\097\115\116\114\097\095\104\111\111\107"] or _g_env["\095\095\097\105\095\115\097\110\100\098\111\120"] or _g_env["\095\095\100\101\099\111\109\112\105\108\101\114\095\115\116\097\116\101"]) then
            valid = false;
        end
        if _g_env and getmetatable(_g_env) ~= nil then
            valid = false;
        end
        if getrawmetatable and _g_env and getrawmetatable(_g_env) ~= nil then
            valid = false;
        end

        local _core_builtins = {
            { _f_pcall, "pcall" },
            { _f_type, "type" },
            { _f_setmt, "setmetatable" },
            { _f_sbyte, "string.byte" },
            { _f_tconcat, "table.concat" },
            { _f_rawget, "rawget" },
            { _f_rawset, "rawset" },
        };
        for _b = 1, #_core_builtins do
            local _fn_entry = _core_builtins[_b];
            if _chk_hook(_fn_entry[1], _fn_entry[2]) then
                valid = false;
            end
        end

        if _g_env[_k_prn] and _chk_hook(_g_env[_k_prn], _k_prn) then valid = false; end
        if print and _chk_hook(print, _k_prn) then valid = false; end
        if _g_env[_k_lds] and _chk_hook(_g_env[_k_lds], _k_lds) then valid = false; end
        if loadstring and _chk_hook(loadstring, _k_lds) then valid = false; end
        if _g_env[_k_wrn] and _chk_hook(_g_env[_k_wrn], _k_wrn) then valid = false; end

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
end
    ]]

    local parsed = Parser:new({LuaVersion = Enums.LuaVersion.Lua51}):parse(code);
    local doStat = parsed.body.statements[1];
    doStat.body.scope:setParent(ast.body.scope);
    table.insert(ast.body.statements, 1, doStat);

    return ast;
end

return AntiTamper;
