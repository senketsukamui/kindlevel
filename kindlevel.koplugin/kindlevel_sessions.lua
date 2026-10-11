-- Stream original recorded intervals; do not retain every page event in memory.
local Sessions = {}
Sessions.__index = Sessions

function Sessions:new(gaps, breaks, now)
    local boundaries = {}
    for _, timestamp in ipairs(breaks or {}) do
        if type(timestamp) == "number" and timestamp <= now then boundaries[#boundaries + 1] = timestamp end
    end
    table.sort(boundaries)
    return setmetatable({gaps=gaps,breaks=boundaries,now=now,states={},best={}},self)
end

function Sessions:hasBreak(first,last)
    if last < first then return false end
    local low,high = 1,#self.breaks+1
    while low < high do
        local middle = math.floor((low+high)/2)
        if self.breaks[middle] < first then low=middle+1 else high=middle end
    end
    return self.breaks[low] ~= nil and self.breaks[low] <= last
end

function Sessions:add(book_id,start,duration)
    local finish = math.min(self.now,start+duration)
    if duration <= 0 or start > self.now or finish <= start then return end
    -- A native interval may span a pause while excluding its duration. Its exact
    -- before/after allocation is unknown, so exclude it from continuous sessions.
    if self:hasBreak(start+1,finish-1) then self.states={}; return end
    for _,gap in ipairs(self.gaps) do
        local state = self.states[gap]
        if not state or state.book_id ~= book_id or start > state.finish+gap
            or self:hasBreak(state.finish,start) then
            state={book_id=book_id,start=start,finish=finish,seconds=finish-start}
            self.states[gap]=state
        else
            -- Overlapping intervals count once; gaps contribute no reading time.
            state.seconds=state.seconds+math.max(0,finish-math.max(start,state.finish))
            state.finish=math.max(state.finish,finish)
        end
        if not self.best[gap] or state.seconds > self.best[gap].seconds then
            self.best[gap]={book_id=book_id,start=state.start,finish=state.finish,seconds=state.seconds}
        end
    end
end

return Sessions
