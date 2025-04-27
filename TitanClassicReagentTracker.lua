-- **************************************************************************
-- * TitanClassicReagentTracker.lua
-- *
-- * By: Initial fork of Titan Reagent by L'ombra. Retrofitted for Classic by cliaz / Murd,
-- *     with a lot of help from the Titan Panel Development Team (Urnati) rewriting this to
-- *     support Titan Panel v8 
-- **************************************************************************

-- High level functional overview:
-- In broad terms, this addon:
--  - builds a list of all spells that your player class can know, grouped by reagent (see spellData.lua)
--  - checks which spells a player knows, and the reagents for those spells
--  - does some funky stuff to display the reagents in the Titan Panel bar using labels and font pixel calculations
--  - allows the player to track reagents for spells they know, and to buy those reagents from a vendor


local add_on, addon = ...   -- get the addon name and namespace

-- ******************************** Constants *******************************
local _G = getfenv(0);
local TITAN_REAGENTTRACKER_ID = "ReagentTracker"
local RT_BUTTON_NAME = "TitanPanelReagentTrackerButton"
local REAGENT_PRE = "TitanPanelReagentTracker"
local addon_frame = {} -- will be set later during 'on load' as the main addon frame with scripts
-- ******************************** Variables *******************************
local media = nil -- set at OnShow to take advantage of a Titan lib

-- setting this to true will enable a lot of debug messages being output on the wow chat
local debug = false -- true false 

-- Get the toon class so we know which reagents to track from spells table
local playerClass = select(2, UnitClass("player"))

local possessed = {}    -- store spells that the player knows here
local buttons = {}      -- store reagent frames created to show icon - count pairs

-- note: look at addon.registry to see variables saved between restarts

local spells = addon.spells[playerClass]    -- generate a list of all possible spells that a player's Class can know, and associated reagents
if not spells then return end               -- don't continue addon load if there are no reagents associated to our character class

-- looks funky but we need to calc width in pixels of " " (space) in the current Titan font
addon.font = "GameFontHighlightSmall"
addon.font_calc = {} -- fontstring set below after addon frame created
addon.font_calc_width = 0 -- set below after addon frame created

addon.label_default = "Reagent Tracker"
addon.reagent_width_total = 0 -- holds width of all visible reagent icon-count pairs


-- ******************************** Functions *******************************
local function num_out(num) -- debug to output shorter float values
	local res = ""
	if type(num) == 'number' then
		res = string.format("%.2f", num)
	else
		res = num
	end
	return res
end

local function dbg_out(msg) -- debug output
	local color = "|cffeda55f"
	print(color.."RT "..msg.."|r")
end

--[[
-- **************************************************************************
-- NAME : UpdateFont()
-- DESC : Calc the width in pixels of a " " (space) in the current Titan font
-- VARS : 
-- NOTE : Key calc to create plugin text.
-- **************************************************************************
--]]
local function UpdateFont()
	-- Once Titan is loaded per the TOC dependency, we can use one of the libs it includes
	if media == nil then
		media = LibStub("LibSharedMedia-3.0")
	else
		-- don't slam LibStub :)
	end
	local newfont = media:Fetch("font", TitanPanelGetVar("FontName"))
	if newfont == addon.font then
		-- no work needed
	else
		-- seems real funky :)
		-- Calc the width of a "0" in the font
		addon.font_calc:SetFont(newfont, TitanPanelGetVar("FontSize"))
		addon.font_calc_width = addon.font_calc:GetWidth()
		addon.font = newfont
		
		-- also set the font for the label
	end
end

--[[
-- **************************************************************************
-- NAME : UpdateText()
-- DESC : Create the plugin label and text for Titan (TitanPanelButton_UpdateButton)
-- VARS : 
-- NOTE : Key to create plugin text that will sit behind the reagent info.
-- **************************************************************************
--]]
local function UpdateText()

	--===
	--[[
	This section is the key trick / hack allowing the use of children frames.
	Titan calculates the plugin width for a combo based on the :
	- width of icon, if shown
	- width of label + plugin text
	So make the plugin text a string of spaces the same width as the children we want visible.
	
	WoW places child frames on top of the parent which helps us.
	--]]
	UpdateFont()

	local spaces = " " -- buffer
	addon.font_calc:SetText(" ") -- only way to get width on UI
	-- a touch dangerous, at least there is a max :)
	for idx = 1, 50 do 
		spaces = spaces.." "
		addon.font_calc:SetText(spaces)
		if addon.font_calc:GetWidth() >= addon.reagent_width_total then
			break
		else
			-- add another space
		end
	end
	
	-- The label (spaces) *should* cover the reagents now...
	if debug then
		dbg_out("UpdateText"
		.." "..num_out(addon.font_calc_width)..""
		.." "..num_out(addon.reagent_width_total)..""
		.." "..tostring(string.len(spaces))..""
		--.." "..tostring(addon.font)..""
		.." "..num_out(TitanPanelReagentTrackerButton:GetWidth())..""
		.." "..num_out(TitanPanelReagentTrackerButtonText:GetWidth())..""
		)
	end

	addon.tracker_text_buff = spaces
	--===

	return "", addon.tracker_text_buff
