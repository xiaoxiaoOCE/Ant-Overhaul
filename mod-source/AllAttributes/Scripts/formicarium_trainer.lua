-- Home-only editor. Native counters/save variables retain save ownership;
-- input callbacks only queue actions, and every write rechecks the live mode.
local M={maximum=1000000,fields={'food','population','territory'}}
local FIELDS={food=true,population=true,territory=true}
local CAP='EAA_HomeTrainer_PopCap'
local HAS_CAP='EAA_HomeTrainer_HasPopCap'
local MAPS={LabFormicarium=true,LabFormicariumStage2=true,LabFormicariumStage3=true,LabFormicariumStage4=true}
local WORDS={
 zh={title='养殖箱控制台',subtitle='仅限养殖箱休整，挑战中停用',food='食物数量',population='最大人口',territory='最大领土',
  apply='设置',close='关闭',hint='Shift + CapsLock 显示 / 隐藏',saved='正常保存游戏后保留修改。',
  food_info='食物容量 %d',population_info='当前上限 %s；0 表示不限人口',territory_info='已挖 %d 格 + 可用 %d 格',unlimited='不限',
  integer='请输入 0～1000000 的整数。',capacity='不能超过当前食物容量（%d）。',dug='总领土不能小于已挖开的格数（%d）。',
  busy='正在载入或保存，请稍后设置。',done='已设置%s：%s',failed='设置未完成，请查看日志。'},
 en={title='Formicarium console',subtitle='Home only; disabled in challenges',food='Food',population='Pop. cap',territory='Territory',
  apply='Set',close='Close',hint='Shift + CapsLock to show / hide',saved='Save the game normally to retain changes.',
  food_info='Food capacity: %d',population_info='Current cap: %s; 0 means unlimited',territory_info='%d excavated + %d available',unlimited='Unlimited',
  integer='Enter a whole number from 0 to 1000000.',capacity='Cannot exceed current food capacity (%d).',dug='Total territory cannot be below excavated tiles (%d).',
  busy='Loading or saving. Please try again shortly.',done='%s set to %s.',failed='Could not apply. Please check the log.'},
}
local function integer(value)return type(value)=='number'and value==value and value>=0 and value<=M.maximum and value%1==0 end
function M.parse(value)
 if type(value)=='number'then return integer(value)and value or nil end
 if type(value)~='string'or #value>32 then return nil end
 local text=value:match('^%s*(%d+)%s*$')
 local n=text and tonumber(text)
 return n and integer(n)and n or nil
end
function M.allowed(ctx)
 return type(ctx)=='table'and ctx.home==true and ctx.in_mission==false and ctx.arena~=true
  and type(ctx.key)=='string'and ctx.key~=''
end
function M.plan(field,input,snapshot)
 if not FIELDS[field]then return nil,'integer'end
 local value=M.parse(input);if not value then return nil,'integer'end
 if field=='food'and value>snapshot.capacity then return nil,'capacity',snapshot.capacity end
 if field=='territory'and value<snapshot.dug then return nil,'dug',snapshot.dug end
 return value
end

