-- Body sweeps and underground tile clearance for cooperative executions.
local M={half_size={X=52,Y=37,Z=16},height=10,clearance=3,channels={0,4}}
local function vec(p)return {X=p.X,Y=p.Y,Z=p.Z}end
function M.install(o)
 local api={checks=0,shortened=0,gridChecks=0}
 function api.limit(actor,start,finish,ignored)
  local dx,dy,dz=finish.X-start.X,finish.Y-start.Y,finish.Z-start.Z
  local length=math.sqrt(dx*dx+dy*dy+dz*dz)
  if length<.001 then return vec(start),{blocked=false,length=0,requested=length}end
  local yaw=math.deg(math.atan(dy,dx))
  local from,to=vec(start),vec(finish);from.Z=from.Z+M.height;to.Z=to.Z+M.height
  local fraction,channel=1,nil
  for _,kind in ipairs(M.channels)do
   api.checks=api.checks+1
   local blocked,hit=o.trace(actor,from,to,M.half_size,{Pitch=0,Yaw=yaw,Roll=0},kind,ignored)
   assert(type(blocked)=='boolean','path_guard_trace_failed')
   if blocked then
    local time=tonumber(hit.Time)
    assert(time and time==time and time>=0 and time<=1,'path_guard_hit_time_invalid')
    -- UE4SS exposes the packed hit booleans as aliases in this build.
    -- A genuine initial overlap already has Time=0; use the numeric sweep time.
    if time<fraction then fraction,channel=time,kind end
   end
  end
  local safe=channel and math.max(0,length*fraction-M.clearance)or length
  local gridBlocked=false
  if o.walkable then
   local planar=math.sqrt(dx*dx+dy*dy)
   local ux,uy=planar>0 and dx/planar or 1,planar>0 and dy/planar or 0
   local function clear(at,all)
    local cx,cy,cz=start.X+dx*at/length,start.Y+dy*at/length,start.Z+dz*at/length
    local forwards=all and{-M.half_size.X,0,M.half_size.X}or{M.half_size.X}
    for _,ahead in ipairs(forwards)do for _,side in ipairs({-M.half_size.Y,0,M.half_size.Y})do
     api.gridChecks=api.gridChecks+1
     if not o.walkable(actor,{X=cx+ux*ahead-uy*side,Y=cy+uy*ahead+ux*side,Z=cz})then return false end
    end end
    return true
   end
   if not clear(0,true)then safe=0;gridBlocked=true
   else
    local previous,at=0,math.min(20,safe)
    while at>previous do
     if not clear(at,false)then
      local low,high=previous,at
      while high-low>.05 do local mid=(low+high)/2;if clear(mid,false)then low=mid else high=mid end end
      safe=math.max(0,low-M.clearance);gridBlocked=true;break
     end
     previous=at;at=math.min(at+20,safe)
    end
   end
  end
  if channel or gridBlocked then api.shortened=api.shortened+1 end
  return {X=start.X+dx*safe/length,Y=start.Y+dy*safe/length,Z=start.Z+dz*safe/length},
   {blocked=channel~=nil or gridBlocked,channel=channel,gridBlocked=gridBlocked,length=safe,requested=length,fraction=fraction,clearance=M.clearance}
 end
 return api
end
return M
