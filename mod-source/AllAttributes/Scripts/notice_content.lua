-- Player-facing V0.2 notes. Chinese and English sections must stay in the same order.
local portraits='/Game/UI/InGame/UIUpdate/CharacterIcons/SquareImages/'
local abilities='/Game/UI/InGame/TechTree/AbilityImages/'
local function asset(base,name)return base..name..'.'..name end
local black=asset(portraits,'UI_Creature_LittleBlackAntSoldier_Square_Icon')
local jaw=asset(portraits,'UI_Creature_TrapJaw_Square_Icon')
local driver=asset(portraits,'UI_Creature_DriverAnt_Major_Square_Icon')
local hunter=asset(portraits,'UI_Creature_DriverAnt_Soldier_Square_Icon')
local slaver=asset(portraits,'UI_Creature_FormicaSanguinea_SlaveMaker_Square_Icon')
local fixes=asset(abilities,'AbilityNimble')
local zh={
 revision='2026-11-16-release-0.2.0',version='0.2.0',release_date='26/11/16',title='蚂蚁大修 V0.2.0',status='V0.2.0',
 subtitle='26/11/16',
 expand='放大',collapse='收起',nexus='模组主页',switch_language='English',
 nexus_url='https://www.nexusmods.com/empiresoftheundergrowth/mods/29',
 highlights={
  {title='普通黑色行军蚁获得了更新',text='三蚁合猎可以发动处决，也能合力钳制更大的猎物。',icon=hunter},
  {title='大型黑色行军蚁获得了更新',text='冲锋可以保护友军，也可以进入带横扫与吸血的狂战状态。',icon=driver},
  {title='小黑蚁获得了更新',text='新增特化型与双生型，以及信息素、集群防御和魅惑技能。',icon=black},
 },
 sections={
  {title='新版安装与更新',icon=fixes,text='本版将配套资源整理为一个 PAK 文件。完整功能仍需随包的脚本与加载器，建议使用安装器；从旧版更新无需重新开档，请先正常保存并退出游戏。剧情关卡中途保存仍未开放。'},
  {title='养殖箱休整时可以调整三项数值',icon=fixes,text=table.concat({
   '养殖箱控制台默认关闭。先到「设置 → 常规」启用「养殖箱控制台」，点击「确定」保存设置，再在养殖箱休整时按 Shift + CapsLock 呼出；再按一次收起。控制台可以调整食物、最大人口和总领土。',
   '食物不能超过仓库容量。最大人口填 0 代表不限人口。总领土包含已经挖开的格子和剩余可挖额度，调整它不会直接帮你挖地。',
   '面板只在养殖箱休整时可用，养殖箱挑战和其他关卡里都不能使用。改完记得正常保存游戏。',
  },'\n\n')},
  {title='普通黑色行军蚁的合围技能',icon=hunter,text=table.concat({
   '新增四个技能，左右两组各选一个。',
   '蚕食鲸吞：三只本单位近战合猎同一只小型生物，且猎物生命低于七成时，就会发动处决。一只咬住猎物，另外两只蓄力后冲刺穿过它，沿途其他敌人也会受到约三倍攻击伤害。处决完成后，尸体食物增加约20%；原本不掉食物的，也会留下少量食物。',
   '处决中的三只兵蚁免疫抓取，并获得约45%的普通、毒液和范围减伤。处决完成前有人阵亡或受控，就会中断；如果只有一只冲刺成功，猎物会损失当时约四分之三的生命，而不会直接被处决。发动后需要冷却。',
   '插翅难逃：多只兵蚁可以合力钳住中型、大型和泰坦生物，体型越大，需要的兵蚁越多。猎物不能移动，攻速降低近一半，普攻伤害降低约三成；钳制者也不能移动或攻击，但会获得减伤。钳制有时间限制，有人阵亡或受控就会解除。',
   '插翅难逃不再按猎物的最大生命值持续扣血。咬持时仍用眩晕状态锁住参与者的移动和攻击，但不显示这项动作锁的眩晕图标；敌人招式造成的真实眩晕、困惑仍正常显示。撕裂伤口的易伤和刷新规则保留。',
   '猎物的部分特殊招式可以把钳制者甩开，落地时不会额外眩晕。被禁锢的目标会显示红色断足图标，能和嘲讽区分开。',
   '以战养战：亲手击杀猎物后，取用尸体的一部分食物，给附近受伤的同种兵蚁回血。每只单次最多恢复约两成最大生命，实际恢复多少取决于食物和伤势；一具尸体只能用一次。',
   '撕裂伤口：普攻和咬持会不断加深猎物的伤口，让它受到的近战物理普攻伤害最多提高约20%。其他友军和奴隶也能利用伤口多打伤害，但只有带此技能的普通黑色行军蚁能叠加和刷新伤口。受伤目标会冒出血红色液滴，特效会随伤口结束或单位死亡一起消失。',
  },'\n\n')},
  {title='黑色大型行军蚁的冲锋技能',icon=driver,text=table.concat({
   '新增四个技能，左右两组各选一个。选择任一左侧技能后，充能全满时会主动冲锋，支援附近正在交战的友军。每次冲锋都消耗一次充能，后续按原版条件触发的冲锋，也会获得所选技能的效果。',
   '冲锋陷阵：冲锋会嘲讽落点周围的敌人，并获得约10秒减伤，最高约80%，同时提高附近友军的物理与毒液抗性。撞中的敌人越多，眩晕越久；撞晕的敌人越多，保护效果越强。增益期间免疫抓取和斩杀。',
   '破釜沉舟：冲锋命中后进入约10秒狂战，提升攻速并获得普攻吸血，撞晕的敌人越多，加成越强。普攻还会横扫目标附近的小范围敌人，数量不限。普攻或横扫击杀敌人可以续时，但剩余狂战时间不会超过最初的约10秒。狂战期间免疫抓取和斩杀。',
   '蓄势待发：冲锋冷却缩短约20%，消耗的充能补得更快。',
   '厉兵秣马：额外储备一次冲撞充能，能多发动一次冲锋。',
  },'\n\n')},
  {title='小黑蚁的形态怎么选',icon=black,text=table.concat({
   '小黑蚁现在有两种形态。点击它的图标，就能像火蚁一样打开形态选择，两边都有静音视频预览。形态共用数值培养；在养殖箱切换时花少量蚁皇浆，关前和其他模式可以免费选。',
   '特化型：普通攻击改为尾针蛰击，造成毒液伤害，仍然可以让敌人困惑。',
   '双生型：二级巢格可以额外孵化一只一级副蚁；巢格升到三级后，副蚁也会升到二级。副蚁孵化和补生都免费，也会继承技能和数值培养。',
   '同一个巢格的两只小黑蚁，有任意一只阵亡，活着的那只就会获得约20%的攻击力和攻速加成，直到自己阵亡。同类加成不叠加。切回特化型后，巢格里的副蚁会移除。',
   '首次选择双生型时，会显示一条游玩小提示：大群体和密集交战可能影响流畅度，不同电脑的感受会有所差异。提示只显示一次，退出重进或新建存档后也不会重复，不限制选择和数量。',
  },'\n\n')},
  {title='小黑蚁的新技能',icon=asset(abilities,'AbilityFierce_Mother'),text=table.concat({
   '新增四个技能，两种形态都可以使用，左右两组各选一个。',
   '混乱信号：阵亡时有约10%的概率释放一小团信息素，让附近敌人短暂陷入困惑。',
   '进攻信号：阵亡时有机会释放信息素，让附近友军攻速提高约10%。最多叠加三层，每层各自计时。',
   '集群防御：同一层附近聚集超过15只存活友军时，自己受到的范围伤害降低约30%。',
   '群体魅惑：三级后，攻击造成的困惑会变成持续约两三秒的魅惑，让敌人转头攻击原本的队友。大型及更大的生物只会困惑；中型生物的魅惑结束后会短暂免疫，小型生物再次被魅惑会刷新时间。如果周围没有它原本的队友，就改为困惑。',
   '优化了小黑蚁密集交战时的技能判断，以及魅惑续期时对原目标的检查。目标在同一瞬间移动后，会按实时位置判断是否仍能维持魅惑。免费附蚁、等级、羁绊和信息素仍按原来的规则生效。',
  },'\n\n')},
  {title='大颚猛蚁怎么用回跳和尾刺',icon=jaw,text=table.concat({
   '大颚猛蚁的回跳现在也能进攻：弹开时，会重击刚刚攻击且还在近战范围内的敌人。第一次回跳后，改用尾刺蛰击，普通攻击造成毒液伤害。建造费用调整为80食物。',
   '新增四个技能，左右两组各选一个。',
   '快速恢复：回跳时回血翻倍，也就是+100%。',
   '暂避锋芒：受到致命伤害且回跳已经就绪时，保留1点生命，立刻回跳并短暂无敌。如果回跳还在冷却，就不能触发这次保命。',
   '危险回避：回跳冷却缩短约40%。',
   '特化尾刺：尾刺的攻击间隔缩短约25%。这个技能替换了之前的「捕鼠夹」。',
  },'\n\n')},
  {title='奴隶制造者的技能说明',icon=slaver,text=table.concat({
   '二阶就能俘虏，不用先买技能：打出致命一击时，有约25%的概率把可俘虏的敌人打晕。友军把它带到蚁后身边转化后，它会满血加入我方，出现在下方操控栏中，可以分配编队。相同物种合并显示。',
   '可以俘虏部分普通蚂蚁和能战斗的小型生物；蚁后、剧情专用单位等不在俘虏范围内。没有蚁后的模式仍然正常击杀，不会把敌人打晕等着转化。',
   '新增四个技能，左右两组各选一个。',
   '特调奴隶主：二阶起，致命一击打晕敌人的概率提高到约50%。',
   '强敌俘获：升到三阶后，也能打晕并俘虏部分中型生物。',
   '监工督战：本单位在附近时，友方奴隶的攻速提高约15%。',
   '协同搬运：本单位在附近时，友方奴隶搬运物品或单位的移动速度提高约15%。两种支援加成都不会因为附近有多只奴隶制造者而重复叠加。',
   '转化后的奴隶属于友军，可以战斗和接受调遣。也修正了同种奴隶不合并、拾取和分割食物异常、搬运时发呆，以及奴隶被算成敌人导致女王警报或无法过关的问题。',
  },'\n\n')},
  {title='其他改动和修复',icon=fixes,text=table.concat({
   '修复斗兽场左侧长列表超出屏幕的问题。内容较多时可以向下滚动，切换页面、左右阵营或分辨率后仍能正常操作。',
   '公告会跟随游戏语言显示中文或英文，放大后也可以手动切换。模组公告和官方公告按顺序排列，展开时不会互相遮住。',
   '修复中文用户名和存档路径下培养记录无法正常读写的问题，保留已有的培养记录。',
   '移除了 F8 卸载快捷键，避免在游玩时误触。',
   '优化大群蚂蚁同时攻击时的重复检查，减少周期性长卡顿；无效的单位记录也会分批清理，避免集中处理。',
   '培养属性按出生、升阶和载入等变化更新，避免反复扫描全场单位；没有奴隶时，操控栏检查会休眠。普通攻击会提前跳过用不到的技能检查；对象存活检查与斗兽场技能读取也减少了无用的引擎调用。大规模混战仍有性能开销，实际帧率受到同场单位数量和电脑性能影响。',
   '遇到问题可以通过下方「模组主页」反馈。请说明游戏版本、模组版本和复现步骤；如果有报错，也可以附上 UE4SS.log。',
  },'\n\n')},
  {title='还没做完的功能',icon=asset(abilities,'AbilityEfficient_Brood'),text=table.concat({
   '剧情关卡的保存和继续游玩还没做完，V0.2里仍然不能用。这个功能完成后，会再单独说明。',
  },'\n\n')},
 },
}
local en={
 revision=zh.revision,version=zh.version,release_date=zh.release_date,title='Ant Overhaul V0.2.0',status='V0.2.0',
 subtitle='26/11/16',
 expand='Expand',collapse='Close',nexus='Mod page',switch_language='中文',
 highlights={
  {title='Driver ant soldiers have been updated',text='Hunt in threes to execute small prey, or work together to pin larger creatures.',icon=hunter},
  {title='Large driver ant soldiers have been updated',text='Charge to protect allies, or enter a frenzy with cleaving attacks and lifesteal.',icon=driver},
  {title='Little black ants have been updated',text='Choose a specialist or twin form, with new pheromone, defense and charm skills.',icon=black},
 },
 sections={
  {title='Installing and updating this release',icon=fixes,text='The supporting assets are now combined into one PAK. The full mod still needs the bundled scripts and loader, so the installer is recommended. Updating does not require a new colony: save normally and exit the game first. Mid-mission story saving remains unavailable.'},
  {title='Adjust three values while resting in the formicarium',icon=fixes,text=table.concat({
   'The formicarium console is off by default. Enable Formicarium console in Settings → General and confirm with OK. Then press Shift + CapsLock while resting in the formicarium to show or hide the panel. It adjusts food, the population cap and total territory.',
   'Food cannot exceed storage capacity. Set the population cap to 0 for unlimited population. Total territory includes excavated tiles and your remaining digging allowance; changing it does not dig any tiles for you.',
   'The panel only works while resting in the formicarium. It is disabled during formicarium challenges and other missions. Remember to save normally after making changes.',
  },'\n\n')},
  {title='Cooperative driver ant hunting skills',icon=hunter,text=table.concat({
   'Four new skills: choose one from each of the two branches.',
   'Swarm Feast: three soldiers fighting the same small creature in melee can execute it once its health falls below 70%. One holds the prey while the other two wind up and dash through it. Other enemies along each dash take about three times the dasher\'s attack damage. A completed execution adds about 20% corpse food, and prey that normally drops none still leaves a little.',
   'The three soldiers are immune to grabs during the execution and take about 45% less normal, venom and area damage. A death or control effect before completion interrupts the move. If only one dash gets through, the prey loses about three quarters of its current health instead of being executed. The skill needs time to recharge.',
   'No Escape: soldiers can work together to hold medium, large and titan creatures. Bigger prey needs more captors. The prey cannot move, loses almost half its attack speed and deals about 30% less basic-attack damage. Captors cannot move or attack either, but take less damage. The pin has a time limit and breaks if a captor dies or is controlled.',
   'No Escape no longer drains a percentage of the prey\'s maximum health. Captors still use a stun effect to lock movement and attacks, but its overhead stun icon is hidden. Actual enemy stuns and confusion still display normally. Rending Wounds keeps its damage vulnerability and refresh rules.',
   'Some special moves can fling the captors away, without an extra stun on landing. Pinned targets show a red split-leg icon, distinct from taunt.',
   'Live off the Hunt: after a personal kill, spend some corpse food to heal nearby wounded soldiers of the same species. Each ant can recover up to about 20% of its maximum health per use, depending on food and injuries. Each corpse can only be used once.',
   'Rending Wounds: basic attacks and holding prey deepen its wounds, increasing damage taken from melee physical basic attacks by up to about 20%. Other allies and slaves benefit too, but only ordinary driver soldiers with this skill can build or refresh the wound. Wounded targets shed blood-red droplets until the wound ends or the unit dies.',
  },'\n\n')},
  {title='Black driver ant charge skills',icon=driver,text=table.concat({
   'Four new skills: choose one from each branch. Either left-branch skill lets the ant rush to help nearby fighting allies when its charges are full. Every Ram spends one charge. Later Rams still follow the native triggers and also grant the chosen skill effect.',
   'Rush to the Rescue: Ram taunts nearby enemies and grants about 10 seconds of damage reduction, up to about 80%, while boosting nearby allies\' physical and venom resistance. Hit more enemies to extend the stuns; stun more enemies for stronger protection. The ant is immune to grabs and executions while its own bonus lasts.',
   'Desperate Charge: landing Ram starts a roughly 10-second frenzy with faster attacks and basic-attack lifesteal. Stunning more enemies strengthens the bonuses. Basic attacks also cleave every enemy in a small area around the target, with no target-count limit. Basic-attack or cleave kills extend the frenzy, but its remaining time cannot exceed the original roughly 10 seconds. The ant is immune to grabs and executions during the frenzy.',
   'Ready to Charge: reduces Ram cooldown by about 20%, replenishing spent charges sooner.',
   'Battle Reserves: stores one extra Ram charge for an additional charge attack.',
  },'\n\n')},
  {title='Choosing a little black ant form',icon=black,text=table.concat({
   'Little black ants now have two forms. Click their portrait to open a fire-ant-style selector with silent video previews. Both forms share stat upgrades. Switching at home costs a little Royal Jelly; choosing before a mission or in other modes is free.',
   'Specialist: replaces the basic attack with a venom sting, while retaining the ability to confuse enemies.',
   'Twin: a level-two nursery hatches an extra level-one companion. At nursery level three, that companion reaches level two. Hatching and replacing companions is free, and they inherit skills and stat upgrades.',
   'Your first Twin choice shows a small gameplay note: large colonies and dense battles may affect smoothness, with the experience varying by system. The note appears only once, including across restarts and new saves. It does not limit your choices or ant numbers.',
   'When either ant from the same tile dies, its surviving nestmate gains about 20% attack damage and attack speed until its own death. This bonus does not stack. Switching back to specialist removes the companion from the tile.',
  },'\n\n')},
  {title='New little black ant skills',icon=asset(abilities,'AbilityFierce_Mother'),text=table.concat({
   'Four new skills, available to both forms. Choose one from each branch.',
   'Confusion Signal: dying has about a 10% chance to release a small pheromone cloud, briefly confusing nearby enemies.',
   'Attack Signal: dying can release pheromones that give nearby allies about 10% attack speed. It stacks up to three times, with each stack expiring separately.',
   'Swarm Guard: with more than 15 living allies nearby on the same layer, the ant takes about 30% less area damage.',
   'Charm: at level three, confusion from attacks becomes a charm lasting about two to three seconds, making the victim attack its former allies. Large and larger creatures are only confused. Medium creatures gain brief charm immunity afterward; another charm refreshes its duration on small creatures. With no former allies nearby to attack, the victim is confused instead.',
   'Reduced redundant skill checks during dense combat and repeated target checks when refreshing charm. A target that moves within the same instant is checked at its live position. Free siblings, ranks, the twin bond and pheromones retain their existing rules.',
  },'\n\n')},
  {title='Trap-jaw jumps and stings',icon=jaw,text=table.concat({
   'Trap-jaw retreats can now hurt the enemy: jumping back delivers a heavy hit to the ant\'s last target if it is still in melee range. After the first jump, the ant switches to a venom sting for its basic attack. Building a nursery now costs 80 food.',
   'Four new skills: choose one from each branch.',
   'Rapid Recovery: doubles healing from a retreat, or +100%.',
   'Evasive Retreat: a lethal hit leaves 1 health, triggers an immediate jump and briefly grants invulnerability, but only if the retreat is ready. It cannot save the ant while the jump is on cooldown.',
   'Danger Avoidance: reduces retreat cooldown by about 40%.',
   'Specialized Sting: shortens the sting attack interval by about 25%. This replaces the earlier Mousetrap skill.',
  },'\n\n')},
  {title='Slave-maker skill descriptions',icon=slaver,text=table.concat({
   'Capture is available at level two without buying a skill. A lethal hit has about a 25% chance to knock eligible prey out instead. Allies carry it to the queen for conversion, after which it joins your colony at full health. It appears in the control bar and can join groups; members of the same species share an entry.',
   'Some ordinary ants and small combat-capable creatures can be captured. Queens, story-specific units and similar protected targets cannot. Without a queen, slave-makers kill normally rather than knocking enemies out for conversion.',
   'Four new skills: choose one from each branch.',
   'Special Master: from level two, raises the chance of knocking prey out with a lethal hit to about 50%.',
   'Capture Stronger Prey: at level three, also allows some medium creatures to be knocked out and captured.',
   'Overseer Drill: nearby allied slaves gain about 15% attack speed while this soldier is present.',
   'Cooperative Hauling: nearby allied slaves move about 15% faster while carrying items or units. Neither support bonus stacks from having multiple slave-makers nearby.',
   'Converted slaves are allies that can fight and follow your orders. Fixed separate control-bar entries for the same species, problems picking up or harvesting food, carriers getting stuck, and slaves counting as enemies that triggered queen warnings or blocked mission completion.',
  },'\n\n')},
  {title='Other changes and fixes',icon=fixes,text=table.concat({
   'Fixed long lists extending beyond the left Battle Arena panel. Scroll to reach lower entries; switching pages, teams or resolution keeps the panel usable.',
   'The notice follows the game language in Chinese or English, with a manual language button in the expanded view. Mod and official notices stack without covering each other when expanded.',
   'Fixed reading and writing upgrade records when Windows usernames or save paths contain Chinese characters, while preserving existing upgrades.',
   'Removed the F8 uninstall shortcut to prevent accidental activation during play.',
   'Reduced repeated checks when many ants attack at once, cutting periodic battle stalls. Stale unit records are also cleaned up in small batches instead of all at once.',
   'Cultivation attributes update at birth, rank changes, loading and other relevant changes instead of repeatedly scanning every creature. Control-bar checks sleep when there are no slaves. Ordinary attacks skip irrelevant skill checks earlier; object lifetime checks and arena skill reads also avoid unnecessary engine calls. Large battles still have processing costs; frame rate depends on unit counts and hardware.',
   'Use the Mod page button below to report issues. Include the game version, mod version and steps to reproduce the problem. Attach UE4SS.log if an error occurred.',
  },'\n\n')},
  {title='Features still in development',icon=asset(abilities,'AbilityEfficient_Brood'),text=table.concat({
   'Saving and resuming story missions is still unfinished and is not available in V0.2. It will receive a separate announcement when ready.',
  },'\n\n')},
 },
}
return {revision=zh.revision,version=zh.version,release_date=zh.release_date,nexus_url=zh.nexus_url,languages={zh=zh,en=en}}
