-- A single owned native hatch credit, committed to the marked sibling role.
-- Native egg development, affordability, hatching and credit consumption remain
-- authoritative. Never refund food or infer a sibling from the tenant index.
local M={tile_type=18,batch_size=12}
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
 local ok,x=pcall(function()return v:get()end);if ok then return x end;return v
end
local function number(v)local x=tonumber(unbox(v));if x and x==x and x~=math.huge and x~=-math.huge then return x end end
local function text(v)v=unbox(v);if type(v)=='string'then return v end;return v and safe(function()return v:ToString()end)end
function M.install(o)
 local native,combat,is_extra=assert(o.native),assert(o.combat),assert(o.is_extra)
 local owned,reported,birth_guards={},{},{};local world,stopped;local masks={}
 local sensitive={};local poll_head,poll_tail,poll_count=nil,nil,0;local generation=0
 local api={}
 local function fail(e)e=tostring(e);if not reported[e]then reported[e]=true;if o.log then o.log('[LittleBlackTwinCost] '..e)end end;return nil,e end
 local function valid(v)return v~=nil and safe(function()return native.valid_object(v)end)==true end
 local function key(v)return valid(v)and tostring(v:GetAddress())end
 local function same(a,b)local k=key(a);return k~=nil and k==key(b)end
 local function remove_poll(row)
  if not row.poll_queued then return end
  if row.poll_generation~=generation then
   row.poll_previous=nil;row.poll_next=nil;row.poll_queued=nil;return
  end
  local previous,following=row.poll_previous,row.poll_next
  if previous then previous.poll_next=following else poll_head=following end
  if following then following.poll_previous=previous else poll_tail=previous end
  row.poll_previous=nil;row.poll_next=nil;row.poll_queued=nil;poll_count=poll_count-1
 end
 local function schedule(k,row)
  if owned[k]~=row then return end
  row.native_sensitive=row.native_sensitive or(row.timer~=nil and row.timer>0)
  if row.native_sensitive or row.consumed or row.masked then
   remove_poll(row);sensitive[k]=row
  else
   sensitive[k]=nil
   if not row.poll_queued then
    row.poll_key=k;row.poll_previous=poll_tail;row.poll_next=nil;row.poll_queued=true;row.poll_generation=generation
    if poll_tail then poll_tail.poll_next=row else poll_head=row end
    poll_tail=row;poll_count=poll_count+1
   end
  end
 end
 local function forget(k,row)
  remove_poll(row)
  if owned[k]==row then owned[k]=nil end
  if sensitive[k]==row then sensitive[k]=nil end
 end
 local function clear_world()
  owned={};masks={};birth_guards={};sensitive={};poll_head=nil;poll_tail=nil;poll_count=0;generation=generation+1
 end
 local function resolve(n)
  if stopped or not valid(n)then return end
  local ctx=combat.get();if not ctx or ctx.is_arena then return end
  if world and world~=ctx.world_id then clear_world()end;world=ctx.world_id
  if native.world_id(n)~=world then return end
  local tile=unbox(safe(function()return n.OwningTile end))
  if not valid(tile)or number(tile.TileFunction)~=M.tile_type or not same(tile.FunctionRepresentation,n)then return end
  return tile,ctx
 end
 local function matching(row)
  local n=row.nursery
  return valid(n)and n:GetFullName()==row.name and native.world_id(n)==row.world
 end
 local function counts(n,exclude)
  local tile=unbox(n.OwningTile);local a=n.Tennents
  local count=type(a)=='table'and type(a.GetArrayNum)~='function'and #a or number(a:GetArrayNum())
  assert(count and count>=0 and count<=2,'littleblack_cost_tenancy_invalid')
  local primary,extra=0,0
  for i=1,count do
   local c=unbox(a[i])
   if valid(c)and not same(c,exclude)and(number(c.Health)or 0)>0 then
    assert(text(c.CreatureName)=='LittleBlackAnt'and same(c.NurseryTile,tile),'littleblack_cost_foreign_tenant')
    if is_extra(c)then extra=extra+1 else primary=primary+1 end
   end
  end
  return primary,extra
 end
 local function free_state(n)
  local count=number(n.NoOfFreeHatches);local flag=unbox(n.NextSpawnIsFree)
  assert(count and count>=0 and count%1==0 and count<2147483647,'littleblack_cost_credit_count_invalid')
  assert(type(flag)=='boolean','littleblack_cost_credit_flag_invalid')
  return count,flag,number(safe(function()return n.FreeHatchTimer end))
 end
 local function owns_credit(row,matched_now)
  if row.consumed or row.masked or(not matched_now and not matching(row))then return false end
  local count,flag,timer=free_state(row.nursery)
  -- A native timed refill can replace, rather than append to, our allowance.
  -- Do not subtract from a newer native allowance, even if its count matches.
  if timer and row.timer and timer>row.timer+0.0001 then return false end
  if timer then row.timer=timer end
  return flag and count==row.armed_count
 end
 local function restore_base(row)
  if not owns_credit(row)then return false end
  local n=row.nursery
  n.NoOfFreeHatches=row.base_count;n.NextSpawnIsFree=row.base_flag
  return true
 end
 local function hold_hatch_timer(row)
  local timer=assert(number(row.nursery.HatchingTimer),'littleblack_cost_hatching_timer_invalid')
  row.saved_hatching_timer=timer;row.held_hatching_timer=math.max(timer,60)
  row.nursery.HatchingTimer=row.held_hatching_timer
 end
 local function release_hatch_timer(row)
  if row.saved_hatching_timer==nil or not matching(row)then return end
  local current=assert(number(row.nursery.HatchingTimer),'littleblack_cost_hatching_timer_invalid')
  -- Preserve a larger delay applied by native gameplay while saving. Our own
  -- temporary hold is not serialized in FUGTileSaveState, and restoring the
  -- pre-save remaining delay never accelerates the egg's development.
  if current<=row.held_hatching_timer then row.nursery.HatchingTimer=row.saved_hatching_timer end
  row.saved_hatching_timer=nil;row.held_hatching_timer=nil
 end
 local function retire(k,row)
  if not row.consumed and not row.masked then restore_base(row)end
  forget(k,row)
 end
 function api.reconcile(n,details)
  local ok,result=pcall(function()
   local tile,ctx=resolve(n);if not tile then return false end
   local k=key(n);local row=owned[k]
   if row and not matching(row)then forget(k,row);row=nil end
   local birth=birth_guards[k]
   if birth and matching(birth)then return {deferred='native_hatch_stack'}end
   -- The exact birth callback runs inside the original native Tick. That Tick
   -- still needs the flag for its cost visual and then consumes one credit.
   if row and row.consumed then return {deferred='native_credit_consumption'}end
   if row and row.masked then return {deferred='native_save_mask'}end
   local eligible=type(details)=='table'and details.form=='twin'and(number(details.rank)or 0)>=2 and details.capacity==2
   local primary,extra=counts(n)
   if not eligible or extra>0 then if row then retire(k,row)end;return false end
   if row then
    -- Once reserved, the next free birth remains a sibling even if the primary
    -- dies while its egg is developing. Primary replacement stays chargeable.
    if owns_credit(row)then return true end
    forget(k,row);row=nil
   end
   if primary~=1 or extra~=0 or #masks>0 then return false end
   local count,flag,timer=free_state(n)
   -- The native flag itself authorizes one hatch even with a zero counter.
   -- Represent that existing one-shot allowance explicitly before adding ours.
   local armed=(flag and count==0 and 1 or count)+1
   row={nursery=n,name=n:GetFullName(),world=ctx.world_id,base_count=count,base_flag=flag,
    armed_count=armed,timer=timer,consumed=false,
    native_sensitive=count>0 or flag or(timer~=nil and timer>0)}
   -- Write count before the flag so a partial write cannot leave an unowned
   -- permanent flag. Roll back only this exact receiver on failure.
   local changed,why=pcall(function()n.NoOfFreeHatches=armed;n.NextSpawnIsFree=true end)
   if not changed then
    if matching(row)then pcall(function()n.NoOfFreeHatches=count;n.NextSpawnIsFree=flag end)end
    error(why)
   end
   owned[k]=row;schedule(k,row);return true
  end)
  if not ok then return fail(result)end;return result
 end
 api.observe=api.reconcile
 function api.expected_birth_role(n,c)
  local ok,result=pcall(function()
   local tile=resolve(n);if not tile or not valid(c)or text(c.CreatureName)~='LittleBlackAnt'
    or not same(c.NurseryTile,tile)or native.world_id(c)~=world or unbox(n.LoadSpawn)~=false then return end
   local k=key(n);local row=owned[k]
   birth_guards[k]={nursery=n,name=n:GetFullName(),world=world}
   if not row or not owns_credit(row)then return end
   local _,extra=counts(n,c)
   assert(extra==0,'littleblack_cost_existing_sibling_blocks_free_birth')
   row.consumed=true;row.creature=c;row.creature_name=c:GetFullName()
   schedule(k,row)
   return 'extra'
  end)
  if not ok then return fail(result)end;return result
 end
 function api.tick()
  if stopped then return true end
  local ctx=combat.get();if not ctx then return true end
  if world and world~=ctx.world_id then clear_world()end;world=ctx.world_id
  birth_guards={}
  local ok,why=pcall(function()
   local current_generation=generation
   local function check_row(k,row)
    if owned[k]~=row then return end
    if row.consumed then
     -- Called by the engine timer after the native hatch stack has returned.
     -- Native owns the decrement; never remove a second credit here.
     forget(k,row)
    elseif not matching(row)or row.world~=world then forget(k,row)
    elseif generation~=current_generation or owned[k]~=row then return
    elseif row.masked then
     local timer=assert(number(row.nursery.HatchingTimer),'littleblack_cost_hatching_timer_invalid')
     if timer>(row.held_hatching_timer or 60)then row.saved_hatching_timer=timer end
     if timer<60 then row.nursery.HatchingTimer=60 end
     row.held_hatching_timer=math.max(row.held_hatching_timer or 60,timer,60)
    -- Reuse only the identity/world check just performed above. No native
    -- mutation or callback occurs between it and the credit field reads.
    elseif not owns_credit(row,true)then forget(k,row)end
   end
   -- Native allowances/countdown contention, save holds and completed births
   -- keep the original per-callback handling. Only an ordinary mod-only credit
   -- gets batched; hatch/reconcile/save still validate ownership synchronously.
   for k,row in pairs(sensitive)do
    if generation~=current_generation then return end
    check_row(k,row)
   end
   local remaining=math.min(poll_count,M.batch_size);local visited={}
   for _=1,remaining do
    if generation~=current_generation then return end
    local row=poll_head;if not row or visited[row]then break end;visited[row]=true
    local k=row.poll_key;remove_poll(row)
    -- Rotate before reflected reads, so a temporary property failure cannot
    -- strand the receipt. Critical callbacks remove it in O(1), with no dead
    -- queue entries accumulating during mass hatching/replacement.
    if owned[k]==row then schedule(k,row);check_row(k,row)end
   end
  end)
  if not ok then return fail(why)end;return true
 end
 function api.before_save()
  local mask={rows={}};masks[#masks+1]=mask
  local ok,why=pcall(function()
   for _,row in pairs(owned)do
    if not row.consumed and not row.masked and owns_credit(row)then
     -- The overlay's real save can run in a later frame. Suppress this one
     -- nursery's hatch while its free credit is masked, so it cannot spend
     -- food in that interval. Egg development and all other nurseries remain
     -- untouched. No large delay is written to the native tile save state.
     row.masked=true;mask.rows[#mask.rows+1]=row
     schedule(row.poll_key or key(row.nursery),row)
     hold_hatch_timer(row)
     row.nursery.NoOfFreeHatches=row.base_count;row.nursery.NextSpawnIsFree=row.base_flag
    end
   end
  end)
  if not ok then api.after_save(mask);return fail(why)end
  return mask
 end
 function api.after_save(mask)
  if not mask or masks[#masks]~=mask then return fail('littleblack_cost_save_mask_order')end
  masks[#masks]=nil
  local ok,why=pcall(function()
   for _,row in ipairs(mask.rows)do
    if matching(row)and owned[key(row.nursery)]==row and row.masked then
     release_hatch_timer(row)
     local count,flag,timer=free_state(row.nursery)
     if count==row.base_count and flag==row.base_flag then
      row.nursery.NoOfFreeHatches=row.armed_count;row.nursery.NextSpawnIsFree=true;row.timer=timer;row.masked=nil
      schedule(key(row.nursery),row)
     else forget(key(row.nursery),row)end
    end
   end
  end)
  if not ok then return fail(why)end;return true
 end
 function api.reset_cache()
  local errors={}
  for _,row in pairs(owned)do
   local ok,why=pcall(function()release_hatch_timer(row);restore_base(row)end)
   if not ok then errors[#errors+1]=tostring(why)end
  end
  clear_world();world=nil
  if #errors>0 then return fail(table.concat(errors,'; '))end;return true
 end
 function api.stop()local ok,why=api.reset_cache();stopped=true;return ok,why end
 function api.status()local n,p,s=0,0,0;for _,row in pairs(owned)do n=n+1;if row.consumed then p=p+1 end end;for _ in pairs(sensitive)do s=s+1 end;return{credits=n,consumed=p,world=world,stopped=stopped==true,poll_pending=poll_count,immediate=s}end
 return api
end
return M
