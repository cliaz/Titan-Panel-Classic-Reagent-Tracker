local _, addon = ...

-- define variables
-- note: look at addon.registry to see variables saved between restarts
local debug = false -- setting this to true will enable a lot of debug messages being output on the wow screen
local printPurchasingMessages = false   -- TODO: move this to addon.registry stored variables
local playerClass = select(2, UnitClass("player"))
local possessed = {}    -- store spells that the player knows here

local spells = addon.spells[playerClass]    -- generate a list of all possible spells that a player's Class can know, and associated reagents
if not spells then return end   -- don't continue addon load if there are no reagents associated to our character class


TITAN_REAGENTTRACKER_ID = "ReagentTracker"
local L = LibStub("AceLocale-3.0"):GetLocale("Titan", true)
local _G = getfenv(0);

--
-- create a new button for each reagent
--
local function newReagent(parent, i)
	
	local btn = CreateFrame("Button", "TitanPanelReagentTrackerReagent"..i, parent, "TitanPanelChildButtonTemplate")
	btn:SetSize(16, 16)
	btn:SetPoint("LEFT")
	btn:SetPushedTextOffset(0, 0)
	
	local icon = btn:CreateTexture()
	icon:SetSize(16, 16)
	icon:SetPoint("LEFT")
	btn:SetNormalTexture(icon)
	btn.icon = icon
	
	local text = btn:CreateFontString(nil, nil, "GameFontHighlightSmall")
	text:SetPoint("LEFT", icon, "RIGHT", 2, 1)
	text:SetJustifyH("LEFT")
	btn:SetFontString(text)
	
	return btn
end


local function onUpdate(self, elapsed)
	if self.refreshReagents then
		self:RefreshReagents()
		self.refreshReagents = false
	end
	self:UpdateButton()
	TitanPanelButton_UpdateTooltip(self)
	self:SetScript("OnUpdate", nil)
end

-- create a frame to handle all the things
-- this actually seems to be what drives the functions / logic in the addon
-- without it, nothing works
addon = CreateFrame("Button", "TitanPanelReagentTrackerButton", CreateFrame("Frame", nil, UIParent), "TitanPanelButtonTemplate")
addon:SetSize(16, 16)
addon:SetPushedTextOffset(0, 0)

-- tell the addon which events from the game it should be aware of
addon:RegisterEvent("PLAYER_LOGIN")
addon:RegisterEvent("LEARNED_SPELL_IN_TAB")
addon:RegisterEvent("MERCHANT_SHOW")

-- tell the addon what to do on each event
addon:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_LOGIN" then
		self:RefreshReagents()
		self:UpdateButton()
		TitanPanelButton_UpdateTooltip(self)
        self:RegisterEvent("BAG_UPDATE")
    elseif event == "MERCHANT_SHOW" then    -- handle a merchant window opening. this is to autobuy reagents
        if TitanGetVar(TITAN_REAGENTTRACKER_ID, "AutoBuy") then
            self:BuyReagents()
            self:UpdateButton()
            TitanPanelButton_UpdateTooltip(self)
            self:RegisterEvent("BAG_UPDATE")
        end
	else
		-- update on next frame to prevent redundant CPU processing from event spamming
		self.refreshReagents = event == "LEARNED_SPELL_IN_TAB"
		self:SetScript("OnUpdate", onUpdate)
		return
	end
end)

local text = addon:CreateFontString(nil, nil, "GameFontNormalSmall")
text:SetPoint("LEFT", 0, 1)
text:SetText("Reagent Tracker")
addon:SetFontString(text)
addon.label = text


addon.registry = {
    id = TITAN_REAGENTTRACKER_ID,
	version = GetAddOnMetadata("TitanReagentTracker", "Version"),   -- the the value of Version variable from the .toc
	menuText = "Reagent Tracker",
	tooltipTitle = "Reagent Tracker Info", 
	tooltipTextFunction = "TitanPanelReagentTracker_GetTooltipText",
	savedVariables = {
		ShowSpellIcons = false, -- variable used throughout the addon to determine whether to show spell or reagent icons
        AutoBuy = false, -- variable used throughout the addon to determine whether or not to autobuy reagents
	}
}