end

--[[
-- **************************************************************************
-- NAME : newReagent(parent, i)
-- DESC : Creates a Button Frame to display a reagent in Titan Panel
-- VARS : parent = the addon,
        : i = button ID
-- RET  : btn = the button frame, populated with default icon and count, which will be stored in the buttons table
-- NOTE : The way this is called means that a frame is made for every entry in the spell table (as per spellData.lua)
--      : for this class (priest, mage, rogue etc.), and as the player learns spells, the reagents for those spells
--      : are tracked and displayed.
-- **************************************************************************
--]]
local function newReagent(parent, i)

	local reagent_name = REAGENT_PRE..i
	local btn = CreateFrame("Button", reagent_name, parent)

	btn.icon = btn:CreateTexture()                      -- create the icon (texture) holder
	btn.icon:SetSize(16, 16)                            -- expect an icon of this size
    btn.icon:SetPoint("LEFT", btn, "LEFT", 0, 0)        -- Place leftmost and on top of the frame

	-- create count (text) holder
	btn.text = btn:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")   -- requires some font...
	btn.text:SetPoint("LEFT", btn.icon, "RIGHT", 0, 0)                          -- right of the icon

	btn.icon:SetTexture(134400)     -- Default : "?" icon, which will later be set with the reagent icon
	btn.text:SetText("00")          -- Default : no count

	if debug == true then
		dbg_out("newReagent"
		.." "..tostring(i)..""
		.." "..tostring(reagent_name)..""
		.." "..tostring(btn:IsShown())..""
		--.." "..num_out(iconWidth)..""
		.." "..btn.icon:GetTexture()..""
		.." "..btn.text:GetText()..""
		)
	end

	return btn
end

--[[
-- **************************************************************************
-- NAME : onUpdate(self, refresh)
-- DESC : Update the button text in response to game events
-- VARS : self = the addon frame,
        : refresh = refresh the reagents tracker if true
-- NOTE : Then tell Titan to refresh the button whereever the user placed it
-- **************************************************************************
--]]
local function onUpdate(self, refresh)
	if refresh == true then
		addon:RefreshReagents()
	end
	addon:UpdateButton()

	TitanPanelButton_UpdateButton(TITAN_REAGENTTRACKER_ID);
end

--[[
-- **************************************************************************
-- NAME : OnShow(self)
-- DESC : React to the user placing on Titan or on login/reload
-- VARS : self = the addon frame,
-- NOTE : Save some cycles by registering for events only if user is using;
          Update the font (for label calc);
		  Then update the plugin for the user
-- **************************************************************************
--]]
local function OnShow(self)
	-- tell the addon which events from the game it should be aware of
	-- Moved registration of events here to ensure Titan is up and ready
	-- WoW does not guarentee order of events to addons!
	self:RegisterEvent("LEARNED_SPELL_IN_TAB")
	self:RegisterEvent("MERCHANT_SHOW")
    self:RegisterEvent("BAG_UPDATE")

	-- Handle the label here as it is unlikely to change;
	-- it is used to calc offset of first reagent
	UpdateFont()
	local label = addon.label_default
	addon.label_fontstr:SetText(label)
	addon.label_fontstr_width = addon.label_fontstr:GetWidth()

	onUpdate(self, true) -- Now update the plugin for the user
end

--[[
-- **************************************************************************
-- NAME : RefreshReagents()
-- DESC : Build a list of reagents for spells that a player knows
-- **************************************************************************
--]]
function addon:RefreshReagents()
    if debug == true then dbg_out("Player knows the following spells:") end
	for i, buff in ipairs(spells) do
		local possessed_ptr = possessed[i]      -- create a pointer to the possessed table
        wipe(possessed_ptr) -- clear the array (because we are reusing it), instead of creating a new one each time.
                            -- this saves some cycles as we don't call the garbage collector as often

        -- for every spell, get the reagent info
		for index, spell in ipairs(buff.spells) do
			local reagentID = buff.reagent
			local reagentName = GetItemInfo(reagentID)
            if not reagentName then     -- just in case there are spells in spellData.lua with reagents that aren't in the game (yet)
				return
			end

            -- if we know the spell, track the reagent. The way this works is that it only loads reagents for
            -- spells that you know into the tracking table, and as you learn more it shows more. The old implementation
            -- would load all possible ones, and grey out ones that you didn't know yet.
			if IsSpellKnown(spell) then
                if debug == true then dbg_out(" - "..spell) end
                possessed_ptr.reagentName = reagentName
			    possessed_ptr.reagentIcon = GetItemIcon(reagentID)
                possessed_ptr.spellIcon = GetSpellTexture(spell)
            end
		end
	end
end


