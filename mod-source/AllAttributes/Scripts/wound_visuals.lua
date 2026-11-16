-- Rending Wounds reuses the native bleeding droplets with an isolated red
-- particle asset. It never changes a shared vanilla template or debuff actor.
local M={particle='/Game/EAA/RendBloodV1.RendBloodV1'}
function M.install(o)
 local native=assert(o.native)
 local particle,materials,retained_by
 local function valid(v)return v~=nil and native.valid_object(v)==true end
 local function identity(v)return tostring(v:GetAddress())..'|'..v:GetFullName()end
 local function prepare(target)
  local g=StaticFindObject('/Script/Engine.Default__GameplayStatics')
  local gi=g:GetGameInstance(target)
  assert(valid(gi),'wound_visual_game_instance_missing')
  if not valid(particle)then
   particle=StaticFindObject(M.particle)
   if not valid(particle)then particle=LoadAsset(M.particle)end
   -- Custom cooked packages are absent from the game's original registry.
   -- Use the same native FAssetData loader as the execution animations.
   if not valid(particle)then particle=StaticFindObject('/Script/AssetRegistry.Default__AssetRegistryHelpers'):GetAsset({ObjectPath=FName(M.particle)})end
   retained_by=nil;materials=nil
  end
  assert(valid(particle),'wound_visual_asset_missing')
  local ready=materials~=nil
  for _,mat in ipairs(materials or{})do if not valid(mat)then ready=false end end
  if not ready then
   local ml=StaticFindObject('/Script/Engine.Default__KismetMaterialLibrary')
   local new={}
   for i=1,particle.Emitters:GetArrayNum()do
    local base=particle.Emitters[i].LODLevels[1].RequiredModule.Material
    local mat=ml:CreateDynamicMaterialInstance(gi,base,FName('None'),0)
    assert(valid(mat),'wound_visual_material_missing')
    mat:SetVectorParameterValue(FName('SSSColor'),{R=.3,G=.0005,B=.001,A=1})
    new[#new+1]=mat
   end
   materials=new;retained_by=nil
  end
  if retained_by~=identity(gi)then
   local refs,seen={},{}
   for i=1,gi.ReferencedObjects:GetArrayNum()do
    local v=gi.ReferencedObjects[i];refs[#refs+1]=v
    if valid(v)then seen[v:GetAddress()]=true end
   end
   if not seen[particle:GetAddress()]then refs[#refs+1]=particle end
   for _,mat in ipairs(materials)do if not seen[mat:GetAddress()]then refs[#refs+1]=mat end end
   gi.ReferencedObjects=refs
   retained_by=identity(gi)
  end
  return g
 end
 local function remove(handle)
  if not handle or handle.removed then return end
  handle.removed=true
  local c=handle.component
  if valid(c)and identity(c)==handle.identity then
   c:Deactivate()
   local owner=c:GetOwner()
   c:K2_DestroyComponent(valid(owner)and owner or c)
  end
 end
 local function create(target)
  assert(valid(target)and target.Health>0,'wound_visual_target_not_alive')
  local g=prepare(target)
  local root=target.RootComponent
  assert(valid(root),'wound_visual_root_missing')
  -- Match Creature::TickEffects' native BleedEffect creation exactly.
  -- Its scale is WORLD scale; attachment must not multiply it by actor scale.
  -- Native bleeding sets this once on creation, not on every stack refresh.
  local height=math.min(target.ArrivalDist*.6,50)
  local offset=target.DebuffOffset
  local size=height*.125
  local c=g:SpawnEmitterAttached(particle,root,FName('None'),
   {X=offset.X,Y=offset.Y,Z=offset.Z+height},{Pitch=0,Yaw=0,Roll=0},{X=1,Y=1,Z=1},0,false,0,false)
  assert(valid(c),'wound_visual_spawn_failed')
  local handle={component=c,identity=identity(c)}
  local ok,why=pcall(function()
   c:SetWorldScale3D({X=size,Y=size,Z=size})
   -- Two immutable instance materials are shared by this effect only.
   -- Native blood/venom materials are never edited, even with many wounds.
   for i,mat in ipairs(materials)do c:SetMaterial(i-1,mat)end
   c:Activate(true)
  end)
  if not ok then remove(handle);error(why)end
  return handle
 end
 return{create=create,remove=remove}
end
return M
