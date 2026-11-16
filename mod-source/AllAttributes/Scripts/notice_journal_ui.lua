-- Native main-menu journal. No scans, input handlers or maintenance in gameplay.
local M={}
local dir=assert(debug.getinfo(1,'S').source:sub(2):match('^(.*)[/\\]'))
local journal_module=dofile(dir..'/notice_journal.lua')
local MENU='/Game/UI/MainMenu/MainMenuWidgetsLab3.MainMenuWidgetsLab3_C'
local BUTTON='/Game/UI/InGame/UIUpdate/Adaptations/PurchaseMenuButton.PurchaseMenuButton_C'
local BACKGROUND='/Game/UI/Dialogue/DialogueSimpleBlueprint.DialogueSimpleBlueprint_C'
local RELEASE='BndEvt__PurchaseMenuButton_Button_K2Node_ComponentBoundEvent_0_OnButtonReleasedEvent__DelegateSignature'
local function hex(name)return '/Game/UI/InGame/TechTree/'..name..'.'..name end
function M.install(api)
 local valid,content=assert(api.valid_object),assert(api.content)
 local control,active,journal,started,hooked={},nil,nil,false,false
 local pending,failed={},{}
 local language,observed_game_language,language_refresh_pending='zh',nil,false
 local function report(v)pcall(api.log or print,'[ModNotice] '..tostring(v))end
 local function unbox(v)local ok,x=pcall(function()return v:get()end);return ok and x or v end
 local function id(o)return valid(o)and tostring(o:GetAddress())or nil end
 local function same(a,b)local k=id(a);return k~=nil and k==id(b)end
 local function class(o)return valid(o)and o:GetClass():GetFName():ToString()or''end
 local function load(p)local o=StaticFindObject(p);if not valid(o)then o=LoadAsset(p)end;assert(valid(o),'missing '..p);return o end
 local function text(v)return StaticFindObject('/Script/Engine.Default__KismetTextLibrary'):Conv_StringToText(v)end
 local function word(v)return v[language]end
 local function words()return journal.words[language]end
 local function live(s)return s and active==s and valid(s.menu)and s.menu:IsInViewport()and valid(s.world)and same(s.menu:GetWorld(),s.world)end
 local function construct(s,kind)
  local o=StaticConstructObject(load('/Script/UMG.'..kind),s.tree);assert(valid(o),'cannot create '..kind);o:SetVisibility(4);return o
 end
 local function place(parent,o,x,y,w,h,ax,ay,bx,by)
  local slot=parent:AddChildToCanvas(o)
  slot:SetAnchors({Minimum={X=ax or 0,Y=ay or 0},Maximum={X=bx or ax or 0,Y=by or ay or 0}})
  slot:SetOffsets({Left=x,Top=y,Right=w,Bottom=h});slot:SetAutoSize(false);return slot
 end
 local function label(s,value,size,color)
  local o=construct(s,'TextBlock');o:SetText(text(value));o:SetAutoWrapText(true)
  o:SetColorAndOpacity(s.menu.SpeachHeader.ColorAndOpacity)
  if color then o:SetColorAndOpacity({SpecifiedColor={R=color[1],G=color[2],B=color[3],A=color[4]or 1},ColorUseRule=0})end
  o:SetFont(s.menu.SpeachHeader.Font);local font=o.Font;font.Size=size;o:SetFont(font);o:SetVisibility(3);return o
 end
 local function image(s,path,color)
  local o=construct(s,'Image');o:SetBrushFromTexture(load(path),true);o:SetVisibility(3)
  if color then o:SetColorAndOpacity({R=color[1],G=color[2],B=color[3],A=color[4]or 1})end;return o
 end
 local function portrait(s,entry)
  local canvas=construct(s,'CanvasPanel');canvas:SetVisibility(3);local glows={}
  for i=3,1,-1 do
   local n=i*4;local o=image(s,hex('T_UI_SpeciesHex_Border_Brown'),{3,2.4,.35,.26})
   place(canvas,o,-n,-n,151+n*2,133+n*2);glows[#glows+1]=o
  end
  place(canvas,image(s,hex('T_UI_SpeciesHex_Base'),{.75,.75,.75,1}),0,0,151,133)
  place(canvas,image(s,entry.icon),15.5,6.5,120,120)
  place(canvas,image(s,hex('T_UI_SpeciesHex_Border_Brown')),0,0,151,133)
  canvas:SetRenderTransformPivot({X=.5,Y=.5});return canvas,glows
 end
 local function glow(objects,on)for _,o in ipairs(objects)do o:SetVisibility(on and 3 or 1)end end
 local function button(s,caption,action,official,plain)
  local owner=s.menu:GetOwningPlayer()
  local o=load('/Script/UMG.Default__WidgetBlueprintLibrary'):Create(owner,load(BUTTON),owner)
  assert(valid(o),'native button creation failed');official=official or s.menu.ButtonNew
  o.InStyle=official.WidgetStyle;o.ButtonText=text(caption);o.Button:SetStyle(official.WidgetStyle)
  o.TextBlock_143:SetText(o.ButtonText);o.TextBlock_143:RemoveFromParent()
  local slot=o.Button:SetContent(o.TextBlock_143)
  slot:SetHorizontalAlignment(2);slot:SetVerticalAlignment(2);slot:SetPadding({Left=0,Top=0,Right=0,Bottom=0})
  o.TextBlock_143:SetAutoWrapText(false);o.TextBlock_143:SetJustification(1)
  local native_text=official:GetContent()
  o.TextBlock_143:SetFont(native_text.Font)
  o.TextBlock_143:SetRenderTranslation({X=0,Y=3});o.Button.IsFocusable=false;o:SetVisibility(4)
  s.actions[id(o)]=action
  if plain then o.Button:SetBackgroundColor({R=1,G=1,B=1,A=0});return o,o end
  local frame=construct(s,'Border');local original=official:GetParent();assert(class(original)=='Border','native button border missing')
  frame:SetBrush(original.Background);frame:SetBrushColor(original.BrushColor);frame:SetPadding(original.Padding);frame:SetContent(o)
  return o,frame
 end
 local function separator(s,parent)
  local line=construct(s,'Border');line:SetBrushColor({R=.38,G=.34,B=.19,A=1})
  local box=construct(s,'SizeBox');box:SetHeightOverride(3);box:SetContent(line)
  parent:AddChildToVerticalBox(box):SetPadding({Left=0,Top=23,Right=0,Bottom=20})
 end
 local function block(s,parent,value,size,color,below)
  local o=label(s,value,size,color);parent:AddChildToVerticalBox(o):SetPadding({Left=0,Top=0,Right=12,Bottom=below or 12});return o
 end
 local show
 local function compact(s)
  for _,key in ipairs(s.compact_action_keys or{})do s.actions[key]=nil end
  s.compact_action_keys={}
  s.compact:ClearChildren();s.compact_ids={}
  for _,entry in ipairs(journal.updated_list(3))do
   s.compact_ids[#s.compact_ids+1]=entry.id
   local b=button(s,word(entry.name),{kind='open',species=entry.id},nil,true)
   s.compact_action_keys[#s.compact_action_keys+1]=id(b)
   local row=construct(s,'CanvasPanel');local icon,glows=portrait(s,entry)
   icon:SetRenderScale({X=.43,Y=.43});glow(glows,true);place(row,icon,-35,-34,151,133)
   place(row,label(s,words().updated,17,{.92,.84,.62}),83,5,440,29)
   place(row,label(s,word(entry.name),14,{.67,.73,.61}),83,34,440,26);b.Button:SetContent(row)
   local box=construct(s,'SizeBox');box:SetHeightOverride(62);box:SetContent(b);s.compact:AddChildToVerticalBox(box)
  end
  if #s.compact_ids==0 then block(s,s.compact,words().caught,17,{.73,.80,.65})end
  if s.holder and s.mode=='compact'then s.holder:SetHeightOverride(154+math.max(1,#s.compact_ids)*69)end
 end
 local function gallery(s)
  place(s.gallery,label(s,words().unread,19,{.79,.71,.44}),6,5,650,34)
  local other,frame=button(s,words().other,{kind='general'});place(s.gallery,frame,-184,-2,180,43,1,0,1,0)
  s.other=other;local width=248
  for i,entry in ipairs(journal.catalog)do
   local b=button(s,word(entry.name),{kind='open',species=entry.id},nil,true)
   local tile=construct(s,'CanvasPanel');local icon,glows=portrait(s,entry);place(tile,icon,(width-151)/2,8,151,133)
   local name=label(s,word(entry.name),22,{.84,.87,.77});name:SetJustification(1);place(tile,name,2,160,width-4,66)
   local marker=label(s,language=='zh'and'更新'or'NEW',17,{.95,.81,.40});marker:SetJustification(1)
   place(tile,marker,156,-1,60,28);marker:SetVisibility(journal.unread(entry.id)and 3 or 1)
   b.Button:SetContent(tile);place(s.gallery,b,((i-1)%6)*width,58+math.floor((i-1)/6)*235,width,225)
   s.cards[entry.id]={button=b,portrait=icon,glows=glows,marker=marker,scale=1};glow(glows,journal.unread(entry.id))
  end
 end
 local function details(s)
  local b,frame=button(s,words().back,{kind='back'});place(s.detail,frame,0,0,190,43);s.back=b
  local scroll=construct(s,'ScrollBox');scroll:SetVisibility(0);scroll:SetScrollWhenFocusChanges(0);scroll:SetConsumeMouseWheel(1)
  place(s.detail,scroll,12,210,12,10,0,0,1,1);s.scroll=scroll
 end
 local function render_detail(s,entry)
  if s.hero then s.hero:RemoveFromParent()end
  s.hero=construct(s,'CanvasPanel');place(s.detail,s.hero,0,53,0,145,0,0,1,0)
  if entry then
   local icon,glows=portrait(s,entry);glow(glows,false);place(s.hero,icon,10,5,151,133)
   place(s.hero,label(s,word(entry.name),33,{.93,.93,.84}),192,40,1000,54)
  else place(s.hero,label(s,words().general,33,{.93,.93,.84}),10,40,1200,54)end
  s.scroll:ClearChildren();local column=construct(s,'VerticalBox');s.scroll:AddChild(column)
  local records=entry and entry.records or{{version='development',current=true,sections={}}}
  if not entry then for _,row in ipairs(journal.general(language))do records[1].sections[#records[1].sections+1]={title={[language]=row.title},text={[language]=row.text}}end end
  for i,record in ipairs(records)do
   if i>1 then separator(s,column)end
   local current=record.current==true
   block(s,column,current and words().latest or words().history,17,{.63,.70,.54},5)
   local version=record.version=='development'and words().status or'v'..record.version
   block(s,column,version..'  ·  '..(current and words().pending or words().published),27,current and{.86,.77,.50}or{.76,.80,.67},20)
   for _,row in ipairs(record.sections)do block(s,column,word(row.title),22,{.89,.90,.81},8);block(s,column,word(row.text),18,{.79,.84,.73},27)end
  end
  if #records==0 then block(s,column,words().none,26,{.80,.81,.68},14);block(s,column,words().empty,22,{.71,.77,.65},20)end
  if #records<2 then separator(s,column);block(s,column,words().no_older,19,{.61,.67,.55},15)end
  s.scroll:ScrollToStart()
 end
 local function stop_hover(s)
  s.hover_epoch=(s.hover_epoch or 0)+1;s.hover_running=false
  for _,card in pairs(s.cards)do if valid(card.portrait)then card.scale=1;card.portrait:SetRenderScale({X=1,Y=1})end end
 end
 local function start_hover(s)
  if s.hover_running then return end;s.hover_running=true;s.hover_epoch=(s.hover_epoch or 0)+1
  local epoch=s.hover_epoch
  local function tick()
   if s.hover_epoch~=epoch then return end
   if not live(s)or s.mode~='gallery'then s.hover_running=false;return end
   for _,card in pairs(s.cards)do
    if valid(card.button)and valid(card.portrait)then
     local target=card.button:IsHovered()and 1.12 or 1
     if math.abs(card.scale-target)>.001 then
      card.scale=math.abs(card.scale-target)<.005 and target or card.scale+(target-card.scale)*.48
      card.portrait:SetRenderScale({X=card.scale,Y=card.scale})
     end
    end
   end
   ExecuteInGameThreadAfterFrames(3,tick)
  end
  ExecuteInGameThreadAfterFrames(3,tick)
 end
 show=function(s,mode,species)
  if not live(s)then return false end
  stop_hover(s);s.mode=mode;s.species=species;local expanded=mode~='compact'
  if expanded then
   if s.official_visibility==nil then s.official_visibility=s.menu.Speach:GetVisibility()end;s.menu.Speach:SetVisibility(1)
  elseif s.official_visibility~=nil then s.menu.Speach:SetVisibility(s.official_visibility);s.official_visibility=nil end
  if s.expanded~=expanded then
   s.panel:RemoveFromParent()
   if expanded then s.root:AddChildToCanvas(s.panel):SetZOrder(s.z);s.holder:SetVisibility(1)
   else s.holder:SetContent(s.panel);s.holder:SetVisibility(4)end
   s.expanded=expanded
  end
  if expanded then
   local slot=s.panel.Slot
   slot:SetAnchors({Minimum={X=.5,Y=.5},Maximum={X=.5,Y=.5}});slot:SetAlignment({X=.5,Y=.5});slot:SetPosition({X=0,Y=0});slot:SetSize({X=1560,Y=910})
  else
   compact(s)
  end
  s.title:SetText(text(words().title));s.subtitle:SetText(text(words().subtitle))
  s.body.Slot:SetPosition({X=10,Y=expanded and 82 or 74})
  s.status_label:SetText(text(words().gallery));s.status_label:SetVisibility(expanded and 3 or 1)
  s.compact:SetVisibility(not expanded and 4 or 1);s.gallery:SetVisibility(mode=='gallery'and 4 or 1)
  s.detail:SetVisibility((mode=='species'or mode=='general')and 4 or 1);s.language_frame:SetVisibility(expanded and 4 or 1)
  s.expand.ButtonText=text(expanded and words().collapse or words().expand);s.expand.TextBlock_143:SetText(s.expand.ButtonText)
  s.expand_frame.Slot:SetPosition({X=12,Y=-49});s.nexus_frame.Slot:SetPosition({X=-202,Y=-49})
  if mode=='species'then render_detail(s,assert(journal.by_id[species]))
  elseif mode=='general'then render_detail(s,nil)
  elseif mode=='gallery'then for key,card in pairs(s.cards)do local unread=journal.unread(key);glow(card.glows,unread);card.marker:SetVisibility(unread and 3 or 1)end;start_hover(s)end
  return true
 end
 local function render_language(s)
  stop_hover(s);local mode,species=s.mode,s.species
  s.actions={};s.cards={};s.body:ClearChildren();s.footer:ClearChildren()
  s.compact=construct(s,'VerticalBox');place(s.body,s.compact,0,0,0,0,0,0,1,0)
  s.gallery=construct(s,'CanvasPanel');place(s.body,s.gallery,0,0,0,0,0,0,1,1)
  s.detail=construct(s,'CanvasPanel');place(s.body,s.detail,0,0,0,0,0,0,1,1)
  s.hero=nil;compact(s);gallery(s);details(s)
  s.expand,s.expand_frame=button(s,words().expand,{kind='expand'},s.menu.ButtonDiscord)
  s.nexus,s.nexus_frame=button(s,words().nexus,{kind='nexus'})
  local language_button,language_frame=button(s,words().language,{kind='language'});s.language_frame=language_frame
  place(s.footer,s.expand_frame,20,-56,190,49,0,1,0,1);place(s.footer,s.nexus_frame,-210,-56,190,49,1,1,1,1)
  place(s.footer,language_frame,-95,-56,190,49,.5,1,.5,1)
  s.status_label:SetText(text(words().status));show(s,mode or'compact',species)
 end
 local function sync_game_language()
  local value=StaticFindObject('/Script/Engine.Default__KismetInternationalizationLibrary'):GetCurrentLanguage()
  local code=(type(value)=='string'and value or value:ToString()):lower();if code==observed_game_language then return end
  observed_game_language=code;local next_language=code:match('^zh')and'zh'or'en'
  if next_language~=language then language=next_language;if live(active)then render_language(active)end end
 end
 local function dispatch(b)
  local s=active;if not live(s)or s.menu.WaitingForFirstInput then return end
  local action=s.actions[id(b)];if not action then return end
  if action.kind=='open'then s.return_mode=s.mode;show(s,'species',action.species)
  elseif action.kind=='back'then
   if s.mode=='species'and s.species then local ok,why=journal.mark_read(s.species);if not ok then report('read state: '..tostring(why))end;compact(s)end
   show(s,s.return_mode=='compact'and'compact'or'gallery')
  elseif action.kind=='general'then show(s,'general')
  elseif action.kind=='expand'then show(s,s.mode=='compact'and'gallery'or'compact')
  elseif action.kind=='language'then language=language=='zh'and'en'or'zh';render_language(s)
  elseif action.kind=='nexus'then StaticFindObject('/Script/Engine.Default__KismetSystemLibrary'):LaunchURL(content.nexus_url)end
 end
 local function await_first_input(s)
  if not live(s)then return end
  if not s.menu.WaitingForFirstInput then sync_game_language();s.panel:SetVisibility(4);return end
  ExecuteInGameThreadAfterFrames(1,function()await_first_input(s)end)
 end
 local function attach(menu)
  sync_game_language()
  if active and same(active.menu,menu)and valid(active.panel)then active.panel:SetVisibility(menu.WaitingForFirstInput and 1 or 4);return true end
  assert(menu:IsInViewport(),'main menu not mounted')
  if not journal then
   local saved=StaticFindObject('/Script/Engine.Default__BlueprintPathsLibrary'):ProjectSavedDir():ToString()
   journal=journal_module.new(content,{path=saved..'EAA_Notice_Read_v1.tsv'})
  end
  local tree=menu.WidgetTree;local root=tree.RootWidget;assert(class(root)=='CanvasPanel','main menu root must be a canvas')
  local s={menu=menu,tree=tree,root=root,world=menu:GetWorld(),mode='compact',expanded=false,actions={},cards={}}
  if not hooked then
   load(BUTTON);RegisterHook(BUTTON..':'..RELEASE,function(receiver)
    local b=unbox(receiver);if not active or not active.actions[id(b)]then return end
    ExecuteInGameThreadAfterFrames(1,function()local ok,why=pcall(dispatch,b);if not ok then report('action: '..tostring(why))end end)
   end);hooked=true
  end
  local panel=construct(s,'CanvasPanel');s.panel=panel
  local owner=menu:GetOwningPlayer();local bg=load('/Script/UMG.Default__WidgetBlueprintLibrary'):Create(owner,load(BACKGROUND),owner)
  assert(valid(bg),'native announcement background missing');bg:SetVisibility(3);place(panel,bg,0,0,0,0,0,0,1,1)
  local original=menu.Speach:GetChildAt(0)
  if class(original)=='DialogueSimpleBlueprint_C'then
   for _,name in ipairs({'GreyBG','Image_49','TopLeft','TopRight','BottomLeft','BottomRight','TopBar','BottomBar','LeftBar','RightBar'})do bg[name]:SetBrush(original[name].Brush);bg[name]:SetColorAndOpacity(original[name].ColorAndOpacity)end
  end
  local canvas=construct(s,'CanvasPanel');s.canvas=canvas;place(panel,canvas,24,18,24,14,0,0,1,1)
  s.title=label(s,words().title,28,{.92,.92,.83});s.title:SetAutoWrapText(false);place(canvas,s.title,10,0,1100,43)
  s.subtitle=label(s,words().subtitle,15,{.66,.72,.60});place(canvas,s.subtitle,10,44,1100,27)
  s.status_label=label(s,words().status,18,{.76,.72,.44});s.status_label:SetJustification(2);place(canvas,s.status_label,-300,12,290,34,1,0,1,0)
  s.body=construct(s,'CanvasPanel');place(canvas,s.body,10,82,10,62,0,0,1,1)
  s.footer=construct(s,'CanvasPanel');place(canvas,s.footer,0,0,0,0,0,0,1,1)
  local top=0;for i=0,root:GetChildrenCount()-1 do top=math.max(top,tonumber(root:GetChildAt(i).Slot.ZOrder)or 0)end
  s.z=top+1
  -- Share the original right-hand column: its native fade animation and layout
  -- now own compact appearance and the space above the expanding official news.
  local column=menu.Speach:GetParent();assert(class(column)=='VerticalBox','native news column missing')
  local children={}
  for i=0,column:GetChildrenCount()-1 do
   local child=column:GetChildAt(i);local slot=child.Slot;local p=slot.Padding
   children[#children+1]={widget=child,size={Value=slot.Size.Value,SizeRule=slot.Size.SizeRule},
    padding={Left=p.Left,Top=p.Top,Right=p.Right,Bottom=p.Bottom},h=slot.HorizontalAlignment,v=slot.VerticalAlignment}
  end
  s.holder=construct(s,'SizeBox');s.holder:SetContent(panel);s.holder:SetVisibility(4)
  column:ClearChildren()
  for _,row in ipairs(children)do
   if same(row.widget,menu.Speach)then
    column:AddChildToVerticalBox(s.holder):SetPadding({Left=row.padding.Left,Top=8,Right=row.padding.Right,Bottom=0})
   end
   local slot=column:AddChildToVerticalBox(row.widget)
   slot:SetSize(row.size);slot:SetPadding(row.padding);slot:SetHorizontalAlignment(row.h);slot:SetVerticalAlignment(row.v)
  end
  active=s;render_language(s);panel:SetVisibility(menu.WaitingForFirstInput and 1 or 4)
  await_first_input(s);report('journal ready '..content.revision);return true
 end
 local function schedule(menu,attempt)
  if not valid(menu)then return end
  local key=id(menu);if pending[key]or failed[key]then return end;pending[key]=true
  ExecuteInGameThreadAfterFrames(attempt==0 and 2 or 15,function()
   pending[key]=nil;if not valid(menu)then return end
   if not menu:IsInViewport()then if attempt<20 then schedule(menu,attempt+1)end;return end
   local ok,why=pcall(attach,menu);if not ok then failed[key]=true;report('not mounted: '..tostring(why))end
  end)
 end
 function control.start()
  if started then return end;started=true;sync_game_language()
  for _,name in ipairs({'SetCurrentCulture','SetCurrentLanguage','SetCurrentLanguageAndLocale'})do
   RegisterHook('/Script/Engine.KismetInternationalizationLibrary:'..name,function()end,function()
    if language_refresh_pending then return end;language_refresh_pending=true
    ExecuteInGameThreadAfterFrames(1,function()language_refresh_pending=false;local ok,why=pcall(sync_game_language);if not ok then report('language: '..tostring(why))end end)
   end)
  end
  NotifyOnNewObject(MENU,function(menu)schedule(menu,0)end)
  for _,menu in ipairs(FindAllOf('MainMenuWidgetsLab3_C')or{})do schedule(menu,0)end
 end
 function control.status()
  local s=active;local ready=live(s)==true;local unread,cards={},{}
  if journal then for _,e in ipairs(journal.unread_list())do unread[#unread+1]=e.id end end
  if ready then for key,card in pairs(s.cards)do cards[key]={address=id(card.button),scale=card.scale,unread=journal.unread(key)}end end
  return{ready=ready,visible=ready and s.panel:IsVisible(),expanded=ready and s.mode~='compact',mode=ready and s.mode or nil,
   species=ready and s.species or nil,revision=content.revision,url=content.nexus_url,language=language,gameLanguage=observed_game_language,
   unread=unread,compact=ready and s.compact_ids or{},cards=cards,readPath=journal and journal.path,readError=journal and journal.error(),hoverRunning=ready and s.hover_running or false}
 end
 return control
end
return M