--[[
-- **************************************************************************
-- NAME : UpdateButton()
-- DESC : Check if any reagents are being tracked, and if so, generates the icon / text / values to be shown
--      : in the titan panel window. if no reagents tracked, hides all buttons
-- **************************************************************************
--]]
function addon:UpdateButton()
	local tracking = false
	local totalWidth = 0
	local ph = TitanPanelReagentTrackerButton:GetHeight() -- poor man's Titan height check :)

	local buttonText = _G[RT_BUTTON_NAME .. TITAN_PANEL_TEXT]
	local reagent_prev = buttonText     -- first one only
	local reagent_begin = "LEFT"        -- overlap by forcing the first one to align left; then switch to right
	local offset_x = 0                  -- use spaces around numbers to get a better width
	local offset_y = 0                 -- Seems a shift down is needed...
	
	for i, buff in pairs(possessed) do
		local button = buttons[i]
		local btn_width = 0 -- icon + count

        -- show/hide reagent trackers
		if buff.reagentName and TitanGetVar(TITAN_REAGENTTRACKER_ID, "TrackReagent"..i) then
			local icon = button.icon
			-- display spell or reagent icon
			if TitanGetVar(TITAN_REAGENTTRACKER_ID, "ShowSpellIcons") then
				icon:SetTexture(buff.spellIcon)
			else
				icon:SetTexture(buff.reagentIcon)
			end

			-- current number of reagents
			button.text:SetText(" "..GetItemCount(buff.reagentName).." ")
			local iconWidth = button.icon:GetWidth() -- could assume 16
			local textWidth = button.text:GetWidth()
			btn_width = iconWidth + textWidth -- for this reagent; will be added to a running total

			button:SetSize(btn_width, ph)
			
			if debug then
				dbg_out("UpdateButton SHOW"
				.." "..tostring(i)..""
				--.." "..tostring(button:GetName())..""
				.." '"..tostring(button.text:GetText()).."'"
				.." "..tostring(button:IsShown())..""
				--.." "..num_out(iconWidth)..""
				.." "..num_out(textWidth)..""
				.." "..num_out(btn_width)..""
				.." "..num_out(button:GetWidth())..""
				)
				dbg_out(">> UpdateButton"
				.." < "..tostring(reagent_prev and reagent_prev:GetName() or "nyl")..""
				.." "..num_out(offset_x)..""
				.." "..num_out(offset_y)..""
				)
			end

			button:ClearAllPoints()
			button:SetPoint("LEFT", reagent_prev, reagent_begin, offset_x, offset_y) -- relative to the addon or prev tracker
			button:Show()

			-- next reagent is to the right of this one
			reagent_begin = "RIGHT" 
			reagent_prev = _G[REAGENT_PRE..i]

			tracking = true
		else

			if debug then
				dbg_out("UpdateButton HIDE"
				.." "..tostring(button:GetName())..""
				)
			end
			
			button:ClearAllPoints();
			button:Hide()
		end
		
		totalWidth = totalWidth + btn_width
	end

	-- adjust width so other Titan plugins are properly offset
	addon.reagent_width_total = totalWidth

	if debug then
		dbg_out("UpdateButton wrap"
		.." "..num_out(totalWidth)..""
		)
	end
end

