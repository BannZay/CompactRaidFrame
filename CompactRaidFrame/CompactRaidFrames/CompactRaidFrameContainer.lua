MAX_RAID_GROUPS = 8;

local frameCreationSpecifiers = {
    raid = { mapping = UnitGUID, setUpFunc = DefaultCompactUnitFrameSetup, updateList = "normal" },
    pet =  { setUpFunc = DefaultCompactMiniFrameSetup, updateList = "mini" },
    flagged = { mapping = UnitGUID, setUpFunc = DefaultCompactUnitFrameSetup, updateList = "normal" },
    target = { setUpFunc = DefaultCompactMiniFrameSetup, updateList = "mini" },
    frameReplacement = { setUpFunc = FrameReplacementCompactUnitFrameSetup, updateList = "frameReplacement" },
}

--Widget Handlers
function CompactRaidFrameContainer_OnLoad(self)
    FlowContainer_Initialize(self)

    self:SetClampRectInsets(0, 200 - self:GetWidth(), 10, 0);

    self.raidUnits = {--[["raid1", "raid2", "raid3", ..., "raid40"]]};
    for i = 1, MAX_RAID_MEMBERS do
        tinsert(self.raidUnits, "raid"..i);
    end
    self.partyUnits = { "player" };
    for i = 1, MAX_PARTY_MEMBERS do
        tinsert(self.partyUnits, "party"..i);
    end

    CompactRaidFrameContainer_UpdateDisplayedUnits(self);

    self:RegisterEvent("PARTY_MEMBERS_CHANGED");
    self:RegisterEvent("PLAYER_ENTERING_WORLD");
    self:RegisterEvent("UNIT_PET");

    local unitFrameReleaseFunc = function(frame)
        CompactUnitFrame_SetUnit(frame, nil);
    end;
    self.frameReservations = {
        raid    = CompactRaidFrameReservation_NewManager(unitFrameReleaseFunc);
        pet     = CompactRaidFrameReservation_NewManager(unitFrameReleaseFunc);
        flagged = CompactRaidFrameReservation_NewManager(unitFrameReleaseFunc); --For Main Tank/Assist units
        target  = CompactRaidFrameReservation_NewManager(unitFrameReleaseFunc); --Target of target for Main Tank/Main Assist
        frameReplacement  = CompactRaidFrameReservation_NewManager(unitFrameReleaseFunc);
    }

    self.frameUpdateList = {
        normal = {},    --Groups are also in this normal list.
        mini = {},
        group = {},
        frameReplacement = {},
    }
    self.unitFrameUnusedFunc = function(frame)
            frame.inUse = false;
        end;

    self.displayPets = true;
    self.keepPetsCloseToOwner = true;
    self.displayFlaggedMembers = true;
end

function CompactRaidFrameContainer_OnEvent(self, event, ...)
    if ( InCombatLockdown() ) then
        self:RegisterEvent("PLAYER_REGEN_ENABLED");
        return;
    end

    if ( event == "PARTY_MEMBERS_CHANGED" ) then
        CompactRaidFrameContainer_UpdateDisplayedUnits(self);
        CompactRaidFrameContainer_TryUpdate(self);
    elseif ( event == "PLAYER_ENTERING_WORLD" ) then
        CompactRaidFrameContainer_UpdateDisplayedUnits(self);
        CompactRaidFrameContainer_TryUpdate(self);
    elseif ( event == "UNIT_PET" ) then
        if ( self.displayPets ) then
            local unit = ...;
            if ( unit == "player" or strsub(unit, 1, 4) == "raid" or strsub(unit, 1, 5) == "party" ) then
                CompactRaidFrameContainer_TryUpdate(self);
            end
        end
    elseif ( event == "PLAYER_REGEN_ENABLED" ) then
        CompactRaidFrameContainer_UpdateDisplayedUnits(self);
        CompactRaidFrameContainer_TryUpdate(self);
        self:UnregisterEvent("PLAYER_REGEN_ENABLED");
    end
end

function CompactRaidFrameContainer_OnSizeChanged(self)
    FlowContainer_DoLayout(self);
    CompactRaidFrameContainer_UpdateBorder(self);
end
--Externally used functions
function CompactRaidFrameContainer_SetGroupMode(self, groupMode)
    self.groupMode = groupMode;
    CompactRaidFrameContainer_TryUpdate(self);
end

function CompactRaidFrameContainer_SetFlowFilterFunction(self, flowFilterFunc)
    --Usage: flowFilterFunc is called as flowFilterFunc("unittoken") and should return whether this frame should be displayed or not.
    self.flowFilterFunc = flowFilterFunc;
    CompactRaidFrameContainer_TryUpdate(self);
end

