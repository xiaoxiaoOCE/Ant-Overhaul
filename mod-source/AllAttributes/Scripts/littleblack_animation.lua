-- Individual native Little Black Ant melee -> native sting clips. No mesh,
-- skeleton, attack-speed, GasterFlag ability, or Blueprint CDO is changed.
local M={}
local base='/Game/Assets/3DModels/Ants/Units/LittleBlackAnt/'
local skeleton='/Game/Assets/3DModels/Ants/Units/FireAnt/SolenopsisInvictaMinor_Skeleton.SolenopsisInvictaMinor_Skeleton'
local cls=base..'LittleBlackAnt_Soldier_AnimBP.LittleBlackAnt_Soldier_AnimBP_C'
local nodes={
 {field='AnimGraphNode_SequencePlayer_5',before='Melee1',after='Sting1'},
 {field='AnimGraphNode_SequencePlayer_6',before='Melee2',after='Sting2'},
 {field='AnimGraphNode_SequencePlayer_7',before='Melee3',after='String3'},
}
local function clip(name)return base..'LittleBlackAntSoldier_Anim_'..name..'.LittleBlackAntSoldier_Anim_'..name end
local function safe(fn)local ok,v=pcall(fn);if ok then return v end end
function M.install(o)
 o=o or{};local states,assets,reported={},{},{};local cursor,stopped
 local api={}
 local function valid(v)
  if v==nil then return false end
  if o.native then return safe(function()return o.native.valid_object(v)end)==true end
  return safe(function()return v:IsValid()end)==true
 end
 local function id(v)return valid(v)and tostring(v:GetAddress())end
 local function path(v)local n=valid(v)and safe(function()return v:GetFullName()end);return type(n)=='string'and(n:match(' (%/.+)$')or n:match('^(%/.+)$'))or nil end
 local function fail(e)e=tostring(e);if not reported[e]then reported[e]=true;if o.log then o.log('[LittleBlackAnimation] '..e)end end;return nil,e end
 local function load(name)
  if valid(assets[name])then return assets[name]end
  local p=clip(name);local a=o.load_asset and o.load_asset(p)or StaticFindObject(p)
  if not valid(a)and not o.load_asset then a=LoadAsset(p)end
  assert(valid(a),'littleblack_sting_asset_missing:'..name)
  assert(path(a.Skeleton)==skeleton,'littleblack_sting_skeleton_mismatch')
  assert(math.abs(tonumber(a.SequenceLength)-.6333333253860474)<.0001,'littleblack_sting_length_changed')
  assets[name]=a;return a
 end
 local function restore(s)
  if valid(s.instance)then for _,n in ipairs(nodes)do
   local row=s.instance[n.field]
   if id(row.Sequence)==id(s.after[n.field])then row.Sequence=s.before[n.field]end
  end end
  return true
 end
 function api.prepare()
  local ok,e=pcall(function()for _,n in ipairs(nodes)do load(n.after)end end)
  if not ok then return fail(e)end;return true
 end
 function api.enable(c)
  local fresh
  local ok,result=pcall(function()
   assert(not stopped and valid(c),'littleblack_animation_invalid_actor')
   local mesh=c.Mesh;assert(valid(mesh)and valid(mesh.SkeletalMesh),'littleblack_mesh_missing')
   assert(path(mesh.SkeletalMesh.Skeleton)==skeleton,'littleblack_skeleton_unsupported')
   assert(tonumber(mesh:GetAnimationMode())==0,'littleblack_animation_busy')
   assert(path(mesh:GetAnimClass())==cls,'littleblack_animclass_unsupported')
   local instance=mesh:GetAnimInstance();assert(valid(instance),'littleblack_animinstance_missing')
   assert(not tostring(path(instance)):find('Default__',1,true),'littleblack_cdo_refused')
   local key=id(c);local old=states[key]
   if old and id(old.instance)~=id(instance)then restore(old);states[key]=nil;old=nil end
   fresh={creature=c,instance=instance,before={},after={}}
   for _,n in ipairs(nodes)do
    local current=instance[n.field].Sequence
    assert(path(current)==clip(n.before)or(old and id(current)==id(old.after[n.field])),'littleblack_node_changed:'..n.field)
    fresh.before[n.field]=old and old.before[n.field]or current;fresh.after[n.field]=load(n.after)
   end
   for _,n in ipairs(nodes)do instance[n.field].Sequence=fresh.after[n.field]end
   states[key]=fresh;fresh=nil;return true
  end)
  if not ok then if fresh then pcall(restore,fresh)end;return fail(result)end;return result
 end
 function api.disable(c)
  local key=id(c);local row=key and states[key];if not row then return true end
  local ok,e=pcall(restore,row);if not ok then return fail(e)end;states[key]=nil;return true
 end
 function api.tick()
  if cursor and not states[cursor]then cursor=nil end
  for _=1,32 do
   local key,s=next(states,cursor);if not key then cursor=nil;break end
   if not valid(s.creature)or not valid(s.instance)or(tonumber(safe(function()return s.creature.Health end))or 0)<=0
    or id(safe(function()return s.creature.Mesh:GetAnimInstance()end))~=id(s.instance)then
    local ok,e=pcall(restore,s);if not ok then return fail(e)end;states[key]=nil
   else cursor=key end
  end
  return true
 end
 function api.reset_cache()
  for key,s in pairs(states)do local ok,e=pcall(restore,s);if not ok then return fail(e)end;states[key]=nil end
  cursor=nil;assets={};return true
 end
 function api.stop()local ok,e=api.reset_cache();if ok then stopped=true end;return ok,e end
 function api.status()local n=0;for _ in pairs(states)do n=n+1 end;return{enabled=n,stopped=stopped==true}end
 return api
end
return M
