local L = AceLibrary("AceLocale-2.2"):new("NotGrid")
NotGrid = AceLibrary("AceAddon-2.0"):new("AceEvent-2.0")
NotGridOptions = {} -- After the addon is fully initialized WoW will fill this up with its saved variables if any

function NotGrid:OnInitialize()
	self.HealComm = AceLibrary("HealComm-1.0")
	self.Banzai = AceLibrary("Banzai-1.0") -- only reports as having aggro if someone with this library is targetting the mob and reporting that the mob is targeting said unit
	self.Gratuity = AceLibrary("Gratuity-2.0") -- for proximity checks using spells on player's hotbar
	self.UnitFrames = {}
	--proximity stuff
	self.ProximityVars = {} -- will hold vars related to proximity handling. Mostly world map stuff
	self:UpdateProximityMapVars() -- need to do this here so I have values on reloadui
	self:GetFortyYardSpell() -- queries the player's action bars for a 40 yard spell to use in proximity checking
	--
	self:CreateFrames()
end

function NotGrid:OnEnable()
	self.o = NotGridOptions -- Need to wait for addon to be fully initialized and saved variables loaded before I set this
	self:SetDefaultOptions() -- if NotGridOptions is empty(no saved varoables) this will fill it up with defaults
	self:DoDropDown()
	self:ConfigUnitFrames()
	self:RegisterEvent("PLAYER_ENTERING_WORLD","PositionFrames")
	self:RegisterEvent("RAID_ROSTER_UPDATE","PositionFrames")
	self:RegisterEvent("PARTY_MEMBERS_CHANGED","PositionFrames")
	--proximity stuff
	self:RegisterEvent("ZONE_CHANGED_NEW_AREA","UpdateProximityMapVars")
	self:RegisterEvent("ACTIONBAR_SLOT_CHANGED", "GetFortyYardSpell")
	for key in L.CombatEvents do
		self:RegisterEvent(key, "CombatEventHandle")
	end
	--
	if Clique then
		self.CliqueProfile = string.format(L["%s of %s"],GetUnitName("player"),GetRealmName())
	end
end

---------------
-- UNIT_MAIN -- Handles the healthbar, healthtext, healcommbar, healcommtext, ressurection, nametext, classcolor..
---------------

function NotGrid:UNIT_MAIN(f)
	local o = self.o
	local unitid = f.unit

	if UnitExists(unitid) then
		local name = UnitName(unitid)
		local shortname = string.sub(name, 1, o.namelength)
		local _,class = UnitClass(unitid)
		local color = RAID_CLASS_COLORS[class] or {r=1,g=0,b=1}
		local powertype = UnitPowerType(unitid)
		local pcolor = ManaBarColor[powertype]
		--update some stuff
		f.name = name
		--handle coloring text
		if o.colorunithealthbarbyclass then
			f.healthbar:SetStatusBarColor(color.r, color.g, color.b)
		end
		if o.colorunitnamehealthbyclass then
			f.namehealthtext:SetTextColor(color.r, color.g, color.b)
		end
		if o.colorunithealthbarbgbyclass then -- is this even a real option?
			f.healcommbar.bgtex:SetVertexColor(color.r-0.5,color.g-0.5,color.b-0.5,0.5)
		end

		f.powerbar:SetStatusBarColor(pcolor.r, pcolor.g, pcolor.b)

		if UnitIsConnected(unitid) then
			local healamount = self.HealComm:getHeal(name)
			local currhealth = UnitHealth(unitid)
			local maxhealth = UnitHealthMax(unitid)
			local deficit = maxhealth - currhealth
			local healtext
			local currpower = UnitMana(unitid)
			local maxpower = UnitManaMax(unitid)

			if healamount > 999 then
				healtext = string.format("+%.1fk", healamount/1000.0)
			else
				healtext = string.format("+%d", healamount)
			end

			f.healthbar:SetMinMaxValues(0, maxhealth)
			f.healthbar:SetValue(currhealth)

			f.powerbar:SetMinMaxValues(0, maxpower)
			f.powerbar:SetValue(currpower)

			if UnitIsDead(unitid) then
				self:UnitHealthZero(f, L["Dead"], shortname)
			elseif UnitIsGhost(unitid) or (deficit >= maxhealth) then -- we can't detect unitisghost if he's not in range so we do the additional conditional. It won't false report for "dead" because that's checked first. Still a lot of false reports. In BGs.
				self:UnitHealthZero(f, L["Ghost"], shortname)
			elseif currhealth/maxhealth*100 <= self.o.healththreshhold then
				local deficittext
				if deficit > 999 then
					deficittext = string.format("-%.1fk", deficit/1000.0)
				else
					deficittext = string.format("-%d", deficit)
				end
				f.namehealthtext:SetText(deficittext)
			else
				f.namehealthtext:SetText(shortname)
			end

			if healamount > 0 then
				self:SetIncHealFrame(f, healamount, currhealth, maxhealth)
				if self.o.showhealcommtext then
					f.healcommtext:SetText(healtext)
					f.healcommtext:Show()
				end
			else
				f.incheal:SetBackdropColor(0,0,0,0) -- instead of hiding the frame, which is parent to healthtext&inchealtext, I set its opacity to 0
				f.healcommtext:Hide()
			end

			if self.HealComm:UnitisResurrecting(unitname) then
				f.incres:Show()
			else
				f.incres:Hide()
			end
		else
			self:UnitHealthZero(f, "Offline", shortname)
		end
	end