function CompactRaidFrameContainer_SetGroupFilterFunction(self, groupFilterFunc)
    --Usage: groupFilterFunc is called as groupFilterFunc(groupNum) and should return whether this group should be displayed or not.
    self.groupFilterFunc = groupFilterFunc;
    CompactRaidFrameContainer_TryUpdate(self);
end

function CompactRaidFrameContainer_SetFlowSortFunction(self, flowSortFunc)
    --Usage: Takes two tokens, should work as a Lua sort function.
    --The ordering must be well-defined, even across units that will be filtered out
    self.flowSortFunc = flowSortFunc;
    CompactRaidFrameContainer_TryUpdate(self);
end

function CompactRaidFrameContainer_KeepPetsCloseToOwner(self, keepPetsCloseToOwner)
    if ( self.keepPetsCloseToOwner ~= keepPetsCloseToOwner ) then
        self.keepPetsCloseToOwner = keepPetsCloseToOwner;
        CompactRaidFrameContainer_TryUpdate(self);
    end
end

function CompactRaidFrameContainer_SetDisplayPets(self, displayPets)
    if ( self.displayPets ~= displayPets ) then
        self.displayPets = displayPets;
        CompactRaidFrameContainer_TryUpdate(self);
    end
end

function CompactRaidFrameContainer_SetDisplayMainTankAndAssist(self, displayFlaggedMembers)
    if ( self.displayFlaggedMembers ~= displayFlaggedMembers ) then
        self.displayFlaggedMembers = displayFlaggedMembers;
        CompactRaidFrameContainer_TryUpdate(self);
    end
end

function CompactRaidFrameContainer_SetBorderShown(self, showBorder)
    self.showBorder = showBorder;
    CompactRaidFrameContainer_UpdateBorder(self);
end

function CompactRaidFrameContainer_SetReplaceTarget(self, replaceTarget)
    self.ReplaceTarget = replaceTarget;
    CompactRaidFrameContainer_TryUpdate(self);
end

function CompactRaidFrameContainer_ApplyToFrames(self, updateSpecifier, func, ...)
    for specifier, list in pairs(self.frameUpdateList) do
        if ( updateSpecifier == "all" or specifier == updateSpecifier ) then
            for i=1, #list do
                list[i]:applyFunc(updateSpecifier, func, ...);
            end
        end
    end
end

--Internally used functions
function CompactRaidFrameContainer_TryUpdate(self)
    if ( CompactRaidFrameContainer_ReadyToUpdate(self) ) then
        CompactRaidFrameContainer_LayoutFrames(self);
    end
end

function CompactRaidFrameContainer_ReadyToUpdate(self)
    if ( not self.groupMode ) then
        return false
    end
    if ( self.groupMode == "flush" and not (self.flowFilterFunc and self.flowSortFunc) ) then
        return false;
    end
    if ( self.groupMode == "discrete" and not self.groupFilterFunc ) then
        return false;
    end

    return true;
end

function CompactRaidFrameContainer_UpdateDisplayedUnits(self)
    if ( IsInRaid() ) then
        self.units = self.raidUnits;
    else
        self.units = self.partyUnits;
    end
end

function CompactRaidFrameContainer_LayoutFrames(self)
    --First, mark everything we currently use as unused. We'll hide all the ones that are still unused at the end of this function. (On release)
    for i=1, #self.flowFrames do
        if ( type(self.flowFrames[i]) == "table" and self.flowFrames[i].unusedFunc ) then
            self.flowFrames[i]:unusedFunc();
        end
    end

    for i=1, #self.standaloneFrames do
        if ( type(self.standaloneFrames[i]) == "table" and self.standaloneFrames[i].unusedFunc ) then
            self.standaloneFrames[i]:unusedFunc();
        end
    end

    FlowContainer_RemoveAllObjects(self);

    FlowContainer_PauseUpdates(self);   --We don't want to update it every time we add an item.

    if ( self.displayFlaggedMembers ) then
        CompactRaidFrameContainer_AddFlaggedUnits(self);
        FlowContainer_AddLineBreak(self);
    end

    if ( self.groupMode == "discrete" ) then
        CompactRaidFrameContainer_AddGroups(self);
    elseif ( self.groupMode == "flush" ) then
        CompactRaidFrameContainer_AddPlayers(self);
    else
        error("Unknown group mode");
    end
    
    if ( self.ReplaceTarget ) then
       CompactRaidFrameContainer_ReplaceUnitFrames(self);
    end
    
    FlowContainer_ResumeUpdates(self);

    CompactRaidFrameContainer_UpdateBorder(self);

    CompactRaidFrameContainer_ReleaseAllReservedFrames(self);
end

