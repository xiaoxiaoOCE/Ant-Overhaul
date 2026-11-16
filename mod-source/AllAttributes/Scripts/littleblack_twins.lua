-- Two ordinary native nursery slots, not synthetic spawned followers. Native
-- egg development, food costs, replacement jobs, group assignment and save
-- tenancy remain authoritative. The marked sibling stays one rank below its
-- nursery (1/2), regardless of native RemoveAtSwap changing its array index.
local M={tile_type=18,marker='EAA_LittleBlackTwin_v1',tick_interval=0.2,batch_interval=0.05,batch_size=6}
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
local function text(v)v=unbox(v);return type(v)=='string'and v or(v and safe(function()return v:ToString()end))end
local function number(v)local n=tonumber(unbox(v));return n and n==n and n~=math.huge and n~=-math.huge and n or nil end
function M.install(o)
 local native,combat=assert(o.native),assert(o.combat)
 local get_choices=assert(o.get_choices)
 local registry,reported,rebuilding,level_changes={},{},{},{};local cursor,world,stopped,last_tick,next_tick
 local birth_sequence=0
 local ensure_hatch_hook=function()return true end
 local api={}
 local function valid(v)return v~=nil and safe(function()return native.valid_object(v)end)==true end
 local function id(v)return valid(v)and tostring(v:GetAddress())end
 local function same(a,b)local x=id(a);return x~=nil and x==id(b)end
 local function fail(e)e=tostring(e);if not reported[e]then reported[e]=true;if o.log then o.log('[LittleBlackTwins] '..e)end end;return nil,e end
 local function values(a)
  if type(a)=='table'and type(a.GetArrayNum)~='function'then return a end
  local n=a and number(a:GetArrayNum());assert(n and n>=0 and n<=8192,'littleblack_twin_array_invalid')
  local out={};for i=1,n do out[i]=unbox(a[i])end;return out
 end
 local function has_marker(c)
  if not valid(c)then return false end
  for _,v in ipairs(values(c.Tags))do if text(v)==M.marker then return true end end
  -- TagsToRestore is populated before FinishSpawningActor during native load.
  local saved=safe(function()return c.TagsToRestore end)
  if saved then for _,v in ipairs(values(saved))do if text(v)==M.marker then return true end end end
  return false
 end
 local function mark(c)
  if has_marker(c)then return end
  local tags={};for _,v in ipairs(values(c.Tags))do tags[#tags+1]=v end
  tags[#tags+1]=FName(M.marker);c.Tags=tags
 end
 local function clear_newborn_marker(c)
  -- HatchAnt does not clear the nursery's saved tag template. A genuinely
  -- new primary can therefore inherit the last loaded sibling's marker.
  -- Only the exact first native hatch receipt authorizes removing it.
  for _,field in ipairs({'Tags','TagsToRestore'})do
   local source=safe(function()return c[field]end)
   if source then
    local retained,changed={},false
    for _,v in ipairs(values(source))do
     if text(v)==M.marker then changed=true else retained[#retained+1]=v end
    end
    if changed then c[field]=retained end
   end
  end
 end
 local function resolve(n,base,batch)
  if stopped or not valid(n)then return end
  local tile=unbox(safe(function()return n.OwningTile end))
  if not valid(tile)or number(tile.TileFunction)~=M.tile_type or not same(tile.FunctionRepresentation,n)then return end
  base=base or combat.get();if not base or base.is_arena or native.world_id(n)~=base.world_id then return end
  local owner=number(safe(function()return n:GetColonyID()end));if not owner or owner<0 or owner%1~=0 then return end
  local ctx=batch and batch.colonies[owner]
  if ctx==nil then
   ctx=combat.for_colony(owner,base)
   if batch then batch.colonies[owner]=ctx or false end
  end
  if not ctx or not valid(ctx.grid)or not same(tile:GetOwner(),ctx.grid)then return end
  return tile,ctx
 end
 local function slot(n,index)return unbox(safe(function()return n.Tennents[index]end))end
 local function capacity(n)return number(safe(function()return n.NoOfTennents end))end
 local function array_size(n)
  local a=n.Tennents;if type(a)=='table'and type(a.GetArrayNum)~='function'then return #a end
  return number(a:GetArrayNum())
 end
 local function known_form(n,ctx,batch)
  local has_queen=valid(ctx.queen)
  if has_queen and batch and batch.forms[ctx.owner]~=nil then return batch.forms[ctx.owner]or nil end
  local representative=has_queen and ctx.queen or slot(n,1)
  if not valid(representative)then representative=slot(n,2)end
  if not valid(representative)then return end
  local chosen=get_choices(representative,'LittleBlackAnt')
  local form=type(chosen)=='table'and chosen.form
  -- Unknown campaign data during load NEVER authorizes shrinking/killing.
  if form~='specialist'and form~='twin'then form=nil end
  if has_queen and batch then batch.forms[ctx.owner]=form or false end
  return form
 end
 function api.is_extra(c)
  if not valid(c)or text(c.CreatureName)~='LittleBlackAnt'then return false end
  local tile=unbox(safe(function()return c.NurseryTile end))
  if not valid(tile)or number(tile.TileFunction)~=M.tile_type then return false end
  local n=unbox(tile.FunctionRepresentation)
  if not valid(n)or not same(n.OwningTile,tile)then return false end
  -- Array positions are not identities: native alive counting compacts them.
  -- A native hatch receipt below is the only way to create a new marker.
  return has_marker(c)
 end
 function api.before_stats(c)
  local desired=api.extra_level(c)
  if stopped or not desired then return false end
  local key=id(c);local changed=number(c.CreatureLevel)~=desired
  if not rebuilding[key]then
   local pending=level_changes[key];local name=c:GetFullName()
   if not pending or pending.name~=name then
    pending={name=name,health=number(c.Health),rebuild=false};level_changes[key]=pending
   end
   pending.rebuild=pending.rebuild or changed
  end
  if changed then c.CreatureLevel=desired end
  return true
 end
 function api.extra_level(c)
  if not api.is_extra(c)then return end
  local tile=unbox(c.NurseryTile)
  local rank=number(safe(function()return tile:GetEffectiveTileUpgradeLevel()end))
  -- Incomplete restored tiles must not demote a saved rank-two sibling.
  if not rank or rank%1~=0 or rank<1 or rank>3 then return end
  return math.max(1,rank-1)
 end
 local function clamp_health(c)
  -- Native hatch finalization can copy the full tile-rank health after our
  -- rank-specific tables have already been corrected. Clamp against the live
  -- FullHealth (including cultivation), never heal an injured/dead sibling.
  local hp,maximum=number(c.Health),number(c.FullHealth)
  if hp and maximum and maximum>0 and hp>maximum then c.Health=maximum end
 end
 local function enforce_extra(c,desired,newborn_primary,confirmed_marked)
  if stopped or not desired then return true end
  if not newborn_primary and not confirmed_marked then mark(c)end
  local key=id(c);if rebuilding[key]then return true end
  local pending=level_changes[key]
  local matched=pending~=nil and pending.name==c:GetFullName()
  local changed=matched and pending.rebuild==true
  local before_health=matched and pending.health or number(c.Health)
  if number(c.CreatureLevel)==desired and not changed then
   if matched and before_health then
    local maximum=assert(number(c.FullHealth),'littleblack_twin_maximum_health_unreadable')
    c.Health=math.min(before_health,maximum);level_changes[key]=nil
   else clamp_health(c)end
   return true
  end
  if not before_health then return fail('littleblack_twin_health_unreadable')end
  local before_name=c:GetFullName()
  rebuilding[key]=true
  level_changes[key]=nil
  local ok,e=pcall(function()
   c.CreatureLevel=desired;c:LookupApplyStatsForLevel(true)
   -- Registration can happen after a hatchling already received the tile's
   -- full-rank abilities. Rebuild both native tables at the sibling rank,
   -- including when a pre-hook already corrected CreatureLevel. Never derive
   -- its rank with ChangeCreatureLevel, which would promote it to tile rank.
   c:LookupApplyAbilitiesForLevel(true)
   assert(number(c.CreatureLevel)==desired,'littleblack_twin_level_write_failed')
   clamp_health(c)
   if o.after_level_change then o.after_level_change(c)end
  end)
  -- PreventHeal still adds cultivated Health to current HP in the native
  -- lookup. Preserve the value from before our rank correction, including
  -- its pre-hook, on both success and failure. Zero/negative HP stays dead.
  local restored,restore_error=pcall(function()
   if not valid(c)or c:GetFullName()~=before_name then return end
   local maximum=assert(number(c.FullHealth),'littleblack_twin_maximum_health_unreadable')
   c.Health=math.min(before_health,maximum)
  end)
  rebuilding[key]=nil
  if not ok or not restored then
   if valid(c)then level_changes[key]={name=c:GetFullName(),health=before_health,rebuild=true}end
   return fail(not ok and e or restore_error)
  end
  return true
 end
 function api.enforce_extra(c)return enforce_extra(c,api.extra_level(c))end
 function api.observe(n)
  ensure_hatch_hook()
  local tile,ctx=resolve(n);if not tile then return false end
  if world~=ctx.world_id then registry={};cursor=nil;last_tick=nil;next_tick=nil;world=ctx.world_id end
  local key,name=id(n),n:GetFullName();local row=registry[key]
  if not row or row.name~=name then registry[key]={nursery=n,name=name,births={}}end
  return true
 end
 function api.observe_actor(c)
  if not valid(c)or text(c.CreatureName)~='LittleBlackAnt'then return false end
  local tile=unbox(safe(function()return c.NurseryTile end))
  if valid(tile)and number(tile.TileFunction)==M.tile_type then
   local n=unbox(tile.FunctionRepresentation)
   if valid(n)then api.observe(n)end
   return api.enforce_extra(c)
  end
  return false
 end
 local function alive(c)return valid(c)and(number(c.Health)or 0)>0 end
 local function members(n,tile)
  local living,marked={},{}
  local count=array_size(n)
  assert(count and count>=0 and count<=2,'littleblack_foreign_nursery_capacity')
  for i=1,count do
   local c=slot(n,i)
   if alive(c)then
    assert(text(c.CreatureName)=='LittleBlackAnt'and same(c.NurseryTile,tile),'littleblack_twin_foreign_tenant')
    living[#living+1]=c
    if has_marker(c)then marked[#marked+1]=c end
   end
  end
  return living,marked
 end
 local function classify_births(n,tile,ctx,form,rank)
  local living,marked=members(n,tile)
  if #marked>1 then return nil,'littleblack_twin_ambiguous_saved_markers' end
  local row=registry[id(n)]
  if not row or row.name~=n:GetFullName()then return living,marked end
  local present,pending={},{}
  for _,c in ipairs(living)do
   local key=id(c);present[key]=true
   local receipt=row.births[key]
   if receipt and(receipt.name~=c:GetFullName()or receipt.world~=ctx.world_id)then row.births[key]=nil;receipt=nil end
   if receipt and receipt.role=='pending'then pending[#pending+1]={creature=c,receipt=receipt}end
  end
  -- A callback can precede final tenant registration. Keep that exact new
  -- object until registration, but discard dead/invalid/reused identities.
  for key,receipt in pairs(row.births)do
   if not present[key]and(not alive(receipt.creature)or receipt.creature:GetFullName()~=receipt.name
    or native.world_id(receipt.creature)~=ctx.world_id or not same(receipt.creature.NurseryTile,tile))then row.births[key]=nil end
  end
  if form~='twin'or rank<2 then
   for _,entry in ipairs(pending)do entry.receipt.role='primary'end
   return living,marked
  end
  local ordinary={}
  for _,entry in ipairs(pending)do
   if entry.receipt.expected_role=='extra'then
    -- An exact, synchronous free-birth ticket can identify a sibling even
    -- when the primary is currently absent. It never authorizes a second one.
    if #marked>0 then return nil,'littleblack_twin_duplicate_expected_sibling'end
    mark(entry.creature);entry.receipt.role='extra';marked[1]=entry.creature
   else ordinary[#ordinary+1]=entry end
  end
  pending=ordinary
  if #marked==1 or #living==1 then
   for _,entry in ipairs(pending)do entry.receipt.role='primary'end
  elseif #living==2 and #pending>0 then
   table.sort(pending,function(a,b)return a.receipt.sequence<b.receipt.sequence end)
   local entry=pending[#pending]
   -- Only this positively identified native newborn is claimed. An older
   -- unmarked occupant is left untouched, including unknown legacy records.
   mark(entry.creature);entry.receipt.role='extra';marked[1]=entry.creature
   for i=1,#pending-1 do pending[i].receipt.role='primary'end
  end
  return living,marked
 end
 local function normalize_birth(c,tile,receipt)
  if receipt.normalization=='done'then return true end
  if receipt.normalization=='running'then return false end
  if not receipt.birth_prepared then
   if o.on_native_birth then
    local good,why=o.on_native_birth(unbox(tile.FunctionRepresentation),c)
    if good==nil then return fail(why or'littleblack_birth_prepare_failed')end
   end
   receipt.birth_prepared=true
  end
  local rank=number(tile:GetEffectiveTileUpgradeLevel())
  if not rank or rank%1~=0 or rank<1 or rank>3 then return fail('littleblack_newborn_rank_unavailable')end
  local hp=number(c.Health)
  -- A failed native lookup may be retried on the next reconciliation. Do
  -- not turn that retry into a heal if the newborn took damage meanwhile.
  if not hp or hp<=0 then return false end
  if receipt.last_health and hp<receipt.last_health then receipt.restore_full=false end
  receipt.normalization='running'
  local ok,why=pcall(function()
   clear_newborn_marker(c)
   local key=id(c)
   -- Force both tables even if an earlier partial attempt already set rank.
   level_changes[key]={name=c:GetFullName(),health=hp,rebuild=true}
   local changed,e=enforce_extra(c,rank,true);assert(changed,e)
   if receipt.restore_full then c.Health=assert(number(c.FullHealth),'littleblack_newborn_maximum_health_unreadable')end
  end)
  receipt.last_health=number(c.Health)
  receipt.normalization=ok and'done'or'pending'
  if not ok then return fail(why)end
  return true
 end
 function api.finish_hatch(n,c)
  if stopped or not valid(c)or text(c.CreatureName)~='LittleBlackAnt'then return false end
  local tile=unbox(safe(function()return c.NurseryTile end))
  local actual,ctx=resolve(n)
  if not actual or not same(actual,tile)or native.world_id(c)~=ctx.world_id then return false end
  -- Only the exact completed FinishSpawningAnt output proves a native birth.
  -- LoadSpawn=true is the separate native restore path and keeps saved tags.
  if safe(function()return n.LoadSpawn end)~=false then return false end
  if not api.observe(n)then return false end
  local row=registry[id(n)];local key,name=id(c),c:GetFullName();local receipt=row.births[key]
  if not receipt or receipt.name~=name then
   local expected=o.expected_birth_role and o.expected_birth_role(n,c)or nil
   assert(expected==nil or expected=='extra','littleblack_birth_role_invalid')
   birth_sequence=birth_sequence+1
   local hp,maximum=number(c.Health),number(c.FullHealth)
   receipt={creature=c,name=name,world=ctx.world_id,sequence=birth_sequence,role='pending',
    expected_role=expected,birth_prepared=false,
    normalization='pending',restore_full=hp and maximum and maximum>0 and hp>=maximum,last_health=hp}
   row.births[key]=receipt
  end
  if alive(c)then
   local ok,why=normalize_birth(c,tile,receipt);if not ok then return ok,why end
  end
  local ok,why=api.reconcile(n)
  if ok==nil then return nil,why end
  return true
 end
 function api.reconcile(n,base,batch)
  local ok,result=pcall(function()
   local tile,ctx=resolve(n,base,batch);if not tile then return false end
   local row=registry[id(n)]
   if row and row.name==n:GetFullName()then
    for _,receipt in pairs(row.births)do
     local c=receipt.creature
     if receipt.normalization~='done'and alive(c)and c:GetFullName()==receipt.name
      and receipt.world==ctx.world_id and native.world_id(c)==ctx.world_id and same(c.NurseryTile,tile)then
      local normalized,why=normalize_birth(c,tile,receipt);assert(normalized,why)
     end
    end
   end
   local form=known_form(n,ctx,batch)
   if not form then return {deferred='form_unresolved',capacity=capacity(n)}end
   local rank=number(tile:GetEffectiveTileUpgradeLevel())
   if not rank or rank<1 or rank>3 then return {deferred='tile_rank_unresolved'}end
   local wanted=form=='twin'and rank>=2 and 2 or 1
   local before=capacity(n);local count=array_size(n)
   assert((before==1 or before==2)and count and count>=0 and count<=2,'littleblack_foreign_nursery_capacity')
   local living,marked=classify_births(n,tile,ctx,form,rank)
   assert(living,marked)
   if wanted==2 then
    if before~=2 then n.NoOfTennents=2 end
    if count<2 then n:InitaliseTennancyArray(2)end
    assert(capacity(n)==2 and array_size(n)==2,'littleblack_twin_capacity_failed')
    -- A stable full-capacity nursery has no native mutating call between
    -- classify_births' marker check and this enforcement. Reuse that exact
    -- synchronous result only here. Array initialization, independent actor
    -- observation and native stat/birth entrypoints retain mark's own check.
    local confirmed_marked=before==2 and count==2
    for _,extra in ipairs(marked)do assert(enforce_extra(extra,math.max(1,rank-1),false,confirmed_marked))end
   elseif before>1 or count>1 then
    assert(#living-#marked<=1,'littleblack_twin_unmarked_shrink_refused')
    -- Kill only the marked sibling. It may be at index zero after a primary
    -- death; ReduceAndKillTennents(1) would blindly kill the replacement.
    local extra=marked[1]
    if extra then
     if o.before_remove_extra then local good,why=o.before_remove_extra(extra);assert(good~=nil,why)end
     extra:KillCreature(nil);assert(not alive(extra),'littleblack_twin_shrink_death_blocked')
    end
    n:CountAliveTennents(false)
    local remaining,remaining_marked=members(n,tile)
    assert(#remaining<=1 and #remaining_marked==0,'littleblack_twin_shrink_identity_failed')
    n.NoOfTennents=1
    if array_size(n)~=1 then n:InitaliseTennancyArray(1)end
    assert(capacity(n)==1 and array_size(n)==1,'littleblack_twin_shrink_failed')
   end
   if row and o.after_native_birth then
    for _,receipt in pairs(row.births)do
     local c=receipt.creature
     if receipt.normalization=='done'and receipt.role~='pending'and not receipt.birth_notified
      and alive(c)and c:GetFullName()==receipt.name and native.world_id(c)==ctx.world_id and same(c.NurseryTile,tile)then
      local good,why=o.after_native_birth(n,c);assert(good~=nil,why)
      receipt.birth_notified=true
     end
    end
   end
   local result={capacity=wanted,changed=before~=wanted,form=form,rank=rank}
   if o.after_reconcile then local good,why=o.after_reconcile(n,result);assert(good~=nil,why)end
   return result
  end)
  if not ok then return fail(result)end;return result
 end
 function api.tick(now)
  if stopped then return true end
  ensure_hatch_hook()
  local ctx=combat.get();if not ctx then return true end
  if world and world~=ctx.world_id then registry={};cursor=nil;last_tick=nil;next_tick=nil end;world=ctx.world_id
  -- Native birth/level/tenant hooks still correct siblings immediately. This
  -- pass only catches restored/new nurseries and native hatch finalization;
  -- spread the previous 24-per-0.2s burst into at most six checks per callback.
  -- Keep the per-nursery 0.2s floor so small colonies do not do more work.
  now=number(now)or number(safe(function()return ctx.gs:GetLevelTime()end))
  if now and last_tick and now<last_tick then cursor=nil;next_tick=nil end
  last_tick=now
  if now then
   if next_tick and now<next_tick-0.00001 then return true end
   next_tick=(next_tick or now)+M.batch_interval
   -- Carry a slightly late deadline forward, but never catch up missed batches
   -- after a pause/stall in one callback.
   if next_tick<=now then next_tick=now+M.batch_interval end
  else next_tick=nil end
  local batch={colonies={},forms={}}
  local visited,current_registry={},registry
  for _=1,M.batch_size do
   if cursor and not registry[cursor]then cursor=nil end
   local key,row=next(registry,cursor)
   if not key then cursor=nil;key,row=next(registry)end
   if not key or visited[key]then break end;visited[key]=true
   if not now or not row.maintenance_time or now<row.maintenance_time or now-row.maintenance_time>=M.tick_interval-0.00001 then
    if not valid(row.nursery)or row.nursery:GetFullName()~=row.name or native.world_id(row.nursery)~=ctx.world_id then registry[key]=nil
    else
     row.maintenance_time=now
     local ok,e=api.reconcile(row.nursery,ctx,batch);if ok==nil then fail(e)end
     -- Native callbacks may reset/replace the registry during reconciliation.
     -- Do not carry an old world's cursor into the replacement registry.
     if registry~=current_registry then break end
     cursor=key
    end
   else cursor=key end
  end
  return true
 end
 function api.reset_cache()registry={};cursor=nil;world=nil;last_tick=nil;next_tick=nil;rebuilding={};level_changes={};birth_sequence=0;return true end
 function api.stop()stopped=true;return api.reset_cache()end
 function api.status()local n=0;for _ in pairs(registry)do n=n+1 end;return{nurseries=n,world=world,stopped=stopped==true}end
 if o.register_hooks~=false then
  local hook=o.register_hook or RegisterHook
  hook('/Script/EotU.Creature:LookupApplyStatsForLevel',function(c)api.before_stats(unbox(c))end,function(c)api.observe_actor(unbox(c))end)
  hook('/Script/EotU.Creature:LookupApplyAbilitiesForLevel',function(c)api.before_stats(unbox(c))end,function(c)api.observe_actor(unbox(c))end)
  hook('/Script/EotU.Creature:ChangeCreatureLevel',function(c)api.before_stats(unbox(c))end,function(c)api.observe_actor(unbox(c))end)
  local hatch_path='/Game/Blueprints/WorldConstruction/NurseryRepresentationBP.NurseryRepresentationBP_C:FinishSpawningAnt'
  local hatch_registered=false
  ensure_hatch_hook=function()
   if stopped or hatch_registered then return hatch_registered end
   -- This Blueprint can be absent at module startup. Nursery observation
   -- retries after its class is loaded; no failed hook can abort the mod.
   if not o.register_hook and not valid(safe(function()return StaticFindObject(hatch_path)end))then return false end
   local ok,why=pcall(hook,hatch_path,function(n,health,c)
    -- UE4SS script hooks run their first callback after the BP body. The
    -- third argument is its creature OutParm (there is no ReturnParm).
    local ran,e=pcall(api.finish_hatch,unbox(n),unbox(c));if not ran then fail(e)end
   end)
   if not ok then fail(why);return false end
   hatch_registered=true;return true
  end
  ensure_hatch_hook()
  -- Both functions return bool (the generated CXX header incorrectly says
  -- void). UE4SS inserts ReturnValue before the native input parameters.
  local function registered(n,result,c)
   api.observe(unbox(n))
   if unbox(result)==true then api.observe_actor(unbox(c))end
  end
  hook('/Script/EotU.NurseryRepresentation:AttemptToRegTennant',function()end,registered)
  hook('/Script/EotU.NurseryRepresentation:RegTennantIntoSpesificPosition',function()end,registered)
 end
 return api
end
return M
