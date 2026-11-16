-- Native effect carriers and temporary combat commands. No allegiance writes.
local M={confusion_name='EAA_LittleBlack_DeathConfusion',attack_name='EAA_LittleBlack_AttackSignal',
 signal_particle='/Game/Assets/Particles/SteamCloud.SteamCloud',signal_scale=.15,
 signal_deactivate=.6,signal_destroy=1.5,signal_limit=32}
-- Exact ordinary termite CreatureName values in current CreatureStats and the
-- roster. This is independent from the older slave-capture species whitelist.
M.termite_names={TermiteWorker=true,TermiteMajorWorker=true,TermiteSoldier=true,
 TermiteMajorSoldier=true,ExplodingTermiteWorker=true,ExplodingTermiteSoldier=true}
local function safe(f)local ok,v=pcall(f);if ok then return v end end
local function num(v)local n=tonumber(v);if n and n==n and math.abs(n)<math.huge then return n end end
local function name(v)return type(v)=='string'and v or v and safe(function()return v:ToString()end)end
local function each(a,f)
 if not a then return end
 if type(a)=='table'and not a.GetArrayNum then for _,v in ipairs(a)do f(v)end;return end
 for i=1,a:GetArrayNum()do f(a[i])end
end
function M.install(o)
 assert(o and o.native,'littleblack_native_dependencies')
 local native=o.native;local cache={};local api={}
 local visuals,visual_attempted,visual_error={},false,nil
 local visual_stats={spawned=0,deactivated=0,destroyed=0,dropped=0,errors=0}
 local function valid(c)return c~=nil and safe(function()return native.valid_object(c)end)==true end
 local function fname(s)return o.fname and o.fname(s)or FName(s)end
 -- Use the game's stock Creature collision query for Gaster effect snapshots.
 -- The caller also includes the direct target and verifies native effect
 -- changes after the attack. This is not a general replacement for the
 -- registry: guard counts and charm searches include non-overlapping actors.
 function api.aoe_candidates(source,center,radius)
  if not valid(source)or type(center)~='table'or not num(radius)or radius<0 then return nil end
  local utility=StaticFindObject('/Script/EotU.Default__EotUUtilities')
  if not valid(utility)then return nil end
  return safe(function()
   return utility:GetNearbyCreaturesAtLocation(source,{X=center.x,Y=center.y,Z=center.z},radius,{})
  end)
 end
 local function visual_fail(e)
  visual_error=tostring(e);visual_stats.errors=visual_stats.errors+1
  return nil,visual_error
 end
 local function visual_key(c)
  if not valid(c)then return nil end
  return tostring(c:GetAddress())..'|'..tostring(c:GetFullName())
 end
 local function destroy_visual(row)
  local c=row.component
  if not valid(c)or visual_key(c)~=row.key then return true end
  if not row.deactivated then c:Deactivate();row.deactivated=true;visual_stats.deactivated=visual_stats.deactivated+1 end
  local owner=c:GetOwner();c:K2_DestroyComponent(valid(owner)and owner or c)
  assert(not valid(c),'littleblack_signal_destroy_not_applied')
  visual_stats.destroyed=visual_stats.destroyed+1;return true
 end
 function api.prepare_signal()
  if visual_attempted then return valid(cache.signal_particle)and valid(cache.signal_gameplay)or nil,visual_error end
  visual_attempted=true
  local ok,why=pcall(function()
   local find=o.find_object or StaticFindObject
   cache.signal_gameplay=find('/Script/Engine.Default__GameplayStatics')
   local particle=find(M.signal_particle)
   if not valid(particle)then
    local load=o.load_asset or LoadAsset
    assert(type(load)=='function','littleblack_signal_loader_unavailable');particle=load(M.signal_particle)
   end
   assert(valid(particle),'littleblack_signal_particle_unavailable')
   assert(valid(cache.signal_gameplay),'littleblack_signal_gameplay_unavailable')
   cache.signal_particle=particle
  end)
  if not ok then return visual_fail(why)end;return true
 end
 function api.emit_signal(c,now)
  -- Never load an asset or discover the gameplay library in a lethal callback.
  if not valid(c)or not num(now)then return visual_fail('littleblack_signal_invalid_source')end
  if not visual_attempted or not valid(cache.signal_particle)or not valid(cache.signal_gameplay)then return visual_fail('littleblack_signal_not_preloaded')end
  if #visuals>=M.signal_limit then visual_stats.dropped=visual_stats.dropped+1;return nil,'littleblack_signal_capacity'end
  local ok,why=pcall(function()
   local p=c:K2_GetActorLocation()
   local component=cache.signal_gameplay:SpawnEmitterAtLocation(c,cache.signal_particle,p,
    {Pitch=0,Yaw=0,Roll=0},{X=M.signal_scale,Y=M.signal_scale,Z=M.signal_scale},true,0,true)
   assert(valid(component),'littleblack_signal_spawn_failed')
   visuals[#visuals+1]={component=component,key=visual_key(component),started=now,world=native.world_id(c)}
   visual_stats.spawned=visual_stats.spawned+1
  end)
  if not ok then return visual_fail(why)end;return true
 end
 function api.tick_visuals(now,world)
  if not num(now)then return visual_fail('littleblack_signal_clock_invalid')end
  local first_error
  for i=#visuals,1,-1 do
   local row=visuals[i];local c=row.component
   local ok,why=pcall(function()
    if not valid(c)or visual_key(c)~=row.key then table.remove(visuals,i);return end
    if now<row.started or now-row.started>=M.signal_destroy or world and row.world~=world then
     destroy_visual(row);table.remove(visuals,i)
    elseif not row.deactivated and now-row.started>=M.signal_deactivate then
     c:Deactivate();row.deactivated=true;visual_stats.deactivated=visual_stats.deactivated+1
    end
   end)
   if not ok then first_error=first_error or why end
  end
  if first_error then return visual_fail(first_error)end;return true
 end
 function api.visual_status()
  local s={active=#visuals,prepared=visual_attempted,last_error=visual_error}
  for k,v in pairs(visual_stats)do s[k]=v end;return s
 end
 local function is_a(c,path)
  local cls=cache[path];if not valid(cls)then cls=StaticFindObject(path);cache[path]=cls end
  return valid(cls)and c:IsA(cls)==true
 end
 local function ordinary(c)
  if not valid(c)or c.CannotBeConfused==true or c.DisableStandardSave==true or c.Immobile==true then return false end
  local n=(name(c.CreatureName)or''):lower();local path=safe(function()return c:GetClass():GetFullName()end)or''
  if n:find('queen')or n:find('king')or path:find('Queen')or path:find('Uber')or path:find('Titan')or path:find('Boss')then return false end
  local forbidden=false;each(c.Tags,function(t)local s=(name(t)or''):lower();if s:find('objective')or s:find('missioncritical')or s:find('quest')or s:find('script')then forbidden=true end end)
  if forbidden then return false end
  if o.is_ordinary then return o.is_ordinary(c)==true end
  return not is_a(c,'/Script/EotU.QueenCreature')and not is_a(c,'/Script/EotU.CreatureAttackPoint')
 end
 function api.charm_size(c)
  if not ordinary(c)or(num(c.AttackDamage)or 0)<=0 or c.HarmlessCreature==true then return nil end
  if o.classify then return o.classify(c)end
  local cls=c:GetClass();local path=cls:GetFullName():match('^[^ ]+ (.+)$')
  local sizes=o.sizes;local value=sizes and sizes[path]
  if value then return value end
  local ants=o.ant_names or{};local species=name(c.CreatureName)
  if ants[species]or M.termite_names[species]then return'small'end
  return nil
 end
 function api.can_charm_target(c)return valid(c)and c.CanBeAttacked~=false and ordinary(c)end
 function api.is_incapacitated(c)
  -- Live normal actors are the overwhelmingly common spatial-index path.
  -- Captive/wounded actors are frozen by the existing adapter; avoid repeatedly
  -- parsing every ordinary creature's persistent tags at 10 Hz.
  if(num(c.Health)or 0)>0 and c.Immobile~=true and c.NoCombat~=true then return false end
  if o.slaver and o.slaver.describe_state then local r=o.slaver.describe_state(c);if r and(r.state=='knocked_out'or r.state=='wounded')then return true end end
  local frozen=false;each(c.Tags,function(t)local s=name(t)or'';if s:match('^EAA_Slaver_v1:knocked_out:')or s:match('^EAA_Slaver_v1:wounded:')then frozen=true end end)
  return frozen
 end
 -- A negative geometry filter may skip later predicates only while these
 -- exact native readers remain installed. On an ordinary live actor the KO
 -- reader returns before consulting the slaver adapter; ordinary target
 -- checks have no external callback unless is_ordinary was supplied.
 local geometry_ko_reader,geometry_target_reader=api.is_incapacitated,api.can_charm_target
 local function geometry_readers_unchanged()
  return o.is_ordinary==nil and api.is_incapacitated==geometry_ko_reader
   and api.can_charm_target==geometry_target_reader and api.position==nil and api.allied==nil
 end
 function api.charm_geometry_prefilter_safe(c)
  if not geometry_readers_unchanged()then return false end
  -- The caller has already proved engine validity and Creature class. Require
  -- primitive finite HP and exact flags, matching the native KO short circuit.
  -- Boxed/unknown values, frozen actors and custom readers use the old path.
  local hp,immobile,no_combat=c.Health,c.Immobile,c.NoCombat
  return type(hp)=='number'and hp>0 and hp<math.huge and immobile==false and no_combat==false
   and geometry_readers_unchanged()
 end
 local function carrier(c)
  local found
  each(c.AbilityList,function(a)
   if(name(a.AbilityName)or''):match('^LittleBlackAntGasterFlag[123]$')then
    each(a.Effects,function(e)if num(e.Type)==6 then found=e end end)
   end
  end);return found
 end
 local function apply_effect(source,target,effect_name,kind,seconds,amount)
  local e=assert(carrier(source),'littleblack_effect_carrier_missing')
  local replace={EffectName=fname(effect_name),Type=kind,Length=seconds,Interval=-1,Timer=-1,Damage=amount,
   DamageType=0,SpecialEffect=15,StackType=0,StackMax=1,CausingColonyID=num(source.ColonyID),CausingTileID=-1,EventName=fname('None')}
  local saved,touched={},{}
  for field in pairs(replace)do saved[field]=e[field];if field=='EffectName'or field=='EventName'then saved[field]=fname(assert(name(saved[field])))end;assert(saved[field]~=nil,'littleblack_effect_unreadable:'..field)end
  local ok,err=pcall(function()for field,value in pairs(replace)do touched[#touched+1]=field;e[field]=value end;target:ApplyEffect(e)end)
  local restored=true;for i=#touched,1,-1 do local f=touched[i];restored=pcall(function()e[f]=saved[f]end)and restored end
  assert(restored,'littleblack_carrier_restore_failed');if not ok then error(err)end
  local found;each(target.Effects,function(v)if name(v.EffectName)==effect_name and num(v.Type)==kind and(num(v.Length)or 0)>0 then found=v end end)
  assert(found,'littleblack_effect_readback_failed:'..effect_name);return found
 end
 function api.confuse(source,target,seconds)
  if not valid(source)or not valid(target)or target.CannotBeConfused==true or seconds<=0 then return false end
  apply_effect(source,target,M.confusion_name,6,seconds,0);return true
 end
 function api.confuse_origin(origin,target,seconds)
  -- A charm outlives its caster. Keep only the validated world/colony values
  -- and create an owned effect value instead of borrowing a dead actor's row.
  local colony=type(origin)=='table'and num(origin.colony)
  seconds=num(seconds)
  if not colony or colony< -1 or colony%1~=0 or not valid(target)or not seconds or seconds<=0
   or origin.world==nil or native.world_id(target)~=origin.world or target.CannotBeConfused==true then return false end
  target:ApplyEffect({EffectName=fname(M.confusion_name),Type=6,Length=seconds,Interval=-1,Timer=-1,Damage=0,
   DamageType=0,SpecialEffect=15,StackType=0,StackMax=1,CausingColonyID=colony,CausingTileID=-1,EventName=fname('None')})
  local found;each(target.Effects,function(e)
   if name(e.EffectName)==M.confusion_name and num(e.Type)==6 and(num(e.Length)or 0)>0 then found=e end
  end)
  assert(found,'littleblack_effect_readback_failed:'..M.confusion_name)
  return true
 end
 function api.update_attack_signal(c,multiplier,remaining,source)
  if not valid(c)then return false end
  local own,positive,negative=nil,0,0
  local resistance=num(c.SlowResist)or 0
  each(c.Effects,function(e)
   if name(e.EffectName)==M.attack_name then own=e
   elseif num(e.Type)==31 and(num(e.Length)or 0)>0 then
    local d=num(e.Damage)or 0;positive=math.max(positive,d);negative=math.min(negative,d+resistance)
   end
  end)
  if multiplier<=1 or remaining<=0 then
   if own then own.Length=0 end
   return true
  end
  local attack=assert(num(c.AttackSpeed),'littleblack_attack_speed_invalid')
  -- Native animation rate is AttackSpeed + AnimSpeedChange. Native Type31
  -- takes max positive and min resistance-adjusted negative. Solve for our
  -- one positive effect, retaining the other effects and the real base stat.
  local baseline=math.max(.05,attack+positive+negative)
  local desired=math.max(positive,baseline*multiplier-attack-negative)
  if not own then
   if not valid(source)then return nil,'littleblack_buff_carrier_source_unavailable'end
   own=apply_effect(source,c,M.attack_name,31,remaining,desired)
  else own.Length=remaining;own.Damage=desired end
  assert(num(own.Type)==31 and math.abs((num(own.Damage)or -1)-desired)<.00001,'littleblack_attack_signal_readback_failed')
  return true
 end
 function api.suppress_confusion(c,e)
  if not valid(c)or num(e.Type)~=6 then return false end
  -- Leave removal/status restoration to native TickEffects. A zero-duration
  -- Confused entry is expired, never converted into a permanent unknown effect.
  e.Length=0;c:TickEffects(0);return true
 end
 local function basic(c)
  local found;each(c.AbilityList,function(a)if name(a.AbilityName)=='BasicAttack'and num(a.AbilityType)==1 then found=a end end);return found
 end
 function api.basic_damage(c)
  -- This is the same native buff calculation used by BasicAttack immediately
  -- before its physical ApplyDamage call, including the actor's current buffs.
  local base=assert(num(c.AttackDamage),'littleblack_attack_damage_invalid')
  local damage=assert(num(c:CalculatedDamageBuff(base)),'littleblack_native_damage_buff_invalid')
  return damage
 end
 function api.apply_charm_basic(c,target,amount)
  if not valid(c)or not valid(target)or(num(c.Health)or 0)<=0 or(num(target.Health)or 0)<=0 then return false end
  local ctl=c:GetController();if not valid(ctl)then return nil,'littleblack_charm_damage_controller_missing'end
  local lib=cache.damage_library
  if not valid(lib)then lib=StaticFindObject('/Script/Engine.Default__GameplayStatics');cache.damage_library=lib end
  local kind=cache.physical_damage
  if not valid(kind)then kind=StaticFindObject('/Script/EotU.EotUPhysicalDamageType');cache.physical_damage=kind end
  assert(valid(lib)and valid(kind),'littleblack_charm_native_damage_unavailable')
  -- Native TakeDamage rejects a same-colony DamageCauser. Only the runtime's
  -- accepted charm hit invokes this bridge; nil causer avoids that filter while
  -- retaining the actual attacker controller and all native damage mitigation.
  lib:ApplyDamage(target,amount,ctl,nil,kind)
  return true -- Dispatch proof, never a claim that armor/evasion allowed damage.
 end
 function api.begin_charm(c,target,effect,source)
  if not ordinary(c)or not valid(target)or not basic(c)then return nil,'littleblack_charm_basic_attack_unavailable'end
  local ctl=c:GetController();if not valid(ctl)then return nil,'littleblack_charm_controller_missing'end
  local brain=ctl.BrainComponent;if not valid(brain)then return nil,'littleblack_charm_brain_missing'end
  local ticket={controller=ctl,brain=brain,was_running=brain:IsRunning()==true,was_paused=brain:IsPaused()==true,
   colony=num(c.ColonyID),no_combat=c.NoCombat,none_bt=c.NoneBTControl,target=c.CurrentTarget,last_command=nil}
  local original_duration=num(effect.Length)or 0
  local ok,err=pcall(function()
   assert(api.suppress_confusion(c,effect),'littleblack_confusion_suppress_failed')
   ctl:StopMovement();brain:StopLogic('Ant Overhaul temporary confusion charm')
   c:ForceLeaveCombat();c.NoCombat=false;c.NoneBTControl=true
   assert(num(c.ColonyID)==ticket.colony,'littleblack_charm_owner_changed')
  end)
  if not ok then
   pcall(api.end_charm,c,ticket)
   if valid(source)and original_duration>0 then pcall(api.confuse,source,c,original_duration)end
   return nil,tostring(err)
  end
  return ticket
 end
 function api.refresh_charm(c,e,ticket)
  if not api.suppress_confusion(c,e)then return false end
  -- Expiring native Confused can reset its behavior tree. Retain the temporary
  -- controller after removing this hit's effect, without touching other effects.
  if ticket and valid(ticket.brain)then ticket.brain:StopLogic('Ant Overhaul temporary confusion charm')end
  return true
 end
 function api.tick_charm(c,target,ticket,now)
  if not valid(c)or not valid(target)or not valid(ticket.controller)or num(c.ColonyID)~=ticket.colony then return false end
  if c.AbilityInUse==true then return true end
  local ability=basic(c);if not ability then return false end
  if ticket.last_command and now-ticket.last_command<0.15 then return true end
  -- ForceUse selects the actor's own ordinary attack and keeps the real owner.
  -- Native BasicAttack's target gate is range/facing, not same-colony rejection.
  -- UseAbility starts its actual animation; the native notify delivers damage.
  c:ForceUseAbilityOnCreature(fname('BasicAttack'),target)
  if name(c.SelectedAbility.AbilityName)~='BasicAttack'then return false end
  if c:TargetWithinAbilityRange(false,target)==true then
   ticket.controller:StopMovement();c:UseAbility();ticket.last_command=now
  else
   local p=target:K2_GetActorLocation();c.CurrentTarget=target;c.CurrentTargetLocation=p
   c:SetTurnToTarget(target)
   if ticket.move_target~=target or not ticket.move_at or now-ticket.move_at>=0.5 then
    local helper=cache.move_helper
    if not valid(helper)then helper=StaticFindObject('/Script/AIModule.Default__AIBlueprintHelperLibrary');cache.move_helper=helper end
    if not valid(helper)then return false end
    ticket.proxy=helper:CreateMoveToProxyObject(c,c,p,nil,math.max(5,num(c.ArrivalDist)or 25),false)
    if not valid(ticket.proxy)then return false end;ticket.move_target=target;ticket.move_at=now
   else c:UpdateMovementGoal(p)end
  end
  return num(c.ColonyID)==ticket.colony
 end
 function api.end_charm(c,ticket)
  if not ticket then return true end
  if not valid(c)or(num(c.Health)or 0)<=0 or num(c.ColonyID)~=ticket.colony or api.is_incapacitated(c)then return true end
  local current_controller=c:GetController()
  if not valid(current_controller)or not valid(ticket.controller)or current_controller:GetAddress()~=ticket.controller:GetAddress()then return true end
  -- Capture/conversion or another task owns any new lifecycle/control state.
  -- Never wake a knocked-out corpse or put its former combat flags back.
  if c.NoneBTControl~=true then return true end
  local no_combat=c.NoCombat
  ticket.controller:StopMovement();c:ForceLeaveCombat()
  c.NoCombat=no_combat==false and ticket.no_combat or no_combat
  c.NoneBTControl=ticket.none_bt
  if ticket.was_running and not ticket.was_paused and valid(ticket.brain)then ticket.brain:RestartLogic()end
  return true
 end
 function api.reset_cache()
  local first_error
  for _,row in ipairs(visuals)do local ok,why=pcall(destroy_visual,row);if not ok then first_error=first_error or why end end
  visuals={};cache={};visual_attempted=false
  if first_error then visual_fail(first_error)end
  -- Presentation cleanup must never stop a world reset or the combat service.
  return true
 end
 return api
end
return M