function CompactRaidFrameContainer_UpdateBorder(self)
    local usedX, usedY = FlowContainer_GetUsedBounds(self);
    if ( self.showBorder and self.groupMode ~= "discrete" and usedX > 0 and usedY > 0 ) then
        self.borderFrame:SetSize(usedX + 11, usedY + 13);
        self.borderFrame:Show();
    else
        self.borderFrame:Hide();
    end
end

do
    local usedGroups = {}; --Enclosure to make sure usedGroups isn't used anywhere else.
    function CompactRaidFrameContainer_AddGroups(self)

        if ( IsInRaid() ) then
            RaidUtil_GetUsedGroups(usedGroups);

            for groupNum, isUsed in ipairs(usedGroups) do
                if ( isUsed and self.groupFilterFunc(groupNum) ) then
                    CompactRaidFrameContainer_AddGroup(self, groupNum);
                end
            end
        else
            CompactRaidFrameContainer_AddGroup(self, "PARTY");
        end
        FlowContainer_SetOrientation(self, "+")
        
        if ( self.displayPets ) then
            CompactRaidFrameContainer_AddPets(self);
        end
    end
end

function CompactRaidFrameContainer_AddGroup(self, id)
    local groupFrame, didCreation;

    if ( type(id) == "number" ) then
        groupFrame, didCreation = CompactRaidGroup_GenerateForGroup(id);
    elseif ( id == "PARTY" ) then
        groupFrame, didCreation = CompactPartyFrame_Generate();
    else
        error("Unknown id");
    end

    groupFrame:SetParent(self);
    groupFrame:SetFrameStrata("LOW");
    groupFrame.unusedFunc = groupFrame.Hide;
    if ( didCreation ) then
        tinsert(self.frameUpdateList.normal, groupFrame);
        tinsert(self.frameUpdateList.group, groupFrame);
    end

    FlowContainer_AddObject(self, groupFrame);

    groupFrame:Show();
end

local function ShouldDisplayFrame(unit)
    return CompactRaidFrameManager_GetSetting("DisplayPlayer") or (unit ~= "unit" and UnitGUID("player") ~= UnitGUID(unit))
end

local function GetPetId(unitId)
    if unitId == nil then
        return nil
    elseif ( string.sub(unitId, 1, 4) == "raid" ) then
        return "raidpet" .. string.sub(unitId, 5);
    elseif ( string.sub(unitId, 1, 5) == "party" ) then
        return "partypet" .. string.sub(unitId, 6);
    elseif ( unitId == "player" ) then
        return "pet";
    else
        error("not expected unitId = " .. unit);
    end
end

function CompactRaidFrameContainer_ReplaceUnitFrames(self)
    local targetFrame = CompactRaidFrameContainer_AddUnitFrame(self, "Target", "frameReplacement", true);
    
    local targetFrameTot = CompactRaidFrameContainer_AddUnitFrame(self, "TargetTarget", "frameReplacement", true);
    targetFrameTot:ClearAllPoints();
    targetFrameTot:SetPoint("BOTTOMRIGHT", targetFrame, "BOTTOMRIGHT", 0, -40);
    targetFrameTot:SetPoint("TOPLEFT", targetFrame, "BOTTOM", 0, 0);
    
    local focusFrame = CompactRaidFrameContainer_AddUnitFrame(self, "Focus", "frameReplacement", true);
end

function CompactRaidFrameContainer_AddPlayers(self)
    --First, sort the players we're going to use
    assert(self.flowSortFunc);  --No sort function defined! Call CompactRaidFrameContainer_SetFlowSortFunction.
    assert(self.flowFilterFunc);    --No filter function defined! Call CompactRaidFrameContainer_SetFlowFilterFunction.

    table.sort(self.units, self.flowSortFunc);
    
    for i=1, #self.units do
        local unit = self.units[i];
        
        if ( ShouldDisplayFrame(unit) ) then
            if ( self.flowFilterFunc(unit) ) then
                CompactRaidFrameContainer_AddUnitFrame(self, unit, "raid");
                if ( self.displayPets and self.keepPetsCloseToOwner ) then
                    local petId = GetPetId(unit)
                    if UnitExists(petId) then
                        CompactRaidFrameContainer_AddUnitFrame(self, petId, "pet");
                    end
                end
            end
        end
    end
    
    FlowContainer_SetOrientation(self, "vertical")

    if ( self.displayPets and not self.keepPetsCloseToOwner ) then
        CompactRaidFrameContainer_AddPets(self);
    end
end

