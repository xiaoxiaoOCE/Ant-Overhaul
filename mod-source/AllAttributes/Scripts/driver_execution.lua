-- Native, per-encounter choreography. Only active casts run a frame callback.
-- Damage/death and harvest ownership stay with the normal hunt/native pipeline.
local M={threshold=.7,cooldown=12,finish=2.8,blend=.16,entry_blend=.30,bite_contact=.62,hold_delay=0,dash_lead=.75,stagger=.12,release_holder=2.55,release_dash=2.21,reduction=.45,partial_fraction=.75,path_multiplier=3,path_radius=37,path_primary=false}
local LOCK='EAA_Execution_Lock'
local PROTECTION='EAA_Execution_Protection_v1'
local GRAB={'CannotBePickedUp','CannotBeStrongPickedUp'}
local CONTROL={[5]=true,[6]=true,[7]=true,[8]=true,[9]=true,[28]=true}
local fields={'Immobile','DontRotate','AbilityInUse','NoCombat'}
local meshfields={'bPauseAnims','VisibilityBasedAnimTickOption','bEnableUpdateRateOptimizations','GlobalAnimRateScale'}
local function clamp(x)return math.max(0,math.min(1,x))end
local function smooth(x)x=clamp(x);return x*x*(3-2*x)end
function M.holder_time(t)
 return t<=M.hold_delay and t or math.max(M.hold_delay,t-M.hold_delay)
end
function M.dasher_time(t)
 -- V7 holds a neutral pose until 0.85 s. Keep only a short lead-in before
 -- its authored wind-up; the native snapshot blend still eases in the pose.
 return t+M.dash_lead
end
function M.partial_damage(health,passes)
 return passes==1 and math.max(0,health)*M.partial_fraction or 0
end
function M.segment_point(p,a,b)
 local x,y,z=b.X-a.X,b.Y-a.Y,b.Z-a.Z;local length=x*x+y*y+z*z
 local t=length>1e-8 and clamp(((p.X-a.X)*x+(p.Y-a.Y)*y+(p.Z-a.Z)*z)/length)or 0
 return{X=a.X+x*t,Y=a.Y+y*t,Z=a.Z+z*t}
end
local function unbox(v)
 if type(v)~='table'and type(v)~='userdata'then return v end
 if type(v)=='userdata'and type(debug)=='table'and type(debug.getmetatable)=='function'then
  local ok,mt=pcall(debug.getmetatable,v)
  local kind=ok and type(mt)=='table'and rawget(mt,'__name')
  if kind=='AActor'or kind=='UObject'or kind=='UWorld'or kind=='UScriptStruct'or kind=='FNameUserdata'or kind=='TArray'then return v end
 end
 local ok,inside=pcall(function()return v:get()end)
 return ok and inside~=nil and inside or v
end
local function each(t,fn)
 if not t then return end
 if type(t)=='table'and not t.GetArrayNum then for _,v in ipairs(t)do fn(unbox(v))end
 else for i=1,t:GetArrayNum()do fn(unbox(t[i]))end end
