-- Supplemental black driver ant branches. Native Ram owns movement, impact,
-- charges and recovery. Only opted-in soldiers enter the rescue scheduler.
local M={duration=10,per_stun=.15,minimum=.15,maximum=.8,taunt_duration=3,
 stun_per_hit=1,stun_maximum=8,guard_radius=160,ally_guard_share=.5,
 sweep_radius=100,sweep_multiplier=.5,kill_extension=2}
local GUARD='rescue_guard'
local FRENZY='rescue_frenzy'
local STUN={
 DriverAntSuperSoldierRampage1='DriverLargeSoldierRampageStun1',
 DriverAntSuperSoldierRampage2='DriverLargeSoldierRampageStun2',
 DriverAntSuperSoldierRampage3='DriverLargeSoldierRampageStun3',
}
local BUFF={[GUARD]='EAA_Driver_RescueGuard',[FRENZY]='EAA_Driver_RescueFrenzy'}
local PROTECTION={'CannotBePickedUp','CannotBeStrongPickedUp','CannotBeExercuted'}
local TAUNT='EAA_Driver_RescueTaunt'
local ALLY_GUARD={EAA_Driver_AllyPhysicalGuard=12,EAA_Driver_AllyVenomGuard=13}
local SEARCH_INTERVAL=.22
local SEARCH_BUDGET=16
local RAM_SPEED=1000

local function safe(f)local ok,value=pcall(f);if ok then return value end end
local function unbox(value)
 local kind=type(value)
 if kind~='userdata'and kind~='table'then return value end
 local inside=safe(function()return value:get()end)
 if inside~=nil then return inside end
 return value
end
local function number(value)
 local n=tonumber(value)
 if n and n==n and math.abs(n)<math.huge then return n end
end
local function name(value)
 return type(value)=='string'and value or value and safe(function()return value:ToString()end)
end
local function each(array,visit)
 if not array then return end
 if type(array)=='table'and type(array.GetArrayNum)~='function'then
  for _,row in ipairs(array)do visit(unbox(row))end
 else
  for i=1,array:GetArrayNum()do visit(unbox(array[i]))end
 end
end
local function point(v)
 local x,y,z=number(v.X),number(v.Y),number(v.Z)
 if x and y and z then return {x=x,y=y,z=z}end
end
local function distance(a,b)
 return (a.x-b.x)^2+(a.y-b.y)^2+(a.z-b.z)^2
end
local function near(a,b)return math.abs(a-b)<=math.max(1e-5,math.abs(b)*1e-6)end

