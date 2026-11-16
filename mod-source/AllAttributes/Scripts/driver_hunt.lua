-- Cooperative driver ant skills. Registries contain opted-in attackers and
-- their actual victims only. Native damage/death and food drops keep ownership.
local M={species='DriverAntSoldier',execute_count=3,food_multiplier=1.2,fallback_food=4,
 wound_per_layer=.015,wound_layers=13,wound_duration=9,holder_reduction=.35,
 target_speed=.55,target_damage=.7,
 feast_fraction=.25,feast_food_limit=8,feast_heal_per_food=8,feast_unit_limit=.2,
 feast_radius=300,attack_window=3,pin_interval=.1}
local PIN_RULES={medium={count=4,duration=9},large={count=6,duration=7.5},titan={count=13,duration=5}}
local ROOT='EAA_Hunt_'
local WOUND=ROOT..'Wound_'
local VICTIM=ROOT..'Victim_'
local HOLDER=ROOT..'Holder_'
local SPEED=ROOT..'Speed_'
local DAMAGE=ROOT..'Damage_'
local REACH=ROOT..'Reach_'
local TAUNT=ROOT..'Taunt_'
local FED=ROOT..'Fed'
local DEVOURED=ROOT..'Devoured'
local DROPPED=ROOT..'Dropped'
local CONTROL={[5]=true,[6]=true,[7]=true,[8]=true,[9]=true,[28]=true}
local VALUE_USERDATA={AActor=true,UObject=true,UWorld=true,UScriptStruct=true,FNameUserdata=true,TArray=true}

local function number(value)
 local n=tonumber(value)
 if n and n==n and math.abs(n)<math.huge then return n end
end
local function name(value)
 if type(value)=='string'then return value end
 return value and value:ToString()
end
local function unbox(value)
 local kind=type(value)
 if kind~='userdata'and kind~='table'then return value end
 if kind=='userdata'and type(debug)=='table'and type(debug.getmetatable)=='function'then
  local ok,meta=pcall(debug.getmetatable,value)
  if ok and type(meta)=='table'and VALUE_USERDATA[rawget(meta,'__name')]then return value end
 end
 local ok,inside=pcall(function()return value:get()end)
 return ok and inside~=nil and inside or value
end
local function each(values,visit)
 if not values then return end
 if type(values)=='table'and not values.GetArrayNum then
  for _,value in ipairs(values)do visit(unbox(value))end
 else
  for i=1,values:GetArrayNum()do visit(unbox(values[i]))end
 end
end
local function near(a,b)return math.abs(a-b)<=math.max(1e-5,math.abs(b)*1e-6)end
local function position(c)
 local p=c:K2_GetActorLocation()
 return {x=p.X,y=p.Y,z=p.Z}
end
local function distance(a,b)return(a.x-b.x)^2+(a.y-b.y)^2+(a.z-b.z)^2 end