--
-- create a button for every spell / reagent in the spell array, to be shown in titan panel horizontally
-- Save these buttons and their settings in titan variables so that they persist across relaunch
-- also create a list in the possessed array, which we'll use to store reagent information later
--
local buttons = {}
for i = 1, #spells do
	buttons[i] = newReagent(addon, i)
	addon.registry.savedVariables["TrackReagent"..i] = (i == 1)
	possessed[i] = {}
end


local queryTooltip = CreateFrame("GameTooltip", "TitanReagentTrackerTooltip", nil, "GameTooltipTemplate")
queryTooltip:SetOwner(UIParent, "ANCHOR_NONE")
queryTooltip:SetScript("OnTooltipSetItem", function(self)
	if TitanReagentTrackerTooltipTextLeft1:GetText() ~= RETRIEVING_ITEM_INFO then
		addon:RefreshReagents()
		addon:UpdateButton()
		TitanPanelButton_UpdateTooltip(addon)
	end
end)


function addon:RefreshReagents()
	for p_index, buff in ipairs(spells) do
		local possessed = possessed[p_index]
        wipe(possessed) -- wtf is this doing? Potentially remove, but haven't fully tested.
        
        -- for every spell, get the reagent info
		for index, spell in ipairs(buff.spells) do
			local reagentID = buff.reagent
			local reagentName = GetItemInfo(reagentID)
            if not reagentName then
				queryTooltip:SetHyperlink("item:"..reagentID)
			return
			end
			
            -- if we know the spell, track the reagent. The way this works is that it only loads reagents for 
            -- spells that you know into the tracking table, and as you learn more it shows more. The old implementation 
            -- would load all possible ones, and grey out ones that you didn't know yet.
			if IsSpellKnown(spell) then
                possessed.reagentName = reagentName
			    possessed.reagentIcon = GetItemIcon(reagentID)
                possessed.spellIcon = GetSpellTexture(spell)
            end
		end
	end
end


--
-- function which checks if any reagents are being tracked, and if so, generates the icon / text / values to be shown
-- in the titan panel window. if no reagents tracked, hides all buttons
--
function addon:UpdateButton()
	local tracking
	local totalWidth = 0
	local offset = 0
	for i, buff in pairs(possessed) do
		local button = buttons[i]
		local nextButton = buttons[i + 1]
		local nextAnchor = "LEFT"
		local nextOffset = 0

        -- show/hide reagent trackers
		if buff.reagentName and TitanGetVar(TITAN_REAGENTTRACKER_ID, "TrackReagent"..i) then
			local icon = button.icon
			button:Show()
			-- display spell or reagent icon
			if TitanGetVar(TITAN_REAGENTTRACKER_ID, "ShowSpellIcons") then
				icon:SetTexture(buff.spellIcon)
			else
				icon:SetTexture(buff.reagentIcon)
			end
			
			-- current number of reagents
			button:SetText(GetItemCount(buff.reagentName))
            
            -- if there is another spell / button left in the array, change the anchor position for it and set 
            -- an appropriate offset
			if nextButton then
				nextAnchor = "RIGHT"
				nextOffset = 6
			end
			
            button:SetWidth(icon:GetWidth() + button:GetTextWidth())    -- set the button width based off of
                                                                        -- icon size and text size. 
			totalWidth = totalWidth + button:GetWidth() -- add up all widths of buttons
			
            offset = offset + 1 -- without this, the titan panel segment for this addon becomes too small, and the next 
                                -- titan panel segment encroaches onto this addon
			tracking = true
		else
			button:Hide()
		end
		
		-- fix offset to next reagent tracker
		if nextButton then
			nextButton:SetPoint("LEFT", button, nextAnchor, nextOffset, 0)
		end
	end
	
    -- show addon label (Reagent Tracker) if no tracking is enabled
	local none = self.label
	if tracking then
		none:Hide()
	else
		none:Show()
		totalWidth = none:GetWidth() + 8
	end
	
	-- adjust width so other plugins are properly offset
	self:SetWidth(totalWidth + ((offset - 1) * 8))
