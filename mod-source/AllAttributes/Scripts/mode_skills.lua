-- Non-campaign custom skill selection. Native numerical improvements and the
-- campaign purchase ledger are deliberately outside this module.
local M={}
local CUSTOM='/Game/UI/Wiki/CustomColonySetup.CustomColonySetup_C'
local FREEPLAY='/Game/UI/GameSetup/FreeplaySetup5.FreeplaySetup5_C'
local ARENA='/Game/UI/BattleArenaUI/BAWidgets.BAWidgets_C'
local CARD='/Game/UI/InGame/TechTree/SpeciesEntryCustomColony.SpeciesEntryCustomColony_C'
local PREFIX='EAA_ModeSkill1:'
local IDS={'TrapjawAnt','SlaveMaker','LittleBlackAnt','DriverAntLargeSoldier','DriverAntSoldier'}
local FIELDS={TrapjawAnt='bTrapjaw',SlaveMaker='bSlaveMaker',LittleBlackAnt='bLittleBlackAnt',DriverAntLargeSoldier='bDriverAntLargeSoldier',DriverAntSoldier='bDriverAntSoldier'}
local BUTTONS={TrapjawAnt='TrapjawAnt',SlaveMaker='SlaveMakerAnt',LittleBlackAnt='LittleBlackAnt',DriverAntLargeSoldier='DriverAntLargeSoldier',DriverAntSoldier='DriverAntSoldier'}
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
 local x=safe(function()return v:get()end);return x~=nil and x or v
end
local function clone(t)if type(t)~='table'then return t end;local out={};for k,v in pairs(t)do out[k]=clone(v)end;return out end
local function number(v)local n=tonumber(unbox(v));return n and n==n and n~=math.huge and n~=-math.huge and n or nil end
local function text(v)if type(v)=='string'then return v end;return safe(function()return v:ToString()end)or''end
local function array(a)
 local out={};if not a then return out end
 if type(a)=='table'and type(a.GetArrayNum)~='function'then for i,v in ipairs(a)do out[i]=v end;return out end
 local n=number(a:GetArrayNum());assert(n and n>=0 and n<=8192,'invalid_mode_array')
 for i=1,n do out[i]=a[i]end;return out
