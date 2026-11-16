-- Supplemental combat operates on validated actors in the current world.
-- Importing this module performs no engine calls, hooks, IO, or scans.
local M = {}
M.invulnerable_effect = 'EAA_Trapjaw_Shelter'
M.evasion_multiplier = 0.6
M.invulnerable_seconds = 1.5
M.sting_marker = 'EAA_Trapjaw_StingMode_v1'
M.retreat_damage_multiplier = 4
M.sting_damage_multiplier = 1.5
M.sting_interval = 0.8
M.specialized_interval_multiplier = 0.75
M.last_target_seconds = 2
M.melee_range = 200

local function safe(fn) local ok,v=pcall(fn);if ok then return v end end
local function unbox(v)
 if v==nil then return nil end
 local inner=safe(function()return v:get()end)
 return inner~=nil and inner or v
end
local function name(v)
 v=unbox(v);if type(v)=='string'then return v end
 return v and safe(function()return v:ToString()end)or nil
end
local function finite(v)return type(v)=='number'and v==v and v~=math.huge and v~=-math.huge end
local function number(v)local n=tonumber(unbox(v));return finite(n)and n or nil end
local function equal(a,b)
 if finite(a)and finite(b)then return math.abs(a-b)<=math.max(1e-6,math.abs(a)*1e-6,math.abs(b)*1e-6)end
 return a==b
end
local function escape(v)
 local s=name(v);return s and s:lower():match('^trapjawescape[123]$')~=nil