function M.install(o)
 local native=assert(o.native)
 local rows,active,charging,reported={},{},{},{}
 local world,cursor,stopped,creature_class,motion_timer
 local utility,damage_library,physical_damage
 local stats={started=0,impacts=0,rescue_impacts=0,stunned=0,taunted=0,reduced=0,leeches=0,
  protected=0,extended_stuns=0,sweeps=0,swept=0,kills=0}
 local api={}
 local function valid(c)return native.valid_object(c)==true end
 local function key(c)return valid(c)and tostring(c:GetAddress())or nil end
 local function same(c,row)
  return key(c)==row.key and native.world_id(c)==row.world and c:GetFullName()==row.name
 end
 local function alive(c)return valid(c)and(number(c.Health)or 0)>0 end
 local function on_layer(c,layer,w)
  return alive(c)and number(c.ColonyLocation)==layer and native.world_id(c)==w
 end
 local function fail(err)
  err=tostring(err);stats.last_error=err
  if not reported[err]then reported[err]=true;if o.log then o.log('[DriverRescue] '..err)end end
  return nil,err
 end
 local function position(c)return point(c:K2_GetActorLocation())end
 local function is_creature(c)
  if not valid(c)then return false end
  if not o.creature_class then return true end
  if not valid(creature_class)then creature_class=o.creature_class()end
  return valid(creature_class)and c:IsA(creature_class)
 end
 local function enemy(c,t,layer,w)
  return is_creature(t)and on_layer(t,layer,w)and t.CanBeAttacked==true and c:IsCreatureEnemy(t)==true
 end
 local function ram(c)
  local found
  each(c.AbilityList,function(a)if STUN[name(a.AbilityName)]then found=a end end)
  return found
 end
 local function finish_cast(row)
  local cast=row.cast
  if not cast then return end
  row.cast=nil;charging[row.key]=nil
  local c=row.actor
  if not same(c,row)or not alive(c)then return end
  if cast.owned_animation then
   c.AbilityInUse=false;c.ChargeEnd=false
   if not cast.impacted and c.CurrentAnimation==3 then c:SetCurrentAnimation(11)end
  end
  local controller=c:GetController()
  if cast.stopped_brain and valid(cast.brain)and valid(controller)
   and controller:GetAddress()==cast.controller and cast.brain:IsRunning()~=true then cast.brain:RestartLogic()end
 end
 local function find_effect(c,wanted)
  local found
  each(c.Effects,function(e)if name(e.EffectName)==wanted then found=e end end)
  return found
 end
 local function apply_effect(c,id,kind,length,interval,owner)
  c:ApplyEffect({EffectName=FName(id),Type=kind,Length=length,Interval=interval,Timer=-1,Damage=0,
   DamageType=14,SpecialEffect=0,StackType=0,StackMax=1,CausingColonyID=owner,
   CausingTileID=-1,EventName=FName('None')})
 end
 local function clear_buff(row,remove_effect)
  local b=row.buff
  if not b then return end
  local c=row.actor
  if same(c,row)then
   for field,base in pairs(b.flags)do if c[field]==true then c[field]=base end end
   if b.speed and near(c.AttackSpeed,b.speed.output)then c.AttackSpeed=b.speed.base end
   if remove_effect then
    local e=find_effect(c,BUFF[b.kind])
    if e then e.Length=0 end
   end
   if b.kind==GUARD and o.unwatch_damage then o.unwatch_damage(c)end
  end
  row.buff=nil;active[row.key]=nil
 end
 local function apply_overlay(row)
  local c,b=row.actor,row.buff
  for _,field in ipairs(PROTECTION)do
   if b.flags[field]==nil or c[field]==false then b.flags[field]=c[field] end
   if c[field]~=true then c[field]=true end
  end
  if b.kind==FRENZY then
   local current=assert(number(c.AttackSpeed),'driver_attack_speed_unreadable')
   local base=b.speed and near(current,b.speed.output)and b.speed.base or current
   local desired=base*(1+b.amount)
   if not near(current,desired)then c.AttackSpeed=desired end
   b.speed={base=base,output=number(c.AttackSpeed)}
  end
 end
 local function attach_buff(row,kind,amount,now,length)
  if row.buff and row.buff.kind~=kind then clear_buff(row,true)end
  local buff=row.buff or{kind=kind,flags={}}
  buff.amount=amount;buff.until_time=now+length
  row.buff=buff;active[row.key]=row
  apply_overlay(row)
  return true
 end
 local function start_buff(row,count,now)
  local amount=math.min(M.maximum,math.max(M.minimum,count*M.per_stun))
  local c=row.actor
  if row.branch==GUARD and o.watch_damage(c)~=true then return false end
  local id=BUFF[row.branch]
  -- A neutral native animation-speed marker carries the saved duration.
  -- Type 31 only reads Damage and Length, leaving Interval for our potency.
  local e=find_effect(c,id)
  if not e then apply_effect(c,id,31,M.duration,-amount,row.owner);e=find_effect(c,id)end
  assert(e and number(e.Type)==31,'driver_buff_marker_missing')
  e.Length=M.duration;e.Interval=-amount
  return attach_buff(row,row.branch,amount,now,M.duration)
 end
 local function clock(ctx)return number(ctx.gs:GetLevelTime())end
 local function live_buff(row,now)
  local buff=row.buff
  return buff and now and now<buff.until_time and buff
 end
 local function protect_allies(row,now)
  local c=row.actor
  local source=position(c)
  if not source or not live_buff(row,now)then return end
  local amount=row.buff.amount*M.ally_guard_share
  local seen={}
  each(o.nearby(c,source,M.guard_radius),function(ally)
   local id=key(ally)
   if not id or id==row.key or seen[id]then return end
   seen[id]=true
   if not on_layer(ally,c.ColonyLocation,row.world)or not is_creature(ally)
    or not c:AmIAlliedWith(ally.ColonyID,ally.AlliedWithAllNoneColony)then return end
   local p=position(ally)
   if not p or distance(source,p)>M.guard_radius^2 then return end
   -- Shared native resistance effects survive saving and prevent this skill's
   -- protection stacking. Weaker casts leave stronger protection to expire.
   for effect,kind in pairs(ALLY_GUARD)do
    local e=find_effect(ally,effect)
    if not(e and e.Length>0 and e.Damage>amount)then
     if not e then
      apply_effect(ally,effect,kind,M.duration,-1,row.owner)
      e=find_effect(ally,effect)
     end
     assert(e and number(e.Type)==kind,'driver_ally_protection_missing')
     e.Length=M.duration;e.Damage=amount
    end
   end
   stats.protected=stats.protected+1
  end)
 end
 local function leech(row,dealt)
  local c=row.actor
  if dealt>0 and alive(c)and c.Health<c.FullHealth then
   c.Health=math.min(c.FullHealth,c.Health+dealt*row.buff.amount)
   stats.leeches=stats.leeches+1
  end
 end
 local function reward_kill(row,now)
  local b=live_buff(row,now)
  if not b or b.kind~=FRENZY then return end
  b.until_time=math.min(now+M.duration,b.until_time+M.kill_extension)
  local e=find_effect(row.actor,BUFF[FRENZY])
  if e then e.Length=b.until_time-now end
  stats.kills=stats.kills+1
 end
 local function sweep(row,token,now)
  local c=row.actor
  if not alive(c)or not token.center or not live_buff(row,now)then return end
  if not valid(damage_library)then damage_library=StaticFindObject('/Script/Engine.Default__GameplayStatics')end
  if not valid(physical_damage)then physical_damage=StaticFindObject('/Script/EotU.EotUPhysicalDamageType')end
  local ctl=c:GetController()
  assert(valid(damage_library)and valid(physical_damage)and valid(ctl),'driver_sweep_damage_unavailable')
  local amount=number(c:CalculatedDamageBuff(c.AttackDamage))
  assert(amount and amount>=0,'driver_sweep_damage_invalid')
  local seen={[token.target_key]=true}
  stats.sweeps=stats.sweeps+1
  each(o.nearby(c,token.center,M.sweep_radius),function(target)
   if not alive(c)or not live_buff(row,now)then return end
   local id=key(target)
   if not id or seen[id]then return end
   seen[id]=true
   if not enemy(c,target,token.layer,row.world)then return end
   local p=position(target)
   if not p or distance(p,token.center)>M.sweep_radius^2 then return end
   local hp=number(target.Health)
   damage_library:ApplyDamage(target,amount*M.sweep_multiplier,ctl,c,physical_damage)
   stats.swept=stats.swept+1
   if not same(c,row)or not alive(c)then return end
   local after=valid(target)and number(target.Health)
   if after then
    leech(row,hp-math.max(0,after))
    if hp>0 and after<=0 then reward_kill(row,now)end
   end
  end)
 end
 function api.observe(c,branch)
  if stopped then return true end
  local id=key(c);if not id then return true end
  local old=rows[id]
  if old and (not same(c,old)or branch~=old.branch or c.ColonyID~=old.owner)then
   finish_cast(old);clear_buff(old,true);rows[id]=nil;old=nil
  end
  if not BUFF[branch]then
   for _,effect in pairs(BUFF)do
    local e=find_effect(c,effect);if e then e.Length=0 end
   end
   return true
  end
  local ctx=o.get_context()
  if not ctx or not on_layer(c,number(c.ColonyLocation),ctx.world_id)then return true end
  if old then
   if old.buff then apply_overlay(old)end
   return true
  end
  local row={actor=c,key=id,name=c:GetFullName(),world=ctx.world_id,owner=c.ColonyID,branch=branch,next_search=0}
  rows[id]=row;world=ctx.world_id
  local e=find_effect(c,BUFF[branch])
  if e and number(e.Type)==31 then
   local length,amount=number(e.Length),number(e.Interval)
   local now=clock(ctx)
   if now and length and length>0 and length<=M.duration and amount and amount<0 and amount>=-M.maximum-.0001 then
    if branch~=GUARD or o.watch_damage(c)==true then attach_buff(row,branch,-amount,now,length)end
   end
  end
  return true
 end
 local function rescue_target(c,a,row)
  local source=position(c)
  local radius=number(a.MaxRange)
  if not source or not radius or radius<=0 then return nil end
  local layer=number(c.ColonyLocation)
  local minimum=math.max(0,number(a.MinRange)or 0)
  local best,best_dist
  each(o.nearby(c,source,radius),function(ally)
   if key(ally)==row.key or not on_layer(ally,layer,row.world) or ally.InCombat~=true
    or not c:AmIAlliedWith(ally.ColonyID,ally.AlliedWithAllNoneColony)then return end
   local t=ally.CurrentTarget
   if not enemy(c,t,layer,row.world)then t=ally.InCombatCreature end
   if not enemy(c,t,layer,row.world)then return end
   local p=position(t);if not p then return end
   local d=distance(source,p)
   if d>=minimum^2 and d<=radius^2 and (not best_dist or d<best_dist)then best,best_dist=t,d end
  end)
  return best
 end
 local function destination(c,target)
  if not valid(utility)then utility=StaticFindObject('/Script/EotU.Default__EotUUtilities')end
  if not valid(utility)then return nil end
  local origin,target_point=c:K2_GetActorLocation(),target:K2_GetActorLocation()
  local zone=c:GetCurrentZoneID()
  local function project(p,out)
   return utility:UEotUProjectToGrid(c,p,out,0,true,c,false,0,false,false,-1,zone,false,0,false,false,false)==true
  end
  local goal={X=0,Y=0,Z=0}
  if not project(target_point,goal)or not point(goal)then return nil end
  -- Use the same grid projection as the stock charge. Check intermediate
  -- tiles so a rescue cannot cut through an unexcavated corner.
  for _,fraction in ipairs({.25,.5,.75})do
   local step={X=origin.X+(goal.X-origin.X)*fraction,Y=origin.Y+(goal.Y-origin.Y)*fraction,Z=origin.Z+(goal.Z-origin.Z)*fraction}
   if not project(step,{X=0,Y=0,Z=0})then return nil end
  end
  return goal
 end
 local function advance_cast(row,ctx,now)
  local cast,c=row.cast,row.actor
  if not cast then return end
  if row.world~=ctx.world_id or not same(c,row)or not alive(c)or c.NoCombat or c.InPickup
   or c.ColonyLocation~=cast.layer or now>=cast.expires or cast.ending and c.AbilityEnd then
   finish_cast(row);return
  end
  if cast.ending or now<=cast.last then return end
  if not enemy(c,cast.target,cast.layer,row.world)then finish_cast(row);return end
  local p=position(c)
  if not p then finish_cast(row);return end
  local goal=cast.goal
  local length=math.sqrt(distance(p,point(goal)))
  local step=(now-cast.last)*RAM_SPEED
  cast.last=now
  local ratio=length>step and step/length or 1
  local next_position={X=p.x+(goal.X-p.x)*ratio,Y=p.y+(goal.Y-p.y)*ratio,Z=p.z+(goal.Z-p.z)*ratio}
  if c:K2_SetActorLocation(next_position,false,{},false)~=true then finish_cast(row);return end
  if ratio==1 or c:TargetReachable(true,true,-1,-1)==true then
   cast.ending=true;c.ChargeEnd=true
  end
 end
 local function ensure_motion_timer()
  if motion_timer then return end
  motion_timer=LoopInGameThreadAfterFrames(1,function()
   if not next(charging)then CancelDelayedAction(motion_timer);motion_timer=nil;return end
   local ctx=o.get_context()
   local now=ctx and clock(ctx)
   if not now then return end
   for _,row in pairs(charging)do
    local ok,err=pcall(advance_cast,row,ctx,now)
    if not ok then pcall(finish_cast,row);fail(err)end
   end
  end)
 end
 local function try_rescue(row,now)
  local c=row.actor
  if row.cast then return end
  local status=number(c.CreatureStatus)
  if c.NoCombat or c.InPickup or c.NoneBTControl or c.Immobile or c.AbilityInUse
   or status==5 or status==6 or status==7 or status==8 or status==9 or status==28 then return end
  local ability=ram(c)
  -- A rescue spends the first charge in a full pool. Further casts retain
  -- the stock activation rules, including the extra reserve branch.
  if not ability or (number(ability.Charges)or 0)<=0 or ability.Charges~=ability.FullCharges then return end
  local target=rescue_target(c,ability,row)
  if not target then return end
  local controller=c:GetController()
  local brain=valid(controller)and controller.BrainComponent
  if not valid(brain)or brain:IsRunning()~=true or c:CanIAttack()~=true then return end
  local goal=destination(c,target)
  if not goal then return end
  local cast={name=name(ability.AbilityName),target=target,goal=goal,layer=c.ColonyLocation,
   expires=now+2.5,last=now,brain=brain,controller=controller:GetAddress()}
  row.cast=cast;charging[row.key]=row
  local ok,started=pcall(function()
   brain:StopLogic('driver rescue charge');cast.stopped_brain=true
   controller:StopMovement()
   local current=ram(c)
   if not current or current.Charges~=current.FullCharges or current.Charges<=0 then return false end
   local timer=current.CooldownTimer
   local selected=c:ForceUseAbilityOnCreature(FName(cast.name),target)
   -- The script selector clears the native recharge timer.
   current=ram(c)
   if current and name(current.AbilityName)==cast.name then current.CooldownTimer=timer end
   if selected~=true then return false end
   c.SelectedAbility.CooldownTimer=timer
   c.CurrentTargetLocation=goal
   c.ChargeEnd=false;c.AbilityEnd=false
   c:UseAbility()
   cast.owned_animation=true;c.AbilityInUse=true
   -- Follow the stock Ram sequence, including its collision phase, and let
   -- the stock finish montage issue the damage notify and spend the charge.
   c:PhaseOut(1,true)
   c:SetTurnToLocation(goal)
   ensure_motion_timer()
   return true
  end)
  if not ok or not started then
   finish_cast(row)
   if not ok then error(started)end
   return
  end
  stats.started=stats.started+1
 end
 local function stun_state(c,wanted)
  local count,total=0,0
  each(c.Effects,function(e)
   if number(e.Type)==7 and name(e.EffectName)==wanted and (number(e.Length)or 0)>0 then
    count=count+1;total=total+e.Length
   end
  end)
  return count,total
 end
 function api.on_trigger_pre(c,id)
  local row=rows[id]
  if not row or not same(c,row)or not alive(c)then return nil end
  local selected=c.SelectedAbility
  local ability=name(selected.AbilityName)
  local cast=row.cast
  if STUN[ability]then
   local a=ram(c)
   if not a or a.Charges<=0 then return nil end
   local layer=number(c.ColonyLocation)
   local source=position(c)
   if not source then return nil end
   local target=c.CurrentTarget
   local target_point=enemy(c,target,layer,row.world)and position(target)or nil
   local radius=math.max(0,number(a.AOERad)or 0)
   local center=a.TargetLocation and point(c.CurrentTargetLocation)or nil
   if not center or distance(center,source)>((number(a.MaxRange)or 0)+radius)^2 then
    center=target_point or source
   end
   local wanted=STUN[ability]
   local victims={}
   local function snapshot(v)
    local k=key(v)
    if not k or victims[k]or not enemy(c,v,layer,row.world)then return end
    local p=position(v);if not p then return end
    local n,total=stun_state(v,wanted)
    victims[k]={actor=v,count=n,total=total,hp=number(v.Health),position=p,signature=v:GetFullName()}
   end
   each(o.nearby(c,center,math.max(160,radius+80)),snapshot)
   if distance(center,source)>1 then each(o.nearby(c,source,radius+80),snapshot)end
   snapshot(target)
   local stun_length=0
   each(selected.Effects,function(e)
    if number(e.Type)==7 and name(e.EffectName)==wanted then stun_length=math.max(stun_length,number(e.Length)or 0)end
   end)
   return {row=row,cast=cast,ability=ability,center=center,layer=layer,victims=victims,
    wanted=wanted,stun_length=stun_length,charges=a.Charges}
  end
  if ability=='BasicAttack'and row.buff and row.buff.kind==FRENZY then
   local ctx=o.get_context()
   local buff=ctx and ctx.world_id==row.world and live_buff(row,clock(ctx))
   local t=c.CurrentTarget
   if buff and enemy(c,t,c.ColonyLocation,row.world)then
    return {row=row,bite=true,buff=buff,target=t,target_key=key(t),center=position(t),
     layer=c.ColonyLocation,hp=t.Health,signature=t:GetFullName()}
   end
  end
 end
 function api.on_trigger_post(c,t,result)
  local row=t.row
  if rows[row.key]~=row or not same(c,row)or not alive(c)then return end
  local ctx=o.get_context()
  local now=ctx and ctx.world_id==row.world and clock(ctx)
  if not now then return end
  if t.bite then
   if result~=true or live_buff(row,now)~=t.buff or not valid(t.target)
    or t.target:GetFullName()~=t.signature or native.world_id(t.target)~=row.world then return end
   local after=number(t.target.Health)
   if not after then return end
   local dealt=t.hp-math.max(0,after)
   leech(row,dealt)
   if t.hp>0 and after<=0 then reward_kill(row,now)end
   sweep(row,t,now)
   return
  end
  local a=ram(c)
  if result~=true or not a or name(a.AbilityName)~=t.ability or a.Charges~=t.charges-1 then return end
  if t.cast and row.cast==t.cast then
   t.cast.impacted=true
   stats.rescue_impacts=stats.rescue_impacts+1
  end
  local count,hits,stunned=0,0,{}
  for _,v in pairs(t.victims)do
   if valid(v.actor)and native.world_id(v.actor)==row.world and v.actor:GetFullName()==v.signature then
    local n,total=stun_state(v.actor,t.wanted)
    local changed=n~=v.count or not near(total,v.total)
    local damaged=v.hp and number(v.actor.Health)and v.actor.Health<v.hp
    if changed or damaged then hits=hits+1 end
    if (changed or damaged)and n>0 and v.actor.CannotBeStunned~=true
     and enemy(c,v.actor,t.layer,row.world)then
     count=count+1;stunned[#stunned+1]=v.actor
    end
   end
  end
  stats.impacts=stats.impacts+1;stats.stunned=stats.stunned+count
  if hits>0 then start_buff(row,count,now)end
  if row.branch==GUARD then
   local extra=math.min(M.stun_maximum,hits*M.stun_per_hit)
   for _,target in ipairs(stunned)do
    local e=find_effect(target,t.wanted)
    if e then
     e.Length=math.max(e.Length,t.stun_length+extra)
     stats.extended_stuns=stats.extended_stuns+1
    end
   end
   if hits>0 then protect_allies(row,now)end
   for _,v in pairs(t.victims)do
    if distance(t.center,v.position)<=160^2 and enemy(c,v.actor,t.layer,row.world)and v.actor:GetFullName()==v.signature then
     v.actor.LatestTaunter=c
     apply_effect(v.actor,TAUNT,10,M.taunt_duration,-1,row.owner)
     stats.taunted=stats.taunted+1
    end
   end
  end
 end
 function api.on_damage(c,damage)
  if not next(active)or not damage or damage<=0 then return false end
  local row=active[key(c)]
  if not row or not same(c,row)or row.buff.kind~=GUARD then return false end
  local ctx=o.get_context()
  local b=ctx and ctx.world_id==row.world and live_buff(row,clock(ctx))
  if not b then return false end
  -- This engine delegate reports the exact post-armour debit before death.
  -- Refunding that fraction here preserves native damage and lethal ordering.
  local hp=number(c.Health)
  if not hp then return false end
  c.Health=math.min(c.FullHealth,hp+damage*b.amount)
  stats.reduced=stats.reduced+1
  return c.Health>0
 end
 function api.tick(ctx)
  if stopped or not next(rows)then return true end
  local ok,why=pcall(function()
   if world~=ctx.world_id then api.reset_cache();return end
   local now=clock(ctx);if not now then return end
   for id,row in pairs(active)do
    local c=row.actor
    if not same(c,row)or not alive(c)or not live_buff(row,now)then clear_buff(row,true)
    else apply_overlay(row)end
   end
   local first
   for _=1,SEARCH_BUDGET do
    local id,row
    if cursor and rows[cursor]then id,row=next(rows,cursor)end
    if not id then id,row=next(rows)end
    if not id or id==first then break end
    first=first or id;cursor=id
    local c=row.actor
    if not same(c,row)or not alive(c)or c.ColonyID~=row.owner then
     finish_cast(row);clear_buff(row,true);rows[id]=nil
    elseif now>=row.next_search then
     row.next_search=now+SEARCH_INTERVAL
     try_rescue(row,now)
    end
   end
  end)
  if not ok then return fail(why)end
  return true
 end
 function api.reset_cache()
  -- Game saves carry the native marker and remaining duration. Restore
  -- transient instance fields before dropping the old Lua world registry.
  for _,row in pairs(active)do clear_buff(row,false)end
  for _,row in pairs(rows)do finish_cast(row)end
  if motion_timer then CancelDelayedAction(motion_timer);motion_timer=nil end
  rows,active,charging,world,cursor={},{},{},nil,nil
  return true
 end
 function api.stop()
  for _,row in pairs(active)do clear_buff(row,true)end
  stopped=true;return api.reset_cache()
 end
 function api.status()
  local result={tracked=0,buffed=0}
  for _ in pairs(rows)do result.tracked=result.tracked+1 end
  for _ in pairs(active)do result.buffed=result.buffed+1 end
  for k,v in pairs(stats)do result[k]=v end
  return result
 end
 return api
end
return M