end

--
-- function that creates the values to be displayed in the right click -> drop down menu of the addon
--
function TitanPanelRightClickMenu_PrepareReagentTrackerMenu()
	TitanPanelRightClickMenu_AddTitle(TitanPlugins[TITAN_REAGENTTRACKER_ID].menuText)
	
	local info = {}
	-- add menu entry for each possessed spell
	for index, buff in ipairs(possessed) do
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
    -- add the autobuy toggle button
    -- TODO: change this to be a button per reagent
    info.text = "Autobuy reagents"
    info.value = "AutoBuy"
    info.checked = TitanGetVar(TITAN_REAGENTTRACKER_ID, "AutoBuy")
    info.keepShownOnClick = 1
    info.func = function()
        TitanToggleVar(TITAN_REAGENTTRACKER_ID, "AutoBuy");
        addon:UpdateButton();
    end
    L_UIDropDownMenu_AddButton(info);
    wipe(info)


    -- if we're currently showing spell icons, display the "show reagent icons" text
	if TitanGetVar(TITAN_REAGENTTRACKER_ID, "ShowSpellIcons") then
		TitanPanelRightClickMenu_AddCommand("Show Reagent Icons", TITAN_REAGENTTRACKER_ID,"TitanPanelReagentTrackerSpellIcon_Toggle");
	else    -- if not, display "show spell icons" text
		TitanPanelRightClickMenu_AddCommand("Show Spell Icons", TITAN_REAGENTTRACKER_ID,"TitanPanelReagentTrackerSpellIcon_Toggle");
	end

	TitanPanelRightClickMenu_AddSpacer()
	
	TitanPanelRightClickMenu_AddCommand("Hide", TITAN_REAGENTTRACKER_ID, TITAN_PANEL_MENU_FUNC_HIDE);

end

--
-- function that simply toggles between showing spell icons, and reagent icons
--
function TitanPanelReagentTrackerSpellIcon_Toggle()
	TitanToggleVar(TITAN_REAGENTTRACKER_ID, "ShowSpellIcons")
	addon:UpdateButton()
end

--
-- function that generates a mouseover text with a summary of all the tracked reagents, and their amounts
-- when the mouse is over the titan panel section where Reagent Tracker is
--
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

