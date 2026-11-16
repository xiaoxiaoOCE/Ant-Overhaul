-- Little black ant combat coordination. Import is inert; main supplies the
-- current-world actor registry, so no skill performs an object scan per frame.
local M={species='LittleBlackAnt',tick_interval=0.1,source_batch_limit=20,guard_radius=200,guard_count=16,charm_target_radius=200,
 signal_probability=0.1,signal_seconds=6,signal_max=3,charm_seconds=2.5,medium_immunity=5}
local function safe(f)local ok,v=pcall(f);if ok then return v end end
-- Native value wrappers are already the value. Trying a reflected get() on a
-- UScriptStruct raises an expensive native exception for every effect row.
-- Unknown wrappers (including RemoteUnrealParam) keep the original unwrap.
local ue_values={AActor=true,UWorld=true,UObject=true,UScriptStruct=true,FNameUserdata=true,TArray=true}
local function unbox(v)
 local kind=type(v)
 if kind=='nil'or kind=='number'or kind=='string'or kind=='boolean'then return v end
 if kind=='userdata'then
  local getter=type(debug)=='table'and rawget(debug,'getmetatable')
  if type(getter)=='function'then
   local ok,mt=pcall(getter,v)
   if ok and type(mt)=='table'and ue_values[rawget(mt,'__name')]then return v end
  end
 end
 local ok,x=pcall(function()return v:get()end);if ok then return x end;return v
end
local function num(v)local n=tonumber(unbox(v));if n and n==n and math.abs(n)<math.huge then return n end end
local function name(v)v=unbox(v);return type(v)=='string'and v or v and safe(function()return v:ToString()end)end
local function each(a,f)
 if not a then return end
 if type(a)=='table'and type(a.GetArrayNum)~='function'then for i,v in ipairs(a)do f(v,i)end;return end
 local n=a:GetArrayNum();assert(n>=0 and n<=65536,'littleblack_array_invalid');for i=1,n do f(unbox(a[i]),i)end