function M.install(o)
 local native=assert(o.native)
 local actors,engagements,pins,held,victims,wounded,attacks={},{},{},{},{},{},{}
 local world,stopped,sequence=nil,false,0
 local execution_pending,generation={},0
 local actor_cursor,engagement_cursor
 local stats={executions=0,pins_started=0,releases=0,struggles=0,wound_hits=0,
   wound_damage=0,healed=0,food_spent=0,drain=0,errors=0,icons_created=0,icon_errors=0,flings_blocked=0,
   wound_visual_create=0,wound_visual_fail=0,wound_visual_remove=0,
   holder_icon_suppressed=0,holder_icon_hidden=0}
 local api={}
 local function valid(c)return c~=nil and native.valid_object(c)==true end
 local function key(c)return valid(c)and tostring(c:GetAddress())or nil end
 local function alive(c)return valid(c)and(number(c.Health)or 0)>0 end
 local function clock()
  local ctx=o.get_context()
  return ctx and number(ctx.gs:GetLevelTime()),ctx
 end
 local function identity(c)
  return {actor=c,key=key(c),name=c:GetFullName(),world=native.world_id(c),owner=c.ColonyID}
 end
 local function same(row)
  local c=row and row.actor
  return valid(c)and key(c)==row.key and c:GetFullName()==row.name and native.world_id(c)==row.world
 end
 local function remove_wound_visual(row)
  if not row or not row.visual then return end
  local handle=row.visual;row.visual=nil
  local service=o.wound_visuals
  local ok,why=pcall(function()if service and service.remove then service.remove(handle)end end)
  if ok then stats.wound_visual_remove=stats.wound_visual_remove+1
  else stats.wound_visual_fail=stats.wound_visual_fail+1;stats.last_wound_visual_error=tostring(why)end
 end
 local function ensure_wound_visual(row,now)
  local service=o.wound_visuals
  if row.visual or not service or not service.create or(row.visual_retry_at and now<row.visual_retry_at)then return end
  -- A wound has one presentation across all stacks and attacking colonies.
  -- Only tick enters here: loading/spawning must never run inside damage hooks.
  row.visual_retry_at=now+2
  local ok,handle,why=pcall(service.create,row.actor)
  if ok and handle then row.visual=handle;row.visual_retry_at=nil;stats.wound_visual_create=stats.wound_visual_create+1
  else
   stats.wound_visual_fail=stats.wound_visual_fail+1
   stats.last_wound_visual_error=tostring(ok and(why or'wound_visual_unavailable')or handle)
  end
 end
 local icons,icon_texture={},nil
 local function remove_icon(id)
  local row=icons[id];if not row then return end;icons[id]=nil
  if valid(row.component)then
   local owner=row.component:GetOwner()
   row.component:K2_DestroyComponent(valid(owner)and owner or row.component)
  end
 end
 local function add_icon(target)
  if not o.status_icon_path or icons[key(target)]then return end
  local ctx=assert(o.get_context(),'pin_icon_context_missing')
  if not valid(icon_texture)then
   local render=StaticFindObject('/Script/Engine.Default__KismetRenderingLibrary')
   icon_texture=render:ImportFileAsTexture2D(target,o.status_icon_path)
   assert(valid(icon_texture),'pin_icon_texture_missing')
   -- Retain the imported texture through native GC, including between pins.
   local gi=StaticFindObject('/Script/Engine.Default__GameplayStatics'):GetGameInstance(target)
   local refs={};each(gi.ReferencedObjects,function(a)refs[#refs+1]=a end)
   refs[#refs+1]=icon_texture;gi.ReferencedObjects=refs
  end
  local origin,extent={},{};target:GetActorBounds(false,origin,extent,true)
  local p=target:K2_GetActorLocation()
  local tr={Rotation={X=0,Y=0,Z=0,W=1},Translation={X=0,Y=0,Z=math.max(25,origin.Z-p.Z+extent.Z+15)},Scale3D={X=.1,Y=.1,Z=.1}}
  local component=target:AddComponentByClass(StaticFindObject('/Script/Engine.BillboardComponent'),false,tr,false)
  assert(valid(component),'pin_icon_component_missing')
  component:SetSprite(icon_texture);component:SetHiddenInGame(false,true);component:SetVisibility(true,true)
  component.bIsScreenSizeScaled=true;component.ScreenSize=.02
  local row=identity(target);row.component=component;icons[row.key]=row
  stats.icons_created=stats.icons_created+1
 end
 local function show_icon(target)
  local ok,why=pcall(add_icon,target)
  if not ok then
   stats.icon_errors=stats.icon_errors+1;stats.last_icon_error=tostring(why)
   if o.log then o.log('[DriverHuntIcon] '..tostring(why))end
  end
 end
 local function is_creature(c)return valid(c)and o.is_creature(c)==true end
 local function logical_target(c)return valid(c)and(o.resolve_target and o.resolve_target(c)or c)or nil end
 local function enemy(source,target)
  return alive(source)and alive(target)and is_creature(target)and(target.CanBeAttacked==true
   or o.is_multipart and o.is_multipart(target)==true or o.classify(target)=='titan')
   and source.ColonyLocation==target.ColonyLocation and native.world_id(source)==native.world_id(target)
   and source:IsCreatureEnemy(target)==true
 end
 local function allied(source,target)
  return source:AmIAlliedWith(target.ColonyID,target.AlliedWithAllNoneColony==true)==true
 end
 local function held_pin(c)
  local id=key(c);local pin=id and held[id]
  if not pin or pins[pin.id]~=pin or not alive(c)or not same(pin.target)or not alive(pin.target.actor)then return nil end
  for _,row in ipairs(pin.members)do
   if row.key==id and same(row)and c.ColonyID==row.owner then return pin end
  end
 end
 local function holder_stun_only(c,pin)
  local own,other=false,false
  each(c.Effects,function(e)
   if e.Length>0 and CONTROL[number(e.Type)]then
    if number(e.Type)==7 and name(e.EffectName)==HOLDER..pin.id then own=true else other=true end
   end
  end)
  return own and not other
 end
 function api.hide_holder_stun_icon(c)
  local pin=not stopped and held_pin(c)
  return pin and holder_stun_only(c,pin)or false
 end
 local function restore_holder_icon(row)
  local hidden=row.hidden_stun;row.hidden_stun=nil
  if hidden and valid(hidden.actor)and key(hidden.actor)==hidden.key
   and hidden.actor:GetFullName()==hidden.name then hidden.actor:SetActorHiddenInGame(hidden.was_hidden)end
 end
 local function sync_holder_icon(row,pin)
  local c=row.actor
  if not holder_stun_only(c,pin)then restore_holder_icon(row);return end
  local actor=c.DebuffActor
  if not valid(actor)or actor:GetClass():GetFName():ToString()~='StunEffect_C'then return end
  local hidden=row.hidden_stun
  if not hidden or hidden.key~=key(actor)or hidden.name~=actor:GetFullName()then
   restore_holder_icon(row)
   row.hidden_stun={actor=actor,key=key(actor),name=actor:GetFullName(),was_hidden=actor.bHidden==true}
   stats.holder_icon_hidden=stats.holder_icon_hidden+1
  end
  actor:SetActorHiddenInGame(true)
 end
 local holder_icon_hook=false
 local function ensure_holder_icon_guard()
  if holder_icon_hook or type(RegisterHook)~='function'then return end
  -- Native ant AI calls this through its debuff behavior-tree task. Suppress
  -- only our movement/attack lock; a real control effect keeps its native icon.
  RegisterHook('/Script/EotU.Creature:CreateDebuffComponent',function(receiver,kind)
   if number(unbox(kind))==7 and api.hide_holder_stun_icon(unbox(receiver))then
    kind:set(0);stats.holder_icon_suppressed=stats.holder_icon_suppressed+1
   end
  end,function(receiver)
   local c=unbox(receiver);local pin=not stopped and held_pin(c)
   if pin then for _,row in ipairs(pin.members)do if row.key==key(c)then sync_holder_icon(row,pin);break end end end
  end)
  holder_icon_hook=true
 end
 local fling_hook_installed=false
 local function ensure_fling_guard(c)
  if fling_hook_installed or name(c.CreatureName)~='EmperorScorpion'then return end
  -- Blueprint RegisterHook's single callback runs after the original function.
  RegisterHook('/Game/Blueprints/Creatures/African/EmperorScorpion.EmperorScorpion_C:FlingCheck',function(receiver,creature,can_fling)
   if stopped or not next(held)then return end
   local pin=held_pin(unbox(creature))
   if pin and key(logical_target(unbox(receiver)))==pin.target.key and unbox(can_fling)==true then
    can_fling:set(false);stats.flings_blocked=stats.flings_blocked+1
   end
  end)
  fling_hook_installed=true
 end
 local function effect(c,wanted)
  local found
  each(c.Effects,function(e)if name(e.EffectName)==wanted then found=e end end)
  return found
 end
 local function apply(c,id,kind,length,interval,owner)
  c:ApplyEffect({EffectName=FName(id),Type=kind,Length=length,Interval=interval or -1,
   Timer=-1,Damage=0,DamageType=14,SpecialEffect=0,StackType=0,StackMax=1,
   CausingColonyID=owner or c.ColonyID,CausingTileID=-1,EventName=FName('None')})
  return effect(c,id)
 end
 local function expire(c,id)
  if valid(c)then local e=effect(c,id);if e then e.Length=0 end end
 end
 local function watch(c)
  local ok,why=o.watch_damage(c)
  assert(ok==true,why or'hunt_damage_watch_failed')
 end
 local function controlled(c,own_effect)
  if c.InPickup==true then return true end
  local found=false
  each(c.Effects,function(e)
   if e.Length>0 and CONTROL[number(e.Type)]and name(e.EffectName)~=own_effect then found=true end
  end)
  return found
 end
 local function source_row(c)
  local row=actors[key(c)]
  if not row or not same(row)or not alive(c)or c.ColonyID~=row.owner or o.is_slave(c)then return nil end
  return row
 end
 local function marker(c,prefix,id,length,interval,owner)
  local e=effect(c,prefix..id)
  if not e then e=apply(c,prefix..id,31,length,interval,owner)end
  assert(e and number(e.Type)==31,'hunt_marker_missing:'..prefix)
  e.Length=length;e.Interval=interval
  return e
 end
 local function wound_row(c)
  local id=key(c)
  local row=id and wounded[id]
  if row and same(row)then return row end
  remove_wound_visual(row)
  row=identity(c);row.sides={};wounded[id]=row
  watch(c)
  return row
 end
 local function add_wound(source,target,count,now)
  if count<=0 or not enemy(source,target)then return end
  local row=wound_row(target)
  local owner=source.ColonyID
  local old=row.sides[owner]
  local layers=old and now<old.expires and old.layers or 0
  layers=math.min(M.wound_layers,layers+count)
  row.sides[owner]={layers=layers,expires=now+M.wound_duration}
  marker(target,WOUND,tostring(owner),M.wound_duration,-layers,owner)
 end
 local function refresh_wound(source,target,now)
  local row=wounded[key(target)]
  local old=row and row.sides[source.ColonyID]
  if old and now<old.expires then
   old.expires=now+M.wound_duration
   marker(target,WOUND,tostring(source.ColonyID),M.wound_duration,-old.layers,source.ColonyID)
  end
 end
 local function restore_field(c,overlay,field)
  if overlay and near(c[field],overlay.output)then c[field]=overlay.base end
 end
 local function overlay_field(c,overlay,field,multiplier)
  local current=assert(number(c[field]),'hunt_stat_unreadable:'..field)
  local base=overlay and near(current,overlay.output)and overlay.base or current
  local output=base*multiplier
  if not near(current,output)then c[field]=output end
  return {base=base,output=number(c[field])}
 end
 local function victim_overlay(pin)
  local c=pin.target.actor
  pin.speed=overlay_field(c,pin.speed,'AttackSpeed',M.target_speed)
  pin.damage=overlay_field(c,pin.damage,'AttackDamage',M.target_damage)
  c.Immobile=true
  local remaining=math.max(0,pin.expires-pin.now)
  marker(c,SPEED,pin.id,remaining,-pin.speed.base,pin.owner)
  marker(c,DAMAGE,pin.id,remaining,-pin.damage.base,pin.owner)
  if pin.reach then marker(c,REACH,pin.id,remaining,-pin.reach.base,pin.owner)end
 end
 local function counter_idle(c)
  local ability=name(c.SelectedAbility.AbilityName)
  return not c.AbilityInUse and not c.NoCombat and not controlled(c)and(ability=='Default'or ability=='BasicAttack')
 end
 local function counterattack_target(pin,now)
  local c=pin.target.actor
  if pin.next_counter and now<pin.next_counter then return end
  pin.next_counter=now+.5
  local best,nearest;local origin=position(c)
  for _,row in ipairs(pin.members)do
   if same(row)and alive(row.actor)then
    local p=position(row.actor);local d=(origin.x-p.x)^2+(origin.y-p.y)^2
    if not nearest or d<nearest then best,nearest=row,d end
   end
  end
  if not best then return end
  -- Native BasicAttack uses XY distance and ArrivalDist + AttackTolDist +
  -- the victim's ReachableDist. ArrivalDist leaves special min/max unchanged.
  local current=assert(number(c.ArrivalDist),'hunt_reach_unreadable')
  local base=pin.reach and near(current,pin.reach.output)and pin.reach.base or current
  local tolerance=assert(number(c.AttackTolDist),'hunt_attack_tolerance_unreadable')
  local reach=assert(number(best.actor.ReachableDist),'hunt_captor_reach_unreadable')
  local output=math.max(base,math.sqrt(nearest)-tolerance-reach+1)
  if not near(current,output)then c.ArrivalDist=output end
  pin.reach={base=base,output=number(c.ArrivalDist)}
  marker(c,REACH,pin.id,math.max(0,pin.expires-now),-base,pin.owner)
  if not counter_idle(c)then return end
  local target=c.CurrentTarget;local current_key=key(target)
  if current_key and pin.member_keys[current_key]and alive(target)then
   local p=position(target)
   local radius=pin.reach.output+tolerance+assert(number(target.ReachableDist),'hunt_captor_reach_unreadable')
   if (origin.x-p.x)^2+(origin.y-p.y)^2<radius^2 then
    c.LatestTaunter=target;pin.counter_key=current_key;return
   end
  end
  local radius=pin.reach.output+tolerance+reach
  local in_range=nearest<radius^2
  c.LatestTaunter=best.actor
  if current_key~=best.key or pin.counter_key~=best.key or not in_range then
   local ctl=c:GetController();if valid(ctl)then ctl:StopMovement()end
   local p=position(best.actor)
   c.CurrentTarget=best.actor;c.CurrentTargetLocation={X=p.x,Y=p.y,Z=p.z}
   c:SetTurnToTarget(best.actor);pin.counter_key=best.key
  end
 end
 local release
 local function throw_holder(c,origin,owner)
  local p=position(c)
  local dx,dy=p.x-origin.x,p.y-origin.y
  local length=math.sqrt(dx*dx+dy*dy)
  if length<1 then dx,dy,length=1,0,1 end
  local point={X=p.x+dx/length*110,Y=p.y+dy/length*110,Z=p.z}
  c:JumpToLocation(point,false,true,300,980)
 end
 release=function(pin,reason,preserve)
  if pins[pin.id]~=pin then return end
  pins[pin.id]=nil
  local target=pin.target
  if target then remove_icon(target.key)end
  local origin=same(target)and position(target.actor)or nil
  if target then victims[target.key]=nil end
  if same(target)then
   local c=target.actor
   if alive(c)then
    restore_field(c,pin.speed,'AttackSpeed');restore_field(c,pin.damage,'AttackDamage')
    restore_field(c,pin.reach,'ArrivalDist')
    if c.ColonyID==target.owner and not o.is_slave(c)and c.Immobile==true then c.Immobile=pin.immobile end
   end
   if not preserve then
    for _,prefix in ipairs({VICTIM,SPEED,DAMAGE,REACH,TAUNT})do expire(c,prefix..pin.id)end
   end
  end
  for _,row in ipairs(pin.members)do
   held[row.key]=nil
   if same(row)then
    local c=row.actor
    if alive(c)and c.ColonyID==row.owner and not o.is_slave(c)and c.Immobile==true then c.Immobile=row.immobile end
    if not preserve then
     expire(c,HOLDER..pin.id)
     -- Clear the ended lock before restoring a hidden native actor, avoiding
     -- a one-frame flash. Real enemy control effects remain in the array.
     if alive(c)then c:TickEffects(0)end
    end
    restore_holder_icon(row)
    if reason=='struggle'and origin and alive(c)then
     throw_holder(c,origin,pin.owner)
    end
   end
  end
  stats.releases=stats.releases+1
  if reason=='struggle'then stats.struggles=stats.struggles+1 end
 end
 local function start_pin(source,target,members,size,now)
  if victims[key(target)]then return end
  local rule=PIN_RULES[size]
  if not rule or #members<rule.count then return end
  sequence=sequence+1
  local id=string.format('%d_%d',math.floor(now*1000),sequence)
  local pin={id=id,target=identity(target),members={},member_keys={},owner=source.ColonyID,
   expires=now+rule.duration,next_tick=now+M.pin_interval,next_wound_refresh=now+1,
   immobile=target.Immobile,now=now,ready_at=now}
  pins[id]=pin;victims[pin.target.key]=pin
  local ok,why=pcall(function()
   ensure_fling_guard(target)
   ensure_holder_icon_guard()
   marker(target,VICTIM,id,rule.duration,pin.immobile and 1 or 0,pin.owner)
   watch(target)
   local wound_source,wound_count=nil,0
   for i=1,rule.count do
    local c=members[i].actor
    local row=identity(c);row.immobile=c.Immobile
    pin.members[#pin.members+1]=row;held[row.key]=pin
    pin.member_keys[row.key]=true
    c.Immobile=true
    local controller=c:GetController()
    if valid(controller)then controller:StopMovement()end
    local e=apply(c,HOLDER..id,7,rule.duration,row.immobile and 1 or -1,pin.owner)
    assert(e,'hunt_holder_stun_rejected')
    sync_holder_icon(row,pin)
    watch(c)
    if members[i].choices.right=='rend_wounds'then wound_source=c;wound_count=wound_count+1 end
   end
   if wound_source then
    local existing=wounded[pin.target.key]
    local side=existing and existing.sides[wound_source.ColonyID]
    local layers=side and now<side.expires and side.layers or 0
    add_wound(wound_source,target,math.max(0,wound_count-layers),now)
    refresh_wound(wound_source,target,now)
   end
   victim_overlay(pin)
   local controller=target:GetController()
   if counter_idle(target)and valid(controller)then controller:StopMovement()end
   assert(apply(target,TAUNT..id,10,rule.duration,-1,pin.owner),'hunt_taunt_rejected')
   counterattack_target(pin,now)
   show_icon(target)
  end)
  if not ok then release(pin,'failed');error(why)end
  stats.pins_started=stats.pins_started+1
 end
 local function has_tag(c,wanted)
  local found=false;each(c.Tags,function(t)if name(t)==wanted then found=true end end)
  return found
 end
 local function tag(c,value)
  local tags={};each(c.Tags,function(t)tags[#tags+1]=t end)
  tags[#tags+1]=FName(value);c.Tags=tags
 end
 local function feast(source,target)
  local row=source_row(source)
  if not row or row.choices.right~='war_feast'or has_tag(target,FED)then return end
  tag(target,FED)
  local food=math.max(0,number(target.FoodValue)or 0)
  local limit=math.min(food,M.feast_food_limit,math.ceil(food*M.feast_fraction))
  if limit<=0 then return end
  local center=position(target)
  local recipients,total,seen={},0,{}
  local function consider(c)
   local id=key(c)
   if not id or seen[id]then return end
   seen[id]=true
   if not alive(c)or name(c.CreatureName)~=M.species or o.is_slave(c)
    or c.ColonyLocation~=target.ColonyLocation or native.world_id(c)~=row.world or not allied(source,c)then return end
   if distance(position(c),center)>M.feast_radius^2 then return end
   local missing=c.FullHealth-c.Health
   local need=math.min(missing,c.FullHealth*M.feast_unit_limit)
   if need>0 then recipients[#recipients+1]={actor=c,need=need};total=total+need end
  end
  each(o.nearby(target,center,M.feast_radius),consider)
  if o.execution and o.execution.candidates then each(o.execution.candidates(target,center,M.feast_radius),consider)end
  consider(source)
  if total<=0 then return end
  local spent=math.min(limit,math.ceil(total/M.feast_heal_per_food))
  local budget=math.min(total,spent*M.feast_heal_per_food)
  target.FoodValue=food-spent
  for _,recipient in ipairs(recipients)do
   local c=recipient.actor
   local heal=budget*recipient.need/total
   c.Health=math.min(c.FullHealth,c.Health+heal)
   stats.healed=stats.healed+heal
  end
  stats.food_spent=stats.food_spent+spent
 end
 local function prepare_execution_food(target)
  if has_tag(target,DEVOURED)then return end
  tag(target,DEVOURED)
  local original=number(target.FoodValue)or 0
  target.FoodValue=original>0 and math.floor(original*M.food_multiplier+.5)or M.fallback_food
  if target.FoodDropType==4 then target.FoodDropType=0 end
  if o.prepare_food then o.prepare_food(target)end
 end
 local function finish_execution_food(target,amount)
  if o.finish_food and has_tag(target,DEVOURED)and not has_tag(target,DROPPED)
   and o.finish_food(target,amount)==true then tag(target,DROPPED)end
 end
 local function execute(source,target)
  if target.CannotBeExercuted==true then return end
  prepare_execution_food(target)
  feast(source,target)
  local food=target.FoodValue
  finish_execution_food(target,food)
  target:KillCreature(source)
  stats.executions=stats.executions+1
 end
 local function members_for(target,branch,now,extra,limit)
  local id=key(target);local bucket=engagements[id]
  local members={}
  if not bucket then bucket={target=identity(target),members={}};engagements[id]=bucket end
  if extra then bucket.members[extra.key]={row=extra,last=now}end
  for member_id,item in pairs(bucket.members)do
   local row=item.row;local c=row.actor
   local current=source_row(c)
   if not current or held[member_id]or now-item.last>M.attack_window then
    bucket.members[member_id]=nil
   elseif current.choices.left==branch and not controlled(c)and(not extra or allied(extra.actor,c))
    and(not o.execution or branch~='swarm_execute'or o.execution.available(c,now))
    and enemy(c,target)and key(logical_target(c.CurrentTarget))==id then
    local aim=c.CurrentTarget
    local max_range=math.max(60,(number(c.SelectedAbility.MaxRange)or 0)+(number(aim.TargetRadius)or 0)+(number(c.TargetRadius)or 0)+50)
    if distance(position(c),position(aim))<=max_range^2 then
     members[#members+1]=current
     if limit and #members>=limit then break end
    end
   end
  end
  table.sort(members,function(a,b)return a.key<b.key end)
  return members
 end
 local function restored_pin(id,owner,now,length)
  local pin=pins[id]
  if pin then
   pin.expires=math.min(pin.expires,now+length)
   return pin
  end
  pin={id=id,owner=owner,members={},member_keys={},expires=now+length,
   next_tick=now,next_wound_refresh=now+1,now=now,ready_at=now+1,restoring=true}
  pins[id]=pin
  return pin
 end
 local function restore_markers(c,now)
  each(c.Effects,function(e)
   local label=name(e.EffectName)
   if not label or e.Length<=0 then return end
   local owner_text=label:match('^'..WOUND..'([%-%d]+)$')
   if owner_text and number(e.Type)==31 then
    local owner,layers=number(owner_text),-(number(e.Interval)or 0)
    if owner and owner%1==0 and layers%1==0 and layers>=1 and layers<=M.wound_layers and e.Length<=M.wound_duration then
     wound_row(c).sides[owner]={layers=layers,expires=now+e.Length}
    end
    return
   end
   local id=label:match('^'..VICTIM..'(%d+_%d+)$')
   if id and number(e.Type)==31 and e.Length<=9 then
    local speed,damage=effect(c,SPEED..id),effect(c,DAMAGE..id)
    if not speed or not damage or not number(speed.Interval)or not number(damage.Interval)then return end
    local base_speed,base_damage=-speed.Interval,-damage.Interval
    if base_speed<0 or base_damage<0 then return end
    local pin=restored_pin(id,e.CausingColonyID,now,e.Length)
    pin.target=identity(c);pin.immobile=e.Interval==1
    local saved_speed=base_speed*M.target_speed
    -- Older pins saved the 65% slowdown. Keep its original base when the
    -- restored actor still has that output; the next overlay applies 45% once.
    if near(c.AttackSpeed,base_speed*.35)then saved_speed=c.AttackSpeed end
    pin.speed={base=base_speed,output=saved_speed}
    pin.damage={base=base_damage,output=base_damage*M.target_damage}
    local reach=effect(c,REACH..id)
    if reach and number(reach.Type)==31 and number(reach.Interval)and reach.Interval<=0 then
     pin.reach={base=-reach.Interval,output=number(c.ArrivalDist)}
    end
    victims[pin.target.key]=pin
    ensure_fling_guard(c)
    show_icon(c)
    watch(c)
    return
   end
   id=label:match('^'..HOLDER..'(%d+_%d+)$')
   if id and number(e.Type)==7 and e.Length<=9 then
    local pin=restored_pin(id,e.CausingColonyID,now,e.Length)
    local row=identity(c)
    pin.member_keys=pin.member_keys or{}
    if not pin.member_keys[row.key]then
     row.immobile=e.Interval==1;pin.members[#pin.members+1]=row
     pin.member_keys[row.key]=true;held[row.key]=pin
     ensure_holder_icon_guard()
     sync_holder_icon(row,pin)
     watch(c)
    end
   end
  end)
 end
 function api.observe(c)
  if stopped or not alive(c)then return true end
  local now,ctx=clock();if not now or native.world_id(c)~=ctx.world_id then return true end
  world=world or ctx.world_id
  if o.execution then o.execution.observe(c)end
  local id=key(c)
  if name(c.CreatureName)==M.species and not o.is_slave(c)then
   local choices=o.get_choices(c,M.species)or{}
   if choices.left or choices.right then
    if choices.left=='swarm_execute'then
     if o.prepare_food_assets then o.prepare_food_assets()end
     if o.execution then local ready,why=o.execution.prepare();assert(ready,why)end
    end
    local row=actors[id]
    if not row or not same(row)then row=identity(c);actors[id]=row end
    row.choices=choices
   else actors[id]=nil end
  else actors[id]=nil end
  restore_markers(c,now)
  return true
 end
 function api.on_trigger_pre(c)
  local id=key(c)
  if held[id]or o.execution and o.execution.owns(c)then
   local a=c.SelectedAbility
   local token={blocked=true,type=a.AbilityType,charges=a.Charges}
   a.AbilityType=0;a.Charges=0
   return token
  end
  local row=source_row(c)
  if not row or name(c.SelectedAbility.AbilityName)~='BasicAttack'then return nil end
  local target=logical_target(c.CurrentTarget)
  if not enemy(c,target)then return nil end
  watch(target)
  local now=clock()
  local bucket=engagements[key(target)]
  local previous=bucket and bucket.members[row.key]
  local size=o.classify(target)
  local limit=row.choices.left=='swarm_execute'and size=='small'and M.execute_count
   or row.choices.left=='collective_pin'and not victims[key(target)]and PIN_RULES[size]and PIN_RULES[size].count
  local potential=limit and members_for(target,row.choices.left,now,row,limit)or{}
  local token={row=row,target=identity(target),hp=target.Health,now=now,members=potential,previous=previous,size=size,limit=limit}
  local active=attacks[token.target.key]or{}
  active[#active+1]=token;attacks[token.target.key]=active
  return token
 end
 function api.on_trigger_post(c,token,result)
  if token.blocked then
   local a=c.SelectedAbility
   if number(a.AbilityType)==0 and number(a.Charges)==0 then a.AbilityType=token.type;a.Charges=token.charges end
   return
  end
  local active=attacks[token.target.key]
  if active then
   for i=#active,1,-1 do if active[i]==token then table.remove(active,i);break end end
   if #active==0 then attacks[token.target.key]=nil end
  end
  if result~=true then
   local bucket=engagements[token.target.key]
   if bucket and bucket.members[token.row.key]and bucket.members[token.row.key].last==token.now then
    bucket.members[token.row.key]=token.previous
   end
  end
  if result~=true or not same(token.target)or not same(token.row)then return end
  local target=token.target.actor
  local now=clock()
  if not now or not alive(c)then return end
  if not alive(target)then return end
  if token.row.choices.right=='rend_wounds'then add_wound(c,target,1,now)end
  local branch=token.row.choices.left
  local members=token.limit and members_for(target,branch,now,token.row,token.limit)or{}
  local size=token.size
  if branch=='swarm_execute'and size=='small'and #members>=M.execute_count then
   if o.execution then
    local tid=key(target)
    if target.FullHealth>0 and target.Health/target.FullHealth<.7 and not execution_pending[tid]then
     local epoch=generation;execution_pending[tid]=true
     ExecuteInGameThreadAfterFrames(1,function()
      if epoch~=generation or stopped then return end
      execution_pending[tid]=nil
      if not same(token.target)or not same(token.row)or not alive(target)or not alive(c)then return end
      local current=members_for(target,branch,clock(),nil,M.execute_count)
      if #current>=M.execute_count then o.execution.start(c,target,current)end
     end)
    end
   elseif target.FullHealth>0 and target.Health/target.FullHealth<.7 then execute(c,target)end
  elseif branch=='collective_pin'and PIN_RULES[size]then start_pin(c,target,members,size,now)end
 end
 function api.commit_execution(source,target)
  if stopped or not enemy(source,target)or o.classify(target)~='small'or target.FullHealth<=0
   or target.Health/target.FullHealth>=.7 or target.CannotBeExercuted==true then return false end
  execute(source,target);return true
 end
 function api.interested(c)
  if stopped or not next(actors)and not next(held)then return false end
  local id=key(c)
  return id~=nil and(actors[id]~=nil or held[id]~=nil)
 end
 function api.is_pinned(c)
  if stopped or not next(pins)then return false end
  local id=key(c)
  return id~=nil and victims[id]~=nil
 end
 function api.is_held(c)
  return not stopped and held_pin(c)~=nil
 end
 function api.on_use(c,accepted)
  if stopped or not next(pins)or accepted~=true then return end
  local pin=victims[key(c)]
  if not pin then return end
  local ability=c.SelectedAbility
  local kind=number(ability.AbilityType)
  -- The native ability dispatcher also handles area/titan basic attacks,
  -- unlimited finishers and locomotion. Those must not count as pin breakouts.
  if not kind or kind<=1 or kind==10 or kind==12 or name(ability.AbilityName)=='BasicAttack'then return end
  local animation=number(ability.Animation)
  if not animation or not(animation>=3 and animation<=7 or animation==9)then return end
  local cooldown=number(ability.Cooldown)
  local charges=number(ability.FullCharges)or number(ability.Charges)
  -- Read maximum charges: the last available charge can already be consumed
  -- when this post-use callback runs.
  if cooldown and cooldown>0 and charges and charges>0 then release(pin,'struggle')end
 end
 local function attacker(causer,instigator)
  if is_creature(causer)then return causer end
  local pawn=valid(instigator)and instigator:GetPawn()
  if is_creature(pawn)then return pawn end
 end
 local function native_floor(c)
  local floor=0
  each(c.Effects,function(e)
   if number(e.Type)==30 and e.Length>0 then floor=math.max(floor,number(e.Damage)or 0)end
  end)
  return floor
 end
 function api.modify_damage(c,damage,kind,causer,instigator)
  if stopped or not damage or damage<=0 then return damage end
  local id=key(c);local now=clock()
  local hit=damage
  local wound=wounded[id]
  if wound and same(wound)and valid(kind)and kind:GetFullName():match('^EotUPhysicalDamageType ')then
   local source=attacker(causer,instigator)
   if source and enemy(source,c)then
    local ability=source.SelectedAbility
    if name(ability.AbilityName)=='BasicAttack'and number(ability.AbilityType)==1 then
     local layers=0
     for owner,side in pairs(wound.sides)do
      if now<side.expires and source:AmIAlliedWith(owner,false)then layers=math.max(layers,side.layers)end
     end
     if layers>0 then
      local extra=damage*layers*M.wound_per_layer
      c.Health=math.max(native_floor(c),c.Health-extra)
      hit=hit+extra;stats.wound_hits=stats.wound_hits+1;stats.wound_damage=stats.wound_damage+extra
     end
    end
   end
  end
  local pin=held[id]
  if pin then
   c.Health=math.min(c.FullHealth,c.Health+hit*M.holder_reduction)
   hit=hit*(1-M.holder_reduction)
   if c.Health<=0 then release(pin,'casualty')end
  end
  if o.execution and o.execution.reduce_damage then hit=o.execution.reduce_damage(c,hit)end
  return hit
 end
 function api.on_lethal(c,damage,kind,causer,instigator)
  if stopped or not valid(c)or c.Health>0 then return end
  local id=key(c);remove_wound_visual(wounded[id]);wounded[id]=nil
  local source=attacker(causer,instigator)
  if not source then return end
  -- Ordinary lethal hits finish normally. The execution bonus is committed
  -- only at the cinematic strike, never merely for having three attackers.
  feast(source,c)
  finish_execution_food(c,c.FoodValue)
 end
 local function valid_pin(pin,now)
  if not same(pin.target)or not alive(pin.target.actor)or now>=pin.expires then return false end
  local target=pin.target.actor
  if target.ColonyID~=pin.target.owner then return false end
  for _,row in ipairs(pin.members)do
   local source=source_row(row.actor)
   if not same(row)or not alive(row.actor)or not source or source.choices.left~='collective_pin'
    or not enemy(row.actor,target)or controlled(row.actor,HOLDER..pin.id)then return false end
  end
  return true
 end
 function api.tick(ctx)
  if stopped then return true end
  local ok,why=pcall(function()
   if world and world~=ctx.world_id then api.reset_cache();return end
   local now=ctx.gs:GetLevelTime()
   for _,pin in pairs(pins)do
    if now>=pin.next_tick then
     pin.next_tick=now+M.pin_interval
     if now>=pin.ready_at then
     local waiting=pin.restoring and o.skills_ready and not o.skills_ready(ctx)
     if waiting and pin.target and same(pin.target)and alive(pin.target.actor)and now<pin.expires then
      -- Profile fingerprints settle after native creature restoration. Keep
      -- the already-saved effect until its choices can be checked, instead
      -- of cancelling it merely because the purchase ledger is still loading.
      pin.now=now;victim_overlay(pin)
     else
     if pin.restoring then
      for _,row in ipairs(pin.members)do if same(row)and not source_row(row.actor)then api.observe(row.actor)end end
      pin.restoring=nil
     end
     if not pin.target or not same(pin.target)or not PIN_RULES[o.classify(pin.target.actor)]
      or #pin.members~=PIN_RULES[o.classify(pin.target.actor)].count or not valid_pin(pin,now)then release(pin,'ended')
     else
      pin.now=now;victim_overlay(pin)
      local target=pin.target.actor
      counterattack_target(pin,now)
      for _,row in ipairs(pin.members)do sync_holder_icon(row,pin)end
      if now>=pin.next_wound_refresh then
       pin.next_wound_refresh=now+1
       for _,row in ipairs(pin.members)do
        if source_row(row.actor).choices.right=='rend_wounds'then refresh_wound(row.actor,target,now);break end
       end
      end
     end
     end
     end
    end
   end
   for id,row in pairs(wounded)do
    if not same(row)or not alive(row.actor)then
     remove_wound_visual(row);wounded[id]=nil
    else
     for owner,side in pairs(row.sides)do if now>=side.expires then row.sides[owner]=nil end end
     if not next(row.sides)then remove_wound_visual(row);wounded[id]=nil
     else ensure_wound_visual(row,now)end
    end
   end
   for _=1,16 do
    if actor_cursor and not actors[actor_cursor]then actor_cursor=nil end
    local id,row=next(actors,actor_cursor)
    if not id then actor_cursor=nil;break end
    actor_cursor=id
    if not same(row)or not alive(row.actor)then actors[id]=nil end
   end
   for _=1,16 do
    if engagement_cursor and not engagements[engagement_cursor]then engagement_cursor=nil end
    local id,bucket=next(engagements,engagement_cursor)
    if not id then engagement_cursor=nil;break end
    engagement_cursor=id
    if not same(bucket.target)or not alive(bucket.target.actor)then engagements[id]=nil
    else
     for member_id,item in pairs(bucket.members)do if now-item.last>M.attack_window then bucket.members[member_id]=nil end end
     if not next(bucket.members)then engagements[id]=nil end
    end
   end
  end)
  if not ok then api.report_error(why);return nil,why end
  return true
 end
 function api.report_error(why)
  stats.errors=stats.errors+1;stats.last_error=tostring(why)
  if o.log then o.log('[DriverHunt] '..tostring(why))end
 end
 function api.reset_cache()
  generation=generation+1;execution_pending={}
  if o.execution then o.execution.reset_cache()end
  for _,pin in pairs(pins)do release(pin,'travel',true)end
  for _,row in pairs(wounded)do remove_wound_visual(row)end
  actors,engagements,pins,held,victims,wounded,attacks={},{},{},{},{},{},{}
  world=nil
  actor_cursor,engagement_cursor=nil,nil
  return true
 end
 function api.stop()
  if o.execution then o.execution.stop()end
  for _,pin in pairs(pins)do release(pin,'stop')end
  for _,row in pairs(wounded)do
   if same(row)then for owner in pairs(row.sides)do expire(row.actor,WOUND..tostring(owner))end end
  end
  api.reset_cache();stopped=true
  return true
 end
 function api.status()
  local result={actors=0,pins=0,wounded=0}
  for _ in pairs(actors)do result.actors=result.actors+1 end
  for _ in pairs(pins)do result.pins=result.pins+1 end
  for _ in pairs(wounded)do result.wounded=result.wounded+1 end
  for k,v in pairs(stats)do result[k]=v end
  return result
 end
 return api
end
return M