--
-- function to actually buy the reagents from the vendor
-- this will buy up to a single stack of items that are tracked as reagents for spells you know
--
function addon:BuyReagents()
   local shoppingCart = {};    -- list of items to buy
   local tableIndex = 1 -- because LUA handles tables poorly, deciding that a table/list which has 2 sequential nil values in it
                    -- has no values after those nils, we have to use a manual counter to correctly store items in a list


    -- first up, let's fill our shopping cart
    -- for every spell we have
    for i = 1, table.getn(possessed) do
        local totalCountOfReagent = 0
        local desiredCountOfReagent = 0
        if possessed[i].reagentName ~= nil then
            -- the 8th variable returned by GetItemInfo() is the itemStackCount; the max an item will stack to
            -- it should never be nil
            _, _, _, _, _, _, _, desiredCountOfReagent = GetItemInfo(possessed[i].reagentName)    -- get the max a stack of this reagent can be
        end                                                                                        -- just so that we buy one stack only

        if debug == true then 
            if possessed[i].reagentName ~= nil then
                DEFAULT_CHAT_FRAME:AddMessage("Searching for "..possessed[i].reagentName);
            end
        end
        -- First up, go add up all the units of this reagent we have
        -- this is in case they have multiple half used stacks
        if possessed[i].reagentName ~= nil then
            -- for every bag slot
            for bagID = 0, 4 do
                -- for even item slot in that bag
                for slot = 1, GetContainerNumSlots(bagID) do
                    -- get the item name and quantity of each item in that slot
                    local bagItemName, bagItemCount = getItemNameItemCountFromBag(bagID, slot);
                                    
                    if bagItemName ~= nil and bagItemCount ~= nil then
                        -- if the ItemName returned from the bag slot matches a reagent we're tracking
                        if bagItemName == possessed[i].reagentName then
                            totalCountOfReagent = totalCountOfReagent + bagItemCount    -- add up how many of that reagent we have
                        end
                    end
                end
            end
            if debug == true then DEFAULT_CHAT_FRAME:AddMessage("Found "..totalCountOfReagent.." "..possessed[i].reagentName.." in bags") end 
            -- enclosing the entire reagent count vs desired reagent comparison in a not-nil if statement for Nihlolino's reported bug
            -- this shouldn't need to exist. a reagent can't stack to nil. 
            if totalCountOfReagent ~= nil and desiredCountOfReagent ~= nil then
                if totalCountOfReagent >= desiredCountOfReagent then
                    -- we got enough not gonna buy any more
                elseif totalCountOfReagent < desiredCountOfReagent then
                    -- we don't have enough, let's buy some more
                    shoppingCart[tableIndex] = {possessed[i].reagentName, desiredCountOfReagent-totalCountOfReagent}
                    tableIndex = tableIndex+1
                    if debug == true then DEFAULT_CHAT_FRAME:AddMessage("Added "..desiredCountOfReagent-totalCountOfReagent.." of "..possessed[i].reagentName.." to cart.") end
                end
            end
        end
    end
 
    -- this is where we do the actual shopping
    -- at this point, shoppingCart looks like this:
    -- shoppingCart[x][1] = the reagent name
    -- shoppingCart[x][2] = how many reagents to buy
    
    local messagedPrinted = false;

    -- for each item in shoppingCart
    for i = 1, table.getn(shoppingCart) do
        -- pass the Reagent name and the required count to the buying function
        if shoppingCart[i][1] ~= nil and shoppingCart[i][2] ~= nil then
            buyItemFromVendor(shoppingCart[i][1], shoppingCart[i][2])
            -- if the user has enabled printing messages about purchasing reagents
            -- TODO: messages are disabled at the moment, need to give users option to enabled / disable
            if printPurchasingMessages == true then 
                -- tell the user we're bought stuff for them
                if messagedPrinted ~= true then
                    DEFAULT_CHAT_FRAME:AddMessage("|cffffff00<TitanPanelReagents> Extra reagents bought.|r");        
                    messagedPrinted = true    -- only want to tell them once 
                end
            end
        end
	end	
end

--
-- Buy a quantity of an item from a vendor
-- the logic is a inelegant: iterate through every item the vendor has, compare it to what we want, 
-- and if it matches buy the desired amount
--
function buyItemFromVendor(itemName, purchaseCount)
    -- check for each of the merchant's items to see if it's what we want
    for index = 0, GetMerchantNumItems() do
        local name, texture, price, quantity = GetMerchantItemInfo(index)
        -- if the merchant's item name matches the name of the item in the shopping cart
        if name == itemName then
            -- buy the item that we're currently looking at, and the amount
            BuyMerchantItem(index, purchaseCount)
        end
    end
end


-- getting passed bag1:slot1, bag1:2, 1:3, etc.
function getItemNameItemCountFromBag(bag, item)    
    -- get the count and link of the item in this bag slot
    local _, itemCount, _, _, _, _, itemLink = GetContainerItemInfo(bag, item);
    local itemName
    
    -- if an item is actually there, get the name of the item, instead of the link
    if itemCount ~= nil and itemLink ~= nil then 
        itemName = GetItemInfo(itemLink)
    end
    
	if itemName ~= nil then
		return itemName, itemCount;
	else
		return "", itemCount;
	end
end