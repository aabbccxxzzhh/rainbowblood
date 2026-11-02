-- Scoped ownership only: never spawns, destroys, moves or edits particles.
return function(select_event, colour_mode)
    local function weak_keys() return setmetatable({}, { __mode = "k" }) end
    local actions, owners, ordinary = weak_keys(), weak_keys(), weak_keys()
    local scope, generation = nil, 0
    local controller = {}
    -- Forward protected-call results as varargs: no per-call result table.
    -- Keep both protection layers: callbacks can reenter or reset ownership.
    local function restore_scope(previous, entered_generation, ok, ...)
        scope = entered_generation == generation and previous or nil
        if not ok then error((...), 0) end
        return ...
    end

    local function complete_action(action, finishing, ok, ...)
        if finishing or not ok then controller.finish(action) end
        if not ok then error((...), 0) end
        return ...
    end

    local function invoke(state, func, ...)
        if not state and not scope then return func(...) end
        local previous, entered_generation = scope, generation
        scope = state
        return restore_scope(previous, entered_generation, pcall(func, ...))
    end

    function controller.begin(action)
        controller.finish(action)
        local template = action and action._weapon_template
        local name = template and template.name
        local owner = action and action._player_unit
        if not owner or type(name) ~= "string" then return false end
        -- All melee sweeps share one attack identity, including ordinary swords.
        -- Separate victims retain their own event across near/far and sticky FX.
        local state = { chain = true, owner = owner, world = action._world, group = {}, event = nil,
            different = colour_mode and colour_mode() == "different" }
        actions[action], owners[owner] = state, state
        return true
    end

    function controller.finish(action)
        local state = action and actions[action]
        if state then
            state.finished = true
            if owners[state.owner] == state then owners[state.owner] = nil end
            actions[action] = nil
        end
    end

    function controller.start_call(action, func, ...)
        controller.begin(action)
        return complete_action(action, false, pcall(invoke, actions[action], func, ...))
    end

    function controller.finish_call(action, func, ...)
        return complete_action(action, true, pcall(invoke, actions[action], func, ...))
    end

    function controller.with_action(action, func, ...)
        return invoke(action and actions[action], func, ...)
    end

    function controller.with_owner(owner, func, ...)
        local state
        if scope and scope.chain and not scope.finished and scope.owner == owner then
            state = scope
        elseif owner then
            state = owners[owner]
            if not state then
                state = ordinary[owner]
                if not state then state = { group = {} }; ordinary[owner] = state end
            end
        end
        return invoke(state, func, ...)
    end

    function controller.with_target(owner, target, func, ...)
        local state
        if scope and scope.owner == owner and not scope.finished then
            state = scope.root or scope
        elseif owner then
            state = owners[owner]
        end
        if not state or not target then return controller.with_owner(owner, func, ...) end
        if state.different then
            if not state.targets then state.targets = weak_keys() end
            local victim = state.targets[target]
            if not victim then
                victim = { chain = true, owner = owner, world = state.world,
                    group = {}, root = state }
                state.targets[target] = victim
            end
            state = victim
        end
        return invoke(state, func, ...)
    end

    function controller.group()
        return scope and scope.group or nil
    end

    function controller.event(position, world)
        local state = scope
        if not state or not state.chain or state.finished or (state.root and state.root.finished) then return nil end
        if world and state.world and world ~= state.world then return nil end
        if world and not state.world then state.world = world end
        if not state.event then
            local root = state.root
            if root then
                -- Seven distinct victims use all seven colours before repeating.
                if not root.used or root.used_count == 7 then root.used, root.used_count = {}, 0 end
            end
            state.event = select_event(position, world or state.world, root and root.used)
            if root then
                root.used[state.event.index] = true
                root.used_count = root.used_count + 1
            end
            return state.event, true
        end
        return state.event, false
    end

    function controller.reset()
        generation = generation + 1
        actions, owners, ordinary = weak_keys(), weak_keys(), weak_keys()
        scope = nil
    end
    return controller
end
