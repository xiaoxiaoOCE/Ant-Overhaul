-- A surviving native nestmate keeps one non-stacking numerical bonus until
-- its own death. Persistent actor tags store entitlement, never base stats.
local M={species='LittleBlackAnt',tile_type=18,marker='EAA_LittleBlackTwinBond_v1',
 twin_marker='EAA_LittleBlackTwin_v1',multiplier=1.2,tick_interval=.1}
local function safe(f)local ok,v=pcall(f);if ok then return v end end
-- Exact UE value types only; remote parameters and unknown wrappers still get unboxed.
local value_userdata={AActor=true,UObject=true,UWorld=true,UScriptStruct=true,FNameUserdata=true,TArray=true}
local function unbox(v)
 local kind=type(v)
 if kind=='nil'or kind=='number'or kind=='string'or kind=='boolean'then return v end
 if kind=='userdata'then
  local getter=type(debug)=='table'and rawget(debug,'getmetatable')
  if type(getter)=='function'then
   local ok,meta=pcall(getter,v)
   if ok and type(meta)=='table'and value_userdata[rawget(meta,'__name')]then return v end
  end
 end
 local x=safe(function()return v:get()end);return x~=nil and x or v
end
local function num(v)local x=tonumber(unbox(v));if x and x==x and math.abs(x)<math.huge then return x end end
local function name(v)v=unbox(v);return type(v)=='string'and v or v and safe(function()return v:ToString()end)end
local function equal(a,b)return a and b and math.abs(a-b)<=math.max(1e-6,math.abs(a)*1e-6,math.abs(b)*1e-6)end
local function values(a)
 if type(a)=='table'and type(a.GetArrayNum)~='function'then return a end
 if not a then return{}end
 local n=num(a:GetArrayNum());assert(n and n>=0 and n<=8192,'twin_bond_array_invalid')
 local out={};for i=1,n do out[#out+1]=unbox(a[i])end;return out
end
function M.install(o)
 local native,combat=assert(o.native),assert(o.combat)
 local choices=assert(o.get_choices)
 local api,registry,fields,reported={},{},{},{}
 local stopped,world,last_tick=false,nil,nil
 local stats={awards=0,deaths=0,suppressed=0,cleared_births=0,writes=0}
 local function valid(c)return c~=nil and safe(function()return native.valid_object(c)end)==true end
 local function key(c)
  if not valid(c)then return end
  return tostring(c:GetAddress())..'|'..tostring(c:GetFullName())
 end
 local function same(a,b)local k=key(a);return k~=nil and k==key(b)end
 local function fail(e)e=tostring(e);if not reported[e]then reported[e]=true;if o.log then pcall(o.log,'[LittleBlackTwinBond] '..e)end end;return nil,e end
 local function context()
  local ctx=combat.get();local gs=ctx and(ctx.gs or ctx.game_state)
  if not valid(gs)then return end
  return ctx,native.world_id(gs)
 end
 local function eligible(c,w,ctx)
  return valid(c)and name(c.CreatureName)==M.species and w~=nil and native.world_id(c)==w
   and combat.eligible(c,ctx.gs or ctx.game_state)==true
 end
 local function alive(c)return valid(c)and(num(c.Health)or 0)>0 end
 local function tagged(c,tag)
  if not valid(c)then return false end
  for _,field in ipairs({'Tags','TagsToRestore'})do
   for _,v in ipairs(values(safe(function()return c[field]end)))do if name(v)==tag then return true end end
  end
  return false
 end
 local function clear_tag(c)
  for _,field in ipairs({'Tags','TagsToRestore'})do
   local source=safe(function()return c[field]end)
   if source then
    local out,changed={},false
    for _,v in ipairs(values(source))do if name(v)==M.marker then changed=true else out[#out+1]=v end end
    if changed then c[field]=out end
   end
  end
 end
 local function add_tag(c)
  if tagged(c,M.marker)then return false end
  local out={};for _,v in ipairs(values(c.Tags))do out[#out+1]=v end
  out[#out+1]=(o.fname or FName)(M.marker);c.Tags=out;return true
 end
 local function restore(c)
  local k=key(c);local row=k and fields[k]
  if not row then return{changed=false}end
  for _,field in ipairs({'AttackDamage','AttackSpeed'})do
   local v=row[field];if equal(num(c[field]),v.after)then c[field]=v.base end
  end
  fields[k]=nil;return{changed=true}
 end
 function api.before_attributes(c)
  local ok,r=pcall(restore,c);if not ok then return fail(r)end;return r
 end
 function api.forget(c)
  -- Call immediately after native stat reconstruction; do not overwrite its
  -- new rank/cultivation baseline with the previous rank's stored numbers.
  local k=key(c);if k then fields[k]=nil end;return true
 end
 function api.decorate(c)
  local ok,r=pcall(function()
   if stopped or not valid(c)or name(c.CreatureName)~=M.species then return{changed=false}end
   local ctx,w=context()
   if not ctx or not eligible(c,w,ctx)then return{changed=false}end
   if not alive(c)then restore(c);clear_tag(c);return{changed=false}end
   if not tagged(c,M.marker)then return restore(c)end
   local k=key(c);local previous=fields[k];local row={creature=c,world=w};local changed=false
   for _,field in ipairs({'AttackDamage','AttackSpeed'})do
    local current=assert(num(c[field]),'twin_bond_stat_unreadable:'..field)
    local prior=previous and previous[field]
    local base=prior and equal(current,prior.after)and prior.base or current
    local desired=base*M.multiplier
    if not equal(current,desired)then c[field]=desired;changed=true;stats.writes=stats.writes+1 end
    row[field]={base=base,after=desired}
   end
   fields[k]=row;return{changed=changed,active=true}
  end);if not ok then return fail(r)end;return r
 end
 local function nursery(c,ctx,w)
  if not eligible(c,w,ctx)then return end
  local tile=unbox(safe(function()return c.NurseryTile end))
  if not valid(tile)or num(tile.TileFunction)~=M.tile_type then return end
  local n=unbox(tile.FunctionRepresentation)
  if not valid(n)or not same(n.OwningTile,tile)or native.world_id(n)~=w then return end
  local owner=num(n:GetColonyID())
  if owner==nil or owner~=num(c.ColonyID)then return end
  return n,tile,owner
 end
 local function twin_form(c)
  local selected=choices(c,M.species);return type(selected)=='table'and selected.form=='twin'
 end
 local function row_for(c,w,n,tile,owner)
  local k=key(c);local row=registry[k]
  if not row then row={creature=c,key=k,world=w};registry[k]=row end
  if row.nursery_key~=key(n)then row.partner=nil end
  row.nursery=n;row.nursery_key=key(n);row.tile=tile;row.tile_key=key(tile);row.owner=owner
  if alive(c)then row.seen_alive=true end
  return row
 end
 local function observe(c)
  -- The global native death hook also receives every unrelated species.
  -- Reject those before resolving the live world/controller context.
  if stopped or not valid(c)or name(c.CreatureName)~=M.species then return false end
  local ctx,w=context();if not ctx or not eligible(c,w,ctx)then return false end
  if world and world~=w then api.reset_cache()end;world=w
  -- A loaded corpse has no live pair provenance. Clear any saved entitlement
  -- once, without adding a permanently polled dead-actor registry entry.
  if not alive(c)then return api.decorate(c)end
  local n,tile,owner=nursery(c,ctx,w)
  if n then
   local row=row_for(c,w,n,tile,owner)
   if alive(c)and twin_form(c)and num(n.NoOfTennents)==2 then
    local rank=num(tile:GetEffectiveTileUpgradeLevel());local occupants={}
    if rank and rank>=2 then
     for _,other in ipairs(values(n.Tennents))do
      if alive(other)and eligible(other,w,ctx)and same(other.NurseryTile,tile)and num(other.ColonyID)==owner then occupants[#occupants+1]=other end
     end
     if #occupants==2 and tagged(occupants[1],M.twin_marker)~=tagged(occupants[2],M.twin_marker)then
      local a,b=occupants[1],occupants[2]
      if twin_form(a)and twin_form(b)then
       local ar,br=row_for(a,w,n,tile,owner),row_for(b,w,n,tile,owner)
       ar.partner={creature=b,key=br.key};br.partner={creature=a,key=ar.key}
      end
     end
    end
   end
  end
  return api.decorate(c)
 end
 function api.observe(c)local ok,r=pcall(observe,c);if not ok then return fail(r)end;return r end
 function api.suppress_removal(c)
  -- The twin capacity service calls this immediately before a form-change
  -- removal. This record survives the later death poll and even a fast toggle.
  if not valid(c)then return false end
  local ctx,w=context();if not ctx or not eligible(c,w,ctx)then return false end
  local k=key(c);local row=registry[k]or{creature=c,key=k,world=w};registry[k]=row
  row.suppressed=true;stats.suppressed=stats.suppressed+1;return true
 end
 function api.on_native_birth(n,c)
  -- Called only by the positively identified FinishSpawningAnt output path.
  -- The native saved-tag template can otherwise leak a dead ant's entitlement.
  local ok,r=pcall(function()
   local ctx,w=context();if not ctx or not eligible(c,w,ctx)then return false end
   local actual=nursery(c,ctx,w)
   if not actual or not same(actual,n)or n.LoadSpawn~=false then return false end
   restore(c);clear_tag(c);registry[key(c)]=nil;stats.cleared_births=stats.cleared_births+1
   return true
  end);if not ok then return fail(r)end;return r
 end
 function api.on_death(c)
  local ok,r=pcall(function()
   if stopped or not valid(c)or name(c.CreatureName)~=M.species or(num(c.Health)or 1)>0 then return false end
   local k=key(c);local row=registry[k]
   -- A final death is processed exactly once. In particular, do not repeat
   -- world queries, stat restoration and two tag-array scans for old corpses.
   if not row or row.death_seen or not row.seen_alive then return false end
   local ctx,w=context();if not ctx or not eligible(c,w,ctx)then return false end
   if o.is_incapacitated and o.is_incapacitated(c)==true then return false end
   if row.world~=w then return false end
   restore(c);clear_tag(c)
   row.death_seen=true;stats.deaths=stats.deaths+1
   if row.suppressed or not row.partner or not twin_form(c)then return false end
   local other=row.partner.creature
   if not alive(other)or key(other)~=row.partner.key or not eligible(other,w,ctx)or not twin_form(other)then return false end
   local n,tile,owner=nursery(other,ctx,w)
   if not n or key(n)~=row.nursery_key or key(tile)~=row.tile_key or owner~=row.owner or num(c.ColonyID)~=owner then return false end
   -- The dead actor need not remain in Tennents after native swap-removal,
   -- but the exact survivor must still belong to that original nursery.
   local present=false;for _,v in ipairs(values(n.Tennents))do if same(v,other)then present=true end end
   if not present then return false end
   local fresh=add_tag(other);assert(api.decorate(other))
   if fresh then stats.awards=stats.awards+1 end
   return fresh
  end);if not ok then return fail(r)end;return r
 end
 function api.tick(now)
  local ok,r=pcall(function()
   if stopped then return false end
   local ctx,w=context();if not ctx then return false end
   now=num(now)or num((ctx.gs or ctx.game_state):GetLevelTime());if not now then return false end
   if world and world~=w or last_tick and now<last_tick then api.reset_cache()end;world=w
   if last_tick and now-last_tick<M.tick_interval then return true end;last_tick=now
   for k,row in pairs(registry)do
    local c=row.creature
    if row.death_seen then registry[k]=nil;fields[k]=nil
    -- A live poll only observes health; it cannot award or restore anything.
    -- Keep the native pending-kill guard before that read, but defer identity
    -- and actor-world reflection until a death can actually mutate gameplay.
    -- All birth/attribute/death entrypoints retain their exact checks. A stale
    -- live receipt therefore never authorizes a replacement actor's bonus.
    elseif not valid(c)then registry[k]=nil;fields[k]=nil
    elseif(num(c.Health)or 0)<=0 then
     if key(c)~=k or native.world_id(c)~=w then registry[k]=nil;fields[k]=nil
     else api.on_death(c)end
    end
    -- Stable live actors need only guarded death monitoring. Entitlement and
    -- its numerical overlay are updated by award/birth/observe and main's
    -- native-stat/cultivation hooks, never by scanning tags every 0.1 seconds.
   end
   return true
  end);if not ok then return fail(r)end;return r
 end
 function api.reset_cache()
  local _,w=context()
  for k,row in pairs(fields)do
   local c=row.creature
   if valid(c)and key(c)==k and row.world==w and native.world_id(c)==w then pcall(restore,c)end
  end
  registry={};fields={};world=nil;last_tick=nil;return true
 end
 function api.stop()api.reset_cache();stopped=true;return true end
 function api.status()
  local r={stopped=stopped,tracked=0,buffed=0};for k,v in pairs(stats)do r[k]=v end
  for _ in pairs(registry)do r.tracked=r.tracked+1 end;for _ in pairs(fields)do r.buffed=r.buffed+1 end;return r
 end
 if o.register_hooks~=false then
  local hook=o.register_hook or RegisterHook
  hook('/Script/EotU.Creature:KillCreature',function(c)api.observe(unbox(c))end,function(c)api.on_death(unbox(c))end)
  hook('/Script/EotU.Creature:CreatureSpesificDeathEvent',function()end,function(c)api.on_death(unbox(c))end)
 end
 return api
end
return M
