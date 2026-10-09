-- This Script is Part of the Prometheus Obfuscator by levno-710
--
-- register.lua
--
-- This Script contains the register management for the compiler.

local Ast = require("prometheus.ast");
local constants = require("prometheus.compiler.constants");
local randomStrings = require("prometheus.randomStrings");

local AstKind = Ast.AstKind;
local MAX_REGS = constants.MAX_REGS;

return function(Compiler)
    function Compiler:obfuscateBlockId(id)
        if type(id) ~= "number" then
            return id;
        end
        local variant = math.random(1, 5);
        if variant == 1 then
            local k = math.random(1001, 89999);
            return Ast.SubExpression(
                Ast.AddExpression(Ast.NumberExpression(id + k), Ast.NumberExpression(k)),
                Ast.NumberExpression(k * 2)
            );
        elseif variant == 2 then
            local k = math.random(1001, 89999);
            return Ast.AddExpression(
                Ast.SubExpression(Ast.NumberExpression(id), Ast.NumberExpression(k)),
                Ast.NumberExpression(k)
            );
        elseif variant == 3 then
            local mul = math.random(2, 4);
            local k = math.random(101, 4999) * mul;
            return Ast.DivExpression(
                Ast.SubExpression(
                    Ast.AddExpression(
                        Ast.MulExpression(Ast.NumberExpression(id), Ast.NumberExpression(mul)),
                        Ast.NumberExpression(k)
                    ),
                    Ast.NumberExpression(k)
                ),
                Ast.NumberExpression(mul)
            );
        elseif variant == 4 then
            local d1 = math.random(500, 9999);
            local d2 = math.random(500, 9999);
            return Ast.SubExpression(
                Ast.SubExpression(
                    Ast.AddExpression(
                        Ast.AddExpression(Ast.NumberExpression(id), Ast.NumberExpression(d1)),
                        Ast.NumberExpression(d2)
                    ),
                    Ast.NumberExpression(d1)
                ),
                Ast.NumberExpression(d2)
            );
        else
            local k = math.random(1001, 89999);
            return Ast.SubExpression(
                Ast.AddExpression(Ast.NumberExpression(id), Ast.NumberExpression(k)),
                Ast.NumberExpression(k)
            );
        end
    end

    function Compiler:freeRegister(id, force)
        if force or not (self.registers[id] == self.VAR_REGISTER) then
            self.usedRegisters = self.usedRegisters - 1;
            self.registers[id] = false
        end
    end

    function Compiler:isVarRegister(id)
        return self.registers[id] == self.VAR_REGISTER;
    end

    function Compiler:allocRegister(isVar)
        self.usedRegisters = self.usedRegisters + 1;

        if not isVar then
            if not self.registers[self.POS_REGISTER] then
                self.registers[self.POS_REGISTER] = true;
                return self.POS_REGISTER;
            end

            if not self.registers[self.RETURN_REGISTER] then
                self.registers[self.RETURN_REGISTER] = true;
                return self.RETURN_REGISTER;
            end
        end

        local id = 0;
        if self.usedRegisters < MAX_REGS * constants.MAX_REGS_MUL then
            repeat
                id = math.random(1, MAX_REGS - 1);
            until not self.registers[id];
        else
            repeat
                id = id + 1;
            until not self.registers[id];
        end

        if id > self.maxUsedRegister then
            self.maxUsedRegister = id;
        end

        if(isVar) then
            self.registers[id] = self.VAR_REGISTER;
        else
            self.registers[id] = true
        end
        return id;
    end

    function Compiler:isUpvalue(scope, id)
        return self.upvalVars[scope] and self.upvalVars[scope][id];
    end

    function Compiler:makeUpvalue(scope, id)
        if(not self.upvalVars[scope]) then
            self.upvalVars[scope] = {}
        end
        self.upvalVars[scope][id] = true;
    end

    function Compiler:getVarRegister(scope, id, functionDepth, potentialId)
        if(not self.registersForVar[scope]) then
            self.registersForVar[scope] = {};
            self.scopeFunctionDepths[scope] = functionDepth;
        end

        local reg = self.registersForVar[scope][id];
        if not reg then
            if potentialId and self.registers[potentialId] ~= self.VAR_REGISTER and potentialId ~= self.POS_REGISTER and potentialId ~= self.RETURN_REGISTER then
                self.registers[potentialId] = self.VAR_REGISTER;
                reg = potentialId;
            else
                reg = self:allocRegister(true);
            end
            self.registersForVar[scope][id] = reg;
        end
        return reg;
    end

    function Compiler:getRegisterVarId(id)
        local varId = self.registerVars[id];
        if not varId then
            varId = self.containerFuncScope:addVariable();
            self.registerVars[id] = varId;
        end
        return varId;
    end

    function Compiler:register(scope, id)
        if id == self.POS_REGISTER then
            return self:pos(scope);
        end

        if id == self.RETURN_REGISTER then
            return self:getReturn(scope);
        end

        if id < MAX_REGS then
            local vid = self:getRegisterVarId(id);
            scope:addReferenceToHigherScope(self.containerFuncScope, vid);
            return Ast.VariableExpression(self.containerFuncScope, vid);
        end

        local vid = self:getRegisterVarId(MAX_REGS);
        scope:addReferenceToHigherScope(self.containerFuncScope, vid);
        return Ast.IndexExpression(Ast.VariableExpression(self.containerFuncScope, vid), Ast.NumberExpression((id - MAX_REGS) + 1));
    end

    function Compiler:registerList(scope, ids)
        local l = {};
        for i, id in ipairs(ids) do
            table.insert(l, self:register(scope, id));
        end
        return l;
    end

    function Compiler:registerAssignment(scope, id)
        if id == self.POS_REGISTER then
            return self:posAssignment(scope);
        end
        if id == self.RETURN_REGISTER then
            return self:returnAssignment(scope);
        end

        if id < MAX_REGS then
            local vid = self:getRegisterVarId(id);
            scope:addReferenceToHigherScope(self.containerFuncScope, vid);
            return Ast.AssignmentVariable(self.containerFuncScope, vid);
        end

        local vid = self:getRegisterVarId(MAX_REGS);
        scope:addReferenceToHigherScope(self.containerFuncScope, vid);
        return Ast.AssignmentIndexing(Ast.VariableExpression(self.containerFuncScope, vid), Ast.NumberExpression((id - MAX_REGS) + 1));
    end

    function Compiler:setRegister(scope, id, val, compundArg)
        if(compundArg) then
            return compundArg(self:registerAssignment(scope, id), val);
        end
        if id == self.POS_REGISTER and val then
            local function obfuscateNode(n)
                if type(n) ~= "table" then return n end
                if n.kind == AstKind.NumberExpression then
                    return self:obfuscateBlockId(n.value);
                elseif n.kind == AstKind.OrExpression then
                    n.lhs = obfuscateNode(n.lhs);
                    n.rhs = obfuscateNode(n.rhs);
                elseif n.kind == AstKind.AndExpression then
                    n.lhs = obfuscateNode(n.lhs);
                    n.rhs = obfuscateNode(n.rhs);
                end
                return n;
            end
            val = obfuscateNode(val);
        end
        return Ast.AssignmentStatement({
            self:registerAssignment(scope, id)
        }, {
            val
        });
    end

    function Compiler:setRegisters(scope, ids, vals)
        local idStats = {};
        for i, id in ipairs(ids) do
            table.insert(idStats, self:registerAssignment(scope, id));
        end

        return Ast.AssignmentStatement(idStats, vals);
    end

    function Compiler:copyRegisters(scope, to, from)
        local idStats = {};
        local vals = {};
        for i, id in ipairs(to) do
            local fromId = from[i];
            if(fromId ~= id) then
                table.insert(idStats, self:registerAssignment(scope, id));
                table.insert(vals, self:register(scope, fromId));
            end
        end

        if(#idStats > 0 and #vals > 0) then
            return Ast.AssignmentStatement(idStats, vals);
        end
    end

    function Compiler:resetRegisters()
        self.registers = {};
    end

    function Compiler:pos(scope)
        scope:addReferenceToHigherScope(self.containerFuncScope, self.posVar);
        return Ast.VariableExpression(self.containerFuncScope, self.posVar);
    end

    function Compiler:posAssignment(scope)
        scope:addReferenceToHigherScope(self.containerFuncScope, self.posVar);
        return Ast.AssignmentVariable(self.containerFuncScope, self.posVar);
    end

    function Compiler:args(scope)
        scope:addReferenceToHigherScope(self.containerFuncScope, self.argsVar);
        return Ast.VariableExpression(self.containerFuncScope, self.argsVar);
    end

    function Compiler:unpack(scope)
        scope:addReferenceToHigherScope(self.scope, self.unpackVar);
        return Ast.VariableExpression(self.scope, self.unpackVar);
    end

    function Compiler:env(scope)
        scope:addReferenceToHigherScope(self.scope, self.envVar);
        return Ast.VariableExpression(self.scope, self.envVar);
    end

    function Compiler:jmp(scope, to)
        scope:addReferenceToHigherScope(self.containerFuncScope, self.posVar);
        return Ast.AssignmentStatement({Ast.AssignmentVariable(self.containerFuncScope, self.posVar)},{to});
    end

    function Compiler:setPos(scope, val)
        if not val then
            local v = Ast.IndexExpression(self:env(scope), randomStrings.randomStringNode(math.random(12, 14)));
            scope:addReferenceToHigherScope(self.containerFuncScope, self.posVar);
            return Ast.AssignmentStatement({Ast.AssignmentVariable(self.containerFuncScope, self.posVar)}, {v});
        end
        scope:addReferenceToHigherScope(self.containerFuncScope, self.posVar);
        local targetExpr;
        if type(val) == "number" then
            targetExpr = self:obfuscateBlockId(val);
        elseif type(val) == "table" and val.kind == AstKind.NumberExpression then
            targetExpr = self:obfuscateBlockId(val.value);
        else
            targetExpr = val;
        end
        return Ast.AssignmentStatement({Ast.AssignmentVariable(self.containerFuncScope, self.posVar)}, {targetExpr});
    end

    function Compiler:setReturn(scope, val)
        scope:addReferenceToHigherScope(self.containerFuncScope, self.returnVar);
        return Ast.AssignmentStatement({Ast.AssignmentVariable(self.containerFuncScope, self.returnVar)}, {val});
    end

    function Compiler:getReturn(scope)
        scope:addReferenceToHigherScope(self.containerFuncScope, self.returnVar);
        return Ast.VariableExpression(self.containerFuncScope, self.returnVar);
    end

    function Compiler:returnAssignment(scope)
        scope:addReferenceToHigherScope(self.containerFuncScope, self.returnVar);
        return Ast.AssignmentVariable(self.containerFuncScope, self.returnVar);
    end

    function Compiler:setUpvalueMember(scope, idExpr, valExpr, compoundConstructor)
        scope:addReferenceToHigherScope(self.scope, self.upvaluesTable);
        if compoundConstructor then
            return compoundConstructor(Ast.AssignmentIndexing(Ast.VariableExpression(self.scope, self.upvaluesTable), idExpr), valExpr);
        end
        return Ast.AssignmentStatement({Ast.AssignmentIndexing(Ast.VariableExpression(self.scope, self.upvaluesTable), idExpr)}, {valExpr});
    end

    function Compiler:getUpvalueMember(scope, idExpr)
        scope:addReferenceToHigherScope(self.scope, self.upvaluesTable);
        return Ast.IndexExpression(Ast.VariableExpression(self.scope, self.upvaluesTable), idExpr);
    end
end