--[[
-- **************************************************************************
-- NAME : TitanPanelRightClickMenu_PrepareReagentTrackerMenu()
-- DESC : Create the values to be displayed in the right click -> drop down menu of the addon
-- **************************************************************************
--]]
function TitanPanelRightClickMenu_PrepareReagentTrackerMenu()
    local info

    -- level 3
    if _G["L_UIDROPDOWNMENU_MENU_LEVEL"] == 3 then
        for index, buff in ipairs(possessed) do
            local info1 = {};
            local info2 = {};
            local info3 = {};
            local info4 = {};
            local info5 = {};
            local info6 = {};
            local reagent = buff.reagentName
            if reagent then
                if _G["L_UIDROPDOWNMENU_MENU_VALUE"] == reagent.." Options" then    -- make sure it only builds buttons for the right reagent
                    -- Button for One Stack
                    info1.text = "Buy 1 stack of "..reagent
                    info1.value = "Buy 1 stack of "..reagent
                    info1.checked = TitanGetVar(TITAN_REAGENTTRACKER_ID, "Reagent"..index.."OneStack")
                    info1.func = function()
                        TitanSetVar(TITAN_REAGENTTRACKER_ID, "Reagent"..index.."OneStack", true);
                        TitanSetVar(TITAN_REAGENTTRACKER_ID, "Reagent"..index.."TwoStack", false);
                        TitanSetVar(TITAN_REAGENTTRACKER_ID, "Reagent"..index.."ThreeStack", false);
                        TitanSetVar(TITAN_REAGENTTRACKER_ID, "Reagent"..index.."FourStack", false);
                        TitanSetVar(TITAN_REAGENTTRACKER_ID, "Reagent"..index.."FiveStack", false);
                        TitanSetVar(TITAN_REAGENTTRACKER_ID, "Reagent"..index.."NoStacks", false);
                    end

                    -- Button for Two Stacks
                    info2.text = "Buy 2 stacks of "..reagent
                    info2.value = "Buy 2 stacks of "..reagent
                    info2.checked = TitanGetVar(TITAN_REAGENTTRACKER_ID, "Reagent"..index.."TwoStack")
                    info2.func = function()
                        TitanSetVar(TITAN_REAGENTTRACKER_ID, "Reagent"..index.."OneStack", false);
                        TitanSetVar(TITAN_REAGENTTRACKER_ID, "Reagent"..index.."TwoStack", true);
                        TitanSetVar(TITAN_REAGENTTRACKER_ID, "Reagent"..index.."ThreeStack", false);
                        TitanSetVar(TITAN_REAGENTTRACKER_ID, "Reagent"..index.."FourStack", false);
                        TitanSetVar(TITAN_REAGENTTRACKER_ID, "Reagent"..index.."FiveStack", false);
                        TitanSetVar(TITAN_REAGENTTRACKER_ID, "Reagent"..index.."NoStacks", false);
                    end

                    -- Button for Three Stacks
                    info3.text = "Buy 3 stacks of "..reagent
                    info3.value = "Buy 3 stacks of "..reagent
                    info3.checked = TitanGetVar(TITAN_REAGENTTRACKER_ID, "Reagent"..index.."ThreeStack")
                    info3.func = function()
                        TitanSetVar(TITAN_REAGENTTRACKER_ID, "Reagent"..index.."OneStack", false);
                        TitanSetVar(TITAN_REAGENTTRACKER_ID, "Reagent"..index.."TwoStack", false);
                        TitanSetVar(TITAN_REAGENTTRACKER_ID, "Reagent"..index.."ThreeStack", true);
                        TitanSetVar(TITAN_REAGENTTRACKER_ID, "Reagent"..index.."FourStack", false);
                        TitanSetVar(TITAN_REAGENTTRACKER_ID, "Reagent"..index.."FiveStack", false);
                        TitanSetVar(TITAN_REAGENTTRACKER_ID, "Reagent"..index.."NoStacks", false);
                    end

                    -- Button for Four Stacks
                    info4.text = "Buy 4 stacks of "..reagent
                    info4.value = "Buy 4 stacks of "..reagent
                    info4.checked = TitanGetVar(TITAN_REAGENTTRACKER_ID, "Reagent"..index.."FourStack")
                    info4.func = function()
                        TitanSetVar(TITAN_REAGENTTRACKER_ID, "Reagent"..index.."OneStack", false);
                        TitanSetVar(TITAN_REAGENTTRACKER_ID, "Reagent"..index.."TwoStack", false);
                        TitanSetVar(TITAN_REAGENTTRACKER_ID, "Reagent"..index.."ThreeStack", false);
                        TitanSetVar(TITAN_REAGENTTRACKER_ID, "Reagent"..index.."FourStack", true);
                        TitanSetVar(TITAN_REAGENTTRACKER_ID, "Reagent"..index.."FiveStack", false);
                        TitanSetVar(TITAN_REAGENTTRACKER_ID, "Reagent"..index.."NoStacks", false);
                    end

                    -- Button for Five Stacks
                    info5.text = "Buy 5 stacks of "..reagent
                    info5.value = "Buy 5 stacks of "..reagent
                    info5.checked = TitanGetVar(TITAN_REAGENTTRACKER_ID, "Reagent"..index.."FiveStack")
                    info5.func = function()
                        TitanSetVar(TITAN_REAGENTTRACKER_ID, "Reagent"..index.."OneStack", false);
                        TitanSetVar(TITAN_REAGENTTRACKER_ID, "Reagent"..index.."TwoStack", false);
                        TitanSetVar(TITAN_REAGENTTRACKER_ID, "Reagent"..index.."ThreeStack", false);
                        TitanSetVar(TITAN_REAGENTTRACKER_ID, "Reagent"..index.."FourStack", false);
                        TitanSetVar(TITAN_REAGENTTRACKER_ID, "Reagent"..index.."FiveStack", true);
                        TitanSetVar(TITAN_REAGENTTRACKER_ID, "Reagent"..index.."NoStacks", false);
                    end

                    -- Button to not autobuy any stacks
                    info6.text = "Do not autobuy "..reagent
                    info6.value = "Do not autobuy "..reagent
                    info6.checked = TitanGetVar(TITAN_REAGENTTRACKER_ID, "Reagent"..index.."NoStacks")
                    info6.func = function()
                        TitanSetVar(TITAN_REAGENTTRACKER_ID, "Reagent"..index.."OneStack", false);
                        TitanSetVar(TITAN_REAGENTTRACKER_ID, "Reagent"..index.."TwoStack", false);
                        TitanSetVar(TITAN_REAGENTTRACKER_ID, "Reagent"..index.."ThreeStack", false);
                        TitanSetVar(TITAN_REAGENTTRACKER_ID, "Reagent"..index.."FourStack", false);
                        TitanSetVar(TITAN_REAGENTTRACKER_ID, "Reagent"..index.."FiveStack", false);
                        TitanSetVar(TITAN_REAGENTTRACKER_ID, "Reagent"..index.."NoStacks", true);
                    end

                    -- add all buttons
                    L_UIDropDownMenu_AddButton(info1, _G["L_UIDROPDOWNMENU_MENU_LEVEL"]);
                    L_UIDropDownMenu_AddButton(info2, _G["L_UIDROPDOWNMENU_MENU_LEVEL"]);
                    L_UIDropDownMenu_AddButton(info3, _G["L_UIDROPDOWNMENU_MENU_LEVEL"]);
                    L_UIDropDownMenu_AddButton(info4, _G["L_UIDROPDOWNMENU_MENU_LEVEL"]);
                    L_UIDropDownMenu_AddButton(info5, _G["L_UIDROPDOWNMENU_MENU_LEVEL"]);
                    L_UIDropDownMenu_AddButton(info6, _G["L_UIDROPDOWNMENU_MENU_LEVEL"]);
                end
            end
        end
        return
    end
    -- /level 3


	-- level 2
	if _G["L_UIDROPDOWNMENU_MENU_LEVEL"] == 2 then
		if _G["L_UIDROPDOWNMENU_MENU_VALUE"] == "Autobuy Options" then
			TitanPanelRightClickMenu_AddTitle("Options", _G["L_UIDROPDOWNMENU_MENU_LEVEL"])

            for index, buff in ipairs(possessed) do
                info = {};
                local reagent = buff.reagentName
                if reagent then
                    info.text = reagent.." Options"
                    info.value = reagent.." Options"
                    info.notCheckable = true
                    info.hasArrow = 1;
                    info.keepShownOnClick = 1

                    L_UIDropDownMenu_AddButton(info, _G["L_UIDROPDOWNMENU_MENU_LEVEL"]);

                end
            end
		end
		return
	end
    -- /level 2

	-- level 1
    TitanPanelRightClickMenu_AddTitle(TitanPlugins[TITAN_REAGENTTRACKER_ID].menuText)

    info = {};
	info.notCheckable = true
	info.text = "Autobuy Options";
	info.value = "Autobuy Options";
	info.hasArrow = 1;
    L_UIDropDownMenu_AddButton(info);
    TitanPanelRightClickMenu_AddSpacer();

	-- add menu entry for each possessed spell
    for index, buff in ipairs(possessed) do
        info = {};
		local reagent = buff.reagentName
		if reagent then
			info.text = "Track "..reagent
			info.value = "TrackReagent"..index
			info.checked = TitanGetVar(TITAN_REAGENTTRACKER_ID, "TrackReagent"..index)
			info.keepShownOnClick = 1
			info.func = function()
                TitanToggleVar(TITAN_REAGENTTRACKER_ID, "TrackReagent"..index); -- just a note on TitanToggleVar. It 'toggles' the variable
                                                                                -- between '1' and '', instead of true/false. Can be problematic
				addon:UpdateButton();
			end
            L_UIDropDownMenu_AddButton(info);
		end
	end

    TitanPanelRightClickMenu_AddSpacer()

    -- if we're currently showing spell icons, display the "show reagent icons" text
	if TitanGetVar(TITAN_REAGENTTRACKER_ID, "ShowSpellIcons") then
		TitanPanelRightClickMenu_AddCommand("Show Reagent Icons", TITAN_REAGENTTRACKER_ID,"TitanPanelReagentTrackerSpellIcon_Toggle");
	else    -- if not, display "show spell icons" text
		TitanPanelRightClickMenu_AddCommand("Show Spell Icons", TITAN_REAGENTTRACKER_ID,"TitanPanelReagentTrackerSpellIcon_Toggle");
	end

	TitanPanelRightClickMenu_AddSpacer()

	TitanPanelRightClickMenu_AddCommand("Hide", TITAN_REAGENTTRACKER_ID, TITAN_PANEL_MENU_FUNC_HIDE);
    TitanPanelRightClickMenu_AddCommand("Toggle Side", TITAN_REAGENTTRACKER_ID, "TitanPanelReagentTrackerDisplayOnRightSide_Toggle");
    -- /level 1

