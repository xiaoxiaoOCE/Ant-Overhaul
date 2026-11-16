-- Little Black Ant form combat. Numerical cultivation stays under the existing
-- species ledger. Only a successful native BasicAttack changes damage type.
local M={species='LittleBlackAnt',tag_prefix='EAA_LittleBlackForm_v1:'}
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
 local a=safe(function()return v:get()end);return a~=nil and a or v
end
local function text(v)v=unbox(v);return type(v)=='string'and v or(v and safe(function()return v:ToString()end))end
local function number(v)local n=tonumber(unbox(v));return n and n==n and n~=math.huge and n~=-math.huge and n or nil end
local function array(a)
 if type(a)=='table'and type(a.GetArrayNum)~='function'then return a end
 local n=a and number(a:GetArrayNum());assert(n and n>=0 and n<=8192,'littleblack_tags_invalid')
 local out={};for i=1,n do out[i]=a[i]end;return out
end
function M.install(o)
 local native,combat=assert(o.native),assert(o.combat)
 local animation=assert(o.animation);local choices=assert(o.get_choices)
 local api,active,pending,reported={},{},{},{};local stopped=false;local hits=0;local last_cleanup,cleanup_world
 local venom_library,venom_type
 local valid=function(v)return v~=nil and safe(function()return native.valid_object(v)end)==true end
 local function identity_fields(c)
  return tostring(c:GetAddress()),tostring(c:GetFullName())..'|'..tostring(number(c.CreatureLevel))
 end
 local function identity(c)
  if not valid(c)then return end
  return identity_fields(c)
 end
 local function callback_address(c)
  -- GetAddress reads UE4SS's stored wrapper pointer, not actor fields. This
  -- also lets a failed/destroyed receiver retire its pending placeholder;
  -- every real token still performs identity/lifetime checks in the API.
  local address=c~=nil and safe(function()return c:GetAddress()end)or nil
  return address~=nil and tostring(address)or nil
 end
 local function fail(e)e=tostring(e);if not reported[e]then reported[e]=true;if o.log then o.log('[LittleBlackForms] '..e)end end;return nil,e end
 local function candidate(c,basic_only)
  if stopped or not valid(c)or text(c.CreatureName)~='LittleBlackAnt'or(number(c.Health)or 0)<=0 then return end
  if basic_only then
   local ability=c.SelectedAbility
   if not ability or text(ability.AbilityName)~='BasicAttack'or number(ability.AbilityType)~=1 then return end
  end
  return true
 end
 local function resolve(c,basic_only)
  if not candidate(c,basic_only)then return end
  local ctx=combat.get();if not ctx then return end
  local eligible,world=combat.eligible(c,ctx.gs)
  if not eligible then return end
  return ctx,world
 end
 local function saved_form(c)
  for _,v in ipairs(array(c.Tags))do
   local name=text(v)or'';local form=name:sub(#M.tag_prefix+1)
   if name:sub(1,#M.tag_prefix)==M.tag_prefix and(form=='specialist'or form=='twin')then return form end
  end
 end
 local function selected_form(c)
  local picked=choices(c,M.species);local f=type(picked)=='table'and picked.form
  if f=='specialist'or f=='twin'then return f end
  -- Choice adapters can reenter. Recheck before touching a fallback tag.
  if not valid(c)or text(c.CreatureName)~='LittleBlackAnt'then return end
  return saved_form(c)or'specialist'
 end
 function api.get_form(c)
  if not valid(c)or text(c.CreatureName)~='LittleBlackAnt'then return end
  return selected_form(c)
 end
 local function write_form(c,form)
  local wanted=M.tag_prefix..form;local out,seen,changed={},false,false
  for _,v in ipairs(array(c.Tags))do
   local name=text(v)or''
   if name:sub(1,#M.tag_prefix)==M.tag_prefix then
    if name==wanted and not seen then out[#out+1]=v;seen=true else changed=true end
   else out[#out+1]=v end
  end
  if not seen then out[#out+1]=FName(wanted);changed=true end
  if changed then c.Tags=out end
 end
 function api.decorate(c)
  local ok,result=pcall(function()
   if not resolve(c)then return animation.disable(c)end
   local form=api.get_form(c);write_form(c,form)
   if form=='specialist'then return assert(animation.enable(c))end
   return animation.disable(c)
  end)
  if not ok then return fail(result)end;return result
 end
 api.observe=api.decorate
 local function hostile(c,t,world,token)
  if not valid(t)or native.world_id(t)~=world or(number(t.Health)or 0)<=0 then return false end
  -- The post callback validates the target afresh. Use that same live
  -- receiver check to read its identity before deciding allegiance.
  if token then
   local key,signature=identity_fields(t)
   if key~=token.target_key or signature~=token.target_signature then return false end
  end
  -- A charmed ant may attack exactly its temporarily assigned former ally.
  -- The combat service owns expiry/identity/layer checks; never enable general
  -- friendly fire or trust colony membership alone for this exception.
  if o.is_charm_target and safe(function()return o.is_charm_target(c,t)end)==true then return true,true end
  local owner=number(t.ColonyID)
  return owner~=nil and owner~=number(c.ColonyID)and safe(function()return c:AmIAlliedWith(owner,t.AlliedWithAllNoneColony==true)end)==false
 end
 function api.handles_charm_basic(c,target)
  local ctx=resolve(c);if not ctx or api.get_form(c)~='specialist'then return false end
  local a=c.SelectedAbility
  if not a or text(a.AbilityName)~='BasicAttack'or number(a.AbilityType)~=1 then return false end
  local allowed,charmed=hostile(c,target,native.world_id(ctx.gs));return allowed==true and charmed==true
 end
 local function restore(c,token)
  if token.restored then return end;token.restored=true
  if active[token.key]==token then active[token.key]=nil end
  local key,sig=identity(c)
  if key==token.key and sig==token.signature and number(c.AttackDamage)==0 then c.AttackDamage=token.amount end
 end
 function api.on_trigger_pre(c)
  local token
  local ok,result=pcall(function()
   -- Twins perform no venom conversion. Resolve their live form first so a
   -- no-op does not construct another combat context. Specialist writes still
   -- revalidate the actor, ability and complete context after the choice read.
   if not candidate(c,true)then return end
   local before_key,before_sig=identity_fields(c)
   local before_world=native.world_id(c)
   if not before_key or not before_world or selected_form(c)~='specialist'then return end
   local ctx,world=resolve(c,true);if not ctx then return end
   local key,sig=identity(c);if not key or active[key]then return end
   world=world or native.world_id(ctx.gs)
   if key~=before_key or sig~=before_sig or world~=before_world then return end
   local target=c.CurrentTarget
   local allowed,charmed=hostile(c,target,world);if not allowed then return end
   local amount=number(c.AttackDamage);if not amount or amount<=0 then return end
   local tk,ts=identity(target)
   token={key=key,signature=sig,creature=c,target=target,target_key=tk,target_signature=ts,world=world,amount=amount,charmed=charmed==true}
   active[key]=token;c.AttackDamage=0
   assert(number(c.AttackDamage)==0,'littleblack_basic_suppress_failed')
   return token
  end)
  if not ok then if token then pcall(restore,c,token)end;return fail(result)end;return result
 end
 local function damage(c,t,amount,charmed)
  local causer=c
  -- EotU's native TakeDamage rejects a same-colony creature DamageCauser.
  -- Only the still-authorized charm hit omits that optional actor; retain the
  -- real attacking controller and native venom/mitigation/death processing.
  if charmed then causer=nil end
  if o.apply_damage then return o.apply_damage(c,t,amount,2,causer)end
  if not valid(venom_library)then
   venom_library=StaticFindObject('/Script/Engine.Default__GameplayStatics')
   assert(valid(venom_library),'littleblack_venom_library_unavailable')
  end
  if not valid(venom_type)then
   venom_type=StaticFindObject('/Script/EotU.EotUVenomDamageType')
   assert(valid(venom_type),'littleblack_venom_type_unavailable')
  end
  return venom_library:ApplyDamage(t,amount,c:GetController(),causer,venom_type)
 end
 function api.on_trigger_post(c,token,native_result)
  if not token or token.finished then return false end;token.finished=true
  local ok,result=pcall(function()
   restore(c,token)
   if native_result~=true then return false end
   local ctx,world=resolve(c)
   if not ctx or(world or native.world_id(ctx.gs))~=token.world then return false end
   local key,sig=identity(c)
   if key~=token.key or sig~=token.signature then return false end
   local allowed,charmed=hostile(c,token.target,token.world,token)
   if not allowed or(token.charmed and not charmed)then return false end
   damage(c,token.target,token.amount,token.charmed and charmed);hits=hits+1;return true
  end)
  if not ok then return fail(result)end;return result
 end
 function api.tick(now)
  -- Animation swaps happen immediately in decorate; the periodic pass only
  -- restores dead/replaced instances. Do not inspect every mesh every 5 frames.
  local ctx=combat.get();if not ctx then return true end
  now=number(now)or number(safe(function()return ctx.gs:GetLevelTime()end))
  if now and cleanup_world==ctx.world_id and last_cleanup and now>=last_cleanup and now-last_cleanup<0.5 then return true end
  last_cleanup=now;cleanup_world=ctx.world_id
  return animation.tick()
 end
 function api.reset_cache()
  for _,t in pairs(active)do restore(t.creature,t)end
  active={};pending={};last_cleanup=nil;cleanup_world=nil;venom_library=nil;venom_type=nil
  return animation.reset_cache()
 end
 function api.stop()local ok,e=api.reset_cache();if not ok then return nil,e end;stopped=true;return animation.stop()end
 function api.status()return{stopped=stopped,venom_basic_hits=hits,animation=animation.status()}end
 if o.register_hooks~=false then
  local hook=o.register_hook or RegisterHook
  hook('/Script/EotU.Creature:TriggerAbility',function(receiver)
   local c=unbox(receiver);if stopped or not valid(c)or text(c.CreatureName)~='LittleBlackAnt'then return end
   local key=callback_address(c);if not key then return end
   local stack=pending[key]
   -- This capability is read-only and can only reject a proven frozen arena
   -- twin. Unknown/specialist cases keep the API's original pre-choice proof.
   if o.native_twin_negative and o.native_twin_negative(c)==true then
    if stack and #stack>0 then stack[#stack+1]=false end
    return
   end
   stack=stack or{};pending[key]=stack;stack[#stack+1]=api.on_trigger_pre(c)or false
  end,function(receiver,result)
   local c=unbox(receiver);local key=callback_address(c);local stack=key and pending[key]
   if not stack or #stack==0 then return end
   local token=table.remove(stack);if #stack==0 then pending[key]=nil end
   if token then api.on_trigger_post(c,token,unbox(result))end
  end)
 end
 return api
end
return M
