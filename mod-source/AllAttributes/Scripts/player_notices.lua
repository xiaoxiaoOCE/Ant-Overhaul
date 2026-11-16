-- Player-only UI preferences. Never reads or writes gameplay saves.
local M={filename='EAA_TwinPerformanceNotice_v1.ini'}
local PAYLOAD='EAA_PLAYER_NOTICE\t1\ntwin_performance\tseen\n'
M.words={
 zh={title='双生型 · 游玩小提示',button='知道了',body='双生型会让蚁群更加壮大。蚂蚁较多、交战密集时，流畅度可能有所波动；性能余量较少的电脑，可能会更早感受到变化。\n\n可以按自己的实际体验搭配阵容，后续版本也会继续优化。'},
 en={title='Twin form · A small gameplay note',button='Got it',body='Twins let your colony grow larger. With many ants or dense battles, you may notice some changes in smoothness. PCs with less performance headroom may notice this at smaller colony sizes.\n\nChoose the mix that feels comfortable for your system. Further optimizations are planned.'},
}
function M.copy(language)return M.words[type(language)=='string'and language:lower():match('^zh')and'zh'or'en']end
function M.new(o)
 assert(type(o)=='table'and type(o.path)=='string'and o.fs,'player_notice_preferences_required')
 local fs,path,shared=o.fs,o.path,o.shared or{}
 local key=path:gsub('\\','/'):lower()
 local row=shared[key];if not row then row={};shared[key]=row end
 local function read(p)
  local ok,f=pcall(fs.open,p,'rb');if not ok or not f then return false end
  local got,s=pcall(f.read,f,129);local closed,value=pcall(f.close,f)
  return got and closed and value~=nil and s==PAYLOAD
 end
 local api={}
 function api.seen()
  if row.seen then return true end
  if read(path)or read(path..'.bak')then row.seen=true end
  return row.seen==true
 end
 function api.claim()
  if api.seen()or row.pending then return nil end
  local token={};row.pending=token;return token
 end
 function api.abandon(token)if row.pending==token then row.pending=nil end end
 function api.mark_shown(token)
  if row.pending~=token then return nil,'player_notice_claim_expired'end
  -- A mounted notice was already visible. Keep it once per process even if
  -- disk access fails; persistence failure must never undo a form purchase.
  row.seen=true;row.pending=nil
  local moved,handle=false,nil
  local ok,why=pcall(function()
   local f=assert(fs.open(path..'.tmp','wb'))
   handle=f;assert(f:write(PAYLOAD));assert(f:close());handle=nil
   assert(read(path..'.tmp'),'player_notice_readback_failed')
   local prior=fs.open(path,'rb')
   if prior then
    assert(prior:close());fs.remove(path..'.bak')
    assert(fs.rename(path,path..'.bak'));moved=true
   end
   local renamed,err=fs.rename(path..'.tmp',path)
   if not renamed then
    if moved then fs.rename(path..'.bak',path);moved=false end
    error(err or'player_notice_commit_failed')
   end
  end)
  if handle then pcall(handle.close,handle)end
  if not ok then
   if moved then pcall(fs.rename,path..'.bak',path)end
   pcall(fs.remove,path..'.tmp');return nil,tostring(why)
  end
  return true
 end
 return api
end
return M
