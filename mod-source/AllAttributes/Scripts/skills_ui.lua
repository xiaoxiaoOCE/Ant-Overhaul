-- Native skill cards and native choice/confirmation dialogs for custom skills.
-- This module owns presentation only; callbacks own payment and persistence.
local M = {}
local HOME='/Game/UI/InGame/TechTree/SpeciesEntry.SpeciesEntry_C'
local ROSTER='/Game/UI/InGame/TechTree/SpeciesEntryCustomColony.SpeciesEntryCustomColony_C'
local OPTIONS='/Game/UI/InGame/TechTree/AbilityOptionSelect.AbilityOptionSelect_C'
local VARIANTS='/Game/UI/InGame/TechTree/SpeciesVariantSelect.SpeciesVariantSelect_C'
local CONFIRM='/Game/UI/InGame/TechTree/PurchaseConfirm.PurchaseConfirm_C'
local PERFORMANCE_NOTE='/Game/UI/GameSetup/DialogueOneOptionWithTitle.DialogueOneOptionWithTitle_C'
local module_dir=debug.getinfo(1,'S').source:sub(2):match('^(.*)[/\\]')
local FORM_BUTTON='/Game/UI/InGame/UIUpdate/Adaptations/PurchaseMenuButton.PurchaseMenuButton_C'
local ICON_BASE='/Game/UI/InGame/TechTree/AbilityImages/'
M.options={
 left={
  {id='recovery',title='快速恢复',description='回跳时的生命恢复量翻倍（+100%）。',icon='fast_recovery'},
  {id='invulnerable',title='暂避锋芒',description='回跳就绪时，受到致命伤害会保留1点生命，立刻回跳并短暂无敌。回跳冷却期间无法触发。',icon='AbilitySelf_Preservation'},
 },
 right={
  {id='evasion',title='危险回避',description='回跳冷却时间缩短约40%，更快准备好下一次回跳。',icon='AbilityEvasive'},
  {id='reward',title='特化尾刺',description='使用尾刺时，攻击间隔缩短约25%，蛰击更加频繁。',icon='AbilityDangerous'},
 },
}
M.ids={'TrapjawAnt','SlaveMaker','LittleBlackAnt','DriverAntLargeSoldier','DriverAntSoldier'}
M.species={
 TrapjawAnt={title='大颚猛蚁',portrait='UI_Creature_TrapJaw_Square_Icon',prefix='EAA_Trapjaw_',options=M.options,
  summary='回跳时重击刚刚攻击且仍在近战范围内的敌人。首次回跳后，改用尾刺进行普通攻击，造成毒液伤害。'},
 SlaveMaker={title='奴隶制造者兵蚁',portrait='UI_Creature_FormicaSanguinea_SlaveMaker_Square_Icon',prefix='EAA_SlaveMaker_',
  summary='升至二阶后，致命一击有约25%的概率击晕可俘虏的敌人。将其运到女王身旁即可转化为奴隶。',
  options={
   left={
    {id='special_master',title='特调奴隶主',description='升至二阶后，致命一击击晕可俘虏敌人的概率提高到约50%。',icon='AbilityCrippling'},
    {id='follow_step',title='强敌俘获',description='升至三阶后，致命一击也有机会击晕可俘虏的中型生物。',icon='AbilitySharp'},
   },
   right={
    {id='overseer_drill',title='监工督战',description='本单位存活时，附近友方奴隶的攻击速度提高约15%。同类加成不叠加。',icon='AbilityRoyal_Decree'},
    {id='overseer_haul',title='协同搬运',description='本单位存活时，附近友方奴隶搬运物品或单位时，移动速度提高约15%。同类加成不叠加。',icon='AbilityNimble'},
   },
  }},
 LittleBlackAnt={title='小黑蚁',portrait='UI_Creature_LittleBlackAntSoldier_Square_Icon',prefix='EAA_LittleBlackAnt_',
  summary='可在特化型与双生型之间切换，形态共用数值培养，技能可以单独选择。在养殖箱切换形态会消耗少量蚁皇浆，关前和其他模式可以免费选择。',
  forms={
   {id='specialist',title='特化型',description='改用尾针蛰击，造成毒液伤害，依然可以使敌人困惑。切换到特化型时，巢格里的副蚁会被移除。',icon='AbilityDangerous',video='EAA_LittleBlackSpecialist.mp4'},
   {id='twin',title='双生型',description='巢格升阶后可免费孵化和补生副蚁，升至满阶时副蚁也会变强。主蚁和副蚁都继承技能与数值培养。同格伙伴阵亡时，幸存者的攻击力和攻速各提高约20%，直到自身阵亡。同类加成只生效一次。',icon='AbilityEfficient_Brood',video='EAA_LittleBlackTwin.mp4'},
  },
  options={
   left={
    {id='confusion_signal',title='混乱信号',description='阵亡时有约10%的概率释放信息素，使附近敌人短暂陷入困惑。',icon='AbilityLast_Laugh'},
    {id='attack_signal',title='进攻信号',description='阵亡时有机会释放信息素，短暂提高附近友军约10%的攻击速度，最多叠加三层，每层独立计时。',icon='AbilityRoyal_Decree'},
   },
   right={
    {id='swarm_guard',title='集群防御',description='同一层附近的存活友军超过15只时，自身受到的范围伤害降低约30%。',icon='AbilityDefensive'},
    {id='charm',title='群体魅惑',description='升至三阶后，攻击造成的困惑变为持续约两三秒的魅惑，让目标攻击原本的队友。大型生物只会陷入困惑，中型生物在魅惑结束后会短暂免疫，小型生物再次被魅惑时刷新时间。没有可攻击的原队友时，改为困惑。',icon='AbilityFierce_Mother'},
   },
  }},
 DriverAntSoldier={
  title='普通黑色行军蚁',portrait='UI_Creature_DriverAnt_Soldier_Square_Icon',prefix='EAA_DriverSoldier_',
  summary='可选择合围处决或集体钳制猎物，并配合食物治疗与伤口易伤。',
  options={
   left={
    {id='swarm_execute',title='蚕食鲸吞',description='三只同种兵蚁近战围攻生命低于七成的小型敌人时，一只钳住猎物，另外两只蓄力冲刺完成处决。尸体食物增加约20%，原本没有食物的也会留下少量食物。发动后需要冷却；同伴阵亡或受控会中断。',icon='AbilityDangerous'},
    {id='collective_pin',title='插翅难逃',description='合围咬住中型、大型或泰坦敌人，使其无法移动，攻速降低近一半，普攻伤害降低约三成。参与者停止移动和攻击，并获得减伤。参与者死亡或受控时解除；目标施放部分特殊技能会将钳制者甩至远处，不额外眩晕。',icon='AbilityCrippling'},
   },
   right={
    {id='war_feast',title='以战养战',description='亲手击杀敌人后，消耗部分尸体食物，为附近受伤的同种兵蚁恢复生命。每只单次最多恢复约20%的最大生命，实际治疗量取决于食物和伤势。每具尸体只结算一次。',icon='fast_recovery'},
    {id='rend_wounds',title='撕裂伤口',description='普攻和咬持逐渐加深伤口，使目标受到的近战物理普攻伤害最多提高约20%。友方其他蚁种和奴隶也能利用这份易伤，但只有携带此技能的普通黑色行军蚁可以施加和刷新伤口。',icon='AbilitySharp'},
   },
  },
 },
 DriverAntLargeSoldier={
  title='黑色大型行军蚁',portrait='UI_Creature_DriverAnt_Major_Square_Icon',prefix='EAA_DriverLarge_',
  options={
   left={
    {id='rescue_guard',title='冲锋陷阵',description='充能全满时，可以冲锋援助附近交战的友军。每次冲锋命中后获得约10秒减伤，最高约80%，并嘲讽落点周围敌人、提高附近友军的物理与毒液抗性。撞中的敌人越多，眩晕越久；撞晕的越多，保护越强。自身增益期间免疫抓取和斩杀。',icon='AbilityDefensive'},
    {id='rescue_frenzy',title='破釜沉舟',description='充能全满时，可以冲锋援助附近交战的友军。每次冲锋命中后进入约10秒狂战，获得攻速和普攻吸血，撞晕的敌人越多，加成越强。普攻横扫目标周围小范围内的所有敌人。普攻或横扫击杀能延长狂战，但剩余时间不会超过初始时长。狂战期间免疫抓取和斩杀。',icon='AbilityDangerous'},
   },
   right={
    {id='ready_charge',title='蓄势待发',description='冲锋冷却时间缩短约20%，更快补回消耗的充能。',icon='AbilityNimble'},
    {id='extra_charge',title='厉兵秣马',description='额外增加1次冲撞充能储备，可以连续发动更多次冲锋。',icon='AbilityEfficient_Brood'},
   },
  },
 },
}
function M.supports(id)return M.species[id]~=nil end
function M.definition(id)return M.species[id]end
function M.copy_choices(value)
 local result={}
 for _,id in ipairs(M.ids)do
  local sides=value and value[id]or{};result[id]={left=sides.left or'none',right=sides.right or'none'}
  if id=='LittleBlackAnt'then result[id].form=sides.form or'specialist'end
 end
 return result