end

--[[
-- **************************************************************************
-- NAME : TitanPanelReagentTrackerSpellIcon_Toggle()
-- DESC : Toggles between showing spell icons and reagent icons
-- **************************************************************************
--]]
function TitanPanelReagentTrackerSpellIcon_Toggle()
	TitanToggleVar(TITAN_REAGENTTRACKER_ID, "ShowSpellIcons")
	addon:UpdateButton()
end

--[[
-- **************************************************************************
-- NAME : TitanPanelReagentTrackerDisplayOnRightSide_Toggle()
-- DESC : Toggles between addon being aligned to right or left side of TitanPanel
-- **************************************************************************
--]]
function TitanPanelReagentTrackerDisplayOnRightSide_Toggle()
	TitanToggleVar(TITAN_REAGENTTRACKER_ID, "DisplayOnRightSide")
	addon:UpdateButton()
end



--[[
-- **************************************************************************
-- NAME : TitanPanelReagentTracker_GetTooltipText()
-- DESC : Generate a mouseover text with a summary of all the tracked reagents, and their amounts
--      : when the mouse is over the titan panel section where Reagent Tracker is
-- **************************************************************************
--]]
function TitanPanelReagentTracker_GetTooltipText()
	local tooltipText = " "

	-- generate the reagent name and count for info in tooltip
	for index, buff in ipairs(possessed) do
        local reagent = buff.reagentName
		if reagent and TitanGetVar(TITAN_REAGENTTRACKER_ID, "TrackReagent"..index) then
			tooltipText = format("%s\n%s\t%s", tooltipText, reagent, GetItemCount(reagent))
		end
	end

	if #tooltipText > 1 then
		return tooltipText
	else
		return " \nNo reagents tracked for known spells."
	end
end

--[[
-- **************************************************************************
-- NAME : BuyReagents()
-- DESC : Buy the reagents from the vendor
--      : this will buy up to a single stack of items that are tracked as reagents for spells a player knows
-- **************************************************************************
--]]
function addon:BuyReagents()
   local shoppingCart = {};    -- list of items to buy
   local tableIndex = 1 -- because LUA handles tables poorly, deciding that a table/list which has 2 sequential nil values in it
                        -- has no values after those nils, we have to use a manual counter to correctly store items in a list

    -- print list of all reagents that the addon has determined that the player needs, based on spells he/she knows
    if debug == true then
        dbg_out("Player knows spells requiring the following reagents:");
        for i, buff in ipairs(possessed) do
            if buff.reagentName ~= nil then
                dbg_out(" - "..buff.reagentName);
            end
        end
        dbg_out("\n");
    end

    -- first up, let's fill our shopping cart
    -- for every spell we have
    for index, buff in ipairs(possessed) do
        -- if the option is set to autobuy the reagent for this spell
        if TitanGetVar(TITAN_REAGENTTRACKER_ID, "Reagent"..index.."OneStack") or TitanGetVar(TITAN_REAGENTTRACKER_ID, "Reagent"..index.."TwoStack") or TitanGetVar(TITAN_REAGENTTRACKER_ID, "Reagent"..index.."ThreeStack") or TitanGetVar(TITAN_REAGENTTRACKER_ID, "Reagent"..index.."FourStack") or TitanGetVar(TITAN_REAGENTTRACKER_ID, "Reagent"..index.."FiveStack") then
            if debug == true then dbg_out("|cffeda55fReagent = "..buff.reagentName) end
            local totalCountOfReagent = 0
            local desiredCountOfReagent = 0
            local maxStackOfReagent = 0
            if buff.reagentName ~= nil then
                -- the 8th variable returned by GetItemInfo() is the itemStackCount; the max an item will stack to
                -- it should never be nil
                _, _, _, _, _, _, _, maxStackOfReagent = GetItemInfo(buff.reagentName)    -- get the max a stack of this reagent can be
                                                                                                -- just so that we buy one stack only


                -- bugfix for Issue #7 from Nihlolino, where GetItemInfo() returns a nil value for max item stack size, and subsequent
                -- arithmetic on a nil value fails. This shouldn't need to exist. A reagent can't stack to nil.
                if totalCountOfReagent ~= nil and maxStackOfReagent ~= nil then
                    if debug == true then dbg_out("totalCountOfReagent = "..totalCountOfReagent.." and desiredCountOfReagent = "..desiredCountOfReagent) end
                    -- cater for buying multiple stacks of reagents
                    if TitanGetVar(TITAN_REAGENTTRACKER_ID, "Reagent"..index.."OneStack") then
                        desiredCountOfReagent = maxStackOfReagent * 1
                    elseif TitanGetVar(TITAN_REAGENTTRACKER_ID, "Reagent"..index.."TwoStack") then
                        desiredCountOfReagent = maxStackOfReagent * 2
                    elseif TitanGetVar(TITAN_REAGENTTRACKER_ID, "Reagent"..index.."ThreeStack") then
                        desiredCountOfReagent = maxStackOfReagent * 3
                    elseif TitanGetVar(TITAN_REAGENTTRACKER_ID, "Reagent"..index.."FourStack") then
                        desiredCountOfReagent = maxStackOfReagent * 4
                    elseif TitanGetVar(TITAN_REAGENTTRACKER_ID, "Reagent"..index.."FiveStack") then
                        desiredCountOfReagent = maxStackOfReagent * 5
                    end
                end

            end

            if debug == true then
                if buff.reagentName ~= nil then
                    dbg_out("Aiming to buy "..desiredCountOfReagent.." of "..buff.reagentName);
                    dbg_out("Searching for "..buff.reagentName.." in bags");
                end
            end
            -- First up, go add up all the units of this reagent we have
            -- this is in case they have multiple half used stacks
            if buff.reagentName ~= nil then
                -- for every bag slot
                for bagID = 0, 4 do
                    -- for even item slot in that bag
                    for slot = 1, C_Container.GetContainerNumSlots(bagID) do
                        -- get the item name and quantity of each item in that slot
                        local bagItemName, bagItemCount = getItemNameItemCountFromBag(bagID, slot);

                        if bagItemName ~= nil and bagItemCount ~= nil then
                            -- if the ItemName returned from the bag slot matches a reagent we're tracking
                            if bagItemName == buff.reagentName then
                                totalCountOfReagent = totalCountOfReagent + bagItemCount    -- add up how many of that reagent we have
                            end
                        end
                    end
                end
                if debug == true then dbg_out("Found "..totalCountOfReagent.." "..buff.reagentName.." in bags") end
                -- enclosing the entire reagent count vs desired reagent comparison in a not-nil if statement for Nihlolino's reported bug
                -- this shouldn't need to exist. A reagent can't stack to nil.
                if totalCountOfReagent ~= nil and desiredCountOfReagent ~= nil and maxStackOfReagent ~= nil then
                    if totalCountOfReagent >= desiredCountOfReagent then
                        -- we got enough not gonna buy any more
                        if debug == true then dbg_out("Have enough "..buff.reagentName.." in bags. Not buying any more.\n\n") end
                    elseif totalCountOfReagent < desiredCountOfReagent then
                        -- we don't have enough, let's buy some more
                        shoppingCart[tableIndex] = {buff.reagentName, desiredCountOfReagent-totalCountOfReagent, maxStackOfReagent}
                        tableIndex = tableIndex+1
                        if debug == true then dbg_out("Added "..desiredCountOfReagent-totalCountOfReagent.." of "..possessed[index].reagentName.." to cart.") end
                    end
                end
            end
        end
    end

    -- this is where we do the actual shopping
    -- at this point, shoppingCart looks like this:
    -- shoppingCart[x][1] = the reagent name
    -- shoppingCart[x][2] = how many reagents to buy
    -- shoppingCart[x][3] = max the reagent will stack to. Required for github issue #9

    -- for each item in shoppingCart
    for i = 1, table.getn(shoppingCart) do
        -- pass the Reagent name and the required count to the buying function
        if shoppingCart[i][1] ~= nil and shoppingCart[i][2] ~= nil and shoppingCart[i][3] ~= nil then
            if debug == true then dbg_out("Trying to buy "..shoppingCart[i][1]) end
            buyItemFromVendor(shoppingCart[i][1], shoppingCart[i][2], shoppingCart[i][3])
        end
	end