end

function NotGrid:UnitHealthZero(f, state, shortname)
	f.namehealthtext:SetText(shortname.."\n"..state)
	f.incheal:SetBackdropColor(0,0,0,0) -- instead of hiding the frame, which is parent to healthtext&inchealtext, I set its opacity to 0
	f.healthbar:SetMinMaxValues(0, 1)
	f.healthbar:SetValue(0)
	f.powerbar:SetMinMaxValues(0, 1)
	f.powerbar:SetValue(0)
	f.healcommtext:Hide()
end

-----------------
-- UNIT_BORDER --
-----------------

function NotGrid:UNIT_BORDER(f) -- 
	local o = self.o
	local unitid = f.unit
	if UnitExists(unitid) then
		local name = UnitName(unitid)
		local targetname = UnitName("Target") -- could get erronous with pets
		local currmana = UnitMana(unitid)
		local maxmana = UnitManaMax(unitid)
		if o.tracktarget and targetname and targetname == name then
			f:SetBackdropBorderColor(unpack(o.targetcolor))
		elseif o.trackaggro and self.Banzai:GetUnitAggroByUnitId(unitid) then
			f:SetBackdropBorderColor(unpack(o.aggrowarningcolor))
		elseif o.trackmana and UnitPowerType(unitid) == 0 and currmana/maxmana*100 < o.manathreshhold and not UnitIsDeadOrGhost(unitid) then
			f:SetBackdropBorderColor(unpack(o.manawarningcolor))
		else
			f:SetBackdropBorderColor(unpack(o.unitbordercolor))
		end
	end
end

-------------------
-- On Unit Click --
-------------------

function NotGrid:ClickHandle(button)
	if button == "RightButton" and SpellIsTargeting() then
		SpellStopTargeting()
		return
	end
	if button == "LeftButton" then
		if SpellIsTargeting() then
			SpellTargetUnit(this.unit)
		elseif CursorHasItem() then
			DropItemOnUnit(this.unit)
		else
			TargetUnit(this.unit)
		end
	else --Thanks Luna :^)
		local name = UnitName(this.unit)
		local id = string.sub(this.unit,5)
		local unit = this.unit
		local menuFrame = FriendsDropDown
		menuFrame.displayMode = "MENU"
		menuFrame.initialize = function() UnitPopup_ShowMenu(getglobal(UIDROPDOWNMENU_OPEN_MENU), "PARTY", unit, name, id) end
		ToggleDropDownMenu(1, nil, FriendsDropDown, "cursor")
	end
end

function NotGrid:CliqueHandle(button) -- if/else for Clique handling is done in the frames.lua when creating the frame
	local a,c,s = IsAltKeyDown() or 0, IsControlKeyDown() or 0, IsShiftKeyDown() or 0
	local modifiers = a*1+c*2+s*4
	local foundspell = nil
	for _,value in CliqueDB["chars"][self.CliqueProfile][L["Default Friendly"]] do
		if value["button"] == button and value["modifiers"] == modifiers then
			if value["rank"] then
				foundspell = value["name"]..L["(Rank "]..value["rank"]..")" -- wew
			else
				foundspell = value["name"]
			end
			break
		end
	end
	if foundspell then
		local LastTarget = UnitName("target") -- I use this as a boolean because targetting by name can be erronous
		ClearTarget()
		if LazySpell then --_LazySpell quick and dirty fix
			local lsSpell,lsRank = LazySpell:ExtractSpell(foundspell)
			if self.HealComm.Spells[lsSpell] and lsRank == 1 then
				local lsRank = LazySpell:CalculateRank(lsSpell, this.unit)
				foundspell = lsSpell.."(Rank "..lsRank..")"
			end
		end
		CastSpellByName(foundspell) -- then cast it, but note that because we've cleared target to cast it we're just "spelltargeting"
		self:CliqueCanTarget()
		if SpellIsTargeting() and SpellCanTargetUnit(this.unit) then -- then come back to our own func and see if they can cast on the unit they wanted to cast on
			SpellTargetUnit(this.unit) -- if they can, cast on them
		elseif SpellIsTargeting() then
			SpellStopTargeting() -- otherwise stop targetting
		end
		if LastTarget then -- remember, use it as a boolean.
			TargetLastTarget() -- and finally, if they actually had an old target, then target it
		end
	else
		self:ClickHandle(button) -- if it failed to find anything in clique then we send it to the regular handler
	end
end