-- Change the native construction-price row, so quotes and actual C++ payment
-- share one value. No UI-price override, refund, per-frame scan, or stat changes.
local M={row_name='TrapJawBuild',native_cost=90,build_cost=80}
local function safe(fn)local ok,value=pcall(fn);if ok then return value end end
function M.install(o)
 local native=assert(o.native)
 local valid=assert(native.valid_object)
 local records,seen={},{}
 local enabled,next_check=true,0
 local stats={changed=0,restored=0,unsupported=0,conflicts=0}
 local function identity(value)
  if not valid(value)then return nil end
  return safe(function()return tostring(value:GetAddress())end)
 end
 local function row_of(value)
  -- FindRow returns a reference to the native row. The fallback supports pinned
  -- UE4SS builds which expose only GetRowMap, also with reference-based rows.
  local row=safe(function()return value:FindRow(M.row_name)end)
  if row~=nil then return row end
  return safe(function()return value:GetRowMap()[M.row_name]end)
 end
 local function report(message)
  pcall(o.log or print,'[TrapjawBalance] '..message)
 end
 local function patch(value)
  local key=identity(value)
  if not key or seen[key]then return end
  seen[key]=true
  local row=row_of(value)
  local before=tonumber(safe(function()return row.Cost end))
  if before==M.build_cost then return end
  if before~=M.native_cost then
   stats.unsupported=stats.unsupported+1
   report('construction row not patched; expected '..M.native_cost..', got '..tostring(before))
   return
  end
  local changed=safe(function()row.Cost=M.build_cost;return tonumber(row_of(value).Cost)==M.build_cost end)
  if changed~=true then
   -- A failed reference check must not leave a partial, untracked mutation.
   if safe(function()return tonumber(row.Cost)==M.build_cost end)then
    safe(function()row.Cost=before end)
   end
   stats.unsupported=stats.unsupported+1
   report('native construction row unavailable for writing')
   return
  end
  records[key]={object=value,original=before}
  stats.changed=stats.changed+1
  report('TrapJawBuild '..before..' -> '..M.build_cost..'; hatch and upgrade rows unchanged')
 end
 local api={stats=stats}
 function api.tick(force)
  if not enabled then return end
  local now=(o.now or os.clock)()
  if not force and now<next_check then return end
  next_check=now+1
  local context=safe(o.get_context)
  local gs=context and context.gs
  if not valid(gs)then return end
  patch(safe(function()return gs.GameplayCosts end))
  patch(safe(function()return gs.GameplayCostsFreeplay end))
 end
 function api.stop()
  if not enabled then return end
  enabled=false
  for key,record in pairs(records)do
   if identity(record.object)==key then
    local row=row_of(record.object)
    local current=tonumber(safe(function()return row.Cost end))
    if current==M.build_cost then
     if safe(function()row.Cost=record.original;return tonumber(row.Cost)==record.original end)then
      stats.restored=stats.restored+1
     end
    elseif current~=nil then stats.conflicts=stats.conflicts+1 end
   end
  end
  records,seen={},{}
 end
 return api
end
return M
