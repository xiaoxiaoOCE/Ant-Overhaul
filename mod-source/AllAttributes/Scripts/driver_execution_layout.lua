-- Derive roles and trajectories from current positions. No actor mutations.
local M={exit_distance=200,cross_distance=130}
local function p(v)return{X=v.X,Y=v.Y,Z=v.Z}end
function M.build(starts,target,forwards)
 assert(#starts==3,'execution_requires_three_current_positions')
 local holder,best=1,math.huge
 for i,s in ipairs(starts)do
  local d=(s.X-target.X)^2+(s.Y-target.Y)^2
  if d<best then holder,best=i,d end
 end
 local order={holder};for i=1,3 do if i~=holder then order[#order+1]=i end end
 local result={order=order,target=p(target),members={}}
 for role,index in ipairs(order)do
  local start=p(starts[index]);local dx,dy=target.X-start.X,target.Y-start.Y
  local length=math.sqrt(dx*dx+dy*dy)
  if length<.001 then
   local f=forwards and forwards[index]or{X=1,Y=0};dx,dy=f.X,f.Y;local n=math.sqrt(dx*dx+dy*dy)
   if n<.001 then dx,dy,n=1,0,1 end
   dx,dy=dx/n,dy/n
  else dx,dy=dx/length,dy/length end
  local row={originalIndex=index,role=role,start=start,startDistance=length,direction={X=dx,Y=dy,Z=0},yaw=math.deg(math.atan(dy,dx))}
  row.finish={X=target.X+dx*M.exit_distance,Y=target.Y+dy*M.exit_distance,Z=start.Z}
  row.holderRetreat={X=start.X-dx*18,Y=start.Y-dy*18,Z=start.Z}
  result.members[role]=row
 end
 return result
end
function M.position(row,time,safeLength)
 local cross=math.max(0,math.min(1,(time-1.2)/.22))
 local braking=math.max(0,math.min(1,(time-1.42)/.79))
 local first=math.min(safeLength,row.startDistance+M.cross_distance)
 local follow=math.max(0,safeLength-first)*(2*braking-braking*braking)
 local distance=first*cross+follow
 return {X=row.start.X+row.direction.X*distance,Y=row.start.Y+row.direction.Y*distance,Z=row.start.Z}
end
return M