end
local function equal(a,b)return a and b and math.abs(a-b)<=math.max(1e-6,math.abs(a)*1e-6)end
function M.install(o)
 assert(type(o)=='table'and o.native and o.get_context and o.get_choices,'littleblack_dependencies')
 local native,adapter=o.native,o.adapter or{}
 local registry,sources,fields,buffs,charms,immune,pending={},{},{},{},{},{},{}
 local charm_addresses={}
 local grid,world,last_tick,stopped,choices_epoch,index_time={},nil,nil,false,0,nil
 local source_queue,source_head,source_tail,guard_sources,source_generation={},1,0,0,0
 local registry_serial,registry_phase=0,0
 local signal_rows,signal_time,signal_world,signal_serial,signal_class={},nil,nil,nil,nil
 local charm_rows,charm_index_time,charm_index_world,charm_scan_work={},nil,nil,0
 local choices_scope=false
 local hooks,reported={},{}
 local signal_prepare_requested=false
 local stats={observed=0,deaths=0,rolls=0,signals=0,confused=0,buffs=0,charms=0,
  charm_refreshes=0,charm_fallbacks=0,charm_basic_hits=0,charm_index_builds=0,charm_searches=0,charm_position_reads=0,charm_grid_fallbacks=0,charm_geometry_checks=0,charm_geometry_rejections=0,charm_geometry_fallbacks=0,guard_writes=0,ticks=0,source_visits=0,source_batch_max=0,index_builds=0,signal_snapshots=0,signal_queries=0,signal_position_reads=0,signal_local_rows=0,signal_full_fallbacks=0,visual_errors=0,last_visual_error=nil,last_error=nil}
 local api={}
 local function fail(e)e=tostring(e);stats.last_error=e;if not reported[e]then reported[e]=true;if o.log then pcall(o.log,'[LittleBlack] '..e)end end;return nil,e end
 local function visual_call(method,...)
  if type(adapter[method])~='function'then return end
  local ok,result,why=pcall(adapter[method],...)
  if not ok or result~=true then
   local e=tostring(ok and why or result);stats.visual_errors=stats.visual_errors+1;stats.last_visual_error=e
   if not reported[e]then reported[e]=true;if o.log then pcall(o.log,'[LittleBlack visual] '..e)end end
  end
 end
 local function valid(c)return c~=nil and safe(function()return native.valid_object(c)end)==true end
 local function key(c)
  if not valid(c)then return nil end
  local a=safe(function()return c:GetAddress()end);local n=safe(function()return c:GetFullName()end)
  if a~=nil and type(n)=='string'then return tostring(a)..'|'..n end
 end
 local function callback_address(c)
  local a=c~=nil and safe(function()return c:GetAddress()end)or nil
  if a~=nil then return tostring(a)end
 end
 local function might_be_charmed(c)
  if next(charms)==nil then return false end
  local a=callback_address(c)
  -- This map can only reject. Unknown addresses and every map hit still use
  -- the full live identity, world, ownership and target checks below.
  return a==nil or charm_addresses[a]~=nil
 end
 local function context()
  local ctx=o.get_context();local gs=ctx and(ctx.gs or ctx.game_state)
  if not valid(gs)then return nil end
  return ctx,gs,native.world_id(gs),num(gs:GetLevelTime())
 end
 local function eligible(c,gs,w)
  if not valid(c)or native.world_id(c)~=w then return false end
  if o.combat then return o.combat.eligible(c,gs)==true end
  return num(c.ColonyID)~=nil
 end
 local function alive(c)return valid(c)and(num(c.Health)or 0)>0 end
 local function little(c)return name(safe(function()return c.CreatureName end))==M.species end
 local function choices(c,verified_key)
  local k=verified_key or key(c);local r=k and registry[k]
  if choices_scope and r and r.choices_epoch==choices_epoch then return r.choices end
  local value=o.get_choices(c,M.species)or{}
  if choices_scope and r then r.choices_epoch=choices_epoch;r.choices=value end
  return value
 end
 local function pos(c)
  local p=adapter.position and adapter.position(c)or c:K2_GetActorLocation()
  if p then local x,y,z=num(p.X or p.x),num(p.Y or p.y),num(p.Z or p.z);if x and y and z then return{x=x,y=y,z=z}end end
 end
 local function distance(a,b)local x,y,z=a.x-b.x,a.y-b.y,a.z-b.z;return x*x+y*y+z*z end
 local function allied(a,b)
  if adapter.allied then return adapter.allied(a,b)==true end
  return safe(function()return a:AmIAlliedWith(b.ColonyID,b.AlliedWithAllNoneColony==true)end)==true
 end
 local function active_health(c)
  if(num(c.Health)or 0)<=0 then return false end
  if adapter.is_incapacitated and adapter.is_incapacitated(c)==true then return false end
  return true
 end
 local function active_fields(c)
  if not active_health(c)then return false end
  local layer=num(c.ColonyLocation);return layer~=nil and layer>=-1
 end
 local function active(c)return valid(c)and active_fields(c)end
 local function bucket(layer,x,y)return layer..':'..x..':'..y end
 local function receipt(c,k)
  registry_serial=registry_serial+1
  return{creature=c,key=k,prune_phase=registry_serial%16}
 end
 local function discard(r)
  if registry[r.key]==r then registry[r.key]=nil end
 end
 local function rebuild(w,now)
  stats.index_builds=stats.index_builds+1
  local next_grid={};local generation=source_generation
  local class=safe(function()return StaticFindObject('/Script/EotU.Creature')end)
  local coarse=valid(class)
  registry_phase=(registry_phase+1)%16
  for k,r in pairs(registry)do
   local c=r.creature
   local include,strict=false,not coarse
   if coarse then
    if not valid(c)then discard(r)
    else
     -- Geometry is never authority. IsA still protects the reflected actor
     -- access below if an address has been reused for a different class.
     local ok,is_creature=pcall(function()return c:IsA(class)end)
     if not ok or type(is_creature)~='boolean'then strict=true
     elseif not is_creature then discard(r)
     elseif r.prune_phase==registry_phase and(key(c)~=k or native.world_id(c)~=w)then discard(r)
     else include=true end
    end
   end
   if strict then
    -- Missing class/IsA bindings retain the previous conservative builder.
    if key(c)~=k or native.world_id(c)~=w then discard(r)
    elseif active_fields(c)then include=true end
   end
   if include then
    local p=pos(c);local layer=num(c.ColonyLocation)
    if p and layer and layer>=-1 then
     local b=bucket(layer,math.floor(p.x/200),math.floor(p.y/200));local cell=next_grid[b]
     if not cell then cell={groups={},group_for={}};next_grid[b]=cell end
     cell[#cell+1]=r
     -- These fields belong to the same short-lived spatial snapshot as the
     -- position. They may only exclude a group, never authorize a candidate.
     local ok,owner,flag=pcall(function()return c.ColonyID,c.AlliedWithAllNoneColony end)
     if ok and type(owner)=='number'and num(owner)==owner and owner%1==0
      and(flag==nil or type(flag)=='boolean')then
      flag=flag==true;local gk=tostring(owner)..':'..tostring(flag)
      local group=cell.groups[gk]
      if not group then group={owner=owner,flag=flag};cell.groups[gk]=group end
      cell.group_for[r]=group
     end
    end
   end
   if generation~=source_generation then return end
  end
  -- Each receipt gets a full identity/world sweep within sixteen builds,
  -- including distant or wrong-alliance objects that no query will consume.
  grid=next_grid;index_time=now
 end
 local function index_due(now)
  return not index_time or not now or now<index_time or now-index_time>=M.tick_interval
 end
 local function ensure_index(w,now)
  if index_due(now)then rebuild(w,now)end
 end
 local function signal_grid(source,radius,w,now)
  -- Share receipt enumeration, never positions or ownership, between deaths
  -- in the same frame. A time-only spatial cache misses same-frame jumps and
  -- newly registered births. Every signal samples current geometry afresh.
  local generation,serial=source_generation,registry_serial
  if not valid(source)or native.world_id(source)~=w then return end
  local center=pos(source);local layer=num(source.ColonyLocation)
  if not center or not layer or layer< -1 then return end
  if signal_time~=now or signal_world~=w or signal_serial~=serial then
   local rows={};for _,r in pairs(registry)do rows[#rows+1]=r end
   signal_rows,signal_time,signal_world,signal_serial=rows,now,w,serial
   stats.signal_snapshots=stats.signal_snapshots+1
  end
  if not valid(signal_class)then signal_class=safe(function()return StaticFindObject('/Script/EotU.Creature')end)end
  local class=signal_class;local coarse=valid(class);local local_grid={}
  registry_phase=(registry_phase+1)%16
  local lowx,highx=math.floor((center.x-radius)/200),math.floor((center.x+radius)/200)
  local lowy,highy=math.floor((center.y-radius)/200),math.floor((center.y+radius)/200)
  stats.signal_queries=stats.signal_queries+1
  for _,r in ipairs(signal_rows)do
   if generation~=source_generation then return end
   if serial~=registry_serial then return nil,nil,true end
   if registry[r.key]==r then
    local c=r.creature;local include,strict=false,not coarse
    if coarse then
     if not valid(c)then discard(r)
     else
      local ok,is_creature=pcall(function()return c:IsA(class)end)
      if not ok or type(is_creature)~='boolean'then strict=true
      elseif not is_creature then discard(r)
      elseif r.prune_phase==registry_phase and(key(c)~=r.key or native.world_id(c)~=w)then discard(r)
      else include=true end
     end
    end
    if strict then
     if key(c)~=r.key or native.world_id(c)~=w then discard(r)
     elseif active_fields(c)then include=true end
    end
    if generation~=source_generation then return end
    if serial~=registry_serial then return nil,nil,true end
    if include then
     -- Distant actors need no cell/group allocation or owner reflection.
     -- Layer and position are live; this is still a whole-receipt geometry
     -- pass, not a claim that worst-case signal work is sublinear.
     local current_layer=num(c.ColonyLocation)
     if current_layer==layer then
      local p=pos(c);stats.signal_position_reads=stats.signal_position_reads+1
      if generation~=source_generation then return end
      if serial~=registry_serial then return nil,nil,true end
      if p then
       local x,y=math.floor(p.x/200),math.floor(p.y/200)
       if x>=lowx and x<=highx and y>=lowy and y<=highy then
        local b=bucket(layer,x,y);local cell=local_grid[b]
        if not cell then cell={groups={},group_for={}};local_grid[b]=cell end
        cell[#cell+1]=r;stats.signal_local_rows=stats.signal_local_rows+1
        local ok,owner,flag=pcall(function()return c.ColonyID,c.AlliedWithAllNoneColony end)
        if ok and type(owner)=='number'and num(owner)==owner and owner%1==0
         and(flag==nil or type(flag)=='boolean')then
         flag=flag==true;local gk=tostring(owner)..':'..tostring(flag)
         local group=cell.groups[gk]
         if not group then group={owner=owner,flag=flag};cell.groups[gk]=group end
         cell.group_for[r]=group
        end
       end
      end
     end
    end
   end
  end
  if generation~=source_generation then return end
  if serial~=registry_serial then return nil,nil,true end
  if not valid(source)or native.world_id(source)~=w then return end
  local current=pos(source)
  if generation~=source_generation then return end
  if not valid(source)or native.world_id(source)~=w then return end
  -- A reentrant adapter may move the source while sampling. Retain the old
  -- fresh full-index path for that uncommon case instead of querying a box
  -- centred on its former position.
  if serial~=registry_serial or not current or num(source.ColonyLocation)~=layer
   or current.x~=center.x or current.y~=center.y or current.z~=center.z then return nil,nil,true end
  return local_grid,center
 end
 local function nearby(c,radius,center,fn,prefilter,preferred,relation,indexed_candidate,query_grid)
  query_grid=query_grid or grid
  center=center or pos(c);local layer=num(c.ColonyLocation)
  if not center or not layer then return end
  local lowx,highx=math.floor((center.x-radius)/200),math.floor((center.x+radius)/200)
  local lowy,highy=math.floor((center.y-radius)/200),math.floor((center.y+radius)/200)
  local memo_set,memo_source,memo_source_flag,memo_owner,memo_flag,memo_allied=false
  local group_epoch,group_answers=0,{}
  local function excluded_group(group)
   if not group or type(relation)~='boolean'or adapter.allied then return false end
   local prior=group_answers[group]
   if prior and prior.epoch==group_epoch then return prior.excluded end
   if not valid(c)then return false end
   local friend=safe(function()return c:AmIAlliedWith(group.owner,group.flag)end)
   if type(friend)~='boolean'then group_answers[group]={epoch=group_epoch,excluded=false};return false end
   local excluded=friend~=relation
   group_answers[group]={epoch=group_epoch,excluded=excluded}
   return excluded
  end
  local function excluded(v)
   if relation==nil or adapter.allied then return false end
   if not memo_set and not valid(c)then return true end
   local ok,source_owner,source_flag,owner,flag=pcall(function()
    return c.ColonyID,c.AlliedWithAllNoneColony==true,v.ColonyID,v.AlliedWithAllNoneColony==true
   end)
   if not ok then memo_set=false;return false end
   local friend
   if memo_set and source_owner==memo_source and source_flag==memo_source_flag
    and owner==memo_owner and flag==memo_flag then friend=memo_allied
   else
    friend=safe(function()return c:AmIAlliedWith(owner,flag)end)
    memo_set=type(friend)=='boolean'
    memo_source,memo_source_flag,memo_owner,memo_flag,memo_allied=source_owner,source_flag,owner,flag,friend
   end
   return(not not friend)~=relation
  end
  local function visit(r)
   local v=r.creature
    if not valid(v)then discard(r);return end
    if excluded(v)then return end
    -- Only a consecutive run of rejected native-read-only candidates shares
    -- an alliance answer. Any possible match clears it before health/KO,
    -- custom predicates or effects can call an adapter and reenter gameplay.
    -- Passing candidates still execute the original live alliance predicate.
    memo_set=false
    -- A possible match can call KO, position, target or effect adapters. Do
    -- not carry group answers across any such reentrant gameplay boundary.
    group_epoch=group_epoch+1
    -- A coarse bucket may contain dead, foreign or address-reused actors.
    -- Match the full live identity before any candidate can reach an effect;
    -- stale grid receipts never grant authority after registry replacement.
    if key(v)~=r.key or registry[r.key]~=r then discard(r);return end
    if active_health(v)then
     if native.world_id(v)~=world then discard(r);return end
     -- Read the layer after the health/KO and world checks, once per visit.
     local current_layer=num(v.ColonyLocation)
     if current_layer and current_layer>=-1 and current_layer==layer and(not prefilter or prefilter(v,r))then
      local p=pos(v);local d=p and distance(center,p)
      if d and d<=radius*radius and fn(v,r,p,d)==false then return true end
     end
    end
  end
  -- A single freshly checked rebuild candidate can prove that an existing
  -- charm still has a target. Check its would-be bucket as well as all normal
  -- live query predicates; this does not publish or advance the global index.
  if indexed_candidate then
   local b=indexed_candidate
   -- A retained target can prove its current eligibility directly. visit still
   -- checks identity, world, HP/KO, layer, allegiance, targetability and live
   -- 3D distance; old spatial buckets are not authority for this one receipt.
   if b.direct_fresh or(b.layer==layer and b.x>=lowx and b.x<=highx and b.y>=lowy and b.y<=highy)then visit(b.row)end
   return
  end
  -- Existing small charms only need proof that a legal target still exists;
  -- their refresh path does not use a newly chosen nearest target. Prefer the
  -- old target only if it occurs in this exact index query, then validate it
  -- just like any other candidate. An invalid/moved target uses the full path.
  if preferred then
   for x=lowx,highx do for y=lowy,highy do
    for _,r in ipairs(query_grid[bucket(layer,x,y)]or{})do
     if r.creature==preferred and visit(r)then return end
    end
   end end
  end
  for x=lowx,highx do for y=lowy,highy do
   local cell=query_grid[bucket(layer,x,y)]or{}
   -- Keep flat receipt order (including equal-distance target ties). Skipped
   -- groups cost only Lua table reads, with no per-actor engine reflection.
   for _,r in ipairs(cell)do
    if not excluded_group(cell.group_for and cell.group_for[r])and visit(r)then return end
   end
  end end
 end
 local function restore(c)
  local k=key(c);local row=k and fields[k]
  if row then if equal(num(c.AOEResistance),row.after)then c.AOEResistance=row.base end;fields[k]=nil end
  return{changed=row~=nil}
 end
 local function retire_source(k,r,w)
  if fields[k]then
   if valid(r.creature)and native.world_id(r.creature)==w and key(r.creature)==k then restore(r.creature)end
   fields[k]=nil
  end
  if r.guard_needed then r.guard_needed=nil;guard_sources=guard_sources-1 end
  sources[k]=nil
 end
 local function decorate(c,rebase)
  local k=key(c);if not k then return{changed=false}end
  local _,gs,w,now=context()
  if stopped or not gs or not eligible(c,gs,w)or not active(c)or not little(c)or choices(c).right~='swarm_guard'then return restore(c)end
  -- Attribute callbacks can arrive between maintenance passes. Group-negative
  -- ownership snapshots must obey the same index deadline on this entry too.
  ensure_index(w,now)
  local count=0
  nearby(c,M.guard_radius,nil,function()count=count+1;if count>=M.guard_count then return false end end,
   function(v,r)return r.key~=k and allied(c,v)end,nil,true)
  local prior=not rebase and fields[k]or nil;local current=assert(num(c.AOEResistance),'littleblack_aoe_invalid')
  local base=prior and equal(current,prior.after)and prior.base or current
  local desired=count>=M.guard_count and 1-(1-math.max(0,math.min(1,base)))*0.7 or base
  if not equal(current,desired)then c.AOEResistance=desired;assert(equal(num(c.AOEResistance),desired),'littleblack_aoe_write_failed');stats.guard_writes=stats.guard_writes+1 end
  fields[k]=count>=M.guard_count and{creature=c,base=base,after=desired}or nil
  return{changed=not equal(current,desired),neighbors=count,active=count>=M.guard_count}
 end
 function api.before_attributes(c)local ok,r=pcall(restore,c);if not ok then return fail(r)end;return r end
 function api.decorate(c,rebase)local ok,r=pcall(decorate,c,rebase);if not ok then return fail(r)end;return r end
 function api.forget(c)
  local k=key(c);if not k then return false end
  -- Native has already rebuilt these stats. Drop only our old numeric overlay;
  -- restoring it now would overwrite the new tier/cultivation baseline.
  fields[k]=nil;if registry[k]then registry[k].choices_epoch=nil end;return true
 end
 function api.observe(c)
  local ok,r=pcall(function()
   if stopped then return false end
   local _,gs,w=context();if not gs or not eligible(c,gs,w)then return false end
   if world and world~=w then api.reset_cache()end;world=w
   local k=key(c);if not k then return false end
   if not registry[k]then registry[k]=receipt(c,k);stats.observed=stats.observed+1 end
   registry[k].choices_epoch=nil
   if little(c)then
    if not sources[k]and not registry[k].death_seen then
     sources[k]=registry[k];source_tail=source_tail+1;source_queue[source_tail]=registry[k]
    end
    if alive(c)then registry[k].seen_alive=true end
   end
   return true
  end);if not ok then return fail(r)end;return r
 end
 local function attack_changed(c)
  local b=buffs[key(c)];local _,_,_,now=context();local remaining=0
  if b and now then for _,t in ipairs(b.expiries)do remaining=math.max(remaining,t-now)end end
  if adapter.update_attack_signal then
   local ok,why=adapter.update_attack_signal(c,api.attack_multiplier(c),remaining,b and b.source)
   assert(ok==true,why or'littleblack_attack_signal_update_failed')
  end
  if o.on_attack_signal_change then o.on_attack_signal_change(c,api.attack_multiplier(c))end
 end
 function api.attack_multiplier(c)
  local k=key(c);local b=k and buffs[k];local _,_,_,now=context();local count=0
  if b and now then for _,expiry in ipairs(b.expiries)do if now<expiry then count=count+1 end end end
  return 1+0.1*count
 end
 local function add_buff(c,now,source)
  local k=assert(key(c));local b=buffs[k]or{creature=c,expiries={}};local live={}
  for _,t in ipairs(b.expiries)do if now<t then live[#live+1]=t end end
  if #live>=M.signal_max then return false end
  live[#live+1]=now+M.signal_seconds;b.expiries=live;b.source=source;buffs[k]=b;attack_changed(c);stats.buffs=stats.buffs+1;return true
 end
 local function confuse(source,v,duration)
  if v.CannotBeConfused==true or not active(v)then return false end
  assert(type(adapter.confuse)=='function','littleblack_confusion_adapter_missing')
  local ok,why=adapter.confuse(source,v,duration);assert(ok==true,why or'littleblack_confuse_failed');stats.confused=stats.confused+1;return true
 end
 function api.on_death(c)
  local ok,r=pcall(function()
   if stopped or not valid(c)or not little(c)or(num(c.Health)or 1)>0 then return false end
   local _,gs,w,now=context();if not now or not eligible(c,gs,w)then return false end
   if adapter.is_incapacitated and adapter.is_incapacitated(c)==true then return false end
   local k=key(c);local row=registry[k]or receipt(c,k);registry[k]=row
   if row.death_seen then return false end;row.death_seen=true;stats.deaths=stats.deaths+1
   local branch=choices(c).left;if branch~='confusion_signal'and branch~='attack_signal'then return false end
   local roll=(o.random or math.random)();assert(num(roll)and roll>=0 and roll<1,'littleblack_roll_invalid');stats.rolls=stats.rolls+1
   if roll>=M.signal_probability then return false end
   visual_call('emit_signal',c,now)
   local level=math.max(1,math.min(3,num(c.CreatureLevel)or 1));local radius=35+5*level;local duration=1.2+0.3*level
   local query_grid,center,fallback=signal_grid(c,radius,w,now)
   if fallback then
    stats.signal_full_fallbacks=stats.signal_full_fallbacks+1
    local generation=source_generation;rebuild(w,now)
    if generation~=source_generation or not valid(c)or native.world_id(c)~=w then return false end
   elseif not query_grid then return false end
   nearby(c,radius,center,function(v)
    if branch=='confusion_signal'then confuse(c,v,duration)else add_buff(v,now,c)end
   end,function(v)return(not not allied(c,v))==(branch=='attack_signal')end,nil,branch=='attack_signal',nil,query_grid)
   stats.signals=stats.signals+1;return true
  end);if not ok then return fail(r)end;return r
 end
 local function choose_charm_target(v,preferred,indexed_candidate)
  local best,best_distance;local vp=pos(v);if not vp then return nil end
  -- Only nearby original allies are eligible, never a map-wide forced march.
  local vk=key(v)
  nearby(v,M.charm_target_radius,vp,function(other,_,_,d)
   if not best_distance or d<best_distance then best,best_distance=other,d end
   if preferred then return false end
  end,function(other,r)
   return vk~=r.key and other.CanBeAttacked~=false and allied(v,other)
    and(not adapter.can_charm_target or adapter.can_charm_target(other)==true)
  end,preferred,true,indexed_candidate)
  return best
 end
 local function retained_charm_target(v,preferred,w)
  if w~=world then return nil end
  local generation=source_generation
  local k=key(preferred);local r=k and registry[k]
  if not r or r.creature~=preferred then return nil end
  -- The existing live query performs the complete positive proof once, rather
  -- than sampling world/KO/geometry here and repeating it in visit. No target
  -- or permission is cached; the original AI target remains unchanged.
  local target=choose_charm_target(v,preferred,{row=r,direct_fresh=true})
  if generation~=source_generation or w~=world or registry[k]~=r then return nil end
  return target
 end
 -- Charm searches need the victim's original allies, usually a small fraction
 -- of the army. Share only cheap membership/owner metadata for 0.1 seconds;
 -- do not obtain every friendly ant's position to build a whole-world grid.
 -- This snapshot never authorizes a target. Possible matches still undergo
 -- all live checks below, including actors whose collision is disabled.
 local function charm_snapshot(w,now)
  if charm_index_world==w and charm_index_time and now and now>=charm_index_time
   and now-charm_index_time<M.tick_interval then return charm_rows end
  local rows,groups={},{};local generation=source_generation
  local class=safe(function()return StaticFindObject('/Script/EotU.Creature')end)
  local coarse=valid(class);registry_phase=(registry_phase+1)%16
  for k,r in pairs(registry)do
   local c=r.creature;local include,strict=false,not coarse
   if coarse then
    if not valid(c)then discard(r)
    else
     local ok,is_creature=pcall(function()return c:IsA(class)end)
     if not ok or type(is_creature)~='boolean'then strict=true
     elseif not is_creature then discard(r)
     elseif r.prune_phase==registry_phase and(key(c)~=k or native.world_id(c)~=w)then discard(r)
     else include=true end
    end
   end
   if strict then
    if key(c)~=k or native.world_id(c)~=w then discard(r)
    elseif active_fields(c)then include=true end
   end
   if include then
    local layer=num(c.ColonyLocation)
    if layer and layer>=-1 then
     local group;local ok,owner,flag=pcall(function()return c.ColonyID,c.AlliedWithAllNoneColony end)
     if ok and type(owner)=='number'and num(owner)==owner and owner%1==0
      and(flag==nil or type(flag)=='boolean')then
      flag=flag==true;local gk=tostring(owner)..':'..tostring(flag)
      group=groups[gk]
      if not group then group={owner=owner,flag=flag};groups[gk]=group end
     end
     rows[#rows+1]={row=r,layer=layer,group=group}
    end
   end
   if generation~=source_generation then return nil end
  end
  charm_rows,charm_index_time,charm_index_world,charm_scan_work=rows,now,w,0
  stats.charm_index_builds=stats.charm_index_builds+1;return rows
 end
 local function fresh_charm_target(v,w,now,preferred,no_geometry_prefilter)
  -- A recent general index is already useful (e.g. a death signal just ran).
  if not index_due(now)then return choose_charm_target(v,preferred)end
  local rows=charm_snapshot(w,now);if not rows then return nil end
  local generation,serial=source_generation,registry_serial
  local prefilter_class
  if not no_geometry_prefilter and type(adapter.charm_geometry_prefilter_safe)=='function'then
   prefilter_class=safe(function()return StaticFindObject('/Script/EotU.Creature')end)
  end
  -- This native UClass is shared only within this synchronous search. Any
  -- registry/world reentry below abandons the current geometry pass.
  local prefilter_class_valid=valid(prefilter_class)
  local vk=key(v);if not vk then return nil end
  local vp=pos(v);local layer=num(v.ColonyLocation)
  if not vp or layer==nil then return nil end
  local answers={};local best,best_distance,best_x,best_y
  stats.charm_searches=stats.charm_searches+1
  local function excluded(group)
   if not group or adapter.allied then return false end
   local answer=answers[group];if answer~=nil then return answer end
   if not valid(v)then return false end
   local friend=safe(function()return v:AmIAlliedWith(group.owner,group.flag)end)
   answer=type(friend)=='boolean'and not friend or false
   answers[group]=answer;return answer
  end
  for _,entry in ipairs(rows)do
   local r=entry.row;local c=r.creature
   if entry.layer==layer and not excluded(entry.group)then
    -- A large enemy colony can be spread across the map. Repeated new victims
    -- must not each walk that whole colony through native reflection. Once
    -- shared candidate work reaches one registry pass, build the original
    -- spatial grid once; subsequent queries reuse its local buckets. This is
    -- a work switch, not a target/army cap: every candidate remains eligible.
    if charm_scan_work>=#rows then
     rebuild(w,now)
     if generation~=source_generation or key(v)~=vk or native.world_id(v)~=w then return nil end
     stats.charm_grid_fallbacks=stats.charm_grid_fallbacks+1
     return choose_charm_target(v,preferred)
    end
    charm_scan_work=charm_scan_work+1
    -- No negative answer crosses health/KO/target adapters: they can reenter
    -- gameplay and change allegiances for a later receipt in this same query.
    answers={}
    local negative=false
    if not no_geometry_prefilter and prefilter_class_valid and valid(c)
     and safe(function()return c:IsA(prefilter_class)end)==true
     and safe(function()return adapter.charm_geometry_prefilter_safe(c)end)==true then
     stats.charm_geometry_checks=stats.charm_geometry_checks+1
     if generation~=source_generation then return nil end
     if serial~=registry_serial then
      stats.charm_geometry_fallbacks=stats.charm_geometry_fallbacks+1
      charm_index_time=nil;return fresh_charm_target(v,w,now,preferred,true)
     end
     local current_layer=num(c.ColonyLocation)
     local p=current_layer==layer and pos(c)or nil
     -- Only a proven read-only native path may reject geometry early. An
     -- unknown KO/target/alliance/position adapter retains the original order,
     -- including callbacks that can move a previously distant candidate.
     answers={}
     if generation~=source_generation then return nil end
     if serial~=registry_serial then
      stats.charm_geometry_fallbacks=stats.charm_geometry_fallbacks+1
      charm_index_time=nil;return fresh_charm_target(v,w,now,preferred,true)
     end
     negative=current_layer~=layer or p~=nil and distance(vp,p)>M.charm_target_radius*M.charm_target_radius
     if negative then stats.charm_geometry_rejections=stats.charm_geometry_rejections+1 end
    end
    -- Geometry is rejection-only. Every possible match still runs the exact
    -- live identity/world/KO/target rules and reads its final position below.
    if not negative then
    if key(c)~=r.key or registry[r.key]~=r then discard(r)
    elseif active_health(c)and native.world_id(c)==w and num(c.ColonyLocation)==layer
     and r.key~=vk and c.CanBeAttacked~=false and allied(v,c)
     and(not adapter.can_charm_target or adapter.can_charm_target(c)==true)then
     local p=pos(c);stats.charm_position_reads=stats.charm_position_reads+1
     local d=p and distance(vp,p)
     if d and d<=M.charm_target_radius*M.charm_target_radius then
      local x,y=math.floor(p.x/200),math.floor(p.y/200)
      -- Match the original x/y bucket walk and flat receipt order for ties.
      if not best_distance or d<best_distance or d==best_distance and(x<best_x or x==best_x and y<best_y)then
       best,best_distance,best_x,best_y=c,d,x,y
      end
     end
    end
    end
   end
   if generation~=source_generation then return nil end
  end
  if key(v)~=vk or native.world_id(v)~=w then return nil end
  return best
 end
 local function finish_charm(k,row,now,fallback)
  local c=row.creature
  if valid(c)and adapter.end_charm then adapter.end_charm(c,row.ticket)end
  if charms[k]==row then charms[k]=nil end
  local a=k:match('^([^|]+)|');local hints=a and charm_addresses[a]
  if hints and hints[k]==row then hints[k]=nil;if next(hints)==nil then charm_addresses[a]=nil end end
  if row.size=='medium'then immune[k]={creature=c,until_time=now+M.medium_immunity}end
  if fallback and active(c)then
   local _,_,w=context();local remain=math.max(0,row.expires-now)
   if remain>0 and row.origin.world==w and native.world_id(c)==w and c.CannotBeConfused~=true then
    assert(type(adapter.confuse_origin)=='function','littleblack_confusion_origin_adapter_missing')
    local ok,why=adapter.confuse_origin(row.origin,c,remain)
    assert(ok==true,why or'littleblack_confuse_failed')
    stats.confused=stats.confused+1;stats.charm_fallbacks=stats.charm_fallbacks+1
   end
  end
 end
 function api.on_native_confusion(source,v,effect)
  local ok,r=pcall(function()
   if stopped or not active(source)or not active(v)or not little(source)or(num(source.CreatureLevel)or 0)<3 or choices(source).right~='charm'then return false end
   if v.CannotBeConfused==true or allied(source,v)then return false end
   local _,gs,w,now=context();if not now or not eligible(source,gs,w)or not eligible(v,gs,w)then return false end
   if not effect or num(effect.Type)~=6 or(num(effect.Length)or 0)<=0 then return false end
   local size=adapter.charm_size and adapter.charm_size(v)
   if size~='small'and size~='medium'then return false end
   local k=assert(key(v));local row=charms[k]
   if size=='medium'and row then
    local suppress=adapter.refresh_charm or adapter.suppress_confusion
    assert(suppress(v,effect,row.ticket)==true,'littleblack_confusion_suppress_failed')
    return true -- Do not let a repeated hit interrupt or extend an active charm.
   end
   if size=='medium'and immune[k]and now<immune[k].until_time then return false end
   local target
   if row then target=retained_charm_target(v,row.target,w)end
   if not target then
    target=fresh_charm_target(v,w,now,row and row.target)
   end
   if not target then effect.Length=M.charm_seconds;stats.charm_fallbacks=stats.charm_fallbacks+1;return false end
   if row then
    local suppress=adapter.refresh_charm or adapter.suppress_confusion
    assert(suppress(v,effect,row.ticket)==true,'littleblack_confusion_suppress_failed')
    row.expires=now+M.charm_seconds;stats.charm_refreshes=stats.charm_refreshes+1;return true
   end
   if type(adapter.begin_charm)~='function'then return false end
   local ticket,why=adapter.begin_charm(v,target,effect,source)
   if not ticket then if why then fail(why)end;return false end
   local created={creature=v,origin={world=w,colony=num(source.ColonyID)},size=size,expires=now+M.charm_seconds,target=target,ticket=ticket,
    colony=num(v.ColonyID)}
   local a=assert(k:match('^([^|]+)|'));local hints=charm_addresses[a]or{}
   -- Publish the row and its negative hint together, without native calls.
   charms[k]=created;hints[k]=created;charm_addresses[a]=hints
   stats.charms=stats.charms+1;return true
  end);if not ok then return fail(r)end;return r
 end
 local function charm_target(c,target,expected_row,expected_target_key)
  if stopped or not might_be_charmed(c)then return false end
  local k=key(c);local row=k and charms[k]
  if not row or(expected_row and row~=expected_row)or not active(c)or not active(target)then return false end
  local _,_,w,now=context()
  if now==nil or now>=row.expires or num(c.ColonyID)~=row.colony
   or native.world_id(c)~=w or native.world_id(target)~=w or num(c.ColonyLocation)~=num(target.ColonyLocation)then return false end
  local tk=key(target)
  if not tk or(expected_target_key and tk~=expected_target_key)
   or(not rawequal(target,row.target)and tk~=key(row.target))then return false end
  return allied(c,target)and charms[k]==row
 end
 function api.is_charmed_attack_target(c,target)return charm_target(c,target)end
 api.is_charm_target=api.is_charmed_attack_target
 local function effect_snapshot(v)
  local snap,last={count=0,length=0},nil
  each(v.Effects,function(e)
   if num(e.Type)==6 and name(e.EffectName)=='LBAGasterFlagConfuse3'then
    local length=num(e.Length)or 0
    if length>0 then snap.count=snap.count+1;snap.length=math.max(snap.length,length);last=e end
   end
  end)
  return snap,last
 end
 function api.on_trigger_pre(c)
  local ok,r=pcall(function()
   if stopped or not valid(c)then return nil end
   local selected=c.SelectedAbility;local ability=selected and name(selected.AbilityName)
   if ability=='BasicAttack'then
    if num(selected.AbilityType)~=1 or not might_be_charmed(c)then return nil end
    local source_key=key(c);local row=source_key and charms[source_key]
    local source_world=row and native.world_id(c)
    if not row or not charm_target(c,c.CurrentTarget,row)then return nil end
    -- Specialist venom and retreated trapjaw sting own their existing native
    -- damage replacement. The generic bridge must never add a second hit.
    if o.handles_charm_basic and o.handles_charm_basic(c,c.CurrentTarget)==true then return nil end
    if not o.handles_charm_basic and little(c)and choices(c).form~='twin'then return nil end
    local amount=adapter.basic_damage and adapter.basic_damage(c)or num(c.AttackDamage)
    assert(num(amount)and amount>=0,'littleblack_charm_basic_amount_invalid')
    return{kind='charm_attack',row=row,target=c.CurrentTarget,target_key=key(c.CurrentTarget),amount=amount,
     source_key=source_key,source_world=source_world}
   end
   -- Ordinary attacks cannot add the Gaster Flag confusion carrier. Keep
   -- the scoped charmed BasicAttack bridge above, then reject other abilities
   -- before resolving this actor's colony skill choices.
   if ability~='LittleBlackAntGasterFlag3'then return nil end
   local source_key=key(c);local source_world=source_key and native.world_id(c)
   if not source_key or not source_world then return nil end
   if stopped or not active(c)or not little(c)or(num(c.CreatureLevel)or 0)<3 or choices(c).right~='charm'then return nil end
   local a=selected
   local _,_,w,now=context()
   local center=valid(c.CurrentTarget)and pos(c.CurrentTarget)or pos(c)
   local t={victims={},source_key=source_key,source_world=source_world}
   local radius=num(a.AOERad)or 50
   local candidates=center and adapter.aoe_candidates and adapter.aoe_candidates(c,center,radius)
   if candidates~=nil and w then
    local seen={};local layer=num(c.ColonyLocation)
    local function add(v)
     if not valid(v)then return end
     local id=tostring(v:GetAddress());if seen[id]then return end;seen[id]=true
     -- Most overlap candidates are friendly. Reject them before reflected
     -- KO/world reads, while retaining the later live alliance check for
     -- possible enemies after those adapters have had a chance to reenter.
     if allied(c,v)then return end
     if not active_health(v)or native.world_id(v)~=w or num(v.ColonyLocation)~=layer or allied(c,v)then return end
     local p=pos(v);if not p or distance(center,p)>radius*radius then return end
     t.victims[#t.victims+1]={creature=v,before=effect_snapshot(v)}
    end
    each(candidates,add)
    -- A directly targeted creature may have collision disabled by another
    -- native action; preserve its snapshot without scanning all friendly ants.
    add(c.CurrentTarget)
   else
    if w then ensure_index(w,now)end
    nearby(c,radius,center,function(v)t.victims[#t.victims+1]={creature=v,before=effect_snapshot(v)}end,
     function(v)return not allied(c,v)end,nil,false)
   end
   return t
  end);if not ok then return fail(r)end;return r
 end
 function api.on_trigger_post(c,t,result)
  local ok,r=pcall(function()
   if not t or result~=true then return false end
   if t.kind=='charm_attack'then
    if t.finished then return false end;t.finished=true
    if t.amount<=0 or not charm_target(c,t.target,t.row,t.target_key)then return false end
    assert(type(adapter.apply_charm_basic)=='function','littleblack_charm_damage_adapter_missing')
    local good,why=adapter.apply_charm_basic(c,t.target,t.amount)
    assert(good==true,why or'littleblack_charm_damage_dispatch_failed')
    stats.charm_basic_hits=stats.charm_basic_hits+1;return true
   end
   for _,r in ipairs(t.victims)do local v=r.creature
    if active(v)then local after,last=effect_snapshot(v)
     if after.count>r.before.count or after.length>r.before.length+0.001 then
      -- The effect is from this post callback's own scan, never the pre token.
      if last then api.on_native_confusion(c,v,last)end
     end
    end
   end;return true
  end);if not ok then return fail(r)end;return r
 end
 function api.tick(now)
  if choices_scope then return false end
  choices_epoch=choices_epoch+1;choices_scope=true
  local ok,r=pcall(function()
   if stopped then return false end
   local _,gs,w,t=context();now=num(now)or t;if not now or not gs then return false end
   if world and world~=w or last_tick and now<last_tick then api.reset_cache()end;world=w
   local generation=source_generation
   local maintenance=not last_tick or now-last_tick>=M.tick_interval-0.00001
   if maintenance then last_tick=now;stats.ticks=stats.ticks+1 end
   local batch,visited={},0
   -- The main callback runs every five render frames. Rotate at most twenty
   -- receipts per callback; each source still waits at least 0.1 seconds.
   -- This spreads guard refresh and the missed-death fallback over a round.
   -- Native attack/death callbacks remain immediate and read fresh choices.
   for _=1,M.source_batch_limit do
    if generation~=source_generation then break end
    local r=source_queue[source_head];if not r then break end
    local k=r.key
    if sources[k]==r and r.source_next_time and now<r.source_next_time-0.00001 then break end
    source_queue[source_head]=nil;source_head=source_head+1;visited=visited+1
    if sources[k]==r then
    r.source_next_time=now+M.tick_interval;stats.source_visits=stats.source_visits+1
    -- Requeue before reflected reads: an adapter error must not strand this
    -- source permanently. Retirement leaves a cheap tombstone for the cursor.
    source_tail=source_tail+1;source_queue[source_tail]=r
    -- Completed deaths retain their registry receipt for duplicate native
    -- callbacks, but no longer need per-tick source/skill reflection.
    if r.death_seen then retire_source(k,r,w)
    else
     local c=r.creature
     -- key performs the engine validity check before address/name access.
     -- Match this exact receipt, then retain world_id's own validity guard.
     -- Only this contiguous read-only source pass reuses the checked identity;
     -- callbacks/effect application and subsequent ticks validate afresh.
     local current_key=key(c)
     if current_key~=k or native.world_id(c)~=w then retire_source(k,r,w)
     elseif r.seen_alive and(num(c.Health)or 1)<=0 then
      -- Some native death paths bypass the reflected base death event.
      api.on_death(c)
     elseif active_fields(c)then
      r.seen_alive=true
      local selected=choices(c,current_key)
      if sources[k]==r and generation==source_generation then
       local needed=selected.right=='swarm_guard'
       if needed~=(not not r.guard_needed)then guard_sources=guard_sources+(needed and 1 or -1);r.guard_needed=needed end
       if not signal_prepare_requested and(selected.left=='confusion_signal'or selected.left=='attack_signal')then
        signal_prepare_requested=true;visual_call('prepare_signal')
       end
      end
     end
    end
    if sources[k]==r then
     batch[#batch+1]=r
    end
    end
   end
   if generation~=source_generation then return false end
   stats.source_batch_max=math.max(stats.source_batch_max,visited)
   -- Compact only Lua receipts, with no native traversal. Removed/dead
   -- entries consume the same bounded budget and cannot accumulate forever.
   if source_head>1024 then
    local compact={};for i=source_head,source_tail do compact[#compact+1]=source_queue[i]end
    source_queue=compact;source_head=1;source_tail=#compact
   end
   -- Guard decoration reads the grid below. Stable charms retain their live
   -- target without reading it; defer their rebuild until an actual retarget.
   if guard_sources>0 then ensure_index(w,now)
   elseif maintenance and next(charms)==nil then grid={};index_time=nil end
   if maintenance then
   visual_call('tick_visuals',now,w)
   for k,b in pairs(buffs)do
    if not active(b.creature)then buffs[k]=nil;if valid(b.creature)then attack_changed(b.creature)end
    else local live={};for _,till in ipairs(b.expiries)do if now<till then live[#live+1]=till end end
     if #live~=#b.expiries then b.expiries=live;if #live==0 then buffs[k]=nil end;attack_changed(b.creature)
     elseif adapter.update_attack_signal then
      local remaining=0;for _,till in ipairs(live)do remaining=math.max(remaining,till-now)end
      local good,why=adapter.update_attack_signal(b.creature,1+0.1*#live,remaining,b.source)
      assert(good==true,why or'littleblack_attack_signal_update_failed')
     end
    end
   end
   for k,r in pairs(charms)do
    local c=r.creature
    if not active(c)or num(c.ColonyID)~=r.colony or now>=r.expires then finish_charm(k,r,now,false)
    else
     local cp,tp=pos(c),active(r.target)and pos(r.target)or nil
     if not tp or not cp or distance(cp,tp)>M.charm_target_radius*M.charm_target_radius or not allied(c,r.target)or num(r.target.ColonyLocation)~=num(c.ColonyLocation)then
      r.target=fresh_charm_target(c,w,now)
     end
     if not r.target then finish_charm(k,r,now,true)
     elseif adapter.tick_charm then local good=adapter.tick_charm(c,r.target,r.ticket,now);if good~=true then finish_charm(k,r,now,true)end end
    end
   end
   for k,r in pairs(immune)do if not valid(r.creature)or now>=r.until_time then immune[k]=nil end end
   end
   for _,r in ipairs(batch)do
    local k=r.key
    if sources[k]==r then
    if r.death_seen then retire_source(k,r,w)
    else
     -- The first source pass already resolved this exact actor's choices.
     -- A stat/skill callback can invalidate the receipt during this tick;
     -- only that case needs the usual identity-checked lookup again.
     if fields[k]or r.guard_needed then decorate(r.creature,false)end
    end
    end
   end
   return maintenance or visited>0
  end);choices_scope=false;if not ok then return fail(r)end;return r
 end
 function api.reset_cache()
  for _,r in pairs(fields)do if valid(r.creature)then pcall(restore,r.creature)end end
  for _,r in pairs(charms)do if valid(r.creature)and adapter.end_charm then pcall(adapter.end_charm,r.creature,r.ticket)end end
  local old=buffs;buffs={};for _,r in pairs(old)do if valid(r.creature)then pcall(attack_changed,r.creature)end end
  visual_call('reset_cache')
  registry={};sources={};fields={};charms={};charm_addresses={};immune={};pending={};grid={};world=nil;last_tick=nil;index_time=nil;signal_prepare_requested=false
  charm_rows={};charm_index_time=nil;charm_index_world=nil;charm_scan_work=0
  signal_rows={};signal_time=nil;signal_world=nil;signal_serial=nil;signal_class=nil
  source_queue={};source_head=1;source_tail=0;guard_sources=0;source_generation=source_generation+1
  registry_serial=0;registry_phase=0;return true
 end
 function api.stop()api.reset_cache();stopped=true;return true end
 function api.status()
  local r={};for k,v in pairs(stats)do r[k]=v end;r.hooks=hooks;r.stopped=stopped;r.active_charms=0;r.active_buffs=0
  r.queued_sources=math.max(0,source_tail-source_head+1)
  r.source_queue_tail=source_tail
  for _ in pairs(charms)do r.active_charms=r.active_charms+1 end;for _ in pairs(buffs)do r.active_buffs=r.active_buffs+1 end;return r
 end
 local function hook(path,pre,post)
  if o.register_hooks==false then return end
  local ok,a=pcall(o.register_hook or RegisterHook,path,pre,post)
  hooks[path]=ok and a~=nil;if not hooks[path]then fail('littleblack_hook_failed:'..path..':'..tostring(a))end
 end
 hook('/Script/EotU.Creature:CreatureSpesificDeathEvent',function()end,function(receiver)api.on_death(unbox(receiver))end)
 hook('/Script/EotU.Creature:KillCreature',function()end,function(receiver)api.on_death(unbox(receiver))end)
 hook('/Script/EotU.Creature:TriggerAbility',function(receiver)
  local c=unbox(receiver);local a=callback_address(c);if not a then return end
  local s=pending[a]
  local relevant=false
  if valid(c)then
   local is_little=little(c)
   if is_little or might_be_charmed(c)then
    local selected=c.SelectedAbility;local ability=selected and name(selected.AbilityName)
    -- Ordinary uncharmed bites and unrelated native abilities cannot produce
    -- this module's tokens. Reject them before its scoped API/context wrapper.
    relevant=ability=='BasicAttack'and might_be_charmed(c)and num(selected.AbilityType)==1
     or ability=='LittleBlackAntGasterFlag3'and is_little
   end
  end
  if not relevant then
   if s and #s>0 then s[#s+1]=false end;return
  end
  s=s or{};pending[a]=s;local depth=#s+1;s[depth]=false
  local token=api.on_trigger_pre(c)
  if token then
   -- The API captured these before target/effect adapters could reenter and
   -- replace the receiver. Do not bind a token to a fresh post-snapshot key.
   if token.source_key and token.source_world and pending[a]==s then
    s[depth]={token=token,key=token.source_key,world=token.source_world}
   end
  end
 end,function(receiver,result)
  local c=unbox(receiver);local a=callback_address(c);local s=a and pending[a];if not s or #s==0 then return end
  local entry=table.remove(s);if #s==0 then pending[a]=nil end
  if entry and key(c)==entry.key and native.world_id(c)==entry.world then api.on_trigger_post(c,entry.token,unbox(result))end
 end)
 return api
end
return M
