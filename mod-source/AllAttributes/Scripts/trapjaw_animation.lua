-- Per-individual native attack-sequence substitution. The original mesh,
-- skeleton, movement state machine and native damage notifications are kept.
-- The caller controls when sting mode begins and owns damage/rate modifiers.
local M={}
local base='/Game/Assets/3DModels/Ants/Units/TrapJaw/VU/'
local skeleton=base..'Trapjaw_Ant_Skeleton.Trapjaw_Ant_Skeleton'
local anim_class=base..'Trapjaw_Ant_AnimBlueprint.Trapjaw_Ant_AnimBlueprint_C'
-- The playable fire-ant soldier's real Sting1 clip, bind-pose retargeted to
-- this skeleton. No authored curl/strike key poses or old-pose fallback.
local native_spec={sequence='/Game/EAA/TrapjawFireAntStingV1.TrapjawFireAntStingV1',
 length=0.6333333253860474,hit_time=0.20809637010097504,end_time=0.6026790738105774}
local nodes={
 {name='AnimGraphNode_SequencePlayer_1',original=base..'Trapjaw_Ant_Anim_Melee_1.Trapjaw_Ant_Anim_Melee_1'},
 {name='AnimGraphNode_SequencePlayer_2',original=base..'Trapjaw_Ant_Anim_Melee_2.Trapjaw_Ant_Anim_Melee_2'},
 {name='AnimGraphNode_SequencePlayer_3',original=base..'Trapjaw_Ant_Anim_Melee_3.Trapjaw_Ant_Anim_Melee_3'},
}
local function safe(f)local ok,v=pcall(f);if ok then return v end end
function M.install(options)
 options=options or {}
 local states,reported={},{}
 local asset,stopped,scan_cursor
 local api={}
 local spec=options.sequence_spec or native_spec
 local function valid(o)
  if options.native and options.native.valid_object then return safe(function()return options.native.valid_object(o)end)==true end
  return o~=nil and safe(function()return o:IsValid()end)==true
 end
 local function id(o)return valid(o)and safe(function()return tostring(o:GetAddress())end)end
 local function path(o)
  if not valid(o)then return nil end
  local n=safe(function()return o:GetFullName()end)
  return type(n)=='string'and(n:match(' (%/.+)$')or n:match('^(%/.+)$'))or nil
 end
 local function fail(e)
  e=tostring(e);if not reported[e]then reported[e]=true;if options.log then pcall(options.log,'[TrapjawAnimation] '..e)end end
  return nil,e
 end
 local function load()
  if valid(asset)then return asset end
  asset=options.load_asset and options.load_asset(spec.sequence)or StaticFindObject(spec.sequence)
  if not valid(asset)and not options.load_asset then asset=LoadAsset(spec.sequence)end
  if not valid(asset)then
   -- UE4SS LoadAsset enumerates registry entries and may miss new pak assets.
   -- AssetRegistryHelpers loads an explicit FAssetData ObjectPath directly,
   -- matching the official UE4SS BPModLoader's dynamic asset path.
   local registry=StaticFindObject('/Script/AssetRegistry.Default__AssetRegistryHelpers')
   if valid(registry)then asset=registry:GetAsset({ObjectPath=FName(spec.sequence)})end
  end
  assert(valid(asset),'sting_sequence_missing')
  assert(path(asset.Skeleton)==skeleton,'sting_sequence_skeleton_mismatch')
  local len=tonumber(asset.SequenceLength)
  assert(len and len>0 and math.abs(len-spec.length)<0.0001,'sting_sequence_length_changed')
  return asset
 end
 local function resolve(c)
  assert(not stopped,'sting_animation_stopped')
  assert(valid(c),'sting_creature_invalid')
  local mesh=c.Mesh;assert(valid(mesh),'sting_mesh_missing')
  assert(path(mesh.SkeletalMesh.Skeleton)==skeleton,'sting_skeleton_unsupported')
  assert(tonumber(mesh:GetAnimationMode())==0,'sting_animation_mode_busy')
  assert(path(mesh:GetAnimClass())==anim_class,'sting_animation_class_unsupported')
  local instance=mesh:GetAnimInstance();assert(valid(instance),'sting_animation_instance_missing')
  return mesh,instance
 end
 local function restore(s)
  if not valid(s.instance)then return true end
  local errors={}
  for _,n in ipairs(nodes)do
   local ok,e=pcall(function()
    local node=s.instance[n.name]
    -- A later independent replacement takes precedence over our restoration.
    if id(node.Sequence)==id(s.asset)then node.Sequence=s.before[n.name]end
   end)
   if not ok then errors[#errors+1]=tostring(e)end
  end
  if #errors>0 then return fail(table.concat(errors,';'))end
  return true
 end
 function api.prepare()
  local ok,e=pcall(load);if not ok then return fail(e)end
  return {length=spec.length,hit_time=spec.hit_time,end_time=spec.end_time,sequence=spec.sequence}
 end
 function api.enable(c)
  local fresh
  local ok,result=pcall(function()
   local mesh,instance=resolve(c);local key=id(c);assert(key,'sting_creature_key_missing')
   local s=states[key]
   if s and id(s.instance)==id(instance)then
    local intact=true
    for _,n in ipairs(nodes)do if id(instance[n.name].Sequence)~=id(s.asset)then intact=false;break end end
    if intact then return {length=spec.length,hit_time=spec.hit_time,end_time=spec.end_time,sequence=spec.sequence}end
   elseif s then
    local restored,e=restore(s);assert(restored,e);states[key]=nil
   end
   local a=load();fresh={instance=instance,mesh=mesh,creature=c,asset=a,before={}}
   -- Validate every node before mutating any. Never alter the Blueprint CDO.
   assert(not path(instance):find('Default__',1,true),'sting_cdo_refused')
   for _,n in ipairs(nodes)do
    local node=instance[n.name];local previous=node.Sequence
    assert(path(previous)==n.original or (s and id(previous)==id(s.asset)),
      'sting_native_node_changed:'..n.name)
    fresh.before[n.name]=s and s.before[n.name]or previous
   end
   for _,n in ipairs(nodes)do
    instance[n.name].Sequence=a
    assert(id(instance[n.name].Sequence)==id(a),'sting_node_assignment_failed:'..n.name)
   end
   states[key]=fresh;fresh=nil
   return {length=spec.length,hit_time=spec.hit_time,end_time=spec.end_time,sequence=spec.sequence}
  end)
  if not ok then if fresh then restore(fresh)end;return fail(result)end
  return result
 end
 function api.is_enabled(c)
  local key=id(c);local s=key and states[key]
  if not s or not valid(s.instance)then return false end
  local ok,result=pcall(function()
   if id(c.Mesh:GetAnimInstance())~=id(s.instance)then return false end
   for _,n in ipairs(nodes)do if id(s.instance[n.name].Sequence)~=id(s.asset)then return false end end
   return true
  end)
  return ok and result==true
 end
 function api.disable(c)
  local key=id(c);local s=key and states[key]
  if not s then return true end
  local ok,e=restore(s);if not ok then return nil,e end;states[key]=nil;return true
 end
 function api.tick()
  -- Bounded cleanup: no full creature scan and no periodic asset lookups.
  if scan_cursor and not states[scan_cursor]then scan_cursor=nil end
  for _=1,32 do
   local key,s=next(states,scan_cursor)
   if not key then scan_cursor=nil;break end
   local stale=not valid(s.creature)or not valid(s.instance)
   if not stale then
    local health=tonumber(safe(function()return s.creature.Health end))
    stale=(health and health<=0)or id(safe(function()return s.creature.Mesh:GetAnimInstance()end))~=id(s.instance)
   end
   if stale then
    local ok=restore(s)
    if ok then states[key]=nil else scan_cursor=key end
   else scan_cursor=key end
  end
  return true
 end
 function api.reset_cache()
  local errors={}
  for key,s in pairs(states)do local ok,e=restore(s);if ok then states[key]=nil else errors[#errors+1]=e end end
  if #errors>0 then return fail(table.concat(errors,';'))end
  asset=nil;scan_cursor=nil;return true
 end
 function api.stop()local ok,e=api.reset_cache();if not ok then return nil,e end;stopped=true;return true end
 function api.status()
  local count=0;for key,s in pairs(states)do if valid(s.creature)and valid(s.instance)then count=count+1 else states[key]=nil end end
  return{enabled=count,sequence=spec.sequence,length=spec.length,stopped=stopped==true}
 end
 return api
end
return M
