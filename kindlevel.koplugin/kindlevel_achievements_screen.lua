local Achievements=require("kindlevel_achievements")
local View={}
function View:achievementItems()
    local unlocks=self.owner.settings:readSetting("achievement_unlocks",{})
    local filter,items=self.achievement_filter or "all",{}
    for _,item in ipairs(Achievements.catalog) do
        if filter=="all" or filter=="earned" and unlocks[item.id] or filter=="locked" and not unlocks[item.id] or filter=="books" and item.group=="books" then items[#items+1]=item end
    end
    return items,unlocks
end
function View:achievementNext(direction)
    if self.achievement_detail then return true end
    local items=self:achievementItems()
    self.achievement_page=math.max(1,math.min(math.max(1,math.ceil(#items/3)),(self.achievement_page or 1)+direction))
    self:rebuild();return true
end
function View:achievementDetails(item,progress,unlock)
    -- Custom definitions can have long criteria; keep KOReader's full-text viewer available.
    if #item.description > 220 or #item.text > 90 then
        require("ui/uimanager"):show(require("ui/widget/infomessage"):new{
            text=item.text.."\n\n"..item.description.."\n\n"..(unlock and "Earned" or progress.label)
                .."\n\n"..tostring(item.xp).." XP reserved for future progression.",
        })
        return
    end
    self.achievement_detail={item=item,progress=progress,unlock=unlock};self:rebuild()
end
function View:achievementPanel()
    local p,width=self:px(28),self.width-self:px(56)
    if self.achievement_detail then
        local d=self.achievement_detail;local icon=self:px(80)
        self:rect(p,self:px(100),icon,icon,238);self:outline(p,self:px(100),icon,icon,180)
        self:addWidget(Achievements.iconWidget(d.item,self.owner.plugin_dir,self:px(42)),p+self:px(19),self:px(119))
        self:text(d.item.text,p,self:px(208),width,self:px(85),30,{bold=true})
        self:text(d.item.description,p,self:px(304),width,self:px(90),20,{gray=85})
        self:text(d.unlock and "EARNED · "..os.date("%d %b %Y",d.unlock.unlocked_at) or "IN PROGRESS",p,self:px(409),width,self:px(30),14,{single=true,mono=true,gray=85})
        self:text(d.unlock and "A little milestone, collected." or d.progress.label,p,self:px(459),width,self:px(60),24,{mono=not d.unlock})
        if not d.unlock then self:progress(p,self:px(532),width,d.progress.ratio,self:px(8)) end
        self:text(tostring(d.item.xp).." XP · Reserved for future progression",p,self:px(573),width,self:px(58),14,{mono=true,gray=85})
        self:button("Back to achievements",p,self.height-self:px(137),width,self:px(48),function() self.achievement_detail=nil;self:rebuild() end,false,"achievement-back")
        return
    end
    local context=self.owner.getAchievementContext and self.owner:getAchievementContext() or Achievements.context(self.owner)
    local items,unlocks=self:achievementItems();local earned=0
    for _,item in ipairs(Achievements.catalog) do if unlocks[item.id] then earned=earned+1 end end
    self:pageTitle("Little milestones",string.format("%d of %d earned",earned,#Achievements.catalog))
    local cell=width/4
    for i,filter in ipairs{{"all","All"},{"earned","Earned"},{"locked","Locked"},{"books","Quests"}} do
        local x=p+(i-1)*cell;local active=(self.achievement_filter or "all")==filter[1]
        if active then self:rect(x,self:px(169),cell-self:px(8),self:px(50),34) end
        self:text(filter[2],x,self:px(181),cell-self:px(8),self:px(30),18,{center=true,single=true,gray=active and 255 or 85})
        self:hit(x,self:px(169),cell-self:px(8),self:px(50),function() self.achievement_filter,self.achievement_page=filter[1],1;self:rebuild() end,"achievement-filter-"..filter[1])
    end
    local pages=math.max(1,math.ceil(#items/3));self.achievement_page=math.max(1,math.min(self.achievement_page or 1,pages))
    for slot=0,2 do
        local item=items[(self.achievement_page-1)*3+slot+1]
        if item then
            local y=self:px(241+slot*126);local progress,unlock=Achievements.progress(item,context),unlocks[item.id]
            local icon=self:px(72);self:rect(p,y,icon,icon,238);self:outline(p,y,icon,icon,180)
            self:addWidget(Achievements.iconWidget(item,self.owner.plugin_dir,self:px(36)),p+self:px(18),y+self:px(18))
            local tx,tw=p+self:px(99),width-self:px(99)
            self:text(item.text,tx,y-self:px(5),tw,self:px(36),22,{single=true,bold=true})
            local description=self:text(item.description,tx,y+self:px(34),tw,self:px(48),18,{gray=85,fit_height=true})
            local status_y=y+self:px(42)+description:getSize().h
            self:text(unlock and "Earned · "..os.date("%d %b %Y",unlock.unlocked_at) or progress.label,tx,status_y,tw,self:px(24),14,{single=true,mono=true,gray=85})
            if not unlock then self:progress(tx,status_y+self:px(29),tw,progress.ratio,self:px(6)) end
            if slot<2 then self:divider(y+self:px(122)) end
            self:hit(p,y-self:px(4),width,self:px(126),function() self:achievementDetails(item,progress,unlock) end,"achievement-details-"..item.id)
        end
    end
    if #items==0 then self:text("Your first milestone is still to come.\nKeep a little time for reading.",p,self:px(350),width,self:px(100),22,{gray=85}) end
    local y=self.height-self:px(137)
    self:button("‹",p,y,self:px(50),self:px(48),function() self:achievementNext(-1) end,false,"achievements-previous")
    self:text(string.format("%d / %d",self.achievement_page,pages),p+self:px(80),y+self:px(12),width-self:px(160),self:px(28),16,{single=true,mono=true,gray=85})
    self:button("›",self.width-p-self:px(50),y,self:px(50),self:px(48),function() self:achievementNext(1) end,false,"achievements-next")
end
return View