end
local driver_rampage={
 DriverAntSuperSoldierRampage1=true,
 DriverAntSuperSoldierRampage2=true,
 DriverAntSuperSoldierRampage3=true,
}
local function each(array,fn)
 assert(array~=nil,'missing_array')
 if type(array)=='table'and type(array.GetArrayNum)~='function'then
  assert(#array<=128,'array_too_large')
  for i,v in ipairs(array)do fn(i,unbox(v))end
 else
  local count=array:GetArrayNum()
  assert(finite(count)and count>=0 and count%1==0 and count<=128,'invalid_array_length')
  for i=1,count do fn(i,unbox(array[i]))end
 end
end
local function find_ability(creature,wanted)
 local found
 each(creature.AbilityList,function(_,a)
  if name(a.AbilityName)==wanted then assert(not found,'duplicate_escape_ability');found=a end
 end)
 return found
end
local function find_heal(ability)
 local found
 each(ability.Effects,function(_,e)
  local n=name(e.EffectName)
  if n and n:lower():match('^trapjawescapeheal[123]$')then
   assert(not found,'duplicate_escape_heal');found=e
  end
 end)
 return found
end

function M.install(options)
 assert(type(options)=='table'and type(options.native)=='table','skill_runtime_dependencies_required')
 assert(type(options.get_context)=='function'and type(options.get_choices)=='function','skill_runtime_context_required')
 local native=options.native
 local stopped=false
 local cache,pending,reported,hooks={},{},{},{}
 local watching,rescuing,recent,attacking,escaping={},{},{},{},{}
 local cache_cursor,watching_cursor,recent_cursor
 local ensure_jump_hook
 local geometry_helpers={}
 local control={decorations=0,escapes=0,invulnerable=0,lethal_rescues=0,lethal_failures=0,
  retreat_hits=0,sting_attacks=0,sting_transitions=0,fallback_jumps=0,fallback_blocked=0,last_error=nil}
 local api={}
 local function valid(o)return o~=nil and safe(function()return native.valid_object(o)end)==true end
 local function failure(err)
  err=tostring(err);control.last_error=err
  if not reported[err]then
   reported[err]=true;if options.log then pcall(options.log,'[SupplementalSkills] '..err)end
  end
  return nil,err
 end
 local function identity(c)
  if not valid(c)then return nil end
  local a=safe(function()return c:GetAddress()end)
  local n=safe(function()return c:GetFullName()end)
  if a==nil or type(n)~='string'then return nil end
  return tostring(a),n..'|'..tostring(number(c.CreatureLevel))
 end
 local function authorized(c,allow_lethal)
  if stopped or not valid(c)then return nil end
  local n=name(c.CreatureName)
  if not n or n:lower()~='trapjawant'then return nil end
  local health=number(c.Health);if not health or(health<=0 and not allow_lethal)then return nil end
  local ctx=options.get_context()
  local gs=type(ctx)=='table'and(ctx.gs or ctx.game_state)or nil
  local permitted=valid(gs)and(options.combat and options.combat.eligible(c,gs)or
   (not options.combat and native.is_owned(c,gs)==true))
  if not permitted then return nil end
  local choices=options.get_choices(c)
  if choices==nil then choices={}end -- Innate combat does not require a purchased branch.
  assert(type(choices)=='table','invalid_skill_choices')
  assert(choices.left==nil or choices.left=='recovery'or choices.left=='invulnerable','invalid_left_skill')
  assert(choices.right==nil or choices.right=='evasion'or choices.right=='reward','invalid_right_skill')
  return choices,ctx,gs
 end
 local function tags(c)
  local values={};local a=c.Tags
  if type(a)=='table'and type(a.GetArrayNum)~='function'then
   assert(#a<=8192,'sting_tags_invalid');for _,v in ipairs(a)do values[#values+1]=assert(name(v),'sting_tag_unreadable')end
  else
   local n=number(a:GetArrayNum());assert(n and n>=0 and n<=8192,'sting_tags_invalid')
   for i=1,n do values[#values+1]=assert(name(a[i]),'sting_tag_unreadable')end
  end
  return values
 end
 local function sting_mode(c)
  for _,v in ipairs(tags(c))do if v==M.sting_marker then return true end end
  return false
 end
 function api.is_sting(c)
  if not valid(c)then return false end
  return safe(function()return sting_mode(c)end)==true
 end
 local function enter_sting(c)
  if sting_mode(c)then return false end
  local before,after=tags(c),{}
  for i,v in ipairs(before)do after[i]=FName(v)end
  after[#after+1]=FName(M.sting_marker)
  c.Tags=after
  assert(sting_mode(c),'sting_marker_readback_failed')
  control.sting_transitions=control.sting_transitions+1
  return true
 end
 local function sting_animation(c)
  local a=options.sting_animation
  if not a then return nil end
  local value,why=a.enable(c)
  assert(value,why or 'sting_animation_enable_failed')
  local length=type(value)=='table'and number(value.length)or number(value)
  assert(length and length>0 and length<=10,'sting_animation_length_invalid')
  return length
 end
 local function fields(c)
  local result={}
  each(c.AbilityList,function(_,a)
   if escape(a.AbilityName)then
    local id=name(a.AbilityName)
    assert(not result[id..':cd'],'duplicate_escape_ability')
    local cd=number(a.Cooldown);assert(cd,'escape_cooldown_unreadable')
    result[id..':cd']={owner=a,field='Cooldown',value=cd,kind='cooldown'}
    local heal=find_heal(a)
    if heal then
     local value=number(heal.Damage);assert(value,'escape_heal_unreadable')
     result[id..':heal']={owner=heal,field='Damage',value=value,kind='heal'}
    end
   end
  end)
  local speed=number(c.AttackSpeed)
  if speed then result['sting:speed']={owner=c,field='AttackSpeed',value=speed,kind='speed'}end
  return result
 end
 local function write_fields(c,changes)
  local applied={}
  local ok,err=pcall(function()
   for _,change in ipairs(changes)do
    applied[#applied+1]=change;change.row.owner[change.row.field]=change.after
   end
   local after=fields(c)
   for _,change in ipairs(changes)do
    assert(after[change.key]and equal(after[change.key].value,change.after),'skill_field_readback:'..change.key)
   end
  end)
  if ok then return true end
  local restored=true
  for i=#applied,1,-1 do
   local change=applied[i]
   local good=pcall(function()change.row.owner[change.row.field]=change.before end)
   restored=restored and good
  end
  local checked=safe(function()return fields(c)end)
  for _,change in ipairs(applied)do
   restored=restored and checked~=nil and checked[change.key]~=nil and equal(checked[change.key].value,change.before)
  end
  error(tostring(err)..'; rollback_verified='..tostring(restored))
 end
 local function restore(c)
  local key,signature=identity(c);if not key then return {changed=false}end
  local old=cache[key]
  if not old or old.signature~=signature then cache[key]=nil;return {changed=false}end
  local current,changes=fields(c),{}
  for id,tracked in pairs(old.fields)do
   local row=current[id]
   if row and equal(row.value,tracked.after)and not equal(row.value,tracked.base)then
    changes[#changes+1]={key=id,row=row,before=row.value,after=tracked.base}
   end
  end
  write_fields(c,changes);cache[key]=nil
  return {changed=#changes>0,writes=#changes}
 end
 -- Always bracket extra.apply with before_attributes/decorate. This strips
 -- only our exact last output, so numeric cultivation keeps its own baseline.
 function api.before_attributes(c)
  local ok,result=pcall(restore,c);if not ok then return failure(result)end;return result
 end
 function api.decorate(c,rebase)
  local ok,result=pcall(function()
   local choices=authorized(c)
   if not choices then
    local id=identity(c);if id then watching[id]=nil;recent[id]=nil end
    local result=restore(c)
    if valid(c)and options.sting_animation and type(options.sting_animation.disable)=='function'then
     local ok,why=options.sting_animation.disable(c);assert(ok,why or 'sting_animation_restore_failed')
    end
    return result
   end
   local key,signature=identity(c);assert(key,'skill_identity_unresolved')
   if choices.left=='invulnerable'then
    -- Shared native damage dispatcher registers this exact live instance. A
    -- later corpse cannot become eligible merely by looking like a trapjaw.
    if type(options.watch_damage)=='function'and options.watch_damage(c)==true then
     watching[key]={signature=signature,creature=c,world=native.world_id(c)}
    end
   else watching[key]=nil end
   if ensure_jump_hook then ensure_jump_hook()end
   local sting=sting_mode(c)
   local length=sting and sting_animation(c)or nil
   local interval=M.sting_interval*(choices.right=='reward'and M.specialized_interval_multiplier or 1)
   local old=cache[key]
   if rebase or not old or old.signature~=signature then old={fields={}}end
   local current,next_fields,changes=fields(c),{},{}
   for id,row in pairs(current)do
    local prior=old.fields[id]
    local base=prior and equal(row.value,prior.after)and prior.base or row.value
    local desired=base
    if row.kind=='cooldown'and choices.right=='evasion'and base>0 then desired=base*M.evasion_multiplier end
    if row.kind=='heal'and choices.left=='recovery'and base>0 then desired=base*2 end
    if row.kind=='speed'and length and base>0 then desired=base*length/interval end
    assert(finite(desired),'skill_nonfinite_value')
    if not equal(desired,base)then next_fields[id]={base=base,after=desired}end
    if not equal(desired,row.value)then changes[#changes+1]={key=id,row=row,before=row.value,after=desired}end
   end
   write_fields(c,changes)
   if next(next_fields)then cache[key]={signature=signature,creature=c,fields=next_fields}else cache[key]=nil end
   if #changes>0 then control.decorations=control.decorations+1 end
   return {changed=#changes>0,writes=#changes}
  end)
  if not ok then return failure(result)end;return result
 end
 function api.decorate_driver(c)
  local ok,result=pcall(function()
   if stopped or not valid(c)or name(c.CreatureName)~='DriverAntLargeSoldier' or c.Health<=0 then
    return {changed=false}
   end
   local ability
   each(c.AbilityList,function(_,row)
    if driver_rampage[name(row.AbilityName)]then
     assert(not ability,'duplicate_driver_rampage')
     ability=row
    end
   end)
   if not ability then return {changed=false}end

   local choices=options.get_choices(c,'DriverAntLargeSoldier')or{}
   local before={Cooldown=number(ability.Cooldown),FullCharges=number(ability.FullCharges),Charges=number(ability.Charges)}
   local after={Cooldown=before.Cooldown,FullCharges=before.FullCharges,Charges=before.Charges}
   -- Only replace known stock values or our own outputs. The native
   -- ability continues to own the trigger, live timer and refill rule.
   if before.Cooldown==25 or before.Cooldown==20 then
    after.Cooldown=choices.right=='ready_charge'and 20 or 25
   end
   if (before.FullCharges==2 or before.FullCharges==3)and before.Charges and before.Charges>=0 then
    after.FullCharges=choices.right=='extra_charge'and 3 or 2
    after.Charges=math.min(before.Charges,after.FullCharges)
    local timer=number(ability.CooldownTimer)
    -- A full native pool can keep its timer parked at the recharge length.
    local full_pool=before.Charges==before.FullCharges and timer
     and (timer<=0 or equal(timer,before.Cooldown))
    if after.FullCharges>before.FullCharges and full_pool then
     after.Charges=after.FullCharges
    end
   end
   local written={}
   local applied,err=pcall(function()
    for _,field in ipairs({'Cooldown','FullCharges','Charges'})do
     if after[field]~=before[field]then
      written[#written+1]=field
      ability[field]=after[field]
      assert(number(ability[field])==after[field],'driver_rampage_readback:'..field)
     end
    end
   end)
   if not applied then
    local restored=true
    for i=#written,1,-1 do
     local field=written[i]
     local rollback_ok=pcall(function()
      ability[field]=before[field]
      assert(number(ability[field])==before[field])
     end)
     restored=restored and rollback_ok
    end
    error(tostring(err)..'; rollback_verified='..tostring(restored))
   end
   if options.driver_rescue then options.driver_rescue.observe(c,choices.left)end
   return {changed=#written>0}
  end)
  if not ok then return failure(result)end
  return result
 end
 local function apply_invulnerable(c,ability)
  local existing
  each(c.Effects,function(_,effect)
   if name(effect.EffectName)==M.invulnerable_effect then existing=effect end
  end)
  if existing then
   assert(number(existing.Type)==18,'owned_invulnerable_type_mismatch')
   existing.Length=M.invulnerable_seconds;existing.Timer=-1
   assert(equal(number(existing.Length),M.invulnerable_seconds),'invulnerable_refresh_failed')
   c.CanBeAttacked=false
   assert(c.CanBeAttacked==false,'invulnerable_immediate_flag_failed')
   return true
  end
  -- UE4SS cannot universally marshal an arbitrary FEffect from a Lua table.
  -- Borrow a per-instance FEffect as a synchronous value parameter, then restore
  -- every touched member even if ApplyEffect throws. Never borrow a DataTable row.
  local carrier=assert(find_heal(ability),'escape_effect_carrier_missing')
  local replacements={EffectName=FName(M.invulnerable_effect),Type=18,Length=M.invulnerable_seconds,
   Interval=-1,Timer=-1,Damage=-1,DamageType=0,SpecialEffect=0,StackType=0,StackMax=1,
   CausingColonyID=number(c.ColonyID),CausingTileID=-1,EventName=FName('None')}
  local saved={}
  for field in pairs(replacements)do
   saved[field]=carrier[field];assert(saved[field]~=nil,'effect_member_unreadable:'..field)
   -- Preserve names as independent values, never a possibly mapped wrapper.
   if field=='EffectName'or field=='EventName'then saved[field]=FName(assert(name(saved[field])))end
  end
  local touched={}
  local ok,err=pcall(function()
   for field,value in pairs(replacements)do touched[#touched+1]=field;carrier[field]=value end
   c:ApplyEffect(carrier)
  end)
  local restored=true
  for i=#touched,1,-1 do
   local field=touched[i];local good=pcall(function()carrier[field]=saved[field]end);restored=restored and good
  end
  for _,field in ipairs(touched)do
   local value=safe(function()return carrier[field]end)
   if field=='EffectName'or field=='EventName'then restored=restored and name(value)==name(saved[field])
   else restored=restored and equal(number(value),number(saved[field]))end
  end
  assert(restored,'invulnerable_carrier_restore_failed')
  if not ok then error(err)end
  local observed=false
  each(c.Effects,function(_,e)
   if name(e.EffectName)==M.invulnerable_effect then observed=number(e.Type)==18 and equal(number(e.Length),M.invulnerable_seconds)end
  end)
  assert(observed,'invulnerable_effect_readback_failed')
  -- Type 18 normally sets this flag on TickEffects. Commit it immediately so
  -- a second hit in this same frame cannot kill the rescued actor. Expiry and
  -- restoration remain owned by the native 1.5-second effect, not a Lua timer.
  c.CanBeAttacked=false
  assert(c.CanBeAttacked==false,'invulnerable_immediate_flag_failed')
  return true
 end
 local function hostile_target(c,target,world)
  if not valid(target)or native.world_id(target)~=world then return false end
  local hp=number(safe(function()return target.Health end))
  local colony=number(safe(function()return target.ColonyID end))
  return hp~=nil and hp>0 and colony~=nil and colony~=number(c.ColonyID)
   and safe(function()return c:AmIAlliedWith(colony,target.AlliedWithAllNoneColony==true)end)==false
 end
 local function charm_sting_target(c,target,world)
  return valid(target)and native.world_id(target)==world and(number(target.Health)or 0)>0
   and sting_mode(c)and type(options.is_charm_target)=='function'
   and safe(function()return options.is_charm_target(c,target)end)==true
 end
 function api.handles_charm_basic(c,target)
  local choices,_,gs=authorized(c);if not choices then return false end
  local a=c.SelectedAbility
  return a~=nil and name(a.AbilityName)=='BasicAttack'and number(a.AbilityType)==1
   and charm_sting_target(c,target,native.world_id(gs))==true
 end
 local function fallback_jump(c)
  -- Native Trapjaw BP computes its backward direction from CurrentTarget.
  -- Damage-over-time can have no surviving target. Keep the native ability's
  -- charge/heal execution, then use the same bounded landing search in the
  -- direction opposite this ant's own facing, without spawning a fake enemy.
  local function helper(path)
   local result=geometry_helpers[path]
   if not valid(result)then
    local find=options.find_object or StaticFindObject
    assert(type(find)=='function','escape_geometry_lookup_missing')
    result=find(path);assert(valid(result),'escape_geometry_helper_missing:'..path)
    geometry_helpers[path]=result
   end
   return result
  end
  local utilities=helper('/Script/EotU.Default__EotUUtilities')
  local system=helper('/Script/Engine.Default__KismetSystemLibrary')
  local p,f=c:K2_GetActorLocation(),c:GetActorForwardVector()
  local px,py,pz=number(p.X),number(p.Y),number(p.Z)
  local fx,fy,fz=number(f.X),number(f.Y),number(f.Z)
  assert(px and py and pz and fx and fy and fz,'escape_geometry_vector_invalid')
  local length=math.sqrt(fx*fx+fy*fy+fz*fz)
  if length<=1e-6 then return false end
  local zone,freedom=number(c:GetHomeZoneID()),number(c.MovementFreedom)
  assert(zone and freedom,'escape_geometry_zone_invalid')
  local start={X=px,Y=py,Z=pz}
  for distance=400,100,-60 do
   local origin={X=px-fx/length*distance,Y=py-fy/length*distance,Z=pz-fz/length*distance}
   local projected={X=0,Y=0,Z=0}
   local found=utilities:UEotUProjectToGrid(c,origin,projected,1,true,c,false,0,false,false,-1,
    zone,false,freedom,false,true,false)
   if found==true then
    assert(number(projected.X)and number(projected.Y)and number(projected.Z),'escape_projection_invalid')
    -- TraceTypeQuery5 is enum value 4. Debug drawing is disabled as in BP.
    local hit={}
    local blocked=system:LineTraceSingle(c,start,projected,4,false,{},0,hit,true,
     {R=1,G=0,B=0,A=1},{R=0,G=1,B=0,A=1},5)
    assert(type(blocked)=='boolean','escape_trace_result_invalid')
    if not blocked and c:JumpToLocation(projected,false,false,2000,4900)==true then return true end
   end
  end
  return false
 end
 local function restore_escape_selection(c,transaction)
  if transaction.target_location~=nil and name(c.SelectedAbility.AbilityName)==transaction.ability then
   c.SelectedAbility.TargetLocation=transaction.target_location
   transaction.target_location=nil
  end
  if transaction.fallback and valid(c.CurrentTarget)and c.CurrentTarget:GetAddress()==c:GetAddress()then
   c.CurrentTarget=valid(transaction.target)and transaction.target or nil
  end
 end
 local function current_damage(c)
  local key=identity(c);local outer=key and attacking[key]
  if outer and equal(number(c.AttackDamage),0)then return outer.base end
  return number(c.AttackDamage)
 end
 local function restore_attack(c,token)
  if not token or token.kind~='sting_attack'or token.restored then return end
  token.restored=true
  if attacking[token.key]==token then attacking[token.key]=nil end
  local key,signature=identity(c)
  if key~=token.key or signature~=token.signature then return end
  if equal(number(c.AttackDamage),0)then
   c.AttackDamage=token.base
   assert(equal(number(c.AttackDamage),token.base),'sting_attack_restore_failed')
  end
 end
 local function restore_escape_damage(c,token)
  if escaping[token.key]==token then escaping[token.key]=nil end
  local key,signature=identity(c)
  if key~=token.key or signature~=token.signature then return end
  local selected=c.SelectedAbility
  if token.original_damage~=nil and name(selected.AbilityName)==token.ability and equal(number(selected.Damage),0)then
   selected.Damage=token.original_damage
  end
 end
 local function clear_pending()
  -- A receiver destroyed by the native call cannot supply a key to its post
  -- hook. Drop those retained wrappers on reset; live calls must first regain
  -- the temporary damage fields that their discarded post hook would restore.
  for key,stack in pairs(pending)do
   for i=#stack,1,-1 do
    local token=stack[i]
    if token and not token.driver then
     if token.kind=='escape'then restore_escape_damage(token.creature,token)
     else restore_attack(token.creature,token)end
     token.finished=true
    end
   end
   pending[key]=nil
  end
 end
 local function damage(c,target,amount,kind,charmed)
  assert(finite(amount)and amount>0,'sting_native_damage_invalid')
  local causer=c
  -- Keep the real EventInstigator but omit the optional creature DamageCauser
  -- only for a still-authorized charm hit; native TakeDamage otherwise drops
  -- same-colony damage before applying the normal damage-type pipeline.
  if charmed then causer=nil end
  if type(options.apply_damage)=='function'then return options.apply_damage(c,target,amount,kind,causer)end
  local find=options.find_object or StaticFindObject
  local path='/Script/Engine.Default__GameplayStatics'
  local lib=geometry_helpers[path]
  if not valid(lib)then lib=find(path);assert(valid(lib),'sting_damage_library_missing');geometry_helpers[path]=lib end
  local type_path=kind==2 and'/Script/EotU.EotUVenomDamageType'or'/Script/EotU.EotUPhysicalDamageType'
  local damage_type=geometry_helpers[type_path]
  if not valid(damage_type)then damage_type=find(type_path);assert(valid(damage_type),'sting_damage_class_missing');geometry_helpers[type_path]=damage_type end
  return lib:ApplyDamage(target,amount,c:GetController(),causer,damage_type)
 end
 local function clock(gs)return number(safe(function()return gs:GetLevelTime()end))end
 local function close_target(c,target)
  local layer=number(c.ColonyLocation)
  if layer==nil or layer~=number(target.ColonyLocation)then return false end
  local a,b=c:K2_GetActorLocation(),target:K2_GetActorLocation()
  local ax,ay,az,bx,by,bz=number(a.X),number(a.Y),number(a.Z),number(b.X),number(b.Y),number(b.Z)
  if not(ax and ay and az and bx and by and bz)then return false end
  return(ax-bx)^2+(ay-by)^2+(az-bz)^2<=M.melee_range^2
 end
 local function last_target(c,gs,key,signature)
  local last=recent[key];local now=clock(gs)
  if not last or not now or last.signature~=signature or last.world~=native.world_id(gs)
   or now<last.time or now-last.time>M.last_target_seconds then return nil end
  local tk,ts=identity(last.target)
  if tk~=last.target_key or ts~=last.target_signature
   or not hostile_target(c,last.target,last.world)or not close_target(c,last.target)then return nil end
  return last.target
 end
 -- Native JumpToLocation returns true after scheduling its flight and before
 -- changing actor position (verified native pre/post trace). Its post callback
 -- gives both accepted-jump proof and pre-displacement damage ordering. Failed
 -- landing attempts never strike; one escape token permits one successful hit.
 function api.on_jump_post(c,native_result)
  local ok,result=pcall(function()
   if native_result~=true then return false end
   local choices,_,gs=authorized(c);if not choices then return false end
   local key,signature=identity(c);local token=key and escaping[key]
   if not token or token.signature~=signature or token.hit_attempted then return false end
   token.hit_attempted=true
   local target=last_target(c,gs,key,signature)
   if not target then return false end
   local base=current_damage(c);if not base or base<=0 then return false end
   -- A lethal rescue is at one HP. Commit its native shelter before the new
   -- hit can provoke reflected damage; ordinary escapes still get no shelter.
   if token.rescue and rescuing[key]==token.rescue and choices.left=='invulnerable'then
    local a=find_ability(c,token.ability);assert(a,'rescue_escape_ability_missing')
    apply_invulnerable(c,a)
   end
   damage(c,target,base*M.retreat_damage_multiplier,0)
   control.retreat_hits=control.retreat_hits+1
   return true
  end)
  if not ok then return failure(result)end;return result
 end
 function api.on_trigger_pre(c)
  local token
  local ok,result=pcall(function()
   local choices,_,gs=authorized(c);if not choices then return nil end
   local selected=c.SelectedAbility;if not selected then return nil end
   local key,signature=identity(c);if not key then return nil end
   if not escape(selected.AbilityName)then
    if attacking[key]or name(selected.AbilityName)~='BasicAttack'or number(selected.AbilityType)~=1 then return nil end
    local target=safe(function()return c.CurrentTarget end)
    local charmed=charm_sting_target(c,target,native.world_id(gs))
    if not charmed and not hostile_target(c,target,native.world_id(gs))then return nil end
    local base=current_damage(c);if not base or base<=0 then return nil end
    local tk,ts=identity(target);local now=clock(gs)
    if not tk or not now then return nil end
    token={kind=sting_mode(c)and'sting_attack'or'basic_attack',key=key,signature=signature,base=base,
     creature=c,target=target,target_key=tk,target_signature=ts,time=now,world=native.world_id(gs),charmed=charmed==true}
    if token.kind=='sting_attack'then
     -- Leave native animation, hit validation and native attack events intact.
     -- Suppress only its physical amount; after accepted dispatch send exactly
     -- one direct venom hit, retaining ordinary damage-causer attribution.
     c.AttackDamage=0;attacking[key]=token
     assert(equal(number(c.AttackDamage),0),'sting_attack_suppress_failed')
    end
    return token
   end
   if escaping[key]then return nil end
   local decorated,why=api.decorate(c);assert(decorated,why)
   local id=name(selected.AbilityName);local a=find_ability(c,id)
   if not a or not number(a.Charges)or number(a.Charges)<=0 then return nil end
   local live_heal,selected_heal=find_heal(a),find_heal(selected)
   if live_heal and selected_heal then selected_heal.Damage=live_heal.Damage end
   selected.Cooldown=a.Cooldown
   token={kind='escape',key=key,signature=signature,creature=c,ability=id,charges=number(a.Charges),rescue=rescuing[key],
    original_damage=assert(number(selected.Damage),'escape_damage_unreadable')}
   selected.Damage=0
   assert(equal(number(selected.Damage),0),'escape_damage_suppress_failed')
   escaping[key]=token
   return token
  end)
  if not ok then
   if token then
    local restored,why=pcall(token.kind=='escape'and restore_escape_damage or restore_attack,c,token)
    if not restored then failure(why)end
   end
   return failure(result)
  end
  return result
 end
 function api.on_trigger_post(c,token)
  if not token or token.finished then return false end
  token.finished=true
  local ok,result=pcall(function()
   if token.kind=='sting_attack'or token.kind=='basic_attack'then
    restore_attack(c,token)
    if token.native_result~=true then return false end
    local choices,_,gs=authorized(c);local key,signature=identity(c)
    if not choices or key~=token.key or signature~=token.signature or native.world_id(gs)~=token.world then return false end
    local tk,ts=identity(token.target)
    if tk~=token.target_key or ts~=token.target_signature then return false end
    local charmed=token.charmed and charm_sting_target(c,token.target,token.world)
    if token.charmed and not charmed then return false end
    if not charmed then recent[key]=token end -- Charm never licenses a retreat hit on an ally.
    if token.kind=='sting_attack'and(charmed or hostile_target(c,token.target,token.world))then
     damage(c,token.target,token.base*M.sting_damage_multiplier,2,charmed)
     control.sting_attacks=control.sting_attacks+1
    end
    return true
   end
   -- Restore only our selected-copy damage; the native escape definition never
   -- changes and the native heal/cooldown/charge path stays authoritative.
   if token.kind~='escape'then return false end
   restore_escape_damage(c,token)
   local choices=authorized(c);if not choices then return false end
   local key,signature=identity(c)
   if token.key~=key or token.signature~=signature then return false end
   local ability=find_ability(c,token.ability)
   if not ability or not number(ability.Charges)or number(ability.Charges)>=token.charges then return false end
   control.escapes=control.escapes+1
   if choices.right=='evasion'and number(ability.CooldownTimer)and number(ability.Cooldown)then
    if ability.CooldownTimer>ability.Cooldown and ability.Cooldown>0 then ability.CooldownTimer=ability.Cooldown end
   end
   local rescue=token.rescue
   if rescue and rescuing[key]==rescue and choices.left=='invulnerable'then
    local cooldown=number(ability.Cooldown)
    assert(cooldown and cooldown>0,'lethal_escape_cooldown_unreadable')
    ability.CooldownTimer=cooldown
    assert(equal(number(ability.CooldownTimer),cooldown),'lethal_escape_cooldown_write_failed')
    if rescue.fallback then
     -- Native BP may have skipped a directionless target. Keep this accepted
     -- escape's same hit token around the actual bounded fallback jump too.
     escaping[key]=token
     local ok,jumped=pcall(fallback_jump,c)
     if escaping[key]==token then escaping[key]=nil end
     assert(ok,jumped)
     control[jumped and'fallback_jumps'or'fallback_blocked']=control[jumped and'fallback_jumps'or'fallback_blocked']+1
    end
    apply_invulnerable(c,ability)
    rescue.protected=true
    control.invulnerable=control.invulnerable+1
   end
   enter_sting(c)
   local decorated,why=api.decorate(c);assert(decorated,why)
   return true
  end)
  if not ok then return failure(result)end;return result
 end
 function api.on_damage(c,damage,damage_type,causer,instigator)
  c=unbox(c)
  local transaction
  local ok,result=pcall(function()
   if not number(damage)or number(damage)<=0 then return false end
   -- A positive post-hit HP cannot trigger this lethal-only rescue. Unknown
   -- health keeps the original authorization path; lethal hits still receive
   -- its complete fresh proof and the second HP read immediately before use.
   local nonlethal_hp=valid(c)and number(safe(function()return c.Health end))
   if nonlethal_hp and nonlethal_hp>0 then return false end
   local choices,ctx,gs=authorized(c,true)
   if not choices or choices.left~='invulnerable'then return false end
   local key,signature=identity(c);local watched=key and watching[key]
   if not watched or watched.signature~=signature or watched.world~=native.world_id(gs)
    or rescuing[key]then return false end
   -- OnTakeAnyDamage is synchronous: HP has already had the actual mitigated
   -- hit subtracted, while native hurt/death handling has not yet run.
   local hp=number(c.Health);if not hp or hp>0 then return false end
   local ability
   each(c.AbilityList,function(_,a)
    if escape(a.AbilityName)and number(a.Charges)and number(a.Charges)>0 then
     assert(not ability,'multiple_ready_escape_abilities');ability=a
    end
   end)
   -- Ready native abilities retain a positive CooldownTimer. Charges alone
   -- determine readiness; no independent timer, refill, or cooldown bypass.
   if not ability then return false end
   local world=native.world_id(gs)
   local target=unbox(causer)
   if not hostile_target(c,target,world)then target=safe(function()return c.CurrentTarget end)end
   local fallback=not hostile_target(c,target,world)
   if fallback then target=c end
   transaction={key=key,signature=signature,health=hp,ability=name(ability.AbilityName),
    charges=number(ability.Charges),timer=number(ability.CooldownTimer),protected=false,
    in_use=c.AbilityInUse,target=c.CurrentTarget,fallback=fallback}
   rescuing[key]=transaction
   c.Health=1;assert(number(c.Health)==1,'lethal_escape_health_write_failed')
   -- ForceUseAbilityOnCreature otherwise silently retains an in-progress
   -- BasicAttack. Lethal shelter interrupts that action before selecting jump.
   c.AbilityInUse=false
   c:ForceUseAbilityOnCreature(FName(transaction.ability),target)
   assert(name(c.SelectedAbility.AbilityName)==transaction.ability,'lethal_escape_selection_failed')
   -- Rescue does not require the damage source to remain within melee range.
   -- This copy-only flag skips native target/range gating, while the selected
   -- original ability still spends its own charge and applies its native heal.
   transaction.target_location=c.SelectedAbility.TargetLocation
   assert(type(transaction.target_location)=='boolean','escape_target_location_unreadable')
   c.SelectedAbility.TargetLocation=true
   c:TriggerAbility()
   restore_escape_selection(c,transaction)
   local observed=find_ability(c,transaction.ability)
   assert(transaction.protected and observed and number(observed.Charges)
    and number(observed.Charges)<transaction.charges and(number(c.Health)or 0)>0,'lethal_escape_not_completed')
   rescuing[key]=nil
   control.lethal_rescues=control.lethal_rescues+1
   return true
  end)
  if not ok then
   if transaction then
    rescuing[transaction.key]=nil
    control.lethal_failures=control.lethal_failures+1
    local restored,why=pcall(function()
     local key,signature=identity(c)
     if key~=transaction.key or signature~=transaction.signature then return end
     restore_escape_selection(c,transaction)
     c.Health=transaction.health
     if transaction.in_use~=nil then c.AbilityInUse=transaction.in_use end
     if valid(transaction.target)then c.CurrentTarget=transaction.target end
     -- ForceUseAbilityOnCreature can zero a ready ability's timer. Undo that
     -- side effect only if the attempted native escape consumed no charge.
     local a=find_ability(c,transaction.ability)
     if a and number(a.Charges)==transaction.charges and transaction.timer then a.CooldownTimer=transaction.timer end
    end)
    if not restored then failure(why)end
   end
   failure(result);return false
  end
  return result
 end
 -- Kept as an inert compatibility entrypoint for old diagnostic tools. The
 -- specialized sting branch never observes kills or resets ability cooldowns.
 function api.on_kill()return false end
 function api.forget(c)
  local key=identity(c);if key then cache[key]=nil;watching[key]=nil;recent[key]=nil end
  if options.sting_animation and type(options.sting_animation.disable)=='function'then
   local ok,why=options.sting_animation.disable(c);if not ok then return failure(why)end
  end
  return true
 end
 function api.reset_cache()
  local cleared,why=pcall(clear_pending);if not cleared then return failure(why)end
  -- Reset is also used for branch/configuration refresh in the same world.
  -- Undo exact decorator output before forgetting its baseline.
  for _,entry in pairs(cache)do
   if valid(entry.creature)then local ok,why=api.before_attributes(entry.creature);if not ok then return nil,why end end
  end
  if options.sting_animation and type(options.sting_animation.reset_cache)=='function'then
   local ok,why=options.sting_animation.reset_cache();if not ok then return failure(why)end
  end
  cache={};watching={};recent={}
  cache_cursor,watching_cursor,recent_cursor=nil,nil,nil;return true
 end
 local function prune_registry(registry,cursor,check_health)
  local removed=0
  for _=1,16 do
   if cursor and not registry[cursor]then cursor=nil end
   local key,row=next(registry,cursor)
   if not key then return nil,removed end
   local id,signature=identity(row.creature)
   local stale=id~=key or signature~=row.signature
   if not stale and check_health then stale=(number(safe(function()return row.creature.Health end))or 0)<=0 end
   if stale and registry[key]==row then
    registry[key]=nil;removed=removed+1
   else cursor=key end
  end
  return cursor,removed
 end
 function api.tick()
  -- Cleanup owns no effect duration, restoration or gameplay authorization.
  -- Each consumer still checks fresh identity/ownership; recent targets also
  -- check their own clock window. Spread stale bookkeeping over small batches
  -- without limiting the number of ants or delaying a native shelter expiry.
  local removed,count=0
  cache_cursor,count=prune_registry(cache,cache_cursor,false);removed=removed+count
  watching_cursor,count=prune_registry(watching,watching_cursor,true);removed=removed+count
  recent_cursor,count=prune_registry(recent,recent_cursor,true);removed=removed+count
  if options.sting_animation and type(options.sting_animation.tick)=='function'then
   local ok,why=options.sting_animation.tick();if not ok then failure(why)end
  end
  return removed
 end
 function api.status()
  local result={stopped=stopped,hooks={},cached=0,watched=0,recent_targets=0}
  for k,v in pairs(control)do result[k]=v end
  for path,value in pairs(hooks)do result.hooks[path]=value end
  for _ in pairs(cache)do result.cached=result.cached+1 end
  for _ in pairs(watching)do result.watched=result.watched+1 end
  for _ in pairs(recent)do result.recent_targets=result.recent_targets+1 end
  return result
 end
 function api.stop()
  local cleared,why=pcall(clear_pending);if not cleared then return failure(why)end
  for _,entry in pairs(cache)do
   if valid(entry.creature)then local ok,err=api.before_attributes(entry.creature);if not ok then return nil,err end end
  end
  -- Hook callbacks stay registered but inert. Unregistering UE4SS hooks during
  -- an engine callback has caused access violations in this loader family.
  if options.sting_animation and type(options.sting_animation.stop)=='function'then
   local ok,why=options.sting_animation.stop();if not ok then return failure(why)end
  end
  stopped=true;cache={};watching={};recent={}
  cache_cursor,watching_cursor,recent_cursor=nil,nil,nil;return true
 end
 local register=options.register_hook or RegisterHook
 local function hook(path,pre,post)
  if options.register_hooks==false then return end
  local ok,a,b=pcall(register,path,pre,post)
  if not ok or a==nil then failure('skill_hook_failed:'..path..':'..tostring(a));hooks[path]=false
  else hooks[path]=true end
 end
 local jump_hooked=false
 ensure_jump_hook=function()
  if jump_hooked or options.register_hooks==false then return end
  jump_hooked=true
  hook('/Script/EotU.Creature:JumpToLocation',function()end,function(receiver,native_result)
   if stopped then return end
   local c=unbox(receiver);local key=valid(c)and safe(function()return tostring(c:GetAddress())end)
   if key and escaping[key]then api.on_jump_post(c,unbox(native_result))end
  end)
 end
 local function callback_key(c)
  if not valid(c)then return nil end
  local species=name(c.CreatureName)
  if not species then return nil end
  species=species:lower()
  if species=='driverantsoldier'and options.driver_hunt then
   if options.driver_hunt.interested(c)then return tostring(c:GetAddress()),options.driver_hunt end
   return nil
  end
  local driver=species=='driverantlargesoldier'and options.driver_rescue
  if not driver and species~='trapjawant'then return nil end
  local address=safe(function()return c:GetAddress()end)
  return address~=nil and tostring(address)or nil,driver
 end
 hook('/Script/EotU.Creature:TriggerAbility',function(receiver)
  if stopped then return end
  local c=unbox(receiver)
  local key,driver=callback_key(c);if not key then return end
  if driver then
   local worked,t=pcall(driver.on_trigger_pre,c,key)
   if not worked then failure(t);return end
   if t or pending[key]then
    local stack=pending[key]or{};pending[key]=stack
    if t then t.driver=true end
    stack[#stack+1]=t or false
   end
   return
  end
  local stack=pending[key]or{};pending[key]=stack
  stack[#stack+1]=api.on_trigger_pre(c)or false
 end,function(receiver,return_value)
  local c=unbox(receiver)
  if options.driver_hunt and options.driver_hunt.is_pinned(c)then options.driver_hunt.on_use(c,unbox(return_value))end
  local key,driver=callback_key(c);local stack=key and pending[key]
  if not stack or #stack==0 then return end
  local token=table.remove(stack);if #stack==0 then pending[key]=nil end
  if not token then return end
  if driver then
   local worked,why=pcall(driver.on_trigger_post,c,token,unbox(return_value))
   if not worked then failure(why)end
  else
   token.native_result=unbox(return_value);api.on_trigger_post(c,token)
  end
 end)
 if options.driver_hunt then
  hook('/Script/EotU.Creature:UseAbility',function()end,function(receiver,result)
   if not stopped then
    local c=unbox(receiver)
    if options.driver_hunt.is_pinned(c)then options.driver_hunt.on_use(c,unbox(result))end
   end
  end)
 end
 return api
end
return M
