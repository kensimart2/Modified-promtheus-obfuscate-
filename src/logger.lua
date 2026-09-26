-- This Script is Part of the Prometheus Obfuscator by levno-710
--
-- logger.lua
--
-- This Script provides a Logger for Prometheus.

local logger = {}
local hasConfig, config = pcall(require, "config");
if not hasConfig or type(config) ~= "table" then
	config = {
		Name = "Prometheus",
		NameUpper = "PROMETHEUS",
		Version = "2.1.0"
	}
end

local hasColors, colors = pcall(require, "colors");
if not hasColors or type(colors) ~= "function" then
	colors = function(str) return str end
end

logger.LogLevel = {
	Error = 0,
	Warn = 1,
	Log = 2,
	Info = 2,
	Debug = 3,
}

logger.logLevel = logger.LogLevel.Log;

logger.debugCallback = function(...)
	print(colors(config.NameUpper .. ": " ..  ..., "grey"));
end;
function logger:debug(...)
	if self.logLevel >= self.LogLevel.Debug then
		self.debugCallback(...);
	end
end

logger.logCallback = function(...)
	print(colors(config.NameUpper .. ": ", "magenta") .. ...);
end;
function logger:log(...)
	if self.logLevel >= self.LogLevel.Log then
		self.logCallback(...);
	end
end

function logger:info(...)
	if self.logLevel >= self.LogLevel.Log then
		self.logCallback(...);
	end
end

logger.warnCallback = function(...)
	print(colors(config.NameUpper .. ": " .. ..., "yellow"));
end;
function logger:warn(...)
	if self.logLevel >= self.LogLevel.Warn then
		self.warnCallback(...);
	end
end

logger.errorCallback = function(...)
	print(colors(config.NameUpper .. ": " .. ..., "red"))
	error(...);
end;
function logger:error(...)
	self.errorCallback(...);
	error(config.NameUpper .. ": logger.errorCallback did not throw an Error!");
end


return logger;