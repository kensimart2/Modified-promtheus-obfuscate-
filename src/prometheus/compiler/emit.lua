-- This Script is Part of the Prometheus Obfuscator by levno-710
--
-- emit.lua
--
-- This Script contains the container function body emission for the compiler.

local Ast = require("prometheus.ast");
local Scope = require("prometheus.scope");
local util = require("prometheus.util");
local constants = require("prometheus.compiler.constants");
local AstKind = Ast.AstKind;

local MAX_REGS = constants.MAX_REGS;

return function(Compiler)
    local function hasAnyEntries(tbl)
        return type(tbl) == "table" and next(tbl) ~= nil;
    end

    local function unionLookupTables(a, b)
        local out = {};
        for k, v in pairs(a or {}) do
            out[k] = v;
        end
        for k, v in pairs(b or {}) do
            out[k] = v;
        end
        return out;
    end

    local function canMergeParallelAssignmentStatements(statA, statB)
        if type(statA) ~= "table" or type(statB) ~= "table" then
            return false;
        end

        if statA.usesUpvals or statB.usesUpvals then
            return false;
        end

        local a = statA.statement;
        local b = statB.statement;
        if type(a) ~= "table" or type(b) ~= "table" then
            return false;
        end
        if a.kind ~= AstKind.AssignmentStatement or b.kind ~= AstKind.AssignmentStatement then
            return false;
        end

        if type(a.lhs) ~= "table" or type(a.rhs) ~= "table" or type(b.lhs) ~= "table" or type(b.rhs) ~= "table" then
            return false;
        end

        if #a.lhs ~= #a.rhs or #b.lhs ~= #b.rhs then
            return false;
        end

        -- Cap merged assignments so expression list never exceeds parser recursion / register limits
        if #a.lhs + #b.lhs > 16 then
            return false;
        end

        -- Avoid merging vararg/call assignments because they can affect multi-return behavior.
        local function hasUnsafeRhs(rhsList)
            for _, rhsExpr in ipairs(rhsList) do
                if type(rhsExpr) ~= "table" then
                    return true;
                end
                local kind = rhsExpr.kind;
                if kind == AstKind.FunctionCallExpression or kind == AstKind.PassSelfFunctionCallExpression or kind == AstKind.VarargExpression then
                    return true;
                end
            end
            return false;
        end
        if hasUnsafeRhs(a.rhs) or hasUnsafeRhs(b.rhs) then
            return false;
        end

        local aReads = type(statA.reads) == "table" and statA.reads or {};
        local aWrites = type(statA.writes) == "table" and statA.writes or {};
        local bReads = type(statB.reads) == "table" and statB.reads or {};
        local bWrites = type(statB.writes) == "table" and statB.writes or {};

        -- Allow merging even if one statement has no writes (e.g., x = o(x) style assignments)
        -- Only require that at least one of them has writes
        if not hasAnyEntries(aWrites) and not hasAnyEntries(bWrites) then
            return false;
        end

        for r in pairs(aReads) do
            if bWrites[r] then
                return false;
            end
        end

        for r, b in pairs(aWrites) do
            if bWrites[r] or bReads[r] then
                return false;
            end
        end

        return true;
    end

    local function mergeParallelAssignmentStatements(statA, statB)
        local lhs = {};
        local rhs = {};
        local aLhs, bLhs = statA.statement.lhs, statB.statement.lhs;
        local aRhs, bRhs = statA.statement.rhs, statB.statement.rhs;
        for i = 1, #aLhs do lhs[i] = aLhs[i]; end
        for i = 1, #bLhs do lhs[#aLhs + i] = bLhs[i]; end
        for i = 1, #aRhs do rhs[i] = aRhs[i]; end
        for i = 1, #bRhs do rhs[#aRhs + i] = bRhs[i]; end

        return {
            statement = Ast.AssignmentStatement(lhs, rhs),
            writes = unionLookupTables(statA.writes, statB.writes),
            reads = unionLookupTables(statA.reads, statB.reads),
            usesUpvals = statA.usesUpvals or statB.usesUpvals,
        };
    end

    local function mergeAdjacentParallelAssignments(blockstats)
        local merged = {};
        local i = 1;
        while i <= #blockstats do
            local stat = blockstats[i];
            i = i + 1;

            while i <= #blockstats and canMergeParallelAssignmentStatements(stat, blockstats[i]) do
                stat = mergeParallelAssignmentStatements(stat, blockstats[i]);
                i = i + 1;
            end

            table.insert(merged, stat);
        end
        return merged;
    end

    function Compiler:emitContainerFuncBody()
        local blocks = {};

        local function injectLocalJunk(blockScope, blockstats)
            local d1 = blockScope:addVariable()
            local d2 = blockScope:addVariable()
            local d3 = blockScope:addVariable()

            -- local d1, d2, d3 = rand, rand, rand
            table.insert(blockstats, Ast.LocalVariableDeclaration(blockScope, {d1, d2, d3}, {
                Ast.NumberExpression(math.random(10, 1000)),
                Ast.NumberExpression(math.random(10, 1000)),
                Ast.NumberExpression(math.random(10, 1000))
            }))

            -- d1 = d2 + d3
            table.insert(blockstats, Ast.AssignmentStatement({
                Ast.AssignmentVariable(blockScope, d1)
            }, {
                Ast.AddExpression(Ast.VariableExpression(blockScope, d2), Ast.VariableExpression(blockScope, d3))
            }))

            -- d2 = d1 * rand
            table.insert(blockstats, Ast.AssignmentStatement({
                Ast.AssignmentVariable(blockScope, d2)
            }, {
                Ast.MulExpression(Ast.VariableExpression(blockScope, d1), Ast.NumberExpression(math.random(2, 6)))
            }))
        end

        util.shuffle(self.blocks);

        for i, block in ipairs(self.blocks) do
            local id = block.id;
            local blockstats = block.statements;

            for i = 2, #blockstats do
                local stat = blockstats[i];
                local reads = stat.reads;
                local writes = stat.writes;
                local maxShift = 0;
                local usesUpvals = stat.usesUpvals;
                for shift = 1, i - 1 do
                    local stat2 = blockstats[i - shift];

                    if stat2.usesUpvals and usesUpvals then
                        break;
                    end

                    local reads2 = stat2.reads;
                    local writes2 = stat2.writes;
                    local f = true;

                    for r, b in pairs(reads2) do
                        if(writes[r]) then
                            f = false;
                            break;
                        end
                    end

                    if f then
                        for r, b in pairs(writes2) do
                            if(writes[r]) then
                                f = false;
                                break;
                            end
                            if(reads[r]) then
                                f = false;
                                break;
                            end
                        end
                    end

                    if not f then
                        break
                    end

                    maxShift = shift;
                end

                local shift = math.random(0, maxShift);
                for j = 1, shift do
                    blockstats[i - j], blockstats[i - j + 1] = blockstats[i - j + 1], blockstats[i - j];
                end
            end

            local mergedBlockStats = mergeAdjacentParallelAssignments(blockstats);
            for _=1, 7 do
                mergedBlockStats = mergeAdjacentParallelAssignments(mergedBlockStats);
            end

            blockstats = {};
            for _, stat in ipairs(mergedBlockStats) do
                table.insert(blockstats, stat.statement);
            end

            -- Inject sandboxed local junk mathematical operations (with 35% probability to stay under size budget)
            if math.random() < 0.35 then
                injectLocalJunk(block.scope, blockstats)
            end

            -- Opaque predicate injection rate (35% for optimal balance of deep AST confusion and compactness)
            if #blockstats > 1 and math.random() < 0.35 then
                local k = math.random(5, 45);
                local invVariant = math.random(1, 16);
                local deadCond;

                if invVariant == 1 then
                    -- k * (k + 1) % 2 == 1 (never true)
                    deadCond = Ast.EqualsExpression(
                        Ast.ModExpression(
                            Ast.MulExpression(Ast.NumberExpression(k), Ast.NumberExpression(k + 1)),
                            Ast.NumberExpression(2)
                        ),
                        Ast.NumberExpression(1)
                    );
                elseif invVariant == 2 then
                    -- (k^2 + k) % 2 ~= 0 (never true)
                    deadCond = Ast.NotEqualsExpression(
                        Ast.ModExpression(
                            Ast.AddExpression(Ast.MulExpression(Ast.NumberExpression(k), Ast.NumberExpression(k)), Ast.NumberExpression(k)),
                            Ast.NumberExpression(2)
                        ),
                        Ast.NumberExpression(0)
                    );
                elseif invVariant == 3 then
                    -- (k * k) % 4 == 3 (quadratic residue mod 4 is only 0 or 1, never 3)
                    deadCond = Ast.EqualsExpression(
                        Ast.ModExpression(
                            Ast.MulExpression(Ast.NumberExpression(k), Ast.NumberExpression(k)),
                            Ast.NumberExpression(4)
                        ),
                        Ast.NumberExpression(3)
                    );
                elseif invVariant == 4 then
                    -- (k * (k + 1) * (k + 2)) % 6 ~= 0 (product of 3 consecutive integers is always divisible by 6)
                    deadCond = Ast.NotEqualsExpression(
                        Ast.ModExpression(
                            Ast.MulExpression(
                                Ast.MulExpression(Ast.NumberExpression(k), Ast.NumberExpression(k + 1)),
                                Ast.NumberExpression(k + 2)
                            ),
                            Ast.NumberExpression(6)
                        ),
                        Ast.NumberExpression(0)
                    );
                elseif invVariant == 5 then
                    -- Odd integer square mod 8 is always 1, so != 1 is never true
                    local oddK = k * 2 + 1;
                    deadCond = Ast.NotEqualsExpression(
                        Ast.ModExpression(
                            Ast.MulExpression(Ast.NumberExpression(oddK), Ast.NumberExpression(oddK)),
                            Ast.NumberExpression(8)
                        ),
                        Ast.NumberExpression(1)
                    );
                elseif invVariant == 6 then
                    -- (k^4) % 16 for odd k is always 1, so != 1 is never true
                    local oddK = k * 2 + 1;
                    deadCond = Ast.NotEqualsExpression(
                        Ast.ModExpression(
                            Ast.MulExpression(
                                Ast.MulExpression(Ast.NumberExpression(oddK), Ast.NumberExpression(oddK)),
                                Ast.MulExpression(Ast.NumberExpression(oddK), Ast.NumberExpression(oddK))
                            ),
                            Ast.NumberExpression(16)
                        ),
                        Ast.NumberExpression(1)
                    );
                elseif invVariant == 7 then
                    -- (k * (k^2 - 1)) % 3 ~= 0 (always divisible by 3)
                    deadCond = Ast.NotEqualsExpression(
                        Ast.ModExpression(
                            Ast.MulExpression(
                                Ast.NumberExpression(k),
                                Ast.SubExpression(Ast.MulExpression(Ast.NumberExpression(k), Ast.NumberExpression(k)), Ast.NumberExpression(1))
                            ),
                            Ast.NumberExpression(3)
                        ),
                        Ast.NumberExpression(0)
                    );
                elseif invVariant == 8 then
                    -- (k^5 - k) % 5 ~= 0 (Fermat's little theorem: a^5 - a is always a multiple of 5, safe bounds)
                    local kSmall = math.random(2, 12);
                    local kSq = kSmall * kSmall;
                    local k4 = kSq * kSq;
                    deadCond = Ast.NotEqualsExpression(
                        Ast.ModExpression(
                            Ast.SubExpression(Ast.MulExpression(Ast.NumberExpression(k4), Ast.NumberExpression(kSmall)), Ast.NumberExpression(kSmall)),
                            Ast.NumberExpression(5)
                        ),
                        Ast.NumberExpression(0)
                    );
                elseif invVariant == 9 then
                    -- (k * k) % 3 == 2 (quadratic residue mod 3 is only 0 or 1, never 2)
                    deadCond = Ast.EqualsExpression(
                        Ast.ModExpression(
                            Ast.MulExpression(Ast.NumberExpression(k), Ast.NumberExpression(k)),
                            Ast.NumberExpression(3)
                        ),
                        Ast.NumberExpression(2)
                    );
                elseif invVariant == 10 then
                    -- (oddK * (oddK^2 - 1)) % 24 ~= 0 (product of odd number and predecessor/successor is always divisible by 24)
                    local oddK = k * 2 + 1;
                    deadCond = Ast.NotEqualsExpression(
                        Ast.ModExpression(
                            Ast.MulExpression(
                                Ast.NumberExpression(oddK),
                                Ast.SubExpression(Ast.MulExpression(Ast.NumberExpression(oddK), Ast.NumberExpression(oddK)), Ast.NumberExpression(1))
                            ),
                            Ast.NumberExpression(24)
                        ),
                        Ast.NumberExpression(0)
                    );
                elseif invVariant == 11 then
                    -- (k * k + 1) % 3 == 0 (always false)
                    deadCond = Ast.EqualsExpression(
                        Ast.ModExpression(
                            Ast.AddExpression(Ast.MulExpression(Ast.NumberExpression(k), Ast.NumberExpression(k)), Ast.NumberExpression(1)),
                            Ast.NumberExpression(3)
                        ),
                        Ast.NumberExpression(0)
                    );
                elseif invVariant == 12 then
                    -- (k * k * k - k) % 3 ~= 0 (always false)
                    deadCond = Ast.NotEqualsExpression(
                        Ast.ModExpression(
                            Ast.SubExpression(Ast.MulExpression(Ast.MulExpression(Ast.NumberExpression(k), Ast.NumberExpression(k)), Ast.NumberExpression(k)), Ast.NumberExpression(k)),
                            Ast.NumberExpression(3)
                        ),
                        Ast.NumberExpression(0)
                    );
                elseif invVariant == 13 then
                    -- (k * k) % 5 == 2 (always false)
                    deadCond = Ast.EqualsExpression(
                        Ast.ModExpression(
                            Ast.MulExpression(Ast.NumberExpression(k), Ast.NumberExpression(k)),
                            Ast.NumberExpression(5)
                        ),
                        Ast.NumberExpression(2)
                    );
                elseif invVariant == 14 then
                    -- (k * k) % 5 == 3 (always false)
                    deadCond = Ast.EqualsExpression(
                        Ast.ModExpression(
                            Ast.MulExpression(Ast.NumberExpression(k), Ast.NumberExpression(k)),
                            Ast.NumberExpression(5)
                        ),
                        Ast.NumberExpression(3)
                    );
                elseif invVariant == 15 then
                    -- ((oddK * oddK) - 1) % 8 ~= 0 (always false)
                    local oddK = k * 2 + 1;
                    deadCond = Ast.NotEqualsExpression(
                        Ast.ModExpression(
                            Ast.SubExpression(Ast.MulExpression(Ast.NumberExpression(oddK), Ast.NumberExpression(oddK)), Ast.NumberExpression(1)),
                            Ast.NumberExpression(8)
                        ),
                        Ast.NumberExpression(0)
                    );
                else
                    -- (k * (k + 1) * (k + 2) * (k + 3)) % 24 ~= 0 (product of 4 consecutive numbers is divisible by 24)
                    deadCond = Ast.NotEqualsExpression(
                        Ast.ModExpression(
                            Ast.MulExpression(
                                Ast.MulExpression(Ast.NumberExpression(k), Ast.NumberExpression(k + 1)),
                                Ast.MulExpression(Ast.NumberExpression(k + 2), Ast.NumberExpression(k + 3))
                            ),
                            Ast.NumberExpression(24)
                        ),
                        Ast.NumberExpression(0)
                    );
                end

                local bogusScope = Scope:new(block.scope);
                bogusScope:addReferenceToHigherScope(self.containerFuncScope, self.posVar);
                local ghostStatements = {};
                local ghostVariant = math.random(1, 5);
                if ghostVariant == 1 then
                    table.insert(ghostStatements, Ast.AssignmentStatement({
                        Ast.AssignmentVariable(self.containerFuncScope, self.posVar)
                    }, {
                        Ast.ModExpression(
                            Ast.AddExpression(
                                Ast.MulExpression(Ast.VariableExpression(self.containerFuncScope, self.posVar), Ast.NumberExpression(31)),
                                Ast.NumberExpression(k * 17 + 1024)
                            ),
                            Ast.NumberExpression(16777216)
                        )
                    }));
                elseif ghostVariant == 2 then
                    table.insert(ghostStatements, Ast.AssignmentStatement({
                        Ast.AssignmentVariable(self.containerFuncScope, self.posVar)
                    }, {
                        Ast.AddExpression(
                            Ast.MulExpression(Ast.NumberExpression(k), Ast.NumberExpression(137)),
                            Ast.NumberExpression(math.random(1000, 9999))
                        )
                    }));
                elseif ghostVariant == 3 then
                    table.insert(ghostStatements, Ast.AssignmentStatement({
                        Ast.AssignmentVariable(self.containerFuncScope, self.posVar)
                    }, {
                        Ast.NumberExpression(math.random(1, 2^24))
                    }));
                elseif ghostVariant == 4 then
                    table.insert(ghostStatements, Ast.AssignmentStatement({
                        Ast.AssignmentVariable(self.containerFuncScope, self.posVar)
                    }, {
                        Ast.SubExpression(
                            Ast.MulExpression(Ast.VariableExpression(self.containerFuncScope, self.posVar), Ast.NumberExpression(2)),
                            Ast.NumberExpression(k * 3)
                        )
                    }));
                else
                    -- Safe local variable nesting for anti-decompiler complexity
                    local bd = bogusScope:addVariable()
                    table.insert(ghostStatements, Ast.LocalVariableDeclaration(bogusScope, {bd}, {
                        Ast.TableConstructorExpression({
                            Ast.TableEntry(Ast.TableConstructorExpression({
                                Ast.TableEntry(Ast.TableConstructorExpression({
                                    Ast.TableEntry(Ast.NumberExpression(k))
                                }))
                            }))
                        })
                    }));
                end

                local deadIf = Ast.IfStatement(
                    deadCond,
                    Ast.Block(ghostStatements, bogusScope),
                    {},
                    nil
                );
                local insertIdx = math.random(1, #blockstats);
                table.insert(blockstats, insertIdx, deadIf);
            end

            local block = { id = id, index = i, block = Ast.Block(blockstats, block.scope) }
            table.insert(blocks, block);
            blocks[id] = block;
        end

        -- Massive phantom decoy block injection (hardened random(3, 5) for balanced state explosion & size budget)
        local numDecoys = math.random(3, 5);
        for d = 1, numDecoys do
            local decoyId;
            repeat
                decoyId = math.random(1, 2^24);
            until not self.usedBlockIds[decoyId];
            self.usedBlockIds[decoyId] = true;

            local decoyScope = Scope:new(self.containerFuncScope);
            decoyScope:addReferenceToHigherScope(self.containerFuncScope, self.posVar);

            local k = math.random(10, 999);
            local decoyStats = {
                Ast.AssignmentStatement({
                    Ast.AssignmentVariable(self.containerFuncScope, self.posVar)
                }, {
                    Ast.ModExpression(
                        Ast.AddExpression(
                            Ast.MulExpression(Ast.VariableExpression(self.containerFuncScope, self.posVar), Ast.NumberExpression(37)),
                            Ast.NumberExpression(k * 19 + 71)
                        ),
                        Ast.NumberExpression(16777216)
                    )
                })
            };

            -- Insert sandboxed local junk mathematical operations
            if math.random() < 0.65 then
                injectLocalJunk(decoyScope, decoyStats)
            end

            -- Insert deep fake nested branching inside the decoy blocks
            local nestedScope = Scope:new(decoyScope)
            nestedScope:addReferenceToHigherScope(self.containerFuncScope, self.posVar)
            local fakeIf = Ast.IfStatement(
                Ast.EqualsExpression(Ast.NumberExpression(math.random(1, 100)), Ast.NumberExpression(math.random(101, 200))), -- always false
                Ast.Block({
                    Ast.AssignmentStatement({
                        Ast.AssignmentVariable(self.containerFuncScope, self.posVar)
                    }, {
                        Ast.NumberExpression(math.random(1, 2^24))
                    })
                }, nestedScope),
                {},
                nil
            )
            table.insert(decoyStats, fakeIf)

            local decoyBlockObj = {
                id = decoyId,
                index = #self.blocks + d,
                block = Ast.Block(decoyStats, decoyScope)
            };
            table.insert(blocks, decoyBlockObj);
            blocks[decoyId] = decoyBlockObj;
        end

        table.sort(blocks, function(a, b) return a.id < b.id end);

        -- Build a strict threshold condition between adjacent block IDs.
        -- Using a midpoint avoids exact-id comparisons while preserving dispatch.
        local function buildBlockThresholdCondition(scope, leftId, rightId, useAndOr)
            local bound = math.floor((leftId + rightId) / 2);
            local posExpr = self:pos(scope);
            local boundExpr = self:obfuscateBlockId(bound);

            if useAndOr then
                return Ast.LessThanExpression(posExpr, boundExpr);
            else
                local variant = math.random(1, 4);
                if variant == 1 then
                    return Ast.LessThanExpression(posExpr, boundExpr);
                elseif variant == 2 then
                    return Ast.GreaterThanExpression(boundExpr, posExpr);
                elseif variant == 3 then
                    return Ast.LessThanOrEqualsExpression(posExpr, self:obfuscateBlockId(bound - 1));
                else
                    return Ast.GreaterThanOrEqualsExpression(self:obfuscateBlockId(bound - 1), posExpr);
                end
            end
        end

        -- Build an elseif chain for a range of blocks
        local function buildElseifChain(tb, l, r, pScope)
            -- Handle invalid range by returning an empty block
            if r < l then
                local emptyScope = Scope:new(pScope);
                return Ast.Block({}, emptyScope);
            end

            local len = r - l + 1;

            -- For single block
            if len == 1 then
                tb[l].block.scope:setParent(pScope);
                return tb[l].block;
            end

            -- For small ranges, use elseif chain
            if len <= 4 then
                local ifScope = Scope:new(pScope);
                local elseifs = {};

                -- First block uses the first midpoint threshold
                tb[l].block.scope:setParent(ifScope);
                local firstCondition = buildBlockThresholdCondition(ifScope, tb[l].id, tb[l + 1].id, false);
                local firstBlock = tb[l].block;

                -- Middle blocks use their upper midpoint threshold
                for i = l + 1, r - 1 do
                    tb[i].block.scope:setParent(ifScope);
                    local condition = buildBlockThresholdCondition(ifScope, tb[i].id, tb[i + 1].id, false);
                    table.insert(elseifs, {
                        condition = condition,
                        body = tb[i].block
                    });
                end

                -- Last block becomes else
                tb[r].block.scope:setParent(ifScope);
                local elseBlock = tb[r].block;

                return Ast.Block({
                    Ast.IfStatement(firstCondition, firstBlock, elseifs, elseBlock);
                }, ifScope);
            end

            -- For larger ranges, use binary split with and/or chaining
            local mid = l + math.ceil(len / 2);
            local leftMaxId = tb[mid - 1].id;
            local rightMinId = tb[mid].id;
            -- Float-safe split: any bound strictly between adjacent IDs works.
            -- Midpoint avoids integer-only math.random(min, max) behavior.
            local bound = math.floor((leftMaxId + rightMinId) / 2);
            local ifScope = Scope:new(pScope);

            local lBlock = buildElseifChain(tb, l, mid - 1, ifScope);
            local rBlock = buildElseifChain(tb, mid, r, ifScope);

            -- Randomly choose between different condition styles
            local condStyle = math.random(1, 5);
            local condition;
            local trueBlock, falseBlock;

            if condStyle == 1 then
                condition = Ast.LessThanExpression(self:pos(ifScope), self:obfuscateBlockId(bound));
                trueBlock, falseBlock = lBlock, rBlock;
            elseif condStyle == 2 then
                condition = Ast.GreaterThanExpression(self:obfuscateBlockId(bound), self:pos(ifScope));
                trueBlock, falseBlock = lBlock, rBlock;
            elseif condStyle == 3 then
                condition = Ast.LessThanOrEqualsExpression(self:pos(ifScope), self:obfuscateBlockId(bound - 1));
                trueBlock, falseBlock = lBlock, rBlock;
            elseif condStyle == 4 then
                condition = Ast.GreaterThanOrEqualsExpression(self:obfuscateBlockId(bound - 1), self:pos(ifScope));
                trueBlock, falseBlock = lBlock, rBlock;
            else
                condition = Ast.GreaterThanExpression(self:pos(ifScope), self:obfuscateBlockId(bound));
                trueBlock, falseBlock = rBlock, lBlock;
            end

            return Ast.Block({
                Ast.IfStatement(condition, trueBlock, {}, falseBlock);
            }, ifScope);
        end

        local whileBody = buildElseifChain(blocks, 1, #blocks, self.containerFuncScope);
        if self.whileScope then
            -- Ensure whileScope is properly connected
            self.whileScope:setParent(self.containerFuncScope);
        end

        self.whileScope:addReferenceToHigherScope(self.containerFuncScope, self.returnVar, 1);
        self.whileScope:addReferenceToHigherScope(self.containerFuncScope, self.posVar);

        self.containerFuncScope:addReferenceToHigherScope(self.scope, self.unpackVar);

        local declarations = {
            self.returnVar,
        }

        for i, var in pairs(self.registerVars) do
            if(i ~= MAX_REGS) then
                table.insert(declarations, var);
            end
        end

        local stats = {}

        if self.maxUsedRegister >= MAX_REGS then
            table.insert(stats, Ast.LocalVariableDeclaration(self.containerFuncScope, {self.registerVars[MAX_REGS]}, {Ast.TableConstructorExpression({})}));
        end

        table.insert(stats, Ast.LocalVariableDeclaration(self.containerFuncScope, util.shuffle(declarations), {}));

        table.insert(stats, Ast.WhileStatement(whileBody, Ast.VariableExpression(self.containerFuncScope, self.posVar)));


        table.insert(stats, Ast.AssignmentStatement({
            Ast.AssignmentVariable(self.containerFuncScope, self.posVar)
        }, {
            Ast.LenExpression(Ast.VariableExpression(self.containerFuncScope, self.detectGcCollectVar))
        }));

        table.insert(stats, Ast.ReturnStatement{
            Ast.FunctionCallExpression(Ast.VariableExpression(self.scope, self.unpackVar), {
                Ast.VariableExpression(self.containerFuncScope, self.returnVar)
            });
        });

        return Ast.Block(stats, self.containerFuncScope);
    end
end