end
function M.install(api)
 local valid=assert(api.valid_object)
 local control,bindings,hooks,icons,focus_guards,skill_slots,form_buttons,hover_bindings={},{},{},{},{},{},{},{}
 local active,enabled=nil,true
 local queue_performance_note,notice_preferences,notice_words,notice_pending
 local preview_last={}
 local function get(o,k)if not valid(o)then return nil end;local ok,v=pcall(function()return o[k]end);return ok and v or nil end
 local function unbox(v)local ok,x=pcall(function()return v:get()end);if ok then return x end;return v end
 local function identity(o)return valid(o)and tostring(o:GetAddress())or nil end
 local function same(a,b)local id=identity(a);return id~=nil and id==identity(b)end
 local function report(v)pcall(api.log or print,'[CustomSkills UI] '..tostring(v))end
 local function text(s)return StaticFindObject('/Script/Engine.Default__KismetTextLibrary'):Conv_StringToText(tostring(s))end
 local function load(path)
  local value=StaticFindObject(path);if not valid(value)then value=LoadAsset(path)end
  assert(valid(value),'skill UI asset unavailable: '..path);return value
 end
 local function texture(name)
  if not valid(icons[name])then icons[name]=load(ICON_BASE..name..'.'..name)end
  return icons[name]
 end
 local function live(record)
  return enabled and record and bindings[identity(record.card)]==record and valid(record.world)
   and same(record.card:GetWorld(),record.world)and record.options.alive()==true
 end
 local function hover_live(record)
  return enabled and record and (bindings[identity(record.card)]==record or hover_bindings[identity(record.card)]==record)
   and valid(record.world)and same(record.card:GetWorld(),record.world)and record.options.alive()==true
 end
 local function hover_position(card,animation)
  local ok,playing,forward,time,first,last=pcall(function()
   return card:IsAnimationPlaying(animation),card:IsAnimationPlayingForward(animation),
    card:GetAnimationCurrentTime(animation),animation:GetStartTime(),animation:GetEndTime()
  end)
  if not ok or playing~=true then return nil end
  time,first,last=tonumber(time),tonumber(first),tonumber(last)
  if not time or not first or not last or time~=time or last<=first then return nil end
  return math.max(0,math.min(last-first,time-first)),last-first,forward==true
 end
 local function forget_slots(record)
  if record and valid(record.form_button)then
   form_buttons[identity(record.form_button)]=nil;record.form_button:RemoveFromParent();record.form_button=nil
  end
  for _,id in ipairs(record and record.slot_ids or{})do
   if skill_slots[id]and skill_slots[id].record==record then skill_slots[id]=nil end
  end
 end
 local function skill_overlay(record,key)
  local widget=get(record.card,key)
  if record.options.kind=='roster'and valid(widget)then return widget:GetParent()end
  return widget
 end
 local function track_slots(record)
  record.slot_ids={}
  local keys=record.options.kind=='home'and{'Ability1Hex','Ability2Hex'}or{'Ability1HexLeft','Ability2HexRight'}
  for _,key in ipairs(keys)do
   local id=identity(get(skill_overlay(record,key),'Slot'))
   assert(id,'skill canvas slot unavailable')
   skill_slots[id]={record=record,key=key,native_layer=-1};record.slot_ids[#record.slot_ids+1]=id
  end
  if record.options.kind=='roster'then
   record.main_hex=record.card.MainSpeciesHex:GetParent()
   assert(valid(record.main_hex)and record.main_hex:GetFullName():match('[%.:]MainHexOverlay$'),'native roster main hex unavailable')
   record.roster_hit_canvas=record.main_hex:GetParent()
   assert(valid(record.roster_hit_canvas)
    and same(record.roster_hit_canvas,skill_overlay(record,'Ability1HexLeft'):GetParent())
    and same(record.roster_hit_canvas,skill_overlay(record,'Ability2HexRight'):GetParent()),'native roster skill canvas unavailable')
   record.roster_rest_right=tonumber(skill_overlay(record,'Ability2HexRight').Slot:GetOffsets().Left)
   return
  end
  -- MainHex is a native named child, not an exposed Blueprint property.
  local canvas=record.card.Ability1Hex:GetParent()
  assert(valid(canvas),'skill canvas unavailable')
  for index=0,canvas:GetChildrenCount()-1 do
   local child=canvas:GetChildAt(index)
   if valid(child)and child:GetFullName():match('[%.:]MainHex$')then record.main_hex=child;break end
  end
  assert(valid(record.main_hex),'native main hex unavailable')
 end
 local function invoke(label,fn)
  local ok,err=pcall(fn);if not ok then report(label..': '..tostring(err))end
 end
 local function later(fn)
  ExecuteInGameThreadAfterFrames(1,function()if enabled then invoke('action',fn)end end)
 end
 local function visibility(widget,value)
  if valid(widget)and widget:GetVisibility()~=value then widget:SetVisibility(value)end
 end
 local function home_controls(record,restyle)
  if not live(record)or record.options.kind~='home'or not record.presentation then return end
  if record.restoring then return end
  record.restoring=true
  local ok,err=pcall(function()
  local card=record.card
  -- Native progression assumes level 1-3 and two native purchases. These
  -- supplemental cards have level 0 and independent skill records, so its
  -- visibility gate must not decide whether the actual mouse targets exist.
  card.EntryAbilitiesHidden=false;card.HideImprovmentsButton=false
  local rows=record.definition.options
  card.Ability1Owned=rows.left~=nil and record.presentation.left_choice==rows.left[1].id
  card.Ability3Owned=rows.left~=nil and record.presentation.left_choice==rows.left[2].id
  card.Ability2Owned=record.presentation.right_choice==rows.right[1].id
  card.Ability4Owned=record.presentation.right_choice==rows.right[2].id
  -- Raise the native stack together: skills -1/0 -> 0/1, main 0 -> 1,
  -- plus 1 -> 2. Resting skills stay behind the ant; native hover brings them
  -- to its shared layer, retaining both the original overlap and click order.
  for _,entry in ipairs({{record.main_hex,1},{get(card,'MinorImprovementsSizeBox'),2}})do
   local slot=get(entry[1],'Slot')
   if valid(slot)and tonumber(slot.ZOrder)~=entry[2]then slot:SetZOrder(entry[2])end
  end
  for _,side in ipairs({'left','right'})do
   local left=side=='left'
   local shown=rows[side]~=nil
   local overlay=get(card,left and'Ability1Hex'or'Ability2Hex')
   local button=get(card,left and'AbilityHexLeft'or'AbilityHexRight')
   local slot=get(overlay,'Slot')
   local owned=skill_slots[identity(slot)]
   local layer=owned and owned.native_layer+1 or 0
   if valid(slot)and tonumber(slot.ZOrder)~=layer then slot:SetZOrder(layer)end
   visibility(overlay,shown and 4 or 2) -- SelfHitTestInvisible keeps child buttons clickable.
   visibility(button,shown and 0 or 2)
   if valid(button)and button:GetIsEnabled()~=shown then button:SetIsEnabled(shown)end
   for _,key in ipairs(left and{'Ability1HexBase','Ability1Border'}or{'Ability2HexBase','Ability2Border'})do visibility(get(card,key),3)end
   local image=get(card,left and'AbImgLeft'or'AbImgRight')
   local selected=record.presentation[side]
   visibility(image,selected and 3 or 1)
   if restyle and selected and valid(image)then image:SetBrushFromTexture(selected,false);image:SetRenderOpacity(1)end
  end
  local plus,lock=get(card,'MinorImprovementsHex'),get(card,'MinImprovementsLock')
  -- Reapply the game's own active plus style, independently of skill ownership.
  local locked=valid(lock)and lock:GetVisibility()~=1 and lock:GetVisibility()~=2
  if valid(plus)then
   if restyle or locked or not plus:GetIsEnabled()then plus:SetStyle(card.LevelButtonActive)end
   if not plus:GetIsEnabled()then plus:SetIsEnabled(true)end
  end
  visibility(get(card,'MinorImprovementsSizeBox'),0);visibility(plus,0)
  visibility(lock,1);visibility(get(card,'Plus'),3)
  end)
  record.restoring=false
  if not ok then error(err)end
 end
 local function queue_home_controls(record)
  if not live(record)or record.options.kind~='home'or record.restore_queued or record.restoring then return end
  record.restore_queued=true
  later(function()
   record.restore_queued=false
   home_controls(record,true)
  end)
 end
 local function roster_controls(record,restyle)
  if not live(record)or record.options.kind~='roster'or not record.presentation or record.restoring then return end
  record.restoring=true
  local ok,err=pcall(function()
   local card=record.card
   local chosen=record.options.is_selected==nil or record.options.is_selected()==true
   local selection_changed=record.roster_selected~=chosen or card.Purchased~=chosen
   card.Purchased=chosen
   if selection_changed then
    -- Native selection paints HexBase/SpeciesHex; replacing this button's
    -- original transparent frame with SpeciesButtonActive covers the portrait.
    card:UpdatePurchaseVisuals(false)
    record.roster_selected=chosen
   end
   -- Keep hover over the native card's whole existing canvas. Otherwise a
   -- pointer entering the expanded right wing starts FocusAnimation at zero,
   -- loses the inward-moving button, and repeatedly enters/leaves the card.
   -- The transparent canvas handles no clicks; child buttons retain priority.
   visibility(record.roster_hit_canvas,0)
   visibility(record.main_hex,4);visibility(card.MainSpeciesHex,0)
   if not card.MainSpeciesHex:GetIsEnabled()then card.MainSpeciesHex:SetIsEnabled(true)end
   local main_slot=get(record.main_hex,'Slot')
   if valid(main_slot)and tonumber(main_slot.ZOrder)~=1 then main_slot:SetZOrder(1)end
   for _,side in ipairs({'left','right'})do
    local left=side=='left'
    local shown=record.definition.options[side]~=nil
    local key=left and'Ability1HexLeft'or'Ability2HexRight'
    local button=get(card,key);local overlay=skill_overlay(record,key)
    local slot=get(overlay,'Slot');local owned=skill_slots[identity(slot)]
    local layer=owned and owned.native_layer+1 or 0
    if valid(slot)and tonumber(slot.ZOrder)~=layer then slot:SetZOrder(layer)end
    visibility(overlay,shown and 4 or 2);visibility(button,shown and 0 or 2)
    local enabled=shown and chosen
    if valid(button)and button:GetIsEnabled()~=enabled then button:SetIsEnabled(enabled)end
    for _,name in ipairs(left and{'Ability1HexBase','Ability1HexBorder'}or{'Ability2HexBase','Ability2HexBorder'})do visibility(get(card,name),3)end
    local image=get(card,left and'Ab1ImgLeft'or'Ab2ImgRight');local selected=record.presentation[side]
    visibility(image,selected and 3 or 2)
    if valid(image)then
     if image:GetIsEnabled()~=enabled then image:SetIsEnabled(enabled)end
     if restyle and selected then image:SetBrushFromTexture(selected,false)end
    end
   end
  end)
  record.restoring=false
  if not ok then error(err)end
 end
 local function queue_roster_controls(record)
  if not live(record)or record.options.kind~='roster'or record.restore_queued or record.restoring then return end
  record.restore_queued=true
  later(function()record.restore_queued=false;roster_controls(record,true)end)
 end
 local function option_rows(record,side)
  return side=='form'and record.definition.forms or record.definition.options[side]
 end
 local function form_controls(record)
  local button=record.form_button
  if not valid(button)then return end
  local chosen=record.options.is_selected==nil or record.options.is_selected()==true
  if button.Button:GetIsEnabled()~=chosen then button.Button:SetIsEnabled(chosen)end
  visibility(button,4);visibility(button.Button,0)
 end
 local function prepare_form_media(record,widget)
  local paths=load('/Script/Engine.Default__BlueprintPathsLibrary')
  local directory=paths:ProjectContentDir()
  directory=type(directory)=='string'and directory or directory:ToString()
  directory=directory:gsub('\\','/'):gsub('/+$','')..'/Movies/'
  local factory=load('/Script/Engine.Default__GameplayStatics')
  local cls=load('/Script/MediaAssets.FileMediaSource')
  local media={}
  for index,row in ipairs(record.definition.forms)do
   local path=directory..row.video
   local entry={file=row.video,path=path,state='unavailable',epoch=0}
   media[index]=entry;widget['UnitOption'..index..'Media']=nil
   visibility(get(widget,'MediaImage'..index..'Video'),1)
   -- Match the native variants: a still remains underneath the hover video.
   -- Import only when this dialog opens, and retain it through the widget's
   -- Texture2D UPROPERTY (no global texture roots or background decoding).
   local poster=path:gsub('%.mp4$','.png')
   if paths:FileExists(poster)then
    local ok,why=pcall(function()
     local renderer=load('/Script/Engine.Default__KismetRenderingLibrary')
     local still=renderer:ImportFileAsTexture2D(widget,poster)
     if not valid(still)then entry.poster='invalid';return end
     widget['UnitOption'..index..'Image']=still;entry.poster='ready'
    end)
    if not ok then entry.poster='failed';report('form preview still unavailable: '..tostring(why))end
   else entry.poster='missing'end
   if paths:FileExists(path)then
    local ok,why=pcall(function()
     local source=factory:SpawnObject(cls,widget)
     if not valid(source)then entry.reason='source_unavailable';return end
     source:SetFilePath(path)
     if source:Validate()~=true then entry.reason='source_invalid';return end
     -- Engine path APIs preserve Unicode install paths. The UPROPERTY keeps
     -- the source alive until this dialog is collected, without global roots.
     widget['UnitOption'..index..'Media']=source
     entry.player=get(widget,'MediaPlayer'..index)
     if valid(entry.player)then
      entry.loop=entry.player:IsLooping();entry.play_on_open=entry.player.PlayOnOpen
      entry.state='idle'
     end
    end)
    if not ok then
     widget['UnitOption'..index..'Media']=nil;entry.player=nil;entry.reason=tostring(why)
     report('form preview unavailable: '..entry.file)
    end
   else entry.state='missing'end
  end
  preview_last=media
  return media
 end
 local function close_form_media(session)
  for _,entry in ipairs(session.media or{})do
   entry.epoch=entry.epoch+1
   if valid(entry.player)then
    entry.player:Close()
    if entry.loop~=nil then entry.player:SetLooping(entry.loop)end
    if entry.play_on_open~=nil then entry.player.PlayOnOpen=entry.play_on_open end
   end
   entry.player=nil;entry.state='closed';entry.ready=false;entry.playing=false
  end
 end
 local function observe_form_media(session,index)
  local entry=session.media and session.media[index]
  if not entry or not valid(entry.player)then return end
  entry.epoch=entry.epoch+1;local epoch=entry.epoch
  entry.state='opening';entry.ready=false;entry.playing=false
  local player=entry.player
  player:SetLooping(true);player.PlayOnOpen=true
  local attempts=0
  local function observe()
   if active~=session or entry.epoch~=epoch or not live(session.record)or not valid(session.widget)or not valid(player)then return end
   attempts=attempts+1
   local url=player:GetUrl();entry.url=type(url)=='string'and url or url:ToString()
   entry.ready=player:IsReady()==true;entry.playing=player:IsPlaying()==true
   local selected=entry.url:gsub('\\','/'):lower():sub(-#entry.file)==entry.file:lower()
   if selected and entry.ready and entry.playing and player:GetNumTracks(6)>0 then
    local size=player:GetVideoTrackDimensions(0,0)
    entry.width=tonumber(size.X);entry.height=tonumber(size.Y)
    if entry.width and entry.width>0 and entry.height and entry.height>0 then
     entry.state='playing';report('form preview playing: '..entry.file..' '..entry.width..'x'..entry.height)
     return
    end
   end
   if player:HasError()or attempts>=180 then
    entry.state='failed';report('form preview could not decode: '..entry.file)
    player:Close();entry.ready=false;entry.playing=false
    session.widget['MediaPlaying'..index]=false;session.widget['MediaOpened'..index]=false
    visibility(get(session.widget,'MediaImage'..index..'Video'),1)
    return
   end
   later(observe)
  end
  later(observe)
 end
 local function paint(record)
  if not live(record)then return end
  local card,options=record.card,record.options
  local definition=record.definition;local rows=definition.options
  local choices=assert(options.get_choices(),'custom skill choices unavailable')
  if rows.left then
   card.LeftAbility1Image=texture(rows.left[1].icon)
   card.LeftAbility3Image=texture(rows.left[2].icon)
   card.LeftAbility1Name=FName(definition.prefix..rows.left[1].id)
   card.LeftAbility3Name=FName(definition.prefix..rows.left[2].id)
  end
  card.RightAbility2Image=texture(rows.right[1].icon)
  card.RightAbility4Image=texture(rows.right[2].icon)
  -- Names deliberately do not alias native ColonySetup fields or purchases.
  card.RightAbility2Name=FName(definition.prefix..rows.right[1].id);card.RightAbility4Name=FName(definition.prefix..rows.right[2].id)
  card.Ability1Owned=rows.left~=nil and choices.left==rows.left[1].id
  card.Ability3Owned=rows.left~=nil and choices.left==rows.left[2].id
  card.Ability2Owned=choices.right==rows.right[1].id;card.Ability4Owned=choices.right==rows.right[2].id
  if options.kind=='home'then
   -- Keep the native single-side artwork, including its unpurchased empty
   -- hex. The combined renderer hides both sides at StoredMaxLevel == 0.
   local left=card.Ability1Owned and card.LeftAbility1Image or card.Ability3Owned and card.LeftAbility3Image or nil
   local right=card.Ability2Owned and card.RightAbility2Image or card.Ability4Owned and card.RightAbility4Image or nil
   record.presentation={left=left,right=right,left_choice=choices.left,right_choice=choices.right}
   if rows.left then
    card:SetAbilityButtonState(left~=nil,card.AbilityHexLeft,card.AbImgLeft,left,false,card.Ability1HexBase,card.Ability1Hex)
   end
   card:SetAbilityButtonState(right~=nil,card.AbilityHexRight,card.AbImgRight,right,false,card.Ability2HexBase,card.Ability2Hex)
   home_controls(record,true)
  else
   record.presentation={left=card.Ability1Owned and card.LeftAbility1Image or card.Ability3Owned and card.LeftAbility3Image or nil,
    right=card.Ability2Owned and card.RightAbility2Image or card.Ability4Owned and card.RightAbility4Image or nil}
   card['Set Ability Button States'](card,card.Ability1Owned,card.Ability3Owned,card.Ability2Owned,card.Ability4Owned,false)
   roster_controls(record,true)
  end
  if valid(record.form_button)then
   local name=choices.form=='twin'and'双生型' or'特化型'
   record.form_button.ButtonText=text(name..' ▾')
   record.form_button.TextBlock_143:SetText(record.form_button.ButtonText)
   record.form_button.Button:SetToolTipText(text('免费切换特化型或双生型。形态共用数值培养。切回特化型时会移除副蚁。'))
   form_controls(record)
  elseif definition.forms and options.kind=='home'then
   card.MainSpeciesHex:SetToolTipText(text('点击选择特化型或双生型。切换形态会消耗少量蚁皇浆。'))
  elseif definition.forms and options.form_on_main then
   local name=choices.form=='twin'and'双生型'or'特化型'
   local selected=options.is_selected and options.is_selected()==true
   card.MainSpeciesHex:SetToolTipText(text(selected and('小黑蚁 · '..name..'（已选入）。点击取消携带，再次点击可重新选择形态。')
    or'小黑蚁 · 点击选择特化型或双生型并携带。关前选择免费，左右技能保留。'))
  end
  local chosen=options.is_selected==nil or options.is_selected()==true
  for side,rows in pairs(definition.options)do
   local button=get(card,options.kind=='home'and(side=='left'and'AbilityHexLeft'or'AbilityHexRight')
    or(side=='left'and'Ability1HexLeft'or'Ability2HexRight'))
   if valid(button)then
    button:SetIsEnabled(chosen)
    local title=side=='left'and'左侧技能'or'右侧技能'
    for _,row in ipairs(rows)do if row.id==choices[side]then title=row.title end end
    button:SetToolTipText(text(title..'：'..rows[1].title..' / '..rows[2].title))
   end
  end
 end
 local function release_focus(guard)
  if not guard or focus_guards[guard.id]~=guard then return end
  focus_guards[guard.id]=nil
  if valid(guard.scroll)and valid(guard.world)and same(guard.scroll:GetWorld(),guard.world)
   and get(guard.scroll,'ScrollWhenFocusChanges')==0 then
   guard.scroll:SetScrollWhenFocusChanges(guard.mode)
  end
 end
 local function hold_focus(record)
  if not live(record)then return end
  local scroll=record.options.scroll
  if not valid(scroll)then return end
  local id=identity(scroll);local previous=focus_guards[id]
  local mode=previous and previous.mode or get(scroll,'ScrollWhenFocusChanges')
  if mode==nil then return end
  local guard={id=id,scroll=scroll,world=scroll:GetWorld(),mode=mode,offset=scroll:GetScrollOffset()}
  focus_guards[id]=guard
  scroll:SetScrollWhenFocusChanges(0)
  return guard
 end
 local function finish_focus(guard)
  if not guard or focus_guards[guard.id]~=guard then return end
  -- All synchronous changes here came from removing/refocusing the dialog;
  -- no user input can interleave inside this game-thread callback.
  if valid(guard.scroll)and same(guard.scroll:GetWorld(),guard.world)
   and guard.scroll:GetScrollOffset()~=guard.offset then guard.scroll:SetScrollOffset(guard.offset)end
  -- Slate processes focus scrolling later. Keep NoScroll through two frames,
  -- but never overwrite offsets during that wait: the user may scroll again.
  later(function()later(function()release_focus(guard)end)end)
 end
 local function close(session)
  if active~=session then return end
  local guard=hold_focus(session.record)
  active=nil
  close_form_media(session)
  if valid(session.widget)then session.widget:RemoveFromParent()end
  if live(session.record)then
   local parent=session.record.options.parent
   if valid(parent)and same(get(parent,'ActiveOverlayWidget'),session.widget)then parent.ActiveOverlayWidget=nil end
   if session.record.options.on_close then session.record.options.on_close()end
   local card=session.record.card
   local button=get(card,session.record.options.kind=='home'and(session.side=='left'and'AbilityHexLeft'or'AbilityHexRight')
    or(session.side=='left'and'Ability1HexLeft'or'Ability2HexRight'))
   if session.side=='form'then
    button=valid(session.record.form_button)and session.record.form_button.Button or get(card,'MainSpeciesHex')
   end
   if valid(button)then pcall(function()button:SetKeyboardFocus()end)end
  end
  finish_focus(guard)
 end
 local function make_widget(path,record)
  local cls=load(path)
  local creator=load('/Script/UMG.Default__WidgetBlueprintLibrary')
  local owner=record.card:GetOwningPlayer();assert(valid(owner),'skill dialog owner missing')
  local widget=creator:Create(owner,cls,owner);assert(valid(widget),'skill dialog creation failed')
  return widget
 end
 local function mount(session)
  session.widget:AddToViewport(1100)
  local parent=session.record.options.parent
  if session.record.options.kind=='roster'and valid(parent)then parent.ActiveOverlayWidget=session.widget end
 end
 local function complete(session,value)
  if active~=session or not live(session.record)then close(session);return end
  session.value=value
  local ok,why,job=session.record.options.choose(session.side,value)
  if ok~=true then
   report(why or'skill selection refused')
   local label=get(session.widget,'WarningText')or get(session.widget,'Cost')
   if valid(label)then label:SetText(text(tostring(why or'技能选择未保存，请重试。')));label:SetVisibility(0)end
   session.busy=false;return
  end
  if why=='pending'then
   assert(job and type(session.record.options.purchase_result)=='function','skill transaction result unavailable')
   session.transaction=job;session.busy=true
   local label=get(session.widget,'WarningText')or get(session.widget,'Cost')
   if valid(label)then label:SetText(text('正在保存技能选择，请稍候……'));label:SetVisibility(0)end
   for _,key in ipairs({'ConfirmButton','CancelButton','UnitOption1','UnitOption2','Close'})do
    local button=get(session.widget,key);if valid(button)then button:SetIsEnabled(false)end
   end
   return
  end
  if session.record.options.on_complete then session.record.options.on_complete()end
  paint(session.record);close(session)
  queue_performance_note(session.record,session.side,value)
 end
 local function quote(record,side,value)
  if record.options.kind~='home'then return {cost=0,can_purchase=true}end
  local result=record.options.quote and record.options.quote(side,value)
  assert(type(result)=='table'and type(result.cost)=='number'and result.cost>=0,'skill price unavailable')
  return result
 end
 local function show_confirm(previous,value,price)
  local record,side=previous.record,previous.side
  close(previous)
  if not live(record)then return end
  local widget=make_widget(CONFIRM,record)
  -- The original payment graph is never used. The owned graph hook below
  -- redirects both buttons to our callback before PerformThePurchase runs.
  widget.Cost=0;widget.Species=255;widget.SpecialPurchaseName=FName('EAA_CustomSkill')
  widget.ConfirmButton.ButtonText=text('确定');widget.ConfirmButton.InStyle=widget.PurchaseButtonStyle
  widget.CancelButton.ButtonText=text('取消');widget.CancelButton.InStyle=widget.CancelButtonStyle
  local session={record=record,widget=widget,side=side,value=value,kind='confirm'};active=session
  mount(session)
  widget.ConfirmButton.TextBlock_143:SetText(text('确定'))
  widget.CancelButton.TextBlock_143:SetText(text('取消'))
  widget.ConfirmButton.Button:SetStyle(widget.PurchaseButtonStyle)
  widget.CancelButton.Button:SetStyle(widget.CancelButtonStyle)
  widget.ConfirmButton.Button:SetKeyboardFocus()
  local title=value
  for _,row in ipairs(option_rows(record,side))do if row.id==value then title=row.title end end
  widget.ConfText:SetText(text('花费 '..tostring(price.cost)..' 蚁皇浆选择“'..title..'”？'))
  local choices=record.options.get_choices()
  widget.WarningText:SetText(text(side=='form'and'测试期切换费用：1蚁皇浆。数值培养与左右技能保留；切回特化型会移除额外个体。'
   or choices[side]~='none'and'将替换本侧已选择的技能，原费用不退还。'or''))
  widget.WarningText:SetVisibility((side=='form'or choices[side]~='none')and 0 or 1)
 end
 local function choose_option(session,index)
  if active~=session or session.busy or not live(session.record)then return end
  local value=assert(option_rows(session.record,session.side)[index]).id
  local selected=session.record.options.get_choices()[session.side]
  if session.side=='form'then selected=selected or'specialist'end
  -- An unselected native-style roster card still needs its selection callback
  -- when the player picks the inherited/default form without changing it.
  local selecting_form=session.side=='form'and session.record.options.form_on_main
   and session.record.options.is_selected and not session.record.options.is_selected()
  if selected==value and not selecting_form then
   close(session);queue_performance_note(session.record,session.side,value);return
  end
  local price=quote(session.record,session.side,value)
  if price.can_purchase~=true then
   report(price.reason or'蚁皇浆不足')
   -- The native option callback removes its window after broadcasting. Reopen
   -- this owned dialog on the next frame with a visible reason instead of
   -- accepting a selection that the transaction service cannot commit.
   close(session)
   control.open(session.record.card,session.side,price.reason or'蚁皇浆不足')
   return
  end
  if session.record.options.kind=='home'and price.cost>0 then show_confirm(session,value,price)
  else session.busy=true;complete(session,value)end
 end
 function control.open(card,side,notice)
  local record=bindings[identity(card)]
  if not live(record)or not option_rows(record,side)then return nil,'skill_card_expired'end
  if active then return nil,'skill_dialog_open'end
  if record.options.can_open and not record.options.can_open()then return nil,'another_dialog_open'end
  local is_form=side=='form'
  if record.options.is_selected and not record.options.is_selected()
   and not(is_form and record.options.form_on_main)then return nil,'species_not_selected'end
  local widget=make_widget(is_form and VARIANTS or OPTIONS,record)
  local rows=option_rows(record,side)
  widget.UnitOption1NameText=text(rows[1].title);widget.UnitOption2NameText=text(rows[2].title)
  widget.UnitOption1DescriptionText=text(rows[1].description);widget.UnitOption2DescriptionText=text(rows[2].description)
  if is_form then
   local name=record.definition.portrait
   local portrait=load('/Game/UI/InGame/UIUpdate/CharacterIcons/SquareImages/'..name..'.'..name)
   widget.UnitOption1Image=portrait;widget.UnitOption2Image=portrait
  else widget.UnitOption1Image=texture(rows[1].icon);widget.UnitOption2Image=texture(rows[2].icon)end
  local price=quote(record,side,rows[1].id)
  -- A selected first option quotes zero; both choices still have a common
  -- purchase price, so show the alternative's quote when necessary.
  if record.options.kind=='home'and price.cost==0 then price=quote(record,side,rows[2].id)end
  widget.CostOfChoice=price.cost;widget.HideCost=record.options.kind~='home'
  local session={record=record,side=side,widget=widget,kind=is_form and'variants'or'options'}
  if is_form then session.media=prepare_form_media(record,widget)end
  active=session
  mount(session)
  widget.UnitOption1:SetKeyboardFocus()
  if notice then widget.Cost:SetText(text(notice));widget.Cost:SetVisibility(0)end
  return true
 end
 local function hook(name,path,fn,after)
  if hooks[name]then return end
  assert(valid(StaticFindObject(path)),'skill UI function missing: '..path)
  local pre,post=RegisterHook(path,function(...)local args={...};invoke(name,function()fn(table.unpack(args))end)end,
   function(...)if after then local args={...};invoke(name..' post',function()after(table.unpack(args))end)end end)
  assert(type(pre)=='number'and type(post)=='number','skill UI hook unavailable: '..path)
  hooks[name]={path,pre,post}
 end

 -- One small reminder after a successful Twin choice. There is no combat
 -- polling, count limit or new purchase path. State belongs to this player,
 -- outside Colony saves, and is shared by the home/roster/mode UI instances.
 local function preferences()
  if notice_preferences then return notice_preferences end
  assert(module_dir,'player_notice_module_directory_missing')
  local service=dofile(module_dir..'/player_notices.lua')
  local fs=api.fileio or dofile(module_dir..'/unicode_fs.lua')
  local saved=StaticFindObject('/Script/Engine.Default__BlueprintPathsLibrary'):ProjectSavedDir():ToString()
  local shared=rawget(_G,'EAA_PlayerNoticeOnce')
  if type(shared)~='table'then shared={};rawset(_G,'EAA_PlayerNoticeOnce',shared)end
  notice_preferences=service.new{path=saved..service.filename,fs=fs,shared=shared}
  notice_words=service.copy
  return notice_preferences
 end
 queue_performance_note=function(record,side,value)
  if side~='form'or value~='twin'or record.options.species_id~='LittleBlackAnt'then return end
  local store=preferences();local token=store.claim();if not token then return end
  local reservation={store=store,token=token};notice_pending=reservation
  local scheduled,schedule_error=pcall(later,function()
   if notice_pending==reservation then notice_pending=nil end
   -- Refresh may rebind the same card after a completed home purchase.
   local current=bindings[identity(record.card)]
   if not live(current)or active then store.abandon(token);return end
   local popup
   local ok,why=pcall(function()
    load(PERFORMANCE_NOTE)
    hook('twin-performance-note',PERFORMANCE_NOTE..':RemoveDialogue',function(receiver)
     local session=active
     if session and session.kind=='performance-note'and same(unbox(receiver),session.widget)then
      later(function()close(session)end)
     end
    end)
    local language='en'
    local got,code=pcall(function()
     local v=StaticFindObject('/Script/Engine.Default__KismetInternationalizationLibrary'):GetCurrentLanguage()
     return type(v)=='string'and v or v:ToString()
    end)
    if got and type(code)=='string'then language=code end
    local words=notice_words(language)
    local widget=make_widget(PERFORMANCE_NOTE,current)
    widget.TitleDisplayText=text(words.title);widget.QuestionDisplayText=text(words.body);widget.ButtonDisplayText=text(words.button)
    widget.TextBlock_158:SetText(widget.TitleDisplayText)
    widget.QuestionText:SetText(widget.QuestionDisplayText)
    widget.ButtonText:SetText(widget.ButtonDisplayText)
    widget.QuestionText:SetAutoWrapText(true)
    popup={record=current,side='form',widget=widget,kind='performance-note'};active=popup
    mount(popup);assert(widget:IsInViewport(),'performance_note_not_mounted')
    local saved_ok,saved_why=store.mark_shown(token)
    if not saved_ok then report('Performance reminder preference: '..tostring(saved_why))end
    widget.Button:SetKeyboardFocus()
   end)
   if not ok then
    store.abandon(token)
    if popup and active==popup then close(popup)end
    report('Performance reminder: '..tostring(why))
   end
  end)
  if not scheduled then
   store.abandon(token)
   if notice_pending==reservation then notice_pending=nil end
   report('Performance reminder scheduling: '..tostring(schedule_error))
  end
 end
 local function ensure_hooks(kind)
  load(OPTIONS);load(CONFIRM);load(VARIANTS)
  hook('variants',VARIANTS..':ExecuteUbergraph_SpeciesVariantSelect',function(receiver,entry)
   local session=active
   if not session or session.kind~='variants'or not same(unbox(receiver),session.widget)then return end
   local offset=tonumber(unbox(entry));local widget=session.widget
   if offset==2836 or offset==2875 then
    entry:set(3142);later(function()choose_option(session,offset==2836 and 1 or 2)end)
   elseif offset==2420 or offset==2914 then
    entry:set(3142);later(function()close(session)end)
   elseif offset==2454 or offset==2816 or offset==2635 or offset==2826 then
    local first=offset==2454 or offset==2816
    local media=session.media and session.media[first and 1 or 2]
    if media and valid(media.player)then
     -- Keep native hover OpenSource and its material-backed preview images.
     -- Ready/playing/decoded dimensions are checked separately next frame;
     -- OpenSource's immediate true means only that the request was accepted.
     observe_form_media(session,first and 1 or 2)
    else
     entry:set(3142)
     visibility(widget.UnitOption1SelectionBorder,first and 3 or 1)
     visibility(widget.UnitOption2SelectionBorder,first and 1 or 3)
     visibility(widget.MediaImage1Video,1);visibility(widget.MediaImage2Video,1)
    end
   elseif offset==2236 or offset==2821 or offset==2372 or offset==2831 then
    local media=session.media and session.media[(offset==2236 or offset==2821)and 1 or 2]
    if media then media.epoch=media.epoch+1;media.state='idle';media.playing=false end
   end
  end)
  hook('options',OPTIONS..':ExecuteUbergraph_AbilityOptionSelect',function(receiver,entry)
   local session=active
   if not session or session.kind~='options'or not same(unbox(receiver),session.widget)then return end
   local offset=tonumber(unbox(entry))
   if offset==1073 or offset==1112 then
    -- Prevent native Close Widget from retiring the UI before the deferred
    -- transaction has finished or an insufficient-funds message is displayed.
    entry:set(1294)
    later(function()choose_option(session,offset==1073 and 1 or 2)end)
   elseif offset==883 or offset==1151 then
    -- Own removal too: native Close Widget would remove the dialog before
    -- our deferred scroll guard has been installed.
    entry:set(1294)
    later(function()close(session)end)
   end
  end)
  hook('confirm',CONFIRM..':ExecuteUbergraph_PurchaseConfirm',function(receiver,entry)
   local session=active
   if not session or session.kind~='confirm'or not same(unbox(receiver),session.widget)then return end
   local offset=tonumber(unbox(entry))
   if offset==234 or offset==162 then
    entry:set(244)
    if not session.busy then session.busy=true;later(function()complete(session,session.value)end)end
   elseif offset==229 or offset==224 or offset==200 then
    entry:set(244)
    if not session.transaction then later(function()close(session)end)end
   end
  end)
  local path=kind=='home'and HOME or ROSTER
  load(path)
  local function queue_home(receiver)
   local record=bindings[identity(unbox(receiver))]
   if record then queue_home_controls(record)end
  end
   -- Shift only the two owned animation tracks by one layer. Cache the last
   -- native value so maintenance retains the final hover state after playback.
   hook('home-skill-layer','/Script/UMG.CanvasPanelSlot:SetZOrder',function(receiver,order)
    local slot=unbox(receiver);local owned=skill_slots[identity(slot)]
    if not owned or not live(owned.record)or owned.record.restoring then return end
    local overlay=skill_overlay(owned.record,owned.key)
    if not same(get(overlay,'Slot'),slot)then return end
    local requested=tonumber(unbox(order))
    if requested==-1 or requested==0 then owned.native_layer=requested;order:set(requested+1)end
   end)
  if kind=='home'then
   -- These native functions also run outside ExecuteUbergraph (focus/hover
   -- bindings and RefreshAfterPurchase). Blueprint POST hooks do not fire on
   -- this UE4SS build: queue a single next-frame repair from PRE, after native
   -- rendering, without sidecar reads or world/asset searches.
   for _,name in ipairs({'Set Ability Button States','SetLevelButtonsStates','LevelButtonVisibilitySwitch',
    'GetImprovementsButtonVisibility','Set Main Hex','SetupButton'})do
    hook('home-render:'..name,path..':'..name,queue_home)
   end
  else
   -- The native card briefly reports Leave/Enter while moving onto its wing.
   -- Coalesce that transition at the native animation call: the Blueprint
   -- graph hook runs after PlayAnimation and cannot prevent its restart.
   hook('roster-hover','/Script/UMG.UserWidget:PlayAnimation',function(receiver,animation,start,loops,mode,speed,restore)
    local card=unbox(receiver);local record=bindings[identity(card)]or hover_bindings[identity(card)]
    if not hover_live(record)or record.options.kind~='roster'or record.replaying_hover then return end
    local target=unbox(animation)
    if not same(target,get(card,'FocusAnimation'))then return end
    local direction=tonumber(unbox(mode))
    local ordinary=tonumber(unbox(start))==0 and tonumber(unbox(loops))==1 and unbox(restore)==false
    if direction==0 then
     record.hover_epoch=(record.hover_epoch or 0)+1
     local slot=get(skill_overlay(record,'Ability2HexRight'),'Slot')
     local x=valid(slot)and tonumber(slot:GetOffsets().Left)
     -- Popup focus can collapse the native animation independently of the
     -- remembered hover event. A resting card must always be allowed to open.
     local expanded=x and record.roster_rest_right and math.abs(x-record.roster_rest_right)>0.01
     local position,_,forward=hover_position(card,target)
     if record.roster_hovered and(expanded or position~=nil and forward)then animation:set(nil)
     else
      record.roster_hovered=true
      -- PlayAnimation(reverse, start=0) starts at the END; forward starts at
      -- zero. Crossing a wing during playback must continue at its current
      -- position instead of snapping the root scale and both skill offsets.
      if ordinary and position~=nil then start:set(position)end
     end
    elseif direction==1 then
     local args={unbox(start),unbox(loops),direction,unbox(speed),unbox(restore)}
     animation:set(nil)
     record.hover_epoch=(record.hover_epoch or 0)+1
     local epoch,deadline=record.hover_epoch,os.clock()+0.04
     local function settle()
      if not hover_live(record)or record.hover_epoch~=epoch or card:IsHovered()then return end
      if os.clock()<deadline then later(settle);return end
      record.roster_hovered=false;record.replaying_hover=true
      local ok,err=pcall(function()
       local position,duration,forward=hover_position(card,target)
       if ordinary and position~=nil then
        if not forward then return end -- already closing; do not restart it
        args[1]=duration-position
       end
       card:PlayAnimation(target,table.unpack(args))
      end)
      record.replaying_hover=false
      if not ok then error(err)end
     end
     later(settle)
    end
   end)
   for _,name in ipairs({'Set Ability Button States','SetLevelButtonsStates','Set Main Hex','SetupButton','UpdatePurchaseVisuals'})do
    hook('roster-render:'..name,path..':'..name,function(receiver)
     local record=bindings[identity(unbox(receiver))];if record then queue_roster_controls(record)end
    end)
   end
  end
  hook(kind,path..':ExecuteUbergraph_'..(kind=='home'and'SpeciesEntry'or'SpeciesEntryCustomColony'),function(receiver,entry)
   local card=unbox(receiver);local record=bindings[identity(card)]
   if not live(record)or record.options.kind~=kind then return end
   if kind=='home'then queue_home_controls(record)end
   local offset=tonumber(unbox(entry))
   -- Controller/named wrappers enter the graph at a Jump instruction. A
   -- RegisterHook callback observes the entry only, not its internal target.
   local left=kind=='home'and(offset==11230 or offset==14034)or kind=='roster'and(offset==2705 or offset==17800)
   local right=kind=='home'and(offset==12472 or offset==14039)or kind=='roster'and(offset==4563 or offset==17795)
   if left or right then
    entry:set(kind=='home'and 37032 or 17805)
    local side=left and'left'or'right'
    if not record.definition.options[side]then return end
    later(function()
     if live(record)then
      local opened,reason=control.open(card,side)
      if not opened then report('skill window not opened: '..tostring(reason))end
     end
    end)
   elseif kind=='home'and record.definition.forms and offset==8709 then
    entry:set(37032)
    later(function()if live(record)then control.open(card,'form')end end)
   elseif kind=='roster'and(offset==7114 or offset==17790 or offset==14555)then
    entry:set(17805)
    later(function()
     if not live(record)or active then return end
     -- Match the game's dual-form roster cards: the first click chooses a
     -- form and selects it; a selected main portrait toggles the species off.
     if record.definition.forms and record.options.form_on_main
      and record.options.is_selected and not record.options.is_selected()then control.open(card,'form')
     elseif record.options.toggle then record.options.toggle();paint(record)end
    end)
   end
  end)
 end
 local function add_form_button(record)
  if not record.definition.forms or record.options.kind=='home'or record.options.form_on_main then return end
  load(FORM_BUTTON)
  hook('form-button',FORM_BUTTON..':BndEvt__PurchaseMenuButton_Button_K2Node_ComponentBoundEvent_0_OnButtonReleasedEvent__DelegateSignature',function(receiver)
   local button=unbox(receiver);local current=form_buttons[identity(button)]
   if not live(current)or not same(current.form_button,button)then return end
   later(function()if live(current)then control.open(current.card,'form')end end)
  end)
  local button=make_widget(FORM_BUTTON,record)
  local style=load(CONFIRM):GetCDO().PurchaseButtonStyle
  button.InStyle=style;button.ButtonText=text('特化型 ▾')
  local canvas=record.main_hex:GetParent();local slot=canvas:AddChildToCanvas(button)
  assert(valid(slot),'form button canvas slot unavailable')
  -- Follow the existing portrait anchor. Keep both side skills and the plus
  -- unobstructed with one small native-styled button above the ant.
  local main=record.main_hex.Slot;local offset=main:GetOffsets();local alignment=main:GetAlignment()
  slot:SetAnchors(main:GetAnchors());slot:SetAlignment({X=.5,Y=0})
  slot:SetPosition({X=offset.Left+(0.5-alignment.X)*offset.Right,Y=offset.Top-alignment.Y*offset.Bottom-29})
  slot:SetSize({X=116,Y=26});slot:SetAutoSize(false);slot:SetZOrder(3)
  button.Button:SetStyle(style);button.TextBlock_143:SetText(button.ButtonText)
  local font=button.TextBlock_143.Font;font.Size=14;button.TextBlock_143:SetFont(font)
  record.form_button=button;form_buttons[identity(button)]=record
 end
 function control.bind(card,options)
  assert(valid(card)and(options.kind=='home'or options.kind=='roster'),'invalid custom skill card')
  assert(type(options.alive)=='function'and type(options.get_choices)=='function'and type(options.choose)=='function')
  local definition=assert(M.definition(options.species_id or'TrapjawAnt'),'unknown custom skill species')
  ensure_hooks(options.kind)
  forget_slots(bindings[identity(card)])
  local record={card=card,world=card:GetWorld(),options=options,definition=definition};bindings[identity(card)]=record
  track_slots(record)
  add_form_button(record)
  paint(record);return true
 end
 -- Original hex cards in this story window need only the same continuous
 -- hover animation. Their species selection and native skill UI stay native.
 function control.bind_hover(card,options)
  assert(valid(card)and type(options)=='table'and type(options.alive)=='function','invalid hover-only card')
  ensure_hooks('roster')
  if bindings[identity(card)]then return true end
  local right=card.Ability2HexRight:GetParent()
  assert(valid(right)and valid(right.Slot),'native hover slot unavailable')
  hover_bindings[identity(card)]={card=card,world=card:GetWorld(),options={kind='roster',alive=options.alive},
   roster_rest_right=tonumber(right.Slot:GetOffsets().Left)}
  return true
 end
 function control.unbind_hover(card)local id=identity(card);if id then hover_bindings[id]=nil end end
 function control.refresh(card)local record=bindings[identity(card)];if record then paint(record)end end
 function control.unbind(card)
  local id=identity(card);local record=bindings[id]
  if active and active.record==record then close(active)end
  forget_slots(record)
  if id then bindings[id]=nil end
 end
 function control.cancel(force)
  if active then if force or not active.transaction then close(active)end;return true end
  return false
 end
 function control.get_active()return active end
 function control.preview_status()
  local result={}
  for index,entry in ipairs(preview_last)do
   result[index]={file=entry.file,state=entry.state,poster=entry.poster,reason=entry.reason,url=entry.url,ready=entry.ready,playing=entry.playing,width=entry.width,height=entry.height}
  end
  return result
 end
 function control.tick()
  if active and not live(active.record)then close(active)end
  -- Native dialogue graphs can remove themselves without passing a reflected
  -- RemoveDialogue callback. Retire only this owned one-time overlay as well.
  if active and active.kind=='performance-note'and(not valid(active.widget)or not active.widget:IsInViewport())then close(active)end
  if active and active.transaction then
   local session=active
   local result=session.record.options.purchase_result(session.transaction)
   if result and result.phase=='complete'then
    if session.record.options.on_complete then session.record.options.on_complete()end
    paint(session.record);close(session)
    queue_performance_note(session.record,session.side,session.value)
   elseif result and result.phase=='failed'then
    session.transaction=nil;session.busy=false
    report(result.error or'skill purchase failed')
    local label=get(session.widget,'WarningText')or get(session.widget,'Cost')
    if valid(label)then label:SetText(text('技能购买未完成，请返回后重试。'));label:SetVisibility(0)end
    local cancel=get(session.widget,'CancelButton');if valid(cancel)then cancel:SetIsEnabled(true)end
   end
  end
  for id,record in pairs(bindings)do
   if not live(record)then forget_slots(record);bindings[id]=nil
   elseif record.options.kind=='home'then home_controls(record,false);form_controls(record)
   else roster_controls(record,false);form_controls(record)end
  end
  for id,record in pairs(hover_bindings)do if not hover_live(record)then hover_bindings[id]=nil end end
 end
 function control.stop()
  if notice_pending then notice_pending.store.abandon(notice_pending.token);notice_pending=nil end
  control.cancel(true)
  for _,guard in pairs(focus_guards)do release_focus(guard)end
  for _,record in pairs(bindings)do forget_slots(record)end
  enabled=false
  for _,data in pairs(hooks)do pcall(UnregisterHook,data[1],data[2],data[3])end
  bindings,hooks,skill_slots,form_buttons,hover_bindings={},{},{},{},{}
 end
 return control
end
return M