function M.new(o)
 local api={};local panel,lease,last_key,last_allowed=nil,nil,nil,false
 local enabled=o.enabled==true
 local toggles,actions,epoch,stopped,load_pending=0,{},0,false,true
 local next_poll,next_refresh=0,0
 local stats={applied=0,denied=0,errors=0,contexts=0}
 local function now()return(o.clock or os.clock)()end
 local function words()return WORDS[panel and panel.language or(o.language and o.language()or'zh')]or WORDS.en end
 local function report(why)
  stats.errors=stats.errors+1;stats.last_error=tostring(why)
  if o.log then o.log('[HomeTrainer] '..tostring(why))end
 end
 local function fresh()stats.contexts=stats.contexts+1;return o.context()end
 local function same(ctx,key)return ctx and ctx.key==key end
 local function close(focus)
  if panel then o.close(panel,focus==true);panel=nil;epoch=epoch+1 end
  actions={}
 end
 local function restore(ctx)
  if lease and not ctx then return end
  if lease and same(ctx,lease.key)and lease.owned and o.read(ctx).population==lease.value then o.set_cap(ctx,lease.before)end
  lease=nil
 end
 local function apply_cap(ctx,value)
  local before=lease and lease.key==ctx.key and lease.owned and lease.before or o.read(ctx).population
  o.set_cap(ctx,value)
  assert(o.read(ctx).population==value,'home_cap_readback_failed')
  lease={key=ctx.key,before=before,value=value,owned=true}
 end
 local function message(code,arg)
  local w=words();return arg~=nil and string.format(w[code],arg)or w[code]
 end
 function api.set_enabled(value)
  enabled=value==true
  if not enabled then close(false);toggles=0;actions={}end
  return true
 end
 function api.request_toggle()if not stopped and enabled then toggles=math.min(8,toggles+1)end end
 function api.request_apply(field,input,generation)
  if not stopped and enabled and panel and generation==epoch and #actions<8 then
   actions[#actions+1]={field=field,input=input,epoch=generation,key=panel.key}
  end
 end
 function api.note_external_cap(key)
  if stopped then return end
  if lease and lease.key==key then lease.owned=false end
  load_pending=true;next_poll=0
 end
 function api.loaded()if not stopped then load_pending=true;next_poll=0 end end
 function api.tick()
  if stopped then return true end
  local active_input=toggles>0 or #actions>0
  if not active_input and not panel and not lease and not load_pending then return true end
  local time=now()
  if not active_input and not panel and time<next_poll then return true end
  next_poll=time+.25
  local ok,why=pcall(function()
   local ctx=fresh();local allowed=M.allowed(ctx)
   if ctx and last_key~=ctx.key then close(false);lease=nil;last_key=ctx.key;last_allowed=false;load_pending=true end
   if not allowed then
    local had_override=lease~=nil
    close(false);restore(ctx);toggles=0;last_allowed=false
    if ctx and ctx.home==true then load_pending=load_pending or had_override
    elseif ctx then load_pending=false end
    return
   end
   if load_pending or not last_allowed then
    if o.ready(ctx)then
     local saved=o.saved_cap(ctx)
     if saved~=nil then assert(integer(saved),'invalid_saved_home_cap');apply_cap(ctx,saved)end
     load_pending=false
    end
   end
   last_allowed=true
   local count=toggles;toggles=0
   for _=1,count do
    if panel then close(true)
    elseif o.ready(ctx)then
     epoch=epoch+1
     panel=o.open(ctx,o.read(ctx),epoch,function(...)api.request_apply(...)end)
     panel.key=ctx.key;panel.epoch=epoch;next_refresh=0
    else stats.denied=stats.denied+1 end
   end
   local queued=actions;actions={}
   for _,job in ipairs(queued)do
    if enabled and panel and job.epoch==epoch and job.key==panel.key then
     local live=fresh()
     if not M.allowed(live)or live.key~=job.key then close(false);stats.denied=stats.denied+1
     elseif not o.ready(live)then o.message(panel,words().busy,false)
     else
      local snapshot=o.read(live)
      local value,reason,arg=M.plan(job.field,job.input,snapshot)
      if not value then stats.denied=stats.denied+1;o.message(panel,message(reason,arg),false)
      else
       if job.field=='population'then apply_cap(live,value);o.save_cap(live,value)
       elseif job.field=='food'then o.set_food(live,value,snapshot.food)
       else o.set_territory(live,value-snapshot.dug,snapshot.remaining)end
       local actual=o.read(live)
       assert(actual[job.field]==value,'home_value_readback_failed:'..job.field)
       stats.applied=stats.applied+1
       local label=job.field=='population'and value==0 and words().unlimited or string.format('%d',value)
       o.message(panel,string.format(words().done,words()[job.field],label),true)
       o.value(panel,job.field,value)
      end
     end
    end
   end
   if panel and time>=next_refresh then next_refresh=time+.25;o.refresh(panel,o.read(ctx))end
  end)
  if not ok then report(why);if panel then pcall(o.message,panel,words().failed,false)end;return nil,why end
  return true
 end
 function api.close()close(true);return true end
 function api.stop()
  local ctx=fresh();close(false);restore(ctx);stopped=true;toggles=0;actions={};return true
 end
 function api.status()
  local result={enabled=enabled,visible=panel~=nil,epoch=epoch,stopped=stopped,cap_override=lease and lease.value,load_pending=load_pending}
  for k,v in pairs(stats)do result[k]=v end
  return result
 end
 function api.view()return panel end
 return api
end

function M.install(o)
 local native=assert(o.native)
 local api
 local settings=o.settings
 if not settings then
  local dir=assert(debug.getinfo(1,'S').source:sub(2):match('^(.*)[/\\]'))
  settings=dofile(dir..'/trainer_settings.lua').install{valid_object=native.valid_object,log=o.log,
   changed=function(value)if api then api.set_enabled(value)end end}
 end
 local function valid(v)return v~=nil and native.valid_object(v)==true end
 local function text(v)return type(v)=='string'and v or v:ToString()end
 local function unbox(v)local ok,x=pcall(function()return v:get()end);return ok and x~=nil and x or v end
 local function id(v)return valid(v)and tostring(v:GetAddress())or nil end
 local function load(path)local v=StaticFindObject(path);if not valid(v)then v=LoadAsset(path)end;assert(valid(v),'home_trainer_asset_missing:'..path);return v end
 local function ft(s)return StaticFindObject('/Script/Engine.Default__KismetTextLibrary'):Conv_StringToText(s)end
 local function context()
  local base=o.get_context();if not base then return nil end
  local gs,gm,pc,world=base.gs,base.gm,base.pc,base.world
  if not valid(gs)or not valid(gm)or not valid(pc)or not valid(world)then return nil end
  local wid=native.world_id(gs)
  local home=gm:IsA(StaticFindObject('/Script/EotU.EotUFormicariumGameMode'))==true
  if not home or not MAPS[world:GetFName():ToString()]then return {key=wid..':'..id(gm),home=false}end
  local colony=tonumber(pc:GetColonyID());if not colony or colony<0 then return nil end
  local grid=gs:GetTileGridByColonyID(colony)
  if not valid(grid)or not native.is_owned(grid,gs)or native.world_id(grid)~=wid then return nil end
  local slot=text(gm.FormicariumName)
  return {gs=gs,gm=gm,pc=pc,grid=grid,world=world,world_id=wid,colony=colony,slot=slot,home=true,
   arena=base.is_arena,in_mission=gm.InMission,
   key=table.concat({wid,id(gs),id(gm),id(pc),id(grid),tostring(colony),slot},':')}
 end
 local function read(c)
  local food=c.gs:GetResourcesByColony(c.colony)
  local remaining=c.gs:GetTerritoryByColony(c.colony)
  local dug=c.gs:GetTilesExcavatedByColonyID(c.colony)
  return {food=food,capacity=c.gs:GetMaxResourcesByColony(c.colony),population=c.gs:GetPopCapByID(c.colony),
   remaining=remaining,dug=dug,territory=dug+remaining}
 end
 local function language()
  local code=text(StaticFindObject('/Script/Engine.Default__KismetInternationalizationLibrary'):GetCurrentLanguage()):lower()
  return code:match('^zh')and'zh'or'en'
 end
 local button_path='/Game/UI/InGame/UIUpdate/Adaptations/PurchaseMenuButton.PurchaseMenuButton_C'
 local click=button_path..':BndEvt__PurchaseMenuButton_Button_K2Node_ComponentBoundEvent_0_OnButtonReleasedEvent__DelegateSignature'
 local buttons,hooked,writing={},false,false
 local function construct(v,kind)
  local w=StaticConstructObject(load('/Script/UMG.'..kind),v.tree);assert(valid(w),'home_widget_missing:'..kind);return w
 end
 local function place(v,w,x,y,width,height)
  local s=v.canvas:AddChildToCanvas(w);s:SetPosition({X=x,Y=y});s:SetSize({X=width,Y=height});s:SetZOrder(20);return s
 end
 local function label(v,s,size,x,y,width,height)
  local w=construct(v,'TextBlock');w:SetText(ft(s));w:SetFont(v.font)
  local font=w.Font;font.Size=size;w:SetFont(font);w:SetAutoWrapText(true)
  w:SetColorAndOpacity({SpecifiedColor={R=.88,G=.89,B=.79,A=1},ColorUseRule=0});w:SetVisibility(3)
  place(v,w,x,y,width,height);return w
 end
 local function button(v,caption,x,y,width,field,enqueue,generation)
  local w=load('/Script/UMG.Default__WidgetBlueprintLibrary'):Create(v.ctx.pc,load(button_path),v.ctx.pc)
  assert(valid(w),'home_button_missing');w.InStyle=v.style;w.ButtonText=ft(caption)
  place(v,w,x,y,width,38)
  buttons[id(w)]={widget=w,name=w:GetFullName(),view=v,field=field,enqueue=enqueue,epoch=generation}
  return w
 end
 local function message(v,s,success)
  if not valid(v.widget)then return end
  v.status:SetText(ft(s));v.status:SetColorAndOpacity({SpecifiedColor=success and{R=.47,G=.88,B=.57,A=1}or{R=1,G=.57,B=.38,A=1},ColorUseRule=0})
 end
 local function refresh(v,s)
  local w=WORDS[v.language]
  v.info.food:SetText(ft(string.format(w.food_info,s.capacity)))
  v.info.population:SetText(ft(string.format(w.population_info,s.population==0 and w.unlimited or string.format('%d',s.population))))
  v.info.territory:SetText(ft(string.format(w.territory_info,s.dug,s.remaining)))
 end
 local function make(c,s,generation,enqueue)
  buttons={}
  local creator=load('/Script/UMG.Default__WidgetBlueprintLibrary')
  local root=creator:Create(c.pc,load('/Game/UI/Dialogue/DialogueSimpleBlueprint.DialogueSimpleBlueprint_C'),c.pc)
  assert(valid(root),'home_panel_missing')
  local template=creator:Create(c.pc,load('/Game/UI/InGame/TechTree/PurchaseConfirm.PurchaseConfirm_C'),c.pc)
  local hud=c.pc:GetHUD().TugOfWarWidgetInstance
  local v={widget=root,ctx=c,tree=root.WidgetTree,canvas=root.WidgetTree.RootWidget,language=language(),inputs={},info={},apply={},
   style=template.PurchaseButtonStyle,font=hud.FoodCounterText.Font}
  assert(v.canvas:GetClass():GetFName():ToString()=='CanvasPanel','home_panel_root_not_canvas')
  local w=WORDS[v.language]
  label(v,w.title,25,24,20,285,36)
  label(v,w.subtitle,15,24,61,382,30)
  for i,field in ipairs(M.fields)do
   local y=103+(i-1)*83
   label(v,w[field],19,24,y+6,125,34)
   local input=construct(v,'EditableTextBox');input:SetText(ft(string.format('%d',s[field])))
   input.SelectAllTextWhenFocused=true;input.ClearKeyboardFocusOnCommit=true;input.RevertTextOnEscape=true
   input:SetJustification(1);input:SetIsReadOnly(false)
   local font=v.font;font.Size=20;input.Font=font;input.WidgetStyle.Font=font
   input.ForegroundColor={R=.94,G=.95,B=.87,A=1};input.BackgroundColor={R=.16,G=.20,B=.13,A=1}
   place(v,input,154,y,142,38);v.inputs[field]=input
   v.apply[field]=button(v,w.apply,310,y,94,field,enqueue,generation)
   v.info[field]=label(v,'',14,24,y+44,382,30)
  end
  v.status=label(v,w.saved,15,24,356,382,48)
  label(v,w.hint,14,24,412,382,24)
  v.close=button(v,w.close,316,19,88,'close',enqueue,generation)
  refresh(v,s)
  root:AddToViewport(1050);root:SetDesiredSizeInViewport({X=430,Y=454})
  root:SetPositionInViewport({X=24,Y=0},false)
  root:SetAnchorsInViewport({Minimum={X=0,Y=.5},Maximum={X=0,Y=.5}})
  root:SetAlignmentInViewport({X=0,Y=.5})
  for _,b in pairs(v.apply)do
   b.Button:SetStyle(v.style);b.TextBlock_143:SetText(b.ButtonText)
   b.TextBlock_143:RemoveFromParent();local slot=b.Button:SetContent(b.TextBlock_143)
   slot:SetHorizontalAlignment(2);slot:SetVerticalAlignment(2)
   local font=b.TextBlock_143.Font;font.Size=19;b.TextBlock_143:SetFont(font)
  end
  v.close.Button:SetStyle(v.style);v.close.TextBlock_143:SetText(v.close.ButtonText)
  v.close.TextBlock_143:RemoveFromParent();local slot=v.close.Button:SetContent(v.close.TextBlock_143)
  slot:SetHorizontalAlignment(2);slot:SetVerticalAlignment(2)
  if not hooked then
   RegisterHook(click,function(receiver)
    local w=unbox(receiver);local item=buttons[id(w)]
    if not item or not valid(w)or w:GetFullName()~=item.name then return end
    if item.field=='close'then api.request_toggle()
    else item.enqueue(item.field,text(item.view.inputs[item.field]:GetText()),item.epoch)end
   end)
   hooked=true
  end
  return v
 end
 local function set_cap(c,value)
  writing=true;local ok,why=pcall(function()c.gs:SetPopCapByID(c.colony,value)end);writing=false
  assert(ok,why)
 end
 api=M.new{
  enabled=settings.enabled(),
  context=context,ready=o.ready,clock=o.clock,language=language,log=o.log,read=read,
  saved_cap=function(c)
   if c.gs:GetSaveBoolVar(FName(HAS_CAP))~=true then return nil end
   local found={};local value=c.gs:GetSaveFloatVar(FName(CAP),found)
   assert(found.bFound==true,'saved_home_cap_missing');return value
  end,
  save_cap=function(c,value)
   c.gs:SetSaveFloatVar(FName(CAP),value);c.gs:SetSaveBoolVar(FName(HAS_CAP),true)
   local found={};assert(c.gs:GetSaveFloatVar(FName(CAP),found)==value and found.bFound==true,'home_cap_save_readback_failed')
  end,
  set_cap=set_cap,
  set_food=function(c,value,before)
   if value>before then c.gs:GivePlayerResources(c.colony,value-before,0)
   elseif value<before then assert(c.gs:SpendPlayerResources(c.colony,before-value)==true,'native_food_debit_failed')end
  end,
  set_territory=function(c,value,before)
   if value>before then c.gs:GivePlayerTerritory(c.colony,value-before)
   elseif value<before then c.gs:SpendPlayerTerritory(c.colony,before-value)end
  end,
  open=make,message=message,refresh=refresh,
  value=function(v,field,value)v.inputs[field]:SetText(ft(string.format('%d',value)))end,
  close=function(v,focus)
   buttons={}
   local focused=valid(v.widget)and v.widget:HasFocusedDescendants()
   if valid(v.widget)then v.widget:RemoveFromParent()end
   if focus and focused and valid(v.ctx.pc)and native.world_id(v.ctx.pc)==v.ctx.world_id then
    load('/Script/UMG.Default__WidgetBlueprintLibrary'):SetFocusToGameViewport()
   end
  end,
 }
 RegisterKeyBind(Key.CAPS_LOCK,{ModifierKey.SHIFT},function()api.request_toggle()end)
 RegisterHook('/Script/EotU.EotUGameState:SetPopCapByID',function()end,function(receiver,colony)
  if writing then return end
  local c=context()
  if c and c.gs and id(unbox(receiver))==id(c.gs)and tonumber(unbox(colony))==c.colony then api.note_external_cap(c.key)end
 end)
 NotifyOnNewObject('/Script/EotU.EotUFormicariumGameMode',function()api.loaded()end)
 api.settings=settings
 return api
end
return M