end

--[[
-- **************************************************************************
-- NAME : buyItemFromVendor(itemName, purchaseCount)
-- DESC : Buy a quantity of an item from a vendor
--      : the logic is a inelegant: iterate through every item the vendor has, compare it to what we want,
--      : and if it matches buy the desired amount
-- VAR  : itemName = name of the item (reagent)
--      : purchaseCount = amount of item to buy
-- **************************************************************************
--]]
function buyItemFromVendor(itemName, purchaseCount, maxStackSize)
    -- check for each of the merchant's items to see if it's what we want
    for index = 0, GetMerchantNumItems() do
        local name, texture, price, quantity = GetMerchantItemInfo(index)
        -- if the merchant's item name matches the name of the item in the shopping cart
        if name == itemName then
            -- buy the item that we're currently looking at, and the amount
            if debug == true then dbg_out("Vendor has "..itemName..", calling Blizzard API to buy "..purchaseCount) end

            -- Github issue #9: Blizzard does not support buying of multiple stacks in one API call.
            -- break down the purchasing into <= single stack purchases
            while (purchaseCount / maxStackSize) > 1 do
                if debug == true then dbg_out("Buying "..maxStackSize..", "..purchaseCount-maxStackSize.." remaining") end
                BuyMerchantItem(index, maxStackSize)
                purchaseCount = purchaseCount - maxStackSize
            end
            if purchaseCount <= maxStackSize then
                if debug == true then dbg_out("Buying "..purchaseCount..", "..purchaseCount-purchaseCount.." remaining") end
                BuyMerchantItem(index, purchaseCount)
            end
        end
    end
end

--[[
-- **************************************************************************
-- NAME : getItemNameItemCountFromBag(bagNumber, slotNumber)
-- DESC : gets the item name and count of item for a bag slot
        : This is used (with other logic) to get a total sum of all of a single reagent in a player's bag
-- VAR  : bagNumber = which bag slot is being checked
--      : slotNumber = which slot (within a bag) is being checked
-- **************************************************************************
--]]
function getItemNameItemCountFromBag(bagNumber, slotNumber)
    -- get the count and ID of the item in this bag slot
    local info = C_Container.GetContainerItemInfo(bagNumber, slotNumber);
    local itemCount = info and info.stackCount;
    local itemID = info and info.itemID;
    local itemName

    -- if an item is actually there, get the name of the item, instead of the ID
    if info and itemID then
        itemName = GetItemInfo(itemID)
    end

	if itemName ~= nil then
		return itemName, itemCount;
	else
		return "", itemCount;
	end
end

