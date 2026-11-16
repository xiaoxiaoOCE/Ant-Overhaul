-- Main-menu announcement data and per-species read state. No engine hooks,
-- world scans, purchases, or gameplay save writes occur in this module.
local M={}
local dir=assert(debug.getinfo(1,'S').source:sub(2):match('^(.*)[/\\]'))
local hash=dofile(dir..'/sha256.lua')
local default_fs=dofile(dir..'/unicode_fs.lua')
local function pair(zh,en)return{zh=zh,en=en}end
local portraits='/Game/UI/InGame/UIUpdate/CharacterIcons/SquareImages/'
local function portrait(name)return portraits..name..'.'..name end
local words={
 zh={title='蚂蚁大修 V0.2',gallery='蚁种更新档案',subtitle='26/11/15',status='V0.2',
  updated='此蚂蚁获得了更新！',unread='金光表示尚未查看',all='额外蚁种',back='返回蚁种',
  latest='本次更新',history='历史版本',published='已发布版本',pending='26/11/15',
  none='暂时没有单独的更新记录',empty='这只蚂蚁仍保留在额外兵种列表中。之后对它的改动，会记录在这里。',
  no_older='更早的记录暂未整理',caught='本次更新已全部查看',other='其他更新',general='模组与通用更新',
  expand='放大',collapse='收起',nexus='模组主页',language='English'},
 en={title='Ant Overhaul V0.2',gallery='Species update journal',subtitle='26/11/15',status='V0.2',
  updated='This ant has been updated!',unread='Gold marks unread updates',all='Extra species',back='Back to species',
  latest='Current changes',history='Previous version',published='Published release',pending='26/11/15',
  none='No species-specific changes recorded yet',empty='This ant remains available in the extra-species roster. Future changes to it will appear here.',
  no_older='Earlier records have not been added yet',caught='All updates have been read',other='Other updates',general='General mod updates',
  expand='Expand',collapse='Collapse',nexus='Mod page',language='中文'},
}
local function historical(title,text)return{title=title,text=text}end
function M.new(legacy,options)
 options=options or{};assert(legacy.languages.zh and legacy.languages.en)
 local catalog={};local by_id={};local species_sections={}
 local function add(id,name,image,section_prefixes,history)
  local sections={}
  for _,prefix in ipairs(section_prefixes or{})do
   for i,section in ipairs(legacy.languages.zh.sections)do
    if section.title:sub(1,#prefix)==prefix then
     species_sections[i]=true
     local english=assert(legacy.languages.en.sections[i],'bilingual section missing')
     sections[#sections+1]={title=pair(section.title,english.title),text=pair(section.text,english.text)}
     break
    end
   end
  end
  local entry={id=id,name=name,icon=portrait(image),records=history or{}}
  if #sections>0 then
   local version=legacy.version or'0.2'
   table.insert(entry.records,1,{version=version,sections=sections,current=true})
   local pieces={id,version}
   for _,s in ipairs(sections)do for _,lang in ipairs({'zh','en'})do pieces[#pieces+1]=s.title[lang];pieces[#pieces+1]=s.text[lang]end end
   entry.token=hash(table.concat(pieces,'\n'))
  end
  catalog[#catalog+1]=entry;by_id[id]=entry
 end
 add('DriverAntSoldier',pair('普通黑色行军蚁','Driver ant soldier'),'UI_Creature_DriverAnt_Soldier_Square_Icon',{'普通黑色行军蚁'})
 add('DriverAntLargeSoldier',pair('大型黑色行军蚁','Large driver ant soldier'),'UI_Creature_DriverAnt_Major_Square_Icon',{'黑色大型行军蚁'})
 add('TrapjawAnt',pair('大颚猛蚁','Trap-jaw ant'),'UI_Creature_TrapJaw_Square_Icon',{'大颚猛蚁'},{{version='0.1.18',sections={
  historical(pair('加入四个可购买技能','Four purchasable skills'),pair('加入「快速恢复」「暂避锋芒」「危险回避」「捕鼠夹」两组技能分支。技能可以在生物适应中购买，并在关前选兵时调整。','Added Rapid Recovery, Evasive Retreat, Danger Avoidance and Mousetrap as two skill branches. Skills can be purchased in Biological Adaptation and changed in the pre-mission selector.')),
  historical(pair('保留数值培养','Keep existing stat upgrades'),pair('技能选择与数值培养分开处理，原版和模组扩展的属性加点继续保留。','Skill choices remain separate from stat upgrades, preserving native and mod-added stat improvements.')),
 }}})
 add('SlaveMaker',pair('奴隶制造者兵蚁','Slave-maker soldier'),'UI_Creature_FormicaSanguinea_SlaveMaker_Square_Icon',{'奴隶制造者'},{{version='0.1.18',sections={
  historical(pair('升阶后可以俘虏敌人','Capture enemies after upgrading'),pair('升至二阶后，致命一击有机会改为打晕。友军把俘虏运到蚁后身边后进行转化，按物种合并显示在操控栏中，可以分配编队。','At level two, a lethal hit can knock prey out instead. Allies carry captives to the queen for conversion. Captives share a species entry in the control bar and can join groups.')),
  historical(pair('技能改变俘虏和支援方式','Skills improve capture and support'),pair('左侧技能强化俘虏概率或拓展可俘虏的体型；右侧技能为附近奴隶提供战斗或搬运支援。没有蚁后的模式仍然正常击杀。','The left branch improves capture chance or expands eligible prey sizes. The right branch supports nearby slaves in combat or carrying. Modes without a queen keep normal kills.')),
 }}})
 add('LittleBlackAnt',pair('小黑蚁','Little black ant'),'UI_Creature_LittleBlackAntSoldier_Square_Icon',{'小黑蚁的形态','小黑蚁的新技能'})
 add('StinkAnt',pair('非洲臭猛蚁','African stink ant'),'UI_Creature_AfricanStinkAnt_Square_Icon')
 add('ArmyAnt',pair('军蚁兵蚁','Army ant soldier'),'UI_Creature_EcitonBurchelli_ArmyAnt_Media_Square_Icon')
 add('ArmyAntMajor',pair('大型军蚁','Army ant major'),'UI_Creature_EcitonBurchelli_ArmyAnt_Major_Square_Icon')
 add('BigHeadedMajor',pair('大头蚁兵蚁','Big-headed ant soldier'),'UI_Creature_BigHeadedAnt_Soldier_Square_Icon')
 add('BigHeadedSuperSoldier',pair('大头蚁超级兵','Big-headed ant super soldier'),'UI_Creature_BigHeadedAnt_SuperSoldier_Square_Icon')
 add('LeafcutterSuperMajor',pair('切叶蚁超级兵','Leafcutter super major'),'UI_Creature_AttaCephalotes_SuperMajor_Square_Icon')
 local fs=options.fs or default_fs
 local path=options.path
 local read={};local last_error
 local function parse(value)
  if type(value)~='string'or #value>4096 then return nil end
  local payload,checksum=value:match('^(EAA_NOTICE_READ\t1\n.-)SHA256\t([0-9a-f]+)\n$')
  if not payload or #checksum~=64 or hash(payload)~=checksum then return nil end
  local result={}
  for line in payload:sub(19):gmatch('[^\n]+')do
   local id,token=line:match('^([%w]+)\t([0-9a-f]+)$')
   if not id or #token~=64 or result[id]then return nil end
   if by_id[id]then result[id]=token end
  end
  return result
 end
 local function read_file(file)
  local f=fs.open(file,'rb');if not f then return nil end
  local value=f:read(4097);f:close();return parse(value)
 end
 if path then read=read_file(path)or read_file(path..'.bak')or{}end
 local control={catalog=catalog,by_id=by_id,words=words,path=path}
 function control.unread(id)local e=by_id[id];return e and e.token~=nil and read[id]~=e.token or false end
 function control.unread_list(limit)
  local result={}
  for _,e in ipairs(catalog)do if control.unread(e.id)then result[#result+1]=e;if limit and #result>=limit then break end end end
  return result
 end
 function control.updated_list(limit)
  local result={}
  for _,e in ipairs(catalog)do if e.token then result[#result+1]=e;if limit and #result>=limit then break end end end
  return result
 end
 function control.mark_read(id)
  local e=assert(by_id[id],'unknown notice species')
  if not e.token then return true end
  read[id]=e.token
  if not path then return true end
  local ok,why=pcall(function()
   local rows={'EAA_NOTICE_READ\t1\n'}
   for _,entry in ipairs(catalog)do if read[entry.id]then rows[#rows+1]=entry.id..'\t'..read[entry.id]..'\n'end end
   local payload=table.concat(rows);payload=payload..'SHA256\t'..hash(payload)..'\n'
   local f=assert(fs.open(path..'.tmp','wb'));assert(f:write(payload));assert(f:close())
   local prior=fs.open(path,'rb')
   if prior then prior:close();fs.remove(path..'.bak');assert(fs.rename(path,path..'.bak'))end
   local renamed,err=fs.rename(path..'.tmp',path)
   if not renamed then if prior then fs.rename(path..'.bak',path)end;error(err or'notice read state commit failed')end
  end)
  if not ok then last_error=tostring(why);return nil,last_error end
  last_error=nil;return true
 end
 function control.error()return last_error end
 function control.general(lang)
  local result={{title=lang=='zh'and'公告改为按蚁种查看'or'A species-based announcement journal',
   text=lang=='zh'and'缩略栏保留最多三只本版有更新的蚂蚁，看完后不会移除或换位。放大后可以查看所有额外蚁种及本次、历史记录。看完返回，只清除放大列表中这只蚂蚁的更新标记和金光；之后有新改动时重新亮起。'or'The compact notice keeps up to three species updated in this version, with their positions unchanged after reading. Expand it to browse every extra species and its current and older changes. Returning clears only that species’ NEW badge and glow in the expanded list; a later update lights it up again.'}}
  for i,section in ipairs(legacy.languages[lang].sections)do
   if not species_sections[i]then result[#result+1]=section end
  end
  return result
 end
 return control
end
return M