function CompactRaidFrameContainer_AddPets(self)
    if ( IsInRaid() ) then
        for i=1, MAX_RAID_MEMBERS do
            local unit = "raidpet"..i;
            if ( ShouldDisplayFrame("raid"..i) and UnitExists(unit) ) then
                CompactRaidFrameContainer_AddUnitFrame(self, unit, "pet");
            end
        end
    else
        --Add the player's pet.
        if ( ShouldDisplayFrame("player") and UnitExists("pet") ) then
            CompactRaidFrameContainer_AddUnitFrame(self, "pet", "pet");
        end
        for i=1, GetNumSubgroupMembers() do
            local unit = "partypet"..i;
            if ( UnitExists(unit) ) then
                CompactRaidFrameContainer_AddUnitFrame(self, unit, "pet");
            end
        end
    end
end

local flaggedRoles = { "MAINTANK", "MAINASSIST" };
function CompactRaidFrameContainer_AddFlaggedUnits(self)
    if ( not IsInRaid() ) then
        return;
    end
    for roleIndex = 1, #flaggedRoles do
        local desiredRole = flaggedRoles[roleIndex]
        for i=1, MAX_RAID_MEMBERS do
            local unit = "raid"..i;
            local name, rank, subgroup, level, class, fileName, zone, online, isDead, role, isML = GetRaidRosterInfo(i);
            if ( role == desiredRole ) then
                FlowContainer_BeginAtomicAdd(self); --We want each unit to be right next to its target and target of target.

                CompactRaidFrameContainer_AddUnitFrame(self, unit, "flagged");

                --If we want to display the tank/assist target...
                local targetFrame = CompactRaidFrameContainer_AddUnitFrame(self, unit.."target", "target");
                CompactUnitFrame_SetUpdateAllOnUpdate(targetFrame, true);

                --Target of target?
                local targetOfTargetFrame = CompactRaidFrameContainer_AddUnitFrame(self, unit.."targettarget", "target");
                CompactUnitFrame_SetUpdateAllOnUpdate(targetOfTargetFrame, true);

                --Add some space before the next one.
                --FlowContainer_AddSpacer(self, 36);

                FlowContainer_EndAtomicAdd(self);
            end
        end
    end
end

--Utility Functions
function CompactRaidFrameContainer_AddUnitFrame(self, unit, frameType, standalone)
    local info = frameCreationSpecifiers[frameType];
    local frame = CompactRaidFrameContainer_GetUnitFrame(self, unit, frameType, standalone);

    CompactUnitFrame_SetUnit(frame, unit);
    
    if standalone then
        FlowContainer_AddStandaloneObject(self, frame)
    else
        FlowContainer_AddObject(self, frame);
    end
    return frame;
end

local function applyFunc(unitFrame, updateSpecifier, func, ...)
    func(unitFrame, ...);
end

local unitFramesCreated = {}
function CompactRaidFrameContainer_GetUnitFrame(self, unit, frameType, standalone)
    local info = frameCreationSpecifiers[frameType];
    assert(info);
    assert(info.setUpFunc);

    --Get the mapping for re-using frames
    local mapping;
    if ( info.mapping ) then
        mapping = info.mapping(unit);
    else
        mapping = unit;
    end

    local frame = CompactRaidFrameReservation_GetFrame(self.frameReservations[frameType], mapping);
    if ( not frame ) then
        local name = standalone and "CompactRaidFrameStandalone" or "CompactRaidFrame" -- not to break existing addons that are relies on frame number
        
        if unitFramesCreated[name] == nil then
            unitFramesCreated[name] = 0
        end
        
        unitFramesCreated[name] = unitFramesCreated[name] + 1;
        
        frame = CreateFrame("Button",  name..unitFramesCreated[name], self, "CompactUnitFrameTemplate");
        frame.applyFunc = applyFunc;
        CompactUnitFrame_SetUpFrame(frame, info.setUpFunc, mapping);
        CompactUnitFrame_SetUpdateAllEvent(frame, "PARTY_MEMBERS_CHANGED");
        frame.unusedFunc = self.unitFrameUnusedFunc;
        tinsert(self.frameUpdateList[info.updateList], frame);
        CompactRaidFrameReservation_RegisterReservation(self.frameReservations[frameType], frame, mapping, standalone);

        RegisterStateDriver(frame, "shownState", "[group:party] show; [group:raid] show; [nogroup:party] hide");
        RegisterUnitWatch(frame);
    end

    frame.inUse = true;
    return frame;
end

function CompactRaidFrameContainer_ReleaseAllReservedFrames(self)
    for key, reservations in pairs(self.frameReservations) do
        CompactRaidFrameReservation_ReleaseUnusedReservations(reservations);
    end
end

function RaidUtil_GetUsedGroups(tab)    --Fills out the table with which groups have people.
    for i=1, MAX_RAID_GROUPS do
        tab[i] = false;
    end
    if ( IsInRaid() ) then
        for i=1, GetNumRaidMembers() do
            local name, rank, subgroup = GetRaidRosterInfo(i);
            tab[subgroup] = true;
        end
    end
    return tab;
end
