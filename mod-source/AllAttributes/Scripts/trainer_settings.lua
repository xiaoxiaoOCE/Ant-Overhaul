-- Optional home console preference, outside gameplay saves. Native General
-- settings own the enable/disable widget and their normal OK/Apply/Cancel flow.
local M={}
local dir=assert(debug.getinfo(1,'S').source:sub(2):match('^(.*)[/\\]'))
local fs_default=dofile(dir..'/unicode_fs.lua')
local HEADER='EAA_MOD_SETTINGS\t1\nhome_console\t'
function M.new(o)
 o=o or{};local fs=o.fs or fs_default;local enabled=false
 local function read(path)
  local f=path and fs.open(path,'rb');if not f then return nil end
  local raw=f:read(129);f:close()
  if raw==HEADER..'1\n' then return true elseif raw==HEADER..'0\n' then return false end
 end
 if o.path then
  local value=read(o.path);if value==nil then value=read(o.path..'.bak')end
  enabled=value==true
 end
 local api={}
 function api.enabled()return enabled end
 function api.set(value)
  if type(value)~='boolean'then return nil,'invalid_console_preference'end
  if value==enabled then return true end
  local ok,why=pcall(function()
   assert(type(o.path)=='string','missing_settings_path')
   local f=assert(fs.open(o.path..'.tmp','wb'))
   assert(f:write(HEADER..(value and'1\n'or'0\n')));assert(f:close())
   assert(read(o.path..'.tmp')==value,'settings_readback_failed')
   local prior=fs.open(o.path,'rb')
   if prior then prior:close();fs.remove(o.path..'.bak');assert(fs.rename(o.path,o.path..'.bak'))end
   local renamed,err=fs.rename(o.path..'.tmp',o.path)
   if not renamed then if prior then fs.rename(o.path..'.bak',o.path)end;error(err or'settings_commit_failed')end
  end)
  if not ok then return nil,tostring(why)end
  enabled=value
  if o.changed then o.changed(enabled)end
  return true
 end
 return api
end

