local file = assert(arg[1], 'helper file required')
local selections = 0
local world, other_world, owner, other_owner = {}, {}, {}, {}
local factory = assert(loadfile(file))()
local c = factory(function(position, w)
    selections = selections + 1
    return { index = selections, position = position, world = w }
end)
local function action(unit, name)
    return { _weapon_template = { name = name or 'chainsword_2h_p1_m1' }, _player_unit = unit, _world = world }
end
local a = action(owner)
assert(c.begin(a) and selections == 0, 'miss/start consumed colour')
local selected
c.with_action(a, function()
    local event, created = c.event('near', world)
    assert(created and event.index == 1); selected = event
    assert(c.event('far', other_world) == nil, 'foreign world forced colour')
    assert(c.event('near again', world) == selected)
end)
assert(c.group() == nil)
c.with_owner(owner, function() assert(c.event('far and later', world) == selected) end)
assert(selections == 1, 'one attack selected repeatedly')
local b = action(other_owner)
c.begin(b)
c.with_action(a, function()
    local group = c.group()
    c.with_owner(other_owner, function() assert(c.event('same point', world).index == 2) end)
    assert(c.group() == group and c.event('old attack', world) == selected)
    c.with_owner({}, function() assert(c.event('unrelated', world) == nil) end)
    assert(c.group() == group)
end)
local native_calls = 0
local function native(x,y,z)
    native_calls = native_calls + 1
    assert(x == 'one' and y == nil and z == 'three')
    return 'a', nil, 'c', nil
end
local function pack(...) return { n=select('#',...), ... } end
local r=pack(c.with_owner(owner,native,'one',nil,'three'))
assert(r.n==4 and r[1]=='a' and r[2]==nil and r[3]=='c' and r[4]==nil and native_calls==1)
local ok,message=pcall(c.with_action,a,function()error('native failure sentinel',0)end)
assert(not ok and message=='native failure sentinel' and c.group()==nil, 'error leaked transient scope')
c.with_owner(owner,function()assert(c.event('same ongoing attack',world)==selected)end)
local next_action=action(owner)
c.begin(next_action);c.finish(a)
c.with_owner(owner,function()assert(c.event('next attack',world).index==3)end)
c.finish_call(next_action,function()assert(c.event('finish blood',world).index==3);return 8,nil,10 end)
c.with_owner(owner,function()assert(c.event('finished',world)==nil)end)
local sword=action(owner,'powersword_p1_m1');assert(c.begin(sword))
c.with_action(sword,function()assert(c.event('ordinary melee',world))end)
c.finish(sword)
local failed=action(owner)
ok,message=pcall(c.start_call,failed,function()error('start sentinel',0)end)
assert(not ok and message=='start sentinel');c.with_owner(owner,function()assert(c.event('failed start',world)==nil)end)
c.begin(failed)
ok,message=pcall(c.finish_call,failed,function()error('finish sentinel',0)end)
assert(not ok and message=='finish sentinel');c.with_owner(owner,function()assert(c.event('failed finish',world)==nil)end)
c.begin(a)
c.with_action(a,function()
    c.with_owner(other_owner,function()c.reset()end)
    assert(c.group()==nil and c.event('cleared during nesting',world)==nil)
end)
assert(c.group()==nil, 'reset restored stale outer scope')
c.with_owner(owner,function()assert(c.event('reset owner',world)==nil)end)
print('CHAIN_SCOPE_UNIT_PASS: lazy selection; multi-owner/world isolation; near/far reuse; next attack; native returns; error and reset cleanup')