end
function M.install(o)
 local native,combat,state=assert(o.native),assert(o.combat),assert(o.state)
 local view_module=assert(o.skills_ui)
 local valid=function(v)return v~=nil and safe(function()return native.valid_object(v)end)==true end
 local function get(v,k)return valid(v)and safe(function()return v[k]end)or nil end
 local function id(v)return valid(v)and tostring(v:GetAddress())or nil end
 local function same(a,b)local x=id(a);return x~=nil and x==id(b)end
 local function wid(v)return valid(v)and native.world_id(v)or nil end
 local function log(v)(o.log or print)('[ModeSkills] '..tostring(v))end
 local function empty()local out={};for _,species in ipairs(IDS)do out[species]={left='none',right='none',form=species=='LittleBlackAnt'and'specialist'or nil}end;return out end
 local function normalized(v)local n,why=state.normalize(v or{});assert(n,why);local out=empty();for k,pair in pairs(n)do out[k]=pair end;return out end
 local function key(owner,species)return PREFIX..tostring(owner)..':'..species..':'end
 local function read_tag(actor,owner,species)
  local prefix=key(owner,species)
  for _,value in ipairs(array(get(actor,'Tags')))do
   local name=text(value)
   if name:sub(1,#prefix)==prefix then
    local tail=name:sub(#prefix+1)
    local l,r,form
    if species=='LittleBlackAnt'then l,r,form=tail:match('^([a-z_]+):([a-z_]+):([a-z_]+)$')end
    if not l then l,r=tail:match('^([a-z_]+):([a-z_]+)$')end
    local n=l and state.normalize({[species]={left=l,right=r,form=form}})
    if n then return n[species]end
   end
  end
 end
 local function write_tag(actor,owner,species,pair)
  if not valid(actor)then return end
  local prefix=key(owner,species);local wanted=prefix..pair.left..':'..pair.right
  if species=='LittleBlackAnt'then wanted=wanted..':'..(pair.form or'specialist')end
  local values=array(get(actor,'Tags'));local out,found,changed={},false,false
  for _,value in ipairs(values)do
   local name=text(value)
   if name:sub(1,#prefix)==prefix then
    if name==wanted and not found then out[#out+1]=value;found=true else changed=true end
   else out[#out+1]=value end
  end
  if not found then out[#out+1]=FName(wanted);changed=true end
  if changed then actor.Tags=out end
 end
 local control={}
 local enabled=true
 local world,colonies,configured,actor_cache,cache_count=nil,{},{},{},0
 local arena_world,arena_choices=nil,nil
 local pending,arena_session=nil,nil
 local editor_choices,free_sessions,active_editors,hooks,queue={},{},{},{},{}
 local next_discovery=0
 local clock=o.clock or os.clock
 local view=view_module.install({valid_object=valid,log=log})
 local function later(fn)queue[#queue+1]=fn end
 local function attached(widget)
  local cur=widget
  for _=1,24 do
   if not valid(cur)or safe(function()return cur:IsVisible()end)==false then return false end
   if safe(function()return cur:IsInViewport()end)==true then return true end
   local parent=safe(function()return cur:GetParent()end)
   if valid(parent)then cur=parent else
    local outer=safe(function()return cur:GetOuter()end)
    if not valid(outer)or same(cur,outer)then return false end;cur=outer
   end
  end
  return false
 end
 local function world_reset(ctx)
  if world~=ctx.world_id then
   world,colonies,configured,actor_cache,cache_count=ctx.world_id,{},{},{},0
   if arena_world~=world then arena_world,arena_choices=nil,nil end
  end
  -- A pending new-game setup is consumed once, only by the exact native save
  -- identity it was collected from, never by a later unrelated game.
  if pending and pending.source_world~=world then
   local save=get(ctx.gm,'FreeplaySave')
   if valid(save)and pending.signature then
    local signature=text(get(save,'MapToLoad'))..'\t'..text(get(save,'LinkedSaveGame'))..'\t'..text(get(save,'ColonyName'))
    if signature==pending.signature then
     colonies=clone(pending.colonies);for owner in pairs(colonies)do configured[owner]=true end
     actor_cache={};cache_count=0
    end
    pending=nil
   elseif pending.target_world and pending.target_world~=world then pending=nil
   else pending.target_world=world end
  end
 end
 local function campaign_route(actor,ctx,owner,campaign,campaign_checked)
  if ctx.is_arena then return 'mode' end
  local c=campaign_checked and campaign or nil
  if not campaign_checked then c=o.get_campaign_context and o.get_campaign_context()end
  if c and wid(c.gs or c.game_state)==ctx.world_id then
   -- combat_context.get obtains both fields from native.get_local_controller
   -- (engine player index zero). Reuse only that synchronous lookup, never
   -- the cached local_owner value; validate the controller and read its
   -- current colony again. Incomplete/stale contexts use the original route.
   local pc=ctx.pc
   if valid(pc)and pc==ctx.controller and native.world_id(pc)==ctx.world_id
    and safe(function()return pc:IsLocalController()end)~=false then
    local local_owner=number(safe(function()return pc:GetColonyID()end))
    if local_owner~=nil then return owner==local_owner and 'home'or'foreign'end
   end
   return native.is_owned(actor,ctx.gs)==true and 'home' or 'foreign'
  end
  -- A queen/nursery may restore before the local controller, colony registry
  -- or campaign slot. Absence of the settled campaign context does not prove
  -- that this is a non-campaign game. In particular it must never manufacture
  -- a specialist form that authorizes removing a loaded twin's second slot.
  local kind=number(ctx.game_type)or number(get(ctx.gm,'GameType'))
  if kind==nil or kind==0 or kind==1 or kind==2 then return 'pending' end
  return 'mode'
 end
 function control.get_choices(actor,species,authorize)
  if not enabled or not state.supports(species)then return {}end
  -- Campaign-owned actors delegate to the campaign ledger. Resolve that
  -- route before querying a colony grid and queen whose result would be
  -- discarded. Keep current actor/world/owner validation on every read;
  -- no skill values or UObject contexts are cached across frames.
  local base=combat.get()
  local campaign,campaign_checked
  if type(authorize)=='function'and base and base.world_id and not base.is_arena then
   campaign_checked=true;campaign=o.get_campaign_context and o.get_campaign_context()
   -- On this exact campaign context, skills performs the complete fresh
   -- native ownership check (including actor/world validity and current
   -- engine player zero). Success immediately delegates, with no intervening
   -- native reads. It replaces duplicate checks; it never caches ownership.
   if campaign and(campaign.gs or campaign.game_state)==base.gs
    and wid(base.gs)==base.world_id and authorize(actor,base.gs,campaign)==true then return nil end
  end
  if not base or not valid(base.gs)or not base.world_id or not valid(actor)
   or native.world_id(actor)~=base.world_id then return {}end
  local owner=number(get(actor,'ColonyID'))
  if not owner or owner<0 or owner%1~=0 then return {}end
  local route=campaign_route(actor,base,owner,campaign,campaign_checked)
  if route=='home'then return nil end
  if route=='pending'then return {}end
  local ctx,arena
  if route=='mode'and base.is_arena and arena_world==base.world_id
   and arena_choices and arena_choices[owner]then
   -- Arena choices are already frozen for this live world and side. The
   -- native arena has no queen fallback; its grid/queen lookup is unused.
   world_reset(base)
   arena=arena_choices[owner]
  else
   -- Other modes and foreign campaign colonies retain the original queen
   -- and saved actor-tag fallback, including unresolved arena configurations.
   ctx=combat.for_colony(owner,base);if not ctx then return {}end
   world_reset(ctx)
   owner=ctx.owner
   arena=arena_world==world and arena_choices and arena_choices[owner]
  end
  local choices=colonies[owner]
  if arena then choices=arena end
  if not choices then choices=empty();colonies[owner]=choices end
  local cachekey=id(actor)..':'..tostring(owner)..':'..species
  local cached=actor_cache[cachekey]
  local actor_name=text(safe(function()return actor:GetFullName()end))
  if cached and same(cached.actor,actor)and cached.name==actor_name then return clone(cached.choices)end
  local pair
  if arena or configured[owner]then pair=choices[species]
  else
   -- The queen stores the colony loadout for eggs born after a cold reload.
   -- A soldier's own tag remains a fallback if that queen has since died.
   pair=valid(ctx.queen)and read_tag(ctx.queen,owner,species)or nil
   pair=pair or read_tag(actor,owner,species)or choices[species]
   choices[species]=clone(pair)
  end
  write_tag(actor,owner,species,pair)
  if ctx and valid(ctx.queen)then write_tag(ctx.queen,owner,species,pair)end
  local flat=state.flat({[species]=pair},species)or{}
  if cache_count>=8192 then actor_cache={};cache_count=0 end
  if not actor_cache[cachekey]then cache_count=cache_count+1 end
  actor_cache[cachekey]={actor=actor,name=actor_name,choices=flat,world=world,owner=owner,
   arena_config=arena};return clone(flat)
 end
 -- Negative-only native dispatch capability. A matching receipt was created
 -- by the full live arena route above; all mutable primitive identity fields
 -- are checked again. No choice adapter, combat context, tag fallback, native
 -- mutation or configuration callback is entered here. false means unknown.
 function control.is_frozen_twin(actor)
  if not enabled or not arena_choices or not arena_world or world~=arena_world or not valid(actor)then return false end
  if text(safe(function()return actor.CreatureName end))~='LittleBlackAnt'then return false end
  local owner=number(safe(function()return actor.ColonyID end))
  if not owner or owner<0 or owner%1~=0 then return false end
  local choices=arena_choices[owner]
  if not choices or not choices.LittleBlackAnt or choices.LittleBlackAnt.form~='twin'then return false end
  local address=id(actor);if not address then return false end
  local cached=actor_cache[address..':'..tostring(owner)..':LittleBlackAnt']
  if not cached or cached.world~=arena_world or cached.owner~=owner or cached.arena_config~=choices
   or not cached.choices or cached.choices.form~='twin'or not same(cached.actor,actor)then return false end
  local name=safe(function()return actor:GetFullName()end)
  return type(name)=='string'and name~=''and cached.name==name and native.world_id(actor)==arena_world
 end
 -- Public narrow configuration surface also used by isolated native QA.
 function control.set_colony_choices(owner,choices,ctx)
  ctx=ctx or combat.get();owner=number(owner)
  if not ctx or not owner or owner<0 or owner%1~=0 then return nil,'mode_colony_unavailable'end
  world_reset(ctx);local n=normalized(choices);colonies[owner]=n;configured[owner]=true;actor_cache={};cache_count=0
  local c=combat.for_colony(owner,ctx)
  if c and valid(c.queen)then for _,species in ipairs(IDS)do write_tag(c.queen,owner,species,n[species])end end
  if o.on_change then o.on_change(owner,clone(n))end
  return true
 end
 local function load(path)local v=StaticFindObject(path);if not valid(v)then v=LoadAsset(path)end;assert(valid(v),'mode UI asset unavailable: '..path);return v end
 local function hide(v)if valid(v)then v:SetVisibility(1)end end
 local function strip_numbers(card)
  local seen={}
  local function visit(widget)
   local k=id(widget);if not k or seen[k]then return end;seen[k]=true
   local children={};local count=safe(function()return widget:GetChildrenCount()end)
   if type(count)=='number'then for i=0,count-1 do children[#children+1]=widget:GetChildAt(i)end end
   local tree=get(widget,'WidgetTree');local root=get(tree,'RootWidget');if valid(root)then children[#children+1]=root end
   for _,child in ipairs(children)do visit(child)end
   local name=text(widget:GetFName()):lower()
   if name:find('improv',1,true)or name:find('levelbutton',1,true)or name:find('level1',1,true)
    or name:find('level2',1,true)or name:find('level3',1,true)then
    widget:SetIsEnabled(false);widget:SetVisibility(1);widget:RemoveFromParent()
   end
  end
  visit(card)
 end
 local function make_card(session,species,parent)
  local def=assert(view_module.definition(species));local owner=session.widget:GetOwningPlayer()
  local creator=load('/Script/UMG.Default__WidgetBlueprintLibrary')
  local card=creator:Create(owner,load(CARD),owner);assert(valid(card),'mode skill card unavailable')
  if parent then card.ParentWidget=parent end
  card.SecondaryCast=true;card.SpeciesIdentifier=255;card.SpeciesSubtypeIdentifer=0;card.SpeciesName=FName(species)
  local p='/Game/UI/InGame/UIUpdate/CharacterIcons/SquareImages/'..def.portrait..'.'..def.portrait
  card['Set Main Hex'](card,load(p));card.HideImprovmentsButton=true
  -- Match the established story skill card: detach numerical controls so the
  -- native Construct/hover refresh cannot reveal them again after mounting.
  strip_numbers(card)
  session.cards[species]=card
  return card
 end
 local function ft(s)return load('/Script/Engine.Default__KismetTextLibrary'):Conv_StringToText(s)end
 local function retire_freeplay(session)
  if active_editors[session.parent_id]==session then active_editors[session.parent_id]=nil end
  free_sessions[session.widget_id]=nil
  session.retired=true;session.confirm_requested=false
  for _,card in pairs(session.cards)do view.unbind(card);if valid(card)then card:RemoveFromParent()end end
 end
 local function bind_freeplay(parent,widget)
  if not attached(widget)or free_sessions[id(widget)]then return end
  local slot=number(get(widget,'ID'));if not slot or slot<0 or slot>5 then return end
  local parent_id=id(parent);editor_choices[parent_id]=editor_choices[parent_id]or{}
  local previous=active_editors[parent_id];if previous then retire_freeplay(previous)end
  local session={widget=widget,widget_id=id(widget),parent=parent,parent_id=parent_id,cards={},slot=slot,world=wid(widget),draft=normalized(editor_choices[parent_id][slot])}
  free_sessions[id(widget)]=session
  active_editors[parent_id]=session
  for _,species in ipairs(IDS)do
   local card=make_card(session,species,widget)
   local native_button=get(widget,BUTTONS[species]);hide(native_button)
   local row=get(widget,'TopRow');assert(valid(row),'native custom colony row unavailable')
   local slot_widget=row:AddChildToHorizontalBox(card)
   slot_widget:SetPadding({Left=15,Top=20,Right=15,Bottom=20});slot_widget:SetHorizontalAlignment(2);slot_widget:SetVerticalAlignment(2)
   card.MainSpeciesHex:SetToolTipText(ft(view_module.definition(species).title..'。点击蚁种图标选择是否携带，点击侧边图标选择技能。'))
   view.bind(card,{kind='roster',species_id=species,parent=widget,scroll=get(widget,'ColonySetupList'),
    alive=function()return enabled and not session.retired and active_editors[parent_id]==session and attached(widget)and valid(parent)end,
    is_selected=function()return widget.ColonySetup[FIELDS[species]]==true end,
    get_choices=function()return session.draft[species]end,
    choose=function(side,value)session.draft[species][side]=value;return true end,
    toggle=function()
     local chosen=not widget.ColonySetup[FIELDS[species]];widget.ColonySetup[FIELDS[species]]=chosen
     local checkbox=get(native_button,'TheButton');if valid(checkbox)then checkbox:SetIsChecked(chosen)end
    end})
  end
  local panel=get(widget,'ExtraUnitsUniformGridPanel')
  if valid(panel)then
   local layout=load('/Script/UMG.Default__WidgetLayoutLibrary');local position=0
   for i=0,panel:GetChildrenCount()-1 do
    local child=panel:GetChildAt(i)
    if valid(child)and child:IsVisible()then
     local slot_widget=layout:SlotAsUniformGridSlot(child)
     slot_widget:SetRow(math.floor(position/8));slot_widget:SetColumn(position%8);position=position+1
    end
   end
  end
 end
 local function arena_heading(session)
  session.heading:SetText(ft(session.side==1 and'右方蚁种技能'or'左方蚁种技能'))
 end
 local function arena_height(session)
  local layout=load('/Script/UMG.Default__WidgetLayoutLibrary')
  local viewport=layout:GetViewportSize(session.widget)
  local scale=layout:GetViewportScale(session.widget)
  if viewport.Y<=0 or scale<=0 then return end
  -- Native canvas parents auto-size. Bound the existing scroll box so dense
  -- creature pages cannot push its last skill cards below the viewport.
  local height=math.max(1,viewport.Y/scale-80)
  if session.height~=height then
   session.frame:SetMaxDesiredHeight(height);session.height=height
  end
 end
 local function retire_arena(session)
  for _,card in pairs(session.cards)do view.unbind(card)end
  if valid(session.panel)then session.panel:RemoveFromParent()end
  if valid(session.frame)and valid(session.scroll)and valid(session.parent)
   and same(session.parent:GetContent(),session.frame)then
   session.frame:ClearChildren();session.parent:SetContent(session.scroll)
   local slot=session.scroll.Slot
   slot:SetPadding(session.padding);slot:SetHorizontalAlignment(session.horizontal);slot:SetVerticalAlignment(session.vertical)
   session.scroll:SetScrollbarVisibility(session.bar_visibility);session.scroll:SetAlwaysShowScrollbar(session.always_bar)
  end
  if arena_session==session then arena_session=nil end
 end
 local function bind_arena(widget)
  if not attached(widget)then return end
  if arena_session and same(arena_session.widget,widget)then return end
  if arena_session then retire_arena(arena_session)end
  local arena_wid=wid(widget)
  if arena_world~=arena_wid or not arena_choices then arena_world,arena_choices=arena_wid,{[0]=empty(),[1]=empty()}end
  local session={widget=widget,cards={},world=arena_wid,choices=arena_choices,side=get(widget,'SpawnRight')==true and 1 or 0}
  local tree=get(widget,'WidgetTree')
  local scroll=get(widget,'LeftPanelBox')
  assert(valid(tree)and valid(scroll),'native arena selection panel unavailable')
  local function construct(class)
   local control=StaticConstructObject(load('/Script/UMG.'..class),tree)
   assert(valid(control),'arena skill panel '..class..' unavailable')
   return control
  end
  session.panel=construct('VerticalBox')
  session.heading=construct('TextBlock')
  local label=get(widget,'LevelValue')
  if valid(label)then session.heading:SetFont(label.Font);session.heading:SetColorAndOpacity(label.ColorAndOpacity)end
  arena_heading(session)
  session.panel:AddChildToVerticalBox(session.heading):SetPadding({Left=12,Top=10,Right=12,Bottom=0})
  local grid=construct('UniformGridPanel')
  grid:SetSlotPadding({Left=3,Top=0,Right=3,Bottom=0})
  session.panel:AddChildToVerticalBox(grid)
  arena_session=session
  local ok,why=pcall(function()
   session.scroll=scroll;session.parent=scroll:GetParent()
   assert(valid(session.parent)and same(session.parent:GetContent(),scroll),'native arena scroll parent changed')
   local slot=scroll.Slot;local padding=slot.Padding
   session.padding={Left=padding.Left,Top=padding.Top,Right=padding.Right,Bottom=padding.Bottom}
   session.horizontal=slot.HorizontalAlignment;session.vertical=slot.VerticalAlignment
   session.bar_visibility=scroll.ScrollBarVisibility;session.always_bar=scroll.AlwaysShowScrollbar
   session.frame=construct('SizeBox')
   session.parent:SetContent(session.frame);session.frame:SetContent(scroll)
   local frame_slot=session.frame.Slot
   frame_slot:SetPadding(session.padding);frame_slot:SetHorizontalAlignment(session.horizontal);frame_slot:SetVerticalAlignment(session.vertical)
   scroll:SetScrollbarVisibility(0);scroll:SetAlwaysShowScrollbar(true)
   arena_height(session)
   for index,species in ipairs(IDS)do
   local card=make_card(session,species,widget)
   local fit=construct('ScaleBox')
   fit:SetStretch(2) -- ScaleToFit within the native scroll panel.
   fit:SetContent(card)
   local frame=construct('SizeBox')
   frame:SetWidthOverride(168);frame:SetHeightOverride(120)
   frame:SetContent(fit)
   grid:AddChildToUniformGrid(frame,math.floor((index-1)/2),(index-1)%2)
   card.MainSpeciesHex:SetToolTipText(ft(view_module.definition(species).title..'。切换左方或右方，可以分别设置技能。'))
   view.bind(card,{kind='roster',species_id=species,
    parent=widget,scroll=scroll,
    alive=function()return enabled and arena_session==session and attached(widget)end,
    is_selected=function()return true end,
    get_choices=function()return session.choices[session.side][species]end,
    choose=function(side,value)
     session.choices[session.side][species][side]=value;actor_cache={};cache_count=0
     if o.on_change then o.on_change(session.side,clone(session.choices[session.side]))end
     return true
    end,
    toggle=function()end})
   end
   local slot=scroll:AddChild(session.panel)
   assert(valid(slot),'arena skill panel mount failed')
  end)
  if not ok then retire_arena(session);error(why)end
 end
 local function add_hook(name,path,callback)
  if hooks[name]or not valid(StaticFindObject(path))then return end
  local callback_safe=function(...)
   if not enabled then return end;local worked,why=pcall(callback,...);if not worked then log(name..': '..tostring(why))end
  end
  -- UE4SS dispatches Blueprint completion through argument two. Native
  -- UFunctions have a separate third-argument post callback.
  local ok,pre,post
  if path:sub(1,8)=='/Script/'then ok,pre,post=pcall(RegisterHook,path,function()end,callback_safe)
  else ok,pre,post=pcall(RegisterHook,path,callback_safe)end
  if ok and type(pre)=='number'and type(post)=='number'then hooks[name]={path,pre,post}end
 end
 local function ensure_hooks()
  add_hook('freeplay-dialog',FREEPLAY..':ShowDialog',function(receiver,content)
   local parent,widget=unbox(receiver),unbox(content)
   if valid(widget)and text(widget:GetClass():GetFName())=='CustomColonySetup_C'then later(function()bind_freeplay(parent,widget)end)end
  end)
  add_hook('freeplay-commit',FREEPLAY..':UpdateCustomColony',function(receiver,colony,slot)
   local parent=unbox(receiver);slot=number(slot)
   local parent_id=id(parent);local session=active_editors[parent_id]
   if not session then return end
   -- A Blueprint completion hook can run after its native body has already
   -- broadcast UpdateCustomColony. Resolve only after that whole callback
   -- stack returns, capturing this exact dialog rather than looking up whichever
   -- dialog happens to be current later. Queue processing precedes close cleanup.
   later(function()
    if active_editors[parent_id]~=session or session.retired or not session.confirm_requested or session.slot~=slot then return end
    editor_choices[parent_id]=editor_choices[parent_id]or{}
    editor_choices[parent_id][slot]=clone(session.draft)
    session.confirm_requested=false;session.committed=true
   end)
  end)
  local function arm_confirmation(receiver)
   local widget=unbox(receiver);local session=free_sessions[id(widget)]
   if session and not session.retired and active_editors[session.parent_id]==session then session.confirm_requested=true end
  end
  add_hook('freeplay-confirm-button',CUSTOM..':BndEvt__CustomColonySetup_Button_K2Node_ComponentBoundEvent_2_OnButtonClickedEvent__DelegateSignature',arm_confirmation)
  add_hook('freeplay-confirm-graph',CUSTOM..':ExecuteUbergraph_CustomColonySetup',function(receiver,entry)
   if number(entry)==12862 then arm_confirmation(receiver)end
  end)
  add_hook('freeplay-freeze',FREEPLAY..':SetupColoniesInSave',function(receiver,value)
   local parent,save=unbox(receiver),unbox(value);if not valid(save)then return end
   local edited=editor_choices[id(parent)]or{};local ids=array(get(parent,'ColonyLocationIDs'));local frozen={}
   for slot,choices in pairs(edited)do local owner=number(ids[slot+1]);if owner then frozen[owner]=normalized(choices)end end
   -- MapToLoad / LinkedSaveGame are assigned later in the same graph. Capture
   -- their final identity at the native save call, not this earlier callback.
   pending={source_world=wid(parent),source_save=id(save),colonies=frozen}
  end)
  add_hook('freeplay-save-identity','/Script/Engine.GameplayStatics:SaveGameToSlot',function(receiver,result,value,slot)
   -- Native post callbacks receive the return value before the original args.
   -- A failed write must not authorize the pending next-world loadout.
   if unbox(result)~=true then return end
   local save=unbox(value)
   if pending and valid(save)and pending.source_save==id(save)then
    pending.signature=text(get(save,'MapToLoad'))..'\t'..text(get(save,'LinkedSaveGame'))..'\t'..text(get(save,'ColonyName'))
   end
  end)
 end
 function control.tick()
  if not enabled then return end
  local pending_queue=queue;queue={};for _,fn in ipairs(pending_queue)do local ok,why=pcall(fn);if not ok then log(why)end end
  view.tick()
  local closed={};for _,session in pairs(free_sessions)do if not attached(session.widget)then closed[#closed+1]=session end end
  for _,session in ipairs(closed)do retire_freeplay(session)end
  if arena_session then
   if not attached(arena_session.widget)then
    retire_arena(arena_session)
   else
    local side=get(arena_session.widget,'SpawnRight')==true and 1 or 0
    if arena_session.side~=side then
     arena_session.side=side;arena_heading(arena_session)
     for _,card in pairs(arena_session.cards)do view.refresh(card)end
    end
   end
  end
  local now=clock();if now<next_discovery then return end;next_discovery=now+1
  if arena_session then arena_height(arena_session)end
  ensure_hooks()
  local arena=FindFirstOf('BAWidgets_C');if valid(arena)and attached(arena)then local ok,why=pcall(bind_arena,arena);if not ok then log(why)end end
  local ctx=combat.get();if ctx then
   world_reset(ctx)
   for owner,choices in pairs(colonies)do
    local c=combat.for_colony(owner,ctx)
    if c and valid(c.queen)then for _,species in ipairs(IDS)do
     -- Native loaded queen tags take precedence over an empty in-memory cache.
     local pair=not configured[owner]and read_tag(c.queen,owner,species)or choices[species]
     pair=pair or choices[species];choices[species]=pair;write_tag(c.queen,owner,species,pair)
    end end
   end
  end
 end
 function control.status()return{world=world,colonies=clone(colonies),arena=arena_session,pending=clone(pending),freeplay=free_sessions}end
 function control.stop()
  enabled=false;view.stop()
  for _,session in pairs(free_sessions)do for _,card in pairs(session.cards)do if valid(card)then card:RemoveFromParent()end end end
  if arena_session then retire_arena(arena_session)end
  for _,h in pairs(hooks)do pcall(UnregisterHook,h[1],h[2],h[3])end
  world,colonies,configured,actor_cache,pending,arena_session=nil,{},{},{},nil,nil
  arena_world,arena_choices=nil,nil
 end
 return control
end
return M