end
function M.install(o)
 local native=assert(o.native);local jobs,busy,cooldowns={},{},{}
 local stopped,timer,assets,sequence=false,nil,nil,0
 local keeper,retained=nil,{}
 local stats={started=0,completed=0,interrupted=0,errors=0,frames=0,shortened=0,partial_hits=0,partial_damage=0,reduced_hits=0,damage_refunded=0,failed_outros=0,crossings=0,path_hits=0,path_queries=0}
 local api={}
 local function valid(a)return a~=nil and native.valid_object(a)==true end
 local function key(a)return valid(a)and tostring(a:GetAddress())end
 local function alive(a)return valid(a)and(tonumber(a.Health)or 0)>0 end
 local function path(a)return valid(a)and a:GetFullName():match(' (%/.+)$')end
 local function identity(a)return{actor=a,key=key(a),name=a:GetFullName(),world=native.world_id(a),owner=a.ColonyID}end
 local function same(r)return r and valid(r.actor)and key(r.actor)==r.key and r.actor:GetFullName()==r.name and native.world_id(r.actor)==r.world end
 local function pos(a)local p=a:K2_GetActorLocation();return{X=p.X,Y=p.Y,Z=p.Z}end
 local function controlled(a)
  if a.InPickup==true then return true end
  local yes=false;each(a.Effects,function(e)if e.Length>0 and CONTROL[tonumber(e.Type)]then yes=true end end);return yes
 end
 local function effect(a,wanted)
  wanted=wanted or LOCK
  local e;each(a.Effects,function(v)if v.EffectName:ToString()==wanted then e=v end end);return e
 end
 local function clear_protection(r)
  if not same(r)then return end
  for f,v in pairs(r.grab_before or{})do if r.actor[f]==true then r.actor[f]=v end end
  local e=effect(r.actor,PROTECTION);if e then e.Length=0 end
 end
 local function fail(why)
  stats.errors=stats.errors+1;stats.last_error=tostring(why)
  if o.log then o.log('[DriverExecution] '..tostring(why))end
 end
 local function references(gi)
  local values={}
  each(gi.ReferencedObjects,function(a)if a and a:GetAddress()~=0 then values[#values+1]=a end end)
  return values
 end
 local function retain(a,temporary)
  -- Lua userdata does not keep a UObject alive through Unreal GC. The
  -- GameInstance's native UPROPERTY array does, across arena round changes.
  -- Only resources and montages are retained; actors/worlds are never pinned.
  local ctx=assert(o.get_context(),'execution_asset_world_missing')
  local gi=StaticFindObject('/Script/Engine.Default__GameplayStatics'):GetGameInstance(ctx.gs)
  assert(valid(gi),'execution_asset_keeper_missing')
  if not keeper or keeper:GetAddress()~=gi:GetAddress()then keeper=gi;retained={}end
  local id=tostring(a:GetAddress())
  if retained[id]then return a end
  local values=references(gi);local found=false
  for _,v in ipairs(values)do if v:GetAddress()==a:GetAddress()then found=true;break end end
  if not found then values[#values+1]=a;gi.ReferencedObjects=values end
  retained[id]={temporary=temporary==true,owned=not found}
  return a
 end
 local function release_montage(r)
  if not r.montage then return end
  local id=tostring(r.montage:GetAddress());local row=retained[id]
  if row and row.temporary then
   if row.owned and keeper and valid(keeper)then
    local values={}
    for _,a in ipairs(references(keeper))do if tostring(a:GetAddress())~=id then values[#values+1]=a end end
    keeper.ReferencedObjects=values
   end
   retained[id]=nil
  end
 end
 local function live_instance(r)
  if not same(r)or not alive(r.actor)then return end
  local mesh=r.actor.Mesh
  if not valid(mesh)or not r.mesh or mesh:GetAddress()~=r.mesh:GetAddress()then return end
  local instance=mesh:GetAnimInstance()
  if not valid(instance)then return mesh end
  return mesh,instance
 end
 local function load_asset(p)
  local a=StaticFindObject(p);if not valid(a)then a=LoadAsset(p)end
  if not valid(a)then a=StaticFindObject('/Script/AssetRegistry.Default__AssetRegistryHelpers'):GetAsset({ObjectPath=FName(p)})end
  assert(valid(a),'execution_asset_missing:'..p)
  if p:sub(1,8)~='/Script/'then retain(a,false)end
  return a
 end
 local function capture_pose(mesh)
  -- Own the pose as plain values before replacing the instance. Parent-bone
  -- space is the local-transform space expected by the native snapshot node.
  -- No reflected ref/out-parameter or old animation-instance storage is kept.
  local count=mesh:GetNumBones();assert(count>0,'execution_entry_bones_missing')
  local snapshot={LocalTransforms={},BoneNames={},SkeletalMeshName=mesh.SkeletalMesh:GetFName(),SnapshotName=FName('EAA_Entry'),bIsValid=true}
  for i=0,count-1 do
   local name=mesh:GetBoneName(i);local t=mesh:GetSocketTransform(name,3)
   local q,p,s=t.Rotation,t.Translation,t.Scale3D
   snapshot.BoneNames[i+1]=name
   snapshot.LocalTransforms[i+1]={Rotation={X=q.X,Y=q.Y,Z=q.Z,W=q.W},Translation={X=p.X,Y=p.Y,Z=p.Z},Scale3D={X=s.X,Y=s.Y,Z=s.Z}}
  end
  stats.snapshots=(stats.snapshots or 0)+1
  return snapshot
 end
 local function install_snapshot(r,entry_pose)
  local node=r.instance.AnimGraphNode_EAAEntrySnapshot
  local snapshot=node.Snapshot
  snapshot.LocalTransforms=nil;snapshot.BoneNames=nil
  snapshot.LocalTransforms=entry_pose.LocalTransforms;snapshot.BoneNames=entry_pose.BoneNames
  snapshot.SkeletalMeshName=entry_pose.SkeletalMeshName;snapshot.SnapshotName=entry_pose.SnapshotName;snapshot.bIsValid=true
  node.Mode=1
  assert(snapshot.bIsValid==true and snapshot.BoneNames:GetArrayNum()==#entry_pose.BoneNames and snapshot.LocalTransforms:GetArrayNum()==#entry_pose.LocalTransforms,'execution_entry_pose_copy_failed')
  r.instance.AnimGraphNode_EAAEntryBlend.ActiveChildIndex=0
 end
 function api.prepare()
  if stopped then return nil,'execution_stopped'end
  if assets then return true end
  local ok,result=pcall(function()
   assets={}
   for k,n in pairs({dash='DriverExecutionContinuousDashV7',hold='DriverExecutionContinuousHoldV9',graph='ExecutionDriverMediumAnimBP'})do
    assets[k]=load_asset('/Game/EAA/'..n..'.'..n..(k=='graph'and'_C'or''))
   end
   assets.sys=StaticFindObject('/Script/Engine.Default__KismetSystemLibrary')
   assets.lib=StaticFindObject('/Script/Engine.Default__GameplayStatics')
   assets.physical=load_asset('/Script/EotU.EotUPhysicalDamageType')
   assets.dust=load_asset('/Game/Assets/Particles/EcuadorDustKickup.EcuadorDustKickup')
   assets.blood=load_asset('/Game/Assets/Particles/BloodSpurtOnce.BloodSpurtOnce')
   assets.sphere=load_asset('/Engine/BasicShapes/Sphere.Sphere')
   assets.refraction=load_asset('/Game/Assets/Materials/BaseMaterials/ClearMaterialTransparent.ClearMaterialTransparent')
   assert(path(assets.dash.Skeleton)==path(assets.hold.Skeleton),'execution_clip_rig_mismatch')
   return true
  end)
  if not ok then assets=nil;fail(result);return nil,result end;return true
 end
 local function arm_animation(r,entry_pose)
  local a=r.actor;r.animate=true
  r.mesh=a.Mesh;assert(valid(r.mesh),'execution_mesh_missing')
  assert(path(r.mesh.SkeletalMesh.Skeleton)==path(assets.hold.Skeleton),'execution_ant_rig_unsupported')
  entry_pose=entry_pose or capture_pose(r.mesh)
  r.meshBefore={};for _,f in ipairs(meshfields)do r.meshBefore[f]=r.mesh[f]end
  a:UnsetAnimationOptimised();r.mesh.bPauseAnims=false;r.mesh.VisibilityBasedAnimTickOption=0
  r.mesh.bEnableUpdateRateOptimizations=false;r.mesh.GlobalAnimRateScale=1
  local originalClass,originalMode=r.mesh:GetAnimClass(),r.mesh:GetAnimationMode()
  if not valid(originalClass)or originalClass:GetAddress()~=assets.graph:GetAddress()or originalMode~=0 then
   r.mesh:SetAnimClass(assets.graph);r.mesh:SetAnimationMode(0)
  end
  r.instance=r.mesh:GetAnimInstance()
  if not valid(r.instance)then
   if valid(originalClass)then r.mesh:SetAnimClass(originalClass);r.mesh:SetAnimationMode(originalMode)end
   error('execution_anim_instance_missing')
  end
  r.threaded=r.instance.bUseMultiThreadedAnimationUpdate;r.instance.bUseMultiThreadedAnimationUpdate=false
  install_snapshot(r,entry_pose)
  -- Keep native hit/area queries active. The guarded unswept path owns dash
  -- movement, while native pickup flags and the damage delegate protect it.
 end
 local function remember(a,animate,r)
  r=r or identity(a);r.before={};r.animation=a.CurrentAnimation;r.animate=animate
  local entry_pose
  if animate then
   r.mesh=a.Mesh;assert(valid(r.mesh),'execution_mesh_missing')
   assert(path(r.mesh.SkeletalMesh.Skeleton)==path(assets.hold.Skeleton),'execution_ant_rig_unsupported')
   -- Capture before leaving combat or replacing the animation instance.
   entry_pose=capture_pose(r.mesh)
  end
  -- Finish the current basic-attack command before taking cinematic control.
  for _,f in ipairs(fields)do r.before[f]=a[f]end
  r.before.AbilityInUse=false;r.collision=a:GetActorEnableCollision()
  if r.role then
   r.grab_before={};local bits=0
   for i,f in ipairs(GRAB)do r.grab_before[f]=a[f];if a[f]then bits=bits+2^(i-1)end;a[f]=true end
   a:ApplyEffect({EffectName=FName(PROTECTION),Type=31,Length=M.finish+2,Interval=-bits-1,Timer=-1,Damage=0,DamageType=14,SpecialEffect=0,StackType=0,StackMax=1,CausingColonyID=a.ColonyID,CausingTileID=-1,EventName=FName('None')})
   local watched,why=o.watch_damage(a);assert(watched==true,why or'execution_damage_watch_failed')
  end
  local ctl=a:GetController();r.controller=ctl
  if valid(ctl)then
   ctl:StopMovement()
   if valid(ctl.BrainComponent)then r.brain=ctl.BrainComponent;r.running=r.brain:IsRunning();r.brain:StopLogic('cooperative execution')end
  end
  a:ForceLeaveCombat();a.Immobile=true;a.DontRotate=true;a.AbilityInUse=true;a.NoCombat=r.role==nil
  if animate then
   arm_animation(r,entry_pose)
  end
  local bits=0;for i,f in ipairs(fields)do if r.before[f]then bits=bits+2^(i-1)end end
  if r.collision then bits=bits+16 end
  a:ApplyEffect({EffectName=FName(LOCK),Type=31,Length=M.finish+M.hold_delay+1,Interval=-bits-1,Timer=-1,Damage=0,DamageType=14,SpecialEffect=0,StackType=0,StackMax=1,CausingColonyID=a.ColonyID,CausingTileID=-1,EventName=FName('None')})
  return r
 end
 local function restore(r,t)
  if r.released then return end;r.released=t
  clear_protection(r)
  if not same(r)then return end
  if not alive(r.actor)then
   -- Let native death own the body. Only remove our paused montage, never
   -- replace its animation class or animate a dead actor from a cached proxy.
   local mesh=r.actor.Mesh
   local current=valid(mesh)and mesh:GetAnimInstance()
   if valid(current)and r.instance and current:GetAddress()==r.instance:GetAddress()and valid(r.montage)then
    current:Montage_Resume(r.montage);current:Montage_Stop(M.blend,r.montage)
   end
   return
  end
  local a=r.actor
  -- A conversion/ownership change wins over the old cinematic snapshot.
  if a.ColonyID==r.owner and r.before then
   for _,f in ipairs(fields)do if r.before[f]~=nil then a[f]=r.before[f]end end
   if r.collision~=nil then a:SetActorEnableCollision(r.collision)end
   if r.animate then a:SetCurrentAnimation(r.animation)end
  end
  local e=effect(a);if e then e.Length=0 end
  if r.animate and r.montage then
   local _,current=live_instance(r)
   if current and r.instance and current:GetAddress()==r.instance:GetAddress()and valid(r.montage)then
    current:Montage_Resume(r.montage);current:Montage_Stop(M.blend,r.montage)
   end
  end
  if r.animate then
   local _,current=live_instance(r)
   if current and r.instance and current:GetAddress()==r.instance:GetAddress()then current.AnimGraphNode_EAAEntryBlend.ActiveChildIndex=1 end
  end
  if r.running and valid(r.brain)then r.brain:RestartLogic()end
 end
 local function mesh_restore(r)
  if r.restored then return end;r.restored=true
  local mesh,current=live_instance(r)
  if not mesh then return end
  for f,v in pairs(r.meshBefore or{})do mesh[f]=v end
  if current and r.instance and current:GetAddress()==r.instance:GetAddress()then current.bUseMultiThreadedAnimationUpdate=r.threaded end
 end
 function api.observe(a)
  if stopped or not valid(a)or busy[key(a)]then return end
  local protection=effect(a,PROTECTION)
  if protection and protection.Length>0 and tonumber(protection.Type)==31 then
   local bits=-protection.Interval-1
   if bits%1==0 and bits>=0 and bits<=3 then
    for i,f in ipairs(GRAB)do a[f]=math.floor(bits/2^(i-1))%2==1 end
    protection.Length=0
   end
  end
  if not alive(a)then return end
  -- A native save can contain a transient lock. Resume ordinary AI rather
  -- than replaying a half-finished execution or retaining immobility on load.
  local e=effect(a)
  if e and e.Length>0 and tonumber(e.Type)==31 and e.Interval<=-1 then
   local bits=-e.Interval-1
   if bits%1==0 and bits>=0 and bits<=31 then
    for i,f in ipairs(fields)do a[f]=math.floor(bits/2^(i-1))%2==1 end
    a:SetActorEnableCollision(math.floor(bits/16)%2==1);e.Length=0
    local ctl=a:GetController();if valid(ctl)and valid(ctl.BrainComponent)then ctl.BrainComponent:RestartLogic()end
   end
  end
 end
 local function destroy_air(j)
  for _,v in pairs(j.air or{})do if valid(v.actor)then v.actor:K2_DestroyActor()end end;j.air={}
 end
 local begin_failure,advance_failure,settle_partial
 local function cancel(j,why,t)
  if j.cancelled then return end;j.cancelled=why;j.cleanup_at=t+M.blend+.04
  if not j.killed and why~='travel'and why~='start_rejected'and why~='runtime_error'then
   settle_partial(j,t)
   for _,r in ipairs(j.members)do
    if same(r)and alive(r.actor)and r.actor.ColonyID==r.owner and not controlled(r.actor)and r.montage then
     begin_failure(j,r,t)
    else restore(r,t)end
   end
  else for _,r in ipairs(j.members)do restore(r,t)end end
  if j.target then restore(j.target,t);if busy[j.target.key]==j then busy[j.target.key]=nil end end
  destroy_air(j);stats.interrupted=stats.interrupted+1;stats.last_interruption=why
 end
 local function cleanup(j)
  for _,r in ipairs(j.members)do mesh_restore(r);release_montage(r);if busy[r.key]==j then busy[r.key]=nil end end
  if j.target and busy[j.target.key]==j then busy[j.target.key]=nil end
  destroy_air(j);jobs[j.id]=nil
 end
 local function pose(r,clip,t)
  if r.released then return end
  local mesh,current=live_instance(r)
  assert(mesh and current,'execution_instance_lost')
  if not r.montage then
   if current:GetClass():GetAddress()~=assets.graph:GetAddress()then mesh:SetAnimClass(assets.graph);mesh:SetAnimationMode(0);current=mesh:GetAnimInstance()end
   assert(valid(current),'execution_live_instance_missing')
   r.instance=current;r.instance.bUseMultiThreadedAnimationUpdate=false
   r.montage=r.instance:PlaySlotAnimationAsDynamicMontage(clip,FName('HeadAbdomenSlot'),.04,M.blend,1,1,-1,0)
   assert(valid(r.montage),'execution_montage_missing');retain(r.montage,true);r.instance:Montage_Pause(r.montage)
  elseif current:GetAddress()~=r.instance:GetAddress()then
   error('execution_animation_instance_replaced')
  end
  -- A failure outro reuses its montage but installs a fresh entry snapshot.
  -- Switch back after its evaluation frame, just as for a new montage.
  current.AnimGraphNode_EAAEntryBlend.ActiveChildIndex=1
  current:Montage_SetPosition(r.montage,math.min(clip.SequenceLength,math.max(0,t)))
 end
 local function emit(j,asset,p,size)
  assets.lib:SpawnEmitterAtLocation(j.gs,asset,p,{Pitch=0,Yaw=0,Roll=0},{X=size,Y=size,Z=size},true,0,true)
 end
 local function make_air(j,r)
  local tr=r.actor:GetTransform();local a=assets.lib:BeginDeferredActorSpawnFromClass(j.gs,load_asset('/Script/Engine.StaticMeshActor'),tr,1,nil)
  assert(valid(a),'execution_air_actor_missing');assets.lib:FinishSpawningActor(a,tr)
  a:SetActorEnableCollision(false);a:SetActorHiddenInGame(true)
  local mesh=a.StaticMeshComponent;mesh:SetMobility(2);mesh:SetStaticMesh(assets.sphere);mesh:SetCollisionEnabled(0);mesh:SetCastShadow(false)
  mesh:SetMaterial(0,assets.refraction);local mat=mesh:CreateDynamicMaterialInstance(0,assets.refraction,FName('None'))
  assert(valid(mat),'execution_air_material_missing')
  mat:SetScalarParameterValue(FName('Roughness'),.85);mat:SetScalarParameterValue(FName('Metallic'),0)
  mat:SetScalarParameterValue(FName('Opacity'),0);mat:SetScalarParameterValue(FName('IOR'),1)
  mat:SetScalarParameterValue(FName('FresnelFalloff'),5);mat:SetVectorParameterValue(FName('Colour'),{R=.04,G=.055,B=.075,A=1})
  return{actor=a,material=mat}
 end
 local function path_damage(j,r,from,to,candidates)
  if not r.dashing or not same(r)or not alive(r.actor)or not o.nearby then return end
  local dx,dy,dz=to.X-from.X,to.Y-from.Y,to.Z-from.Z;local length=math.sqrt(dx*dx+dy*dy+dz*dz)
  if length<.001 then return end
  r.path_hits=r.path_hits or{}
  local amount
  each(candidates,function(target)
   if not same(r)or not alive(r.actor)or r.actor.ColonyID~=r.owner or controlled(r.actor)then return end
   if not valid(target)or not alive(target)or native.world_id(target)~=j.world or target.ColonyLocation~=j.layer or not target.CanBeAttacked or not r.actor:IsCreatureEnemy(target)then return end
   local id=key(target)
   if not M.path_primary and j.target and id==j.target.key then return end
   if r.path_hits[id]and same(r.path_hits[id])then return end
   local body=target.RootComponent;local p=pos(target)
   if valid(body)then local c=body:K2_GetComponentLocation();p={X=c.X,Y=c.Y,Z=c.Z}end
   local nearest=M.segment_point(p,from,to);local distance
   if valid(body)then distance=body:GetClosestPointOnCollision(nearest,{},FName('None'))end
   if not distance or distance<0 then
    distance=math.sqrt((p.X-nearest.X)^2+(p.Y-nearest.Y)^2+(p.Z-nearest.Z)^2)
   end
   if distance>M.path_radius then return end
   -- Each dasher has its own set. Adjacent frame segments never charge the
   -- same enemy again, while the other dasher may still hit it once.
   r.path_hits[id]=identity(target)
   amount=amount or math.max(0,r.actor:CalculatedDamageBuff(r.actor.AttackDamage))*M.path_multiplier
   if amount<=0 then return end
   local controller=r.actor:GetController()
   assets.lib:ApplyDamage(target,amount,valid(controller)and controller or nil,r.actor,assets.physical)
   stats.path_hits=stats.path_hits+1
  end)
 end
 local function move(j,r,p)
  local before=pos(r.actor)
  local dx,dy,dz=p.X-before.X,p.Y-before.Y,p.Z-before.Z
  local length=math.sqrt(dx*dx+dy*dy+dz*dz)
  if length<.001 then return end
  local nearby=o.nearby and o.nearby(r.actor,{x=(before.X+p.X)*.5,y=(before.Y+p.Y)*.5,z=(before.Z+p.Z)*.5},length*.5+70)
  local ignored,seen={},{}
  -- Query the current swept body rather than carrying distant creature
  -- pointers through deaths/GC. One native shape query serves both the wall
  -- ignore list and the narrower path-damage contact test; idle casts do none.
  each(nearby or j.ignored,function(a)if valid(a)then local id=key(a);if not seen[id]then seen[id]=true;ignored[#ignored+1]=a end end end)
  stats.path_queries=stats.path_queries+1
  local limited,info=j.guard.limit(r.actor,before,p,ignored)
  r.actor:K2_SetActorLocation(limited,false,{},true)
  if info.blocked then r.blocked=true end
  -- Native out-array entries are parameter proxies. Resolve them before the
  -- sweep reuses native argument storage; only these actor values survive it.
  if r.role and r.role>1 and same(r)then path_damage(j,r,before,pos(r.actor),ignored)end
 end
 local function record_crossing(j,r)
  if r.passed or not same(r)then return end
  local row=j.layout.members[r.role];local p=pos(r.actor)
  if(p.X-j.origin.X)*row.direction.X+(p.Y-j.origin.Y)*row.direction.Y>0 then
   r.passed=true;j.passes=j.passes+1;stats.crossings=stats.crossings+1
   stats.last_cross_count=j.passes
  end
 end
 settle_partial=function(j,t)
  if j.partial_done then return end;j.partial_done=true
  if j.passes~=1 or not j.target or not same(j.target)or not alive(j.target.actor)then return end
  local target=j.target.actor
  if target.ColonyID~=j.target.owner then return end
  local attacker
  for _,r in ipairs(j.members)do if same(r)and valid(r.actor)and r.actor:IsCreatureEnemy(target)then attacker=r.actor;break end end
  if not attacker then return end
  local before=target.Health;local amount=M.partial_damage(before,j.passes)
  -- This is a non-lethal loss of current HP, not an execution or a normal
  -- attack: no kill/food reward, and existing damage labels do not stack it.
  target.Health=before-amount
  stats.partial_hits=stats.partial_hits+1;stats.partial_damage=stats.partial_damage+amount
  stats.last_partial_before=before;stats.last_partial_after=target.Health
  emit(j,assets.blood,{X=j.origin.X,Y=j.origin.Y,Z=j.origin.Z+9},.14)
 end
 begin_failure=function(j,r,t)
  local mesh,current=live_instance(r)
  if not mesh or not current or not r.instance or current:GetAddress()~=r.instance:GetAddress()then restore(r,t);return end
  local clip_time=current:Montage_GetPosition(r.montage)
  local origin=pos(r.actor);local direction=r.actor:GetActorForwardVector()
  local f={origin=origin,direction={X=direction.X,Y=direction.Y,Z=0},prepared_at=t,clip_time=clip_time}
  if r.role==1 then f.from=1.7;f.to=2.55;f.duration=.85;f.distance=-18
  elseif clip_time>=1.2 and clip_time<2.21 then
   f.from=1.42;f.to=2.21;f.duration=.75
   local row=j.layout.members[r.role];local first=math.min(r.plan.length,row.startDistance+130)
   local speed=clip_time<1.42 and first/.22 or math.max(0,r.plan.length-first)*2/.79*(1-clamp((clip_time-1.42)/.79))
   f.distance=math.min(70,math.max(0,speed*.1))
   if not r.passed then
    local to_prey=(j.origin.X-origin.X)*f.direction.X+(j.origin.Y-origin.Y)*f.direction.Y
    f.distance=math.min(f.distance,math.max(0,to_prey-8))
   end
  else f.from=2.0;f.to=2.21;f.duration=.42;f.distance=0 end
  install_snapshot(r,capture_pose(mesh));r.failure=f;r.blocked=false
  j.cleanup_at=math.max(j.cleanup_at,t+f.duration+M.blend+.16)
  stats.failed_outros=stats.failed_outros+1
 end
 advance_failure=function(j,t)
  local all_released=true
  for _,r in ipairs(j.members)do
   if not r.released then
    all_released=false
    if not same(r)or not alive(r.actor)or r.actor.ColonyID~=r.owner or controlled(r.actor)then restore(r,t)
    elseif r.failure then
     local f=r.failure
     if not f.started then f.started=t
     else
      local elapsed=t-f.started;local progress=clamp(elapsed/f.duration)
      r.actor.Immobile=true;r.actor.DontRotate=true;r.actor.AbilityInUse=true;r.actor.NoCombat=false
      for _,field in ipairs(GRAB)do r.actor[field]=true end
      pose(r,r.role==1 and assets.hold or assets.dash,f.from+(f.to-f.from)*progress)
      local movement=r.role==1 and smooth((progress-.40)/.60)or 1-(1-progress)^2
      if f.distance~=0 then move(j,r,{X=f.origin.X+f.direction.X*f.distance*movement,Y=f.origin.Y+f.direction.Y*f.distance*movement,Z=f.origin.Z})end
      if progress>=1 then restore(r,t)end
     end
    else restore(r,t)end
   elseif not r.restored and t>=r.released+M.blend+.02 then mesh_restore(r)end
  end
  return all_released
 end
 local function local_time(r,t)
  if r.role==1 then return M.holder_time(t)end
  return r.delay and M.dasher_time(t-r.delay)or -1
 end
 local function update(j,t,ctx)
  if ctx.world_id~=j.world then cancel(j,'travel',t);cleanup(j);return end
  if j.cancelled then advance_failure(j,t);if t>=j.cleanup_at then cleanup(j)end;return end
  local check_choice=t>=(j.next_choice_check or 0)
  if check_choice then j.next_choice_check=t+.2 end
  for _,r in ipairs(j.members)do
   if not r.released and(not same(r)or not alive(r.actor)or r.actor.ColonyID~=r.owner or r.actor.ColonyLocation~=j.layer or controlled(r.actor)or check_choice and not o.eligible(r.actor))then cancel(j,'participant_interrupted',t);return end
  end
  if not j.killed then
   if not same(j.target)or not alive(j.target.actor)or j.target.actor.ColonyID~=j.target.owner or controlled(j.target.actor)then cancel(j,'target_interrupted',t);return end
   local target=j.target.actor
   if target.ColonyLocation~=j.layer or target.CannotBeExercuted==true or target.Health/target.FullHealth>=M.threshold or not j.members[1].actor:IsCreatureEnemy(target)then cancel(j,'target_ineligible',t);return end
  end
  -- The animation instance gets one native evaluation after construction.
  if not j.ready then j.ready=true;j.started=ctx.gs:GetLevelTime();return end
  if not j.grabbed_at then
   local holder=j.members[1];local _,current=live_instance(holder)
   if holder.montage and current and current:GetAddress()==holder.instance:GetAddress()then
    local at=current:Montage_GetPosition(holder.montage)
    -- Read the previous evaluated pose: the jaws must already have closed
    -- on screen before either dasher changes to its cinematic graph.
    if at>=M.bite_contact then j.grabbed_at=t;stats.last_grab_time=t;stats.last_grab_clip=at end
   end
  end
  for i,r in ipairs(j.members)do if not r.released then
   local row=j.layout.members[i]
   r.actor.Immobile=true;r.actor.DontRotate=true;r.actor.AbilityInUse=true;r.actor.NoCombat=false
   for _,field in ipairs(GRAB)do r.actor[field]=true end
   if i>1 and not r.delay then
    if r.entry_wait then
     r.entry_wait=nil;r.delay=t
     j.strike=math.max(j.strike,t+1.2-M.dash_lead+.22*row.startDistance/(row.startDistance+130)+.01)
     j.finish=math.max(j.finish,t+M.release_dash-M.dash_lead+M.blend+.04)
    elseif j.grabbed_at and t>=j.grabbed_at+(i==3 and M.stagger or 0)then
     -- Keep the ordinary animation while waiting. Capture its latest pose
     -- only now, then give the new instance one native evaluation.
     arm_animation(r);r.entry_wait=true
     j.finish=math.max(j.finish,t+M.release_dash-M.dash_lead+M.blend+.08)
    end
   end
   local u=local_time(r,t)
   if r.animate and not r.entry_wait then
   local turn=(row.yaw-r.heading.Yaw+180)%360-180
   local turn_time=i==1 and u or u-M.dash_lead
   r.actor:K2_SetActorRotation({Pitch=r.heading.Pitch,Yaw=r.heading.Yaw+turn*smooth(turn_time/.35),Roll=r.heading.Roll},false)
   if u>=0 then pose(r,i==1 and assets.hold or assets.dash,u)end
   if i==1 and j.killed and u>=2.08 then
    local f=smooth((u-2.08)/.47);move(j,r,{X=row.start.X+(row.holderRetreat.X-row.start.X)*f,Y=row.start.Y+(row.holderRetreat.Y-row.start.Y)*f,Z=row.start.Z})
   elseif i>1 and u>=1.2 then r.dashing=true;move(j,r,o.layout.position(row,u,r.plan.length));record_crossing(j,r)end
   if i>1 then
    local air=j.air[i]
    if u>=1.18 and u<1.64 then
     local cross=clamp((u-1.2)/.22);local braking=clamp((u-1.42)/.79)
     local fade=u<1.42 and clamp((u-1.18)/.04)or 1-clamp((u-1.42)/.22)
     local length=45+95*math.max(cross,braking);local dx,dy=row.direction.X,row.direction.Y;local p=pos(r.actor)
     air.actor:SetActorHiddenInGame(false);air.actor:K2_SetActorLocation({X=p.X-dx*length*.4,Y=p.Y-dy*length*.4,Z=p.Z+15},false,{},true)
     air.actor:K2_SetActorRotation({Pitch=0,Yaw=row.yaw,Roll=0},false);air.actor:SetActorScale3D({X=length/100,Y=(3+5*fade)/100,Z=(2+1.6*fade)/100})
     air.material:SetScalarParameterValue(FName('Opacity'),.06*fade^1.2);air.material:SetScalarParameterValue(FName('IOR'),1+.16*fade)
     air.material:SetVectorParameterValue(FName('NormalVec'),{R=.025*math.sin(50*u+i),G=.025*math.cos(44*u+i),B=.9995,A=1})
    else air.actor:SetActorHiddenInGame(true)end
    if u>=1.2 and not r.dust then local p=pos(r.actor);p.Z=p.Z-11;emit(j,assets.dust,p,.16);r.dust=true end
   end
   end
  end end
  if not j.killed and(not same(j.target)or not alive(j.target.actor))then cancel(j,'target_killed_during_dash',t);return end
  if j.passes==2 and not j.killed then
   -- Native path damage can synchronously trigger retaliation/death. The
   -- opening frame check must not let that casualty commit a later kill.
   for _,r in ipairs(j.members)do
    if not same(r)or not alive(r.actor)or r.actor.ColonyID~=r.owner or r.actor.ColonyLocation~=j.layer or controlled(r.actor)then cancel(j,'participant_interrupted',t);return end
   end
   local target=j.target.actor
   -- Stop every scripted access to the victim before native death can
   -- unregister it. Never swap its mesh/AnimBP or keep a synthetic corpse.
   restore(j.target,t);j.killed=true;busy[j.target.key]=nil
   local p={X=j.origin.X,Y=j.origin.Y,Z=j.origin.Z+9};emit(j,assets.blood,p,.2)
   local killer=j.source.actor
   if not alive(killer)then for _,r in ipairs(j.members)do if same(r)and alive(r.actor)then killer=r.actor;break end end end
   local committed,why=o.commit(killer,target)
   if committed~=true then cancel(j,why or'kill_not_committed',t);return end
   stats.completed=stats.completed+1
  end
  if not j.killed then
   for i=2,3 do if j.members[i].blocked then cancel(j,'path_blocked',t);return end end
   if t>=j.finish then cancel(j,'incomplete_crossing',t);return end
  end
  for i,r in ipairs(j.members)do
   local u=local_time(r,t)
   if not r.released then
    if i==1 and j.killed and u>=M.release_holder then restore(r,t)
    elseif i>1 and j.killed and u>=1.42 then
     local p=pos(r.actor);local finish=r.finish
     local atEnd=r.plan.blocked and(p.X-finish.X)^2+(p.Y-finish.Y)^2<=16
     if r.blocked or atEnd or u>=M.release_dash then restore(r,t)end
    end
   elseif not r.restored and t>=r.released+M.blend+.02 then mesh_restore(r)end
  end
  if t>=j.finish then cleanup(j)end
 end
 local function frame()
  local ctx=o.get_context()
  if not ctx then api.reset_cache();return end
  local now=ctx.gs:GetLevelTime();stats.frames=stats.frames+1
  for _,j in pairs(jobs)do
   local t=now-j.started
   local ok,why=pcall(update,j,t,ctx)
   if not ok then fail(why);cancel(j,'runtime_error',t)end
  end
  if not next(jobs)and timer then CancelDelayedAction(timer);timer=nil end
 end
 function api.owns(a)return busy[key(a)]~=nil end
 function api.reduce_damage(a,damage)
  if stopped or not next(jobs)or not damage or damage<=0 then return damage end
  local id=key(a);local j=id and busy[id];local r=j and j.participants[id]
  if not r or r.released or not same(r)or a.ColonyID~=r.owner then return damage end
  -- One refund of the actual post-armour debit, before native death. Venom
  -- AOE is one hit here, so its two labels never apply our reduction twice.
  local refund=damage*M.reduction
  a.Health=math.min(a.FullHealth,a.Health+refund)
  stats.reduced_hits=stats.reduced_hits+1;stats.damage_refunded=stats.damage_refunded+refund
  return damage-refund
 end
 function api.candidates(source,center,radius)
  -- Native overlap queries omit the cinematic ants while their collision is
  -- temporarily disabled. Keep them eligible for normal nearby kill rewards.
  local result={};local world=native.world_id(source)
  for _,j in pairs(jobs)do if j.world==world then for _,r in ipairs(j.members)do
   if r.animate and same(r)and alive(r.actor)and not r.actor:GetActorEnableCollision()then
    local p=pos(r.actor)
    if(p.X-center.x)^2+(p.Y-center.y)^2+(p.Z-center.z)^2<=radius^2 then result[#result+1]=r.actor end
   end
  end end end
  return result
 end
 function api.available(a,now)
  local k=key(a);if not k or busy[k]then return false end
  local row=cooldowns[k]
  if row and(not same(row)or now>=row.until_time)then cooldowns[k]=nil;row=nil end
  return not row
 end
 function api.start(source,target,members)
  if stopped or #members<3 or not alive(target)or target.FullHealth<=0 or target.Health/target.FullHealth>=M.threshold or target.CannotBeExercuted==true then return false end
  local ctx=o.get_context();if not ctx or native.world_id(target)~=ctx.world_id or api.owns(target)then return false end
  local now=ctx.gs:GetLevelTime();local picked={}
  for _,row in ipairs(members)do if #picked<3 and api.available(row.actor,now)and alive(row.actor)and not controlled(row.actor)and o.eligible(row.actor)then picked[#picked+1]=row.actor end end
  if #picked~=3 then return false end
  local prepared,why=api.prepare();if not prepared then return nil,why end
  sequence=sequence+1;local j={id=sequence,started=now,world=ctx.world_id,gs=ctx.gs,source=identity(source),layer=target.ColonyLocation,members={},participants={},air={},passes=0}
  jobs[j.id]=j
  local ok,result=pcall(function()
   local starts,forwards={},{}
   for i,a in ipairs(picked)do starts[i]=pos(a);local f=a:GetActorForwardVector();forwards[i]={X=f.X,Y=f.Y,Z=f.Z}end
   j.origin=pos(target);j.layout=o.layout.build(starts,j.origin,forwards);j.ignored={target}
   for _,a in ipairs(picked)do j.ignored[#j.ignored+1]=a end
   if o.nearby then each(o.nearby(source,{x=j.origin.X,y=j.origin.Y,z=j.origin.Z},600),function(a)if valid(a)then j.ignored[#j.ignored+1]=a end end)end
   j.guard=o.guard.install({trace=function(a,s,f,size,rotation,channel,ignored)
    local hit={};local yes=assets.sys:BoxTraceSingle(a,s,f,size,rotation,channel,false,ignored,0,hit,true,{R=1,G=0,B=0,A=1},{R=0,G=1,B=0,A=1},0);return yes,hit
   end,walkable=j.layer>=0 and function(a,p)return o.walkable(ctx,j.layer,p)end or nil})
   j.strike=1.3+M.hold_delay;j.finish=M.finish+M.hold_delay
   for role,index in ipairs(j.layout.order)do
    local a=picked[index];local r=identity(a);r.role=role;j.members[role]=r;j.participants[r.key]=r;busy[r.key]=j
    -- Keep a rollback identity even if an intermediate native call fails.
    local saved=remember(a,role==1,r);j.members[role]=saved;r=saved
    local rot=a:K2_GetActorRotation();r.heading={Pitch=rot.Pitch,Yaw=rot.Yaw,Roll=rot.Roll}
    local cd=identity(a);cd.until_time=now+M.cooldown;cooldowns[r.key]=cd
    if role>1 then
     local row=j.layout.members[role];r.finish,r.plan=j.guard.limit(a,row.start,row.finish,j.ignored)
     if r.plan.length<math.max(0,row.startDistance-15)then error('execution_approach_obstructed')end
     if r.plan.blocked then stats.shortened=stats.shortened+1 end
     j.air[role]=make_air(j,r)
    end
   end
   j.target=identity(target);busy[j.target.key]=j;remember(target,false,j.target)
   return true
  end)
  if not ok then
   -- An obstructed approach is a normal rejected cast, not a script fault.
   if not tostring(result):find('execution_approach_obstructed',1,true)then fail(result)end
   stats.last_start_rejection=tostring(result);cancel(j,'start_rejected',0)
  else stats.started=stats.started+1 end
  if not timer then timer=LoopInGameThreadAfterFrames(1,frame)end
  return ok and true or false
 end
 function api.reset_cache()
  for _,j in pairs(jobs)do
   for _,r in ipairs(j.members)do pcall(restore,r,0);pcall(mesh_restore,r);pcall(release_montage,r)end
   if j.target then pcall(restore,j.target,0)end
   destroy_air(j)
  end
  jobs,busy,cooldowns={},{},{};assets=nil
  if timer then CancelDelayedAction(timer);timer=nil end
  return true
 end
 function api.stop()api.reset_cache();stopped=true;return true end
 function api.status()
  local s={active=0,timerActive=timer~=nil,retainedAssets=0,retainedMontages=0};for _ in pairs(jobs)do s.active=s.active+1 end
  for _,r in pairs(retained)do local k=r.temporary and'retainedMontages'or'retainedAssets';s[k]=s[k]+1 end
  for k,v in pairs(stats)do s[k]=v end;return s
 end
 function api.debug_state()
  -- Scalar-only diagnostics: never hand a cached combatant UObject to QA
  -- across a native collection, death or world transition.
  local out={};local ctx=o.get_context();local now=ctx and ctx.gs:GetLevelTime()
  for _,j in pairs(jobs)do
   local row={id=j.id,elapsed=now and now-j.started,passes=j.passes,killed=j.killed==true,cancelled=j.cancelled,target=j.target and j.target.key,target_health=j.target and same(j.target)and j.target.actor.Health or nil,members={}}
   for _,r in ipairs(j.members)do
    row.members[#row.members+1]={key=r.key,role=r.role,passed=r.passed==true,released=r.released~=nil,animate=r.animate==true,failure=r.failure~=nil,health=same(r)and r.actor.Health or nil}
   end
   out[#out+1]=row
  end
  return out
 end
 return api
end
return M