--[[
-- **************************************************************************
-- NAME : DebugInfo()
-- DESC : Show debug info about the addon
-- NOTE : not fully tested yet
-- **************************************************************************
--]]
function addon:DebugInfo()
    print("|cffeda55fReagentTracker Debug Info|r")

    -- Show how many spells/reagents loaded
    print("- Spells table entries: "..tostring(#spells))

    -- Show saved variables count
    local sv_count = 0
    for k, v in pairs(addon_frame.registry.savedVariables or {}) do
        sv_count = sv_count + 1
    end
    print("- SavedVariables entries: "..sv_count)

    -- Show control variables count
    local cv_count = 0
    for k, v in pairs(addon_frame.registry.controlVariables or {}) do
        cv_count = cv_count + 1
    end
    print("- controlVariables (static) entries: "..cv_count)

    -- Show player class for debugging
    local className, classFileName = UnitClass("player")
    print("- Player Class: "..className.." ("..classFileName..")")

    -- Print a final marker
    print("|cffeda55fDone.|r")
end


--
-- === Debug command handling ===
--
SLASH_REAGENTTRACKER1 = '/rt'

SlashCmdList["REAGENTTRACKER"] = function(msg)
    if msg == "debug" then
        addon:DebugInfo()
    else
        print("|cffeda55fReagentTracker|r commands:")
        print("/rt debug - Show debug info about reagents and controls")
    end
end



--
-- === Move the frame creation here for readability and make use of local functions ===
--
-- create a frame to handle all the things
-- this actually seems to be what drives the functions / logic in the addon
-- without it, nothing works
addon_frame = CreateFrame("Button", "TitanPanelReagentTrackerButton", CreateFrame("Frame", nil, UIParent), "TitanPanelComboTemplate") 

addon.font_calc = addon_frame:CreateFontString(nil, nil, addon.font)
addon.font_calc:SetText(" ")
addon.font_calc_width = addon.font_calc:GetWidth()

addon.label_fontstr = addon_frame:CreateFontString(nil, nil, addon.font)

-- addon frame scripts
addon_frame:SetScript("OnShow", function(self)
	OnShow(self);
	TitanPanelButton_OnShow(self);
end)

-- when the addon is hidden, unregister the events so that it's not using resources
addon_frame:SetScript("OnHide", function(self)
	self:UnregisterEvent("LEARNED_SPELL_IN_TAB")
	self:UnregisterEvent("MERCHANT_SHOW")
	self:UnregisterEvent("BAG_UPDATE")
end)

-- tell the addon what to do on each event
addon_frame:SetScript("OnEvent", function(self, event, ...)
	if debug then
		dbg_out(tostring(event))
	end

    if event == "PLAYER_LOGIN" then
		-- Wait for OnShow to init events, etc
    elseif event == "MERCHANT_SHOW" then    -- handle a merchant window opening. this is to autobuy reagents
        addon:BuyReagents()
		onUpdate(self, false)
	else
		-- Covers spells learned and bag updates (for reagent counts)
		onUpdate(self, true)
	end
end)

-- Update the registry so Titan knows what to do
addon_frame.registry = {
    id = TITAN_REAGENTTRACKER_ID,
	version = GetAddOnMetadata(add_on, "Version"),   -- the the value of Version variable from the .toc
	menuText = "Reagent Tracker",
	buttonTextFunction = UpdateText, -- For Titan update button
	tooltipTitle = "Reagent Tracker Info",
	tooltipTextFunction = "TitanPanelReagentTracker_GetTooltipText",
	icon = "Interface\\AddOns\\TitanClassicReagentTracker\\Tracking",
	iconWidth = 16,
    -- These are used to show or hide 'controls' in the Titan config or Titan right click menu. 
    -- If true, the control is shown to the user.
    -- If false, the control is not shown to the user.
    controlVariables = {
        ShowIcon = true
        ShowLabelText = false
        DisplayOnRightSide = true
        -- Category_AutoBuyNote = "Note: Configure more options via right-click menu on the addon button in Titan Panel."
    },
	savedVariables = {
		ShowIcon = true,                -- force the plugin icon to be shown
		ShowLabelText = false,          -- disable showing the text label otherwise it messes with spacing the icon - count pairs
        DisplayOnRightSide = false,     -- have the plug be left- or right-aligned on TitanPanel
        ShowSpellIcons = false,         -- variable used throughout the addon to determine whether to show spell or reagent icons
	}
}


-- This creates a frame and saved pairs set [i] for every entry in spells for the given toon class.
-- This covers all the spells with reagents the class can learn at max level. 
-- The spells are grouped in spellData.lua by reagent type, meaning the minimum number of buttons are created.
-- As the toon learns the spells they become visible in the addon UI.
--
-- Setting the savedVariables here so Titan will store them per toon.
-- They will be created for a new toon; pulled from the Titan saved vars if already set.
for i = 1, #spells do
    buttons[i] = newReagent(addon_frame, i)
    -- create variables in the addon.registry so that they can be set later by the user
    -- to save the variables across game reload
    addon_frame.registry.savedVariables["TrackReagent"..i] = true
    addon_frame.registry.savedVariables["BuyReagent"..i] = false
    addon_frame.registry.savedVariables["Reagent"..i.."OneStack"] = false
    addon_frame.registry.savedVariables["Reagent"..i.."TwoStack"] = false
    addon_frame.registry.savedVariables["Reagent"..i.."ThreeStack"] = false
    addon_frame.registry.savedVariables["Reagent"..i.."FourStack"] = false
    addon_frame.registry.savedVariables["Reagent"..i.."FiveStack"] = false
    addon_frame.registry.savedVariables["Reagent"..i.."NoStacks"] = false
	possessed[i] = {}   -- to prevent possessed[i] from being nil, because wipe(nil) as called by RefreshReagents() will cause an error
end
