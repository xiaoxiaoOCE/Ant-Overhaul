-- Pure custom-skill records. No native struct fields or attribute ledger data.
local M={schema=1}
local HEADER='EAA_CUSTOM_SKILLS_V1'
local HEADER2='EAA_CUSTOM_SKILLS_V2'
local HEADER3='EAA_CUSTOM_SKILLS_V3'
local HEADER4='EAA_CUSTOM_SKILLS_V4'
local HEADER5='EAA_CUSTOM_SKILLS_V5'
local HEADER6='EAA_CUSTOM_SKILLS_V6'
local IDS={'TrapjawAnt','SlaveMaker','LittleBlackAnt','DriverAntLargeSoldier','DriverAntSoldier'}
local OPTIONS={
 TrapjawAnt={left={none=true,recovery=true,invulnerable=true},right={none=true,evasion=true,reward=true}},
 SlaveMaker={left={none=true,special_master=true,follow_step=true},right={none=true,overseer_drill=true,overseer_haul=true}},
 LittleBlackAnt={left={none=true,confusion_signal=true,attack_signal=true},right={none=true,swarm_guard=true,charm=true}},
 DriverAntLargeSoldier={left={none=true,rescue_guard=true,rescue_frenzy=true},right={none=true,ready_charge=true,extra_charge=true}},
 DriverAntSoldier={left={none=true,swarm_execute=true,collective_pin=true},right={none=true,war_feast=true,rend_wounds=true}},
}
local FORMS={specialist=true,twin=true}
local MAX_RECORDS,MAX_BYTES=8192,4194304
local function plain(t)return type(t)=='table'and getmetatable(t)==nil end
local function clone(t)if type(t)~='table'then return t end local r={};for k,v in pairs(t)do r[k]=clone(v)end;return r end
local function only(t,allowed)if not plain(t)then return false end;for k in pairs(t)do if not allowed[k]then return false end end;return true end
local function slot(s)return type(s)=='string'and #s>0 and #s<=96 and s:match('^[A-Za-z0-9_-]+$')end
local function anchor(s)return type(s)=='string'and #s==129 and s:match('^[a-f0-9]+:[a-f0-9]+$')and s:sub(65,65)==':'end
local function key(s,a)return s..':'..a end
local function keys(t)local r={};for k in pairs(t)do r[#r+1]=k end;table.sort(r);return r end
function M.normalize(choices)
 if not only(choices,OPTIONS)then return nil,'invalid_custom_skills' end
 local out={}
 for _,id in ipairs(IDS)do
  if choices[id]~=nil then
   if not only(choices[id],{left=true,right=true,form=id=='LittleBlackAnt'and true or nil})then return nil,'invalid_custom_skill_pair' end
   out[id]={}
   for _,side in ipairs({'left','right'})do
    local value=choices[id][side]or'none'
    if type(value)~='string'or not OPTIONS[id][side][value]then return nil,'unknown_custom_skill' end
    out[id][side]=value
   end
   if id=='LittleBlackAnt'then
    local form=choices[id].form or'specialist';if not FORMS[form]then return nil,'unknown_custom_form'end
    out[id].form=form
   end
  end
 end
 return out
end
function M.supports(id)return type(id)=='string'and OPTIONS[id]~=nil end
function M.empty()return {TrapjawAnt={left='none',right='none'}}end
function M.flat(choices,species)
 species=species or'TrapjawAnt';if not M.supports(species)then return nil end
 local value=M.normalize(choices);if not value then return nil end
 local row=value[species]or{}
 return {left=row.left~='none'and row.left or nil,right=row.right~='none'and row.right or nil,
  form=species=='LittleBlackAnt'and(row.form or'specialist')or nil}
end
function M.new()return{schema=1,records={}}end
local function equal(a,b)
 local x,y=M.normalize(a),M.normalize(b)
 if not x or not y then return false end
 for _,id in ipairs(IDS)do
  local l,r=x[id]or{},y[id]or{}
  if(l.left or'none')~=(r.left or'none')or(l.right or'none')~=(r.right or'none')then return false end
  if id=='LittleBlackAnt'and(l.form or'specialist')~=(r.form or'specialist')then return false end
 end
 return true
end
local function valid(state)
 if not only(state,{schema=true,records=true})or state.schema~=1 or not plain(state.records)then return nil,'invalid_skill_state' end
 local count=0
 for k,r in pairs(state.records)do
  count=count+1;if count>MAX_RECORDS then return nil,'too_many_skill_records'end
  if not only(r,{slot=true,anchor=true,choices=true})or not slot(r.slot)or not anchor(r.anchor)or k~=key(r.slot,r.anchor)then return nil,'invalid_skill_record'end
  local normalized,why=M.normalize(r.choices);if not normalized then return nil,why end
 end
 return true
end
function M.capture(state,name,fingerprint,choices,replace)
 local ok,why=valid(state);if not ok then return nil,why end
 if not slot(name)or not anchor(fingerprint)then return nil,'invalid_skill_binding'end
 local normalized;normalized,why=M.normalize(choices);if not normalized then return nil,why end
 local k=key(name,fingerprint);local previous=state.records[k]
 if previous and not replace and not equal(previous.choices,normalized)then return nil,'skill_fingerprint_collision'end
 local next_state=clone(state);next_state.records[k]={slot=name,anchor=fingerprint,choices=normalized}
 ok,why=valid(next_state);if not ok then return nil,why end
 return next_state
end
function M.lookup(state,name,fingerprint)
 local ok,why=valid(state);if not ok then return nil,why end
 if not slot(name)or not anchor(fingerprint)then return nil,'invalid_skill_binding'end
 local found=state.records[key(name,fingerprint)]
 if not found then return nil,'unknown_skill_fingerprint'end
 return clone(found.choices)
end
function M.encode(state)
 local ok,why=valid(state);if not ok then return nil,why end
 -- Keep old Trapjaw-only records byte-for-byte V1. V2 is needed only once
 -- a real Slaver choice exists, and old profiles retain their exact anchors.
 local extended,forms,driver,driver_left,hunter=false,false,false,false,false
 for _,r in pairs(state.records)do
  local s=r.choices.SlaveMaker
  if s and((s.left or'none')~='none'or(s.right or'none')~='none')then extended=true end
  local l=r.choices.LittleBlackAnt
  if l and((l.left or'none')~='none'or(l.right or'none')~='none'or(l.form or'specialist')~='specialist')then forms=true;extended=true end
  local d=r.choices.DriverAntLargeSoldier
  if d then
   if (d.left or'none')~='none' then driver_left=true end
   if driver_left or (d.right or'none')~='none' then driver=true;forms=true;extended=true end
  end
  local h=r.choices.DriverAntSoldier
  if h and((h.left or'none')~='none'or(h.right or'none')~='none')then hunter=true end
 end
 if hunter then extended,forms,driver,driver_left=true,true,true,true end
 local rows={hunter and HEADER6 or driver_left and HEADER5 or driver and HEADER4 or forms and HEADER3 or extended and HEADER2 or HEADER}
 for _,k in ipairs(keys(state.records))do
  local r=state.records[k];local c=r.choices.TrapjawAnt or{}
  local row={'PROFILE',r.slot,r.anchor,c.left or'none',c.right or'none'}
  if extended then local s=r.choices.SlaveMaker or{};row[6]=s.left or'none';row[7]=s.right or'none'end
  if forms then local l=r.choices.LittleBlackAnt or{};row[8]=l.left or'none';row[9]=l.right or'none';row[10]=l.form or'specialist'end
  if driver then
   local d=r.choices.DriverAntLargeSoldier or{}
   row[11]=d.right or'none'
   if driver_left then row[12]=d.left or'none'end
  end
  if hunter then local h=r.choices.DriverAntSoldier or{};row[13]=h.left or'none';row[14]=h.right or'none'end
  rows[#rows+1]=table.concat(row,'\t')
 end
 local bytes=table.concat(rows,'\n')..'\n';if #bytes>MAX_BYTES then return nil,'skill_state_too_large'end
 return bytes
end
function M.decode(bytes)
 if type(bytes)~='string'or #bytes==0 or #bytes>MAX_BYTES or bytes:sub(-1)~='\n'or bytes:find('\r',1,true)or bytes:find('%z')then return nil,'invalid_skill_framing'end
 local state=M.new();local index,extended,forms,driver,driver_left,hunter=0,false,false,false,false,false
 for line in bytes:gmatch('([^\n]*)\n')do
  index=index+1
  if index==1 then
   if line~=HEADER and line~=HEADER2 and line~=HEADER3 and line~=HEADER4 and line~=HEADER5 and line~=HEADER6 then return nil,'unknown_skill_schema'end
   hunter=line==HEADER6
   driver_left=hunter or line==HEADER5
   driver=driver_left or line==HEADER4;forms=driver or line==HEADER3;extended=line~=HEADER
  else
   local hunter_left,hunter_right='none','none'
   if hunter then
    line,hunter_left,hunter_right=line:match('^(.*)\t([a-z_]+)\t([a-z_]+)$')
    if not line or not OPTIONS.DriverAntSoldier.left[hunter_left]or not OPTIONS.DriverAntSoldier.right[hunter_right]then return nil,'invalid_skill_record'end
   end
   local left_choice='none'
   if driver_left then
    line,left_choice=line:match('^(.*)\t([a-z_]+)$')
    if not line or not OPTIONS.DriverAntLargeSoldier.left[left_choice]then return nil,'invalid_skill_record'end
   end
   local driver_right
   if driver then
    line,driver_right=line:match('^(.*)\t([a-z_]+)$')
    if not line or not OPTIONS.DriverAntLargeSoldier.right[driver_right]then return nil,'invalid_skill_record'end
   end
   local s,a,l,r,sl,sr,ll,lr,form
   if forms then
    s,a,l,r,sl,sr,ll,lr,form=line:match('^PROFILE\t([A-Za-z0-9_-]+)\t([a-f0-9:]+)\t([a-z_]+)\t([a-z_]+)\t([a-z_]+)\t([a-z_]+)\t([a-z_]+)\t([a-z_]+)\t([a-z_]+)$')
   elseif extended then
    s,a,l,r,sl,sr=line:match('^PROFILE\t([A-Za-z0-9_-]+)\t([a-f0-9:]+)\t([a-z_]+)\t([a-z_]+)\t([a-z_]+)\t([a-z_]+)$')
   else s,a,l,r=line:match('^PROFILE\t([A-Za-z0-9_-]+)\t([a-f0-9:]+)\t([a-z]+)\t([a-z]+)$')end
   if not s or not slot(s)or not anchor(a)or not OPTIONS.TrapjawAnt.left[l]or not OPTIONS.TrapjawAnt.right[r]
    or extended and(not OPTIONS.SlaveMaker.left[sl]or not OPTIONS.SlaveMaker.right[sr])
    or forms and(not OPTIONS.LittleBlackAnt.left[ll]or not OPTIONS.LittleBlackAnt.right[lr]or not FORMS[form])then return nil,'invalid_skill_record'end
   local k=key(s,a);if state.records[k]then return nil,'duplicate_skill_record'end
   state.records[k]={slot=s,anchor=a,choices={TrapjawAnt={left=l,right=r}}}
   if extended then state.records[k].choices.SlaveMaker={left=sl,right=sr}end
   if forms then state.records[k].choices.LittleBlackAnt={left=ll,right=lr,form=form}end
   if driver then state.records[k].choices.DriverAntLargeSoldier={left=left_choice,right=driver_right}end
   if hunter then state.records[k].choices.DriverAntSoldier={left=hunter_left,right=hunter_right}end
  end
 end
 local ok,why=valid(state);if not ok then return nil,why end
 return state
end
return M