local OPTIONS='/Game/UI/InGame/OptionsDialogue2.OptionsDialogue2_C'
local RADIO='/Game/UI/InGame/UIUpdate/EnableDisableRadioButtons.EnableDisableRadioButtons_C'
local WORDS={
 zh={title='养殖箱控制台',hint='蚂蚁大修：启用并点击确定后，按 Shift + CapsLock 呼出。仅养殖箱休整时可用。',failed='控制台设置未保存，请重试。'},
 en={title='Formicarium console',hint='Ant Overhaul: enable and confirm, then press Shift + CapsLock. Available only while resting in the formicarium.',failed='Could not save the console setting. Please try again.'},
}
function M.install(o)
 local valid=assert(o.valid_object);local views,pending={},{}
 local function id(w)return valid(w)and tostring(w:GetAddress())or nil end
 local function mounted(w)return valid(w)and valid(w:GetOwningPlayer())and(w:IsInViewport()or valid(w:GetParent()))end
 local function unbox(v)local ok,x=pcall(function()return v:get()end);return ok and x~=nil and x or v end
 local function log(why)if o.log then o.log('[HomeConsoleSettings] '..tostring(why))end end
 local function ft(v)return StaticFindObject('/Script/Engine.Default__KismetTextLibrary'):Conv_StringToText(v)end
 local function language()
  local v=StaticFindObject('/Script/Engine.Default__KismetInternationalizationLibrary'):GetCurrentLanguage()
  local code=type(v)=='string'and v or v:ToString()
  return code:lower():match('^zh')and'zh'or'en'
 end
 local saved=StaticFindObject('/Script/Engine.Default__BlueprintPathsLibrary'):ProjectSavedDir():ToString()
 local preference=M.new{path=saved..'EAA_ModSettings_v1.ini',changed=o.changed}
 local ensure_hooks
 local function refresh(view)
  local w=WORDS[language()];view.label:SetText(ft(w.title));view.hint:SetText(ft(w.hint))
 end
 local function live(view)return view and valid(view.owner)and valid(view.radio)end
 local function commit(receiver)
  local owner=unbox(receiver);local view=views[id(owner)]
  if not live(view)then return end
  local value=view.radio.EnableCheckbox:IsChecked()==true
  -- Snapshot before native OK closes the menu; persist/apply after its handler.
  ExecuteInGameThreadAfterFrames(1,function()
   local ok,why=preference.set(value)
   if not ok then
    log(why)
    if live(view)then view.radio:SetState(preference.enabled(),true);view.hint:SetText(ft(WORDS[language()].failed))end
   end
  end)
 end
 local function attach(owner)
  if not mounted(owner)then return false end
  ensure_hooks()
  local key=id(owner);if live(views[key])then refresh(views[key]);return true end
  assert(valid(owner.GeneralSettings)and valid(owner.EnableTipsRadioBox),'general_settings_not_ready')
  local grid=owner.GeneralSettings;local row=0
  local original_label
  for i=0,grid:GetChildrenCount()-1 do
   local w=grid:GetChildAt(i);row=math.max(row,w.Slot.Row+1)
   if not original_label and w:GetClass():GetFName():ToString()=='TextBlock'then original_label=w end
  end
  assert(original_label,'general_label_missing')
  local tree=owner.WidgetTree
  local function label()
   local w=StaticConstructObject(StaticFindObject('/Script/UMG.TextBlock'),tree)
   assert(valid(w),'settings_label_missing');w:SetFont(original_label.Font)
   w:SetColorAndOpacity(original_label.ColorAndOpacity);w:SetVisibility(3);return w
  end
  local title=label();local hint=label();hint:SetAutoWrapText(true);hint.WrapTextAt=760
  local font=hint.Font;font.Size=math.max(12,math.floor(font.Size*.78));hint:SetFont(font)
  local creator=StaticFindObject('/Script/UMG.Default__WidgetBlueprintLibrary')
  local radio=creator:Create(owner:GetOwningPlayer(),owner.EnableTipsRadioBox:GetClass(),owner:GetOwningPlayer())
  assert(valid(radio),'settings_radio_missing');radio.StartState=preference.enabled();radio:SetState(preference.enabled(),true)
  local a=grid:AddChildToGrid(title,row,0);a:SetPadding({Left=0,Top=16,Right=20,Bottom=16});a:SetVerticalAlignment(2)
  local b=grid:AddChildToGrid(radio,row,1);b:SetVerticalAlignment(2)
  b:SetHorizontalAlignment(owner.EnableTipsRadioBox.Slot.HorizontalAlignment);b:SetPadding(owner.EnableTipsRadioBox.Slot.Padding)
  local c=grid:AddChildToGrid(hint,row+1,0);c:SetColumnSpan(2);c:SetPadding({Left=0,Top=0,Right=0,Bottom=20})
  views[key]={owner=owner,radio=radio,label=title,hint=hint,row=row};refresh(views[key])
  return true
 end
 local function schedule(owner,attempt)
  local key=id(owner);if not key or pending[key]then return end;pending[key]=true
  ExecuteInGameThreadAfterFrames(attempt==0 and 2 or 10,function()
   pending[key]=nil;if not valid(owner)then return end
   local ok,value=pcall(attach,owner)
   if not ok then log(value)elseif not value and attempt<20 then schedule(owner,attempt+1)end
  end)
 end
 local hooked=false
 ensure_hooks=function()
 if hooked then return end
 for _,name in ipairs({
  'BndEvt__ButtonOK_K2Node_ComponentBoundEvent_182_OnButtonClickedEvent__DelegateSignature',
  'BndEvt__ButtonApply_K2Node_ComponentBoundEvent_142_OnButtonReleasedEvent__DelegateSignature',
  'BndEvt__ButtonOK_1_K2Node_ComponentBoundEvent_32_OnButtonReleasedEvent__DelegateSignature',
 })do RegisterHook(OPTIONS..':'..name,commit)end
 RegisterHook(OPTIONS..':OnOkay',commit)
 RegisterHook(OPTIONS..':UpdateLanguageSelection',function(receiver)
  local view=views[id(unbox(receiver))];if view then ExecuteInGameThreadAfterFrames(2,function()if live(view)then refresh(view)end end)end
 end)
 hooked=true
 end
 NotifyOnNewObject(OPTIONS,function(owner)schedule(owner,0)end)
 for _,owner in ipairs(FindAllOf('OptionsDialogue2_C')or{})do schedule(owner,0)end
 function preference.status()
  local rows={};for key,view in pairs(views)do if live(view)then rows[#rows+1]={owner=key,row=view.row,selected=view.radio.EnableCheckbox:IsChecked(),visible=mounted(view.owner)}end end
  return{enabled=preference.enabled(),path=saved..'EAA_ModSettings_v1.ini',views=rows}
 end
 return preference
end
return M
