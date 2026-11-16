-- Combat changes use the current world and each actor's own colony. This adapter
-- deliberately does not authorize campaign point writes (native.is_owned does).
local M={}
local function safe(fn)local ok,v=pcall(fn);if ok then return v end end
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
local function number(v)local n=tonumber(unbox(v));if n and n==n and n~=math.huge and n~=-math.huge then return n end end
function M.install(o)
 local native=assert(o.native)
 local function valid(v)return v~=nil and safe(function()return native.valid_object(v)end)==true end
 local function colony(v)local n=number(v);return n and n>=0 and n%1==0 and n or nil end
 local function same(a,b)
  if not valid(a)or not valid(b)then return false end
  local address=safe(function()return a:GetAddress()end)
  return address~=nil and tostring(address)==tostring(safe(function()return b:GetAddress()end))
 end
 local api={}
 local function resolve(gs,gm)
  if not valid(gs)or not valid(gm)then return nil end
  local wid=native.world_id(gs)
  if not wid or native.world_id(gm)~=wid then return nil end
  local world=safe(function()return gs:GetWorld()end)
  if not valid(world)then return nil end
  local pc=native.get_local_controller(gs)
  local owner=valid(pc)and colony(safe(function()return pc:GetColonyID()end))or nil
  local initial_ui=number(safe(function()return gm.InitalUISetup end))
  return{gs=gs,gm=gm,world=world,world_id=wid,pc=pc,local_owner=owner,
   game_state=gs,game_mode=gm,controller=pc,game_type=number(safe(function()return gm.GameType end)),
   is_arena=initial_ui==1 or initial_ui==6}
 end
 local function from_actor(actor)
  if not valid(actor)then return nil end
  local actor_world=safe(function()return actor:GetWorld()end)
  if not valid(actor_world)then return nil end
  local gameplay=safe(function()return StaticFindObject('/Script/Engine.Default__GameplayStatics')end)
  if not valid(gameplay)then return nil end
  local gi=unbox(safe(function()return gameplay:GetGameInstance(actor)end))
  -- Engine discovery is read-only. Check the exact world/instance ownership
  -- once at the end, after the GS/GM/controller getters could have reentered.
  -- No context or skill authority escapes before that final proof succeeds.
  if not valid(gi)then return nil end
  local gs=unbox(safe(function()return gameplay:GetGameState(gi)end))
  local gm=unbox(safe(function()return gameplay:GetGameMode(gi)end))
  local ctx=resolve(gs,gm)
  if not ctx or not same(actor_world,ctx.world)or native.world_id(actor)~=ctx.world_id
   or native.world_id(gi)~=ctx.world_id then return nil end
  -- Recheck the owning instance after all reflected lookups. A retained old
  -- actor, wrong GI, or reentrant world transition must use live discovery.
  if not same(unbox(safe(function()return ctx.world.OwningGameInstance end)),gi)then return nil end
  return ctx
 end
 function api.get(actor)
  -- Hook receivers can resolve their current GameInstance/World directly.
  -- Nothing is retained between calls, and player-zero authority still comes
  -- from native.get_local_controller inside resolve. Missing bindings or any
  -- inconsistent world fall through to the original discovery path.
  if actor~=nil then local ok,ctx=pcall(from_actor,actor);if ok and ctx then return ctx end end
  return resolve(FindFirstOf('EotUGameState'),FindFirstOf('EotUGameMode'))
 end
 function api.eligible(c,gs)
  if not valid(c)or not valid(gs)then return false end
  local wid=native.world_id(gs)
  local owner=number(safe(function()return c.ColonyID end))
  -- -1 is the engine's valid unaligned wildlife side. It can receive species
  -- combat changes, but never resolves to a colony queen or a skill loadout.
  if wid~=nil and native.world_id(c)==wid and owner~=nil and owner>=-1 and owner%1==0 then
   return true,wid
  end
  return false
 end
 function api.for_colony(owner,base)
  owner=colony(owner);base=base or api.get()
  if owner==nil or not base then return nil end
  local ctx={};for k,v in pairs(base)do ctx[k]=v end
  ctx.owner=owner;ctx.player_owned=owner==base.local_owner
  local grid=unbox(safe(function()return base.gs:GetTileGridByColonyID(owner)end))
  if valid(grid)and native.world_id(grid)==base.world_id and colony(safe(function()return grid.ColonyID end))==owner then
   ctx.grid=grid;ctx.tile_grid=grid
   local queen=unbox(safe(function()return grid.ColonyQueen end))
   if not base.is_arena and api.eligible(queen,base.gs)and colony(safe(function()return queen.ColonyID end))==owner
    and(number(safe(function()return queen.ColonyLocation end))or -2)>=-1
    and(number(safe(function()return queen.Health end))or 0)>0 then ctx.queen=queen end
  end
  -- Queenless modes intentionally keep ordinary lethal damage. No synthetic
  -- destination or automatic capture is substituted for the native queen.
  ctx.can_capture=ctx.queen~=nil and ctx.grid~=nil
  return ctx
 end
 function api.for_actor(c)
  local ctx=api.get()
  if not ctx or not api.eligible(c,ctx.gs)then return nil end
  return api.for_colony(safe(function()return c.ColonyID end),ctx)
 end
 return api
end
return M
