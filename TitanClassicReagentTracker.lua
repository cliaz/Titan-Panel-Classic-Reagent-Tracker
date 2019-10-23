local _, addon = ...

local debug = false -- setting this to true will enable a lot of debug messages being output on the wow screen

local playerClass = select(2, UnitClass("player"))

-- load the database of reagents mapped to spells/abilities for the given playerClass
local spells = addon.spells[playerClass]

-- don't load if there are no reagents associated to our character class
if not spells then return end

TITAN_REAGENTTRACKER_ID = "ReagentTracker"

local L = LibStub("AceLocale-3.0"):GetLocale("Titan", true)
local _G = getfenv(0);
-- store spells that are known here later
local possessed = {}


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
-- this actually seems to be what calls all the functions / logic in the addon
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
        self:BuyReagents()
        self:UpdateButton()
        TitanPanelButton_UpdateTooltip(self)
        self:RegisterEvent("BAG_UPDATE")
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
	version = GetAddOnMetadata("TitanReagentTracker", "Version"),
	menuText = "Reagent Tracker",
	tooltipTitle = "Reagent Tracker Info", 
	tooltipTextFunction = "TitanPanelReagentTracker_GetTooltipText",
	savedVariables = {
		ShowSpellIcons = false,
	}
}


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
		wipe(possessed)
		for index, spell in ipairs(buff.spells) do
			local reagentID = buff.reagent
			local reagentName = GetItemInfo(reagentID)
			if not reagentName then
				queryTooltip:SetHyperlink("item:"..reagentID)
			return
			end
			-- add this spell to our "known spells" table
			-- if this reagent is already tracked through another spell, we'll want to hide it -- nope, no longer the case
			-- also hide it if we don't know the spell in question, since there's no real point tracking reagents in that case
            
            -- changed the logic from negative to positive, aka if we know the spell, track the reagent. None of this
            -- track and then remove if already tracked stuff. The way this works now is that it only loads reagents for 
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
		if buff.reagentName and not buff.disabled and TitanGetVar(TITAN_REAGENTTRACKER_ID, "TrackReagent"..i) then
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
			
			if nextButton then
				nextAnchor = "RIGHT"
				nextOffset = 6
			end
			
			button:SetWidth(icon:GetWidth() + button:GetTextWidth())
			totalWidth = totalWidth + button:GetWidth()
			
			offset = offset + 1
			tracking = true
		else
			button:Hide()
		end
		
		-- fix offset to next reagent tracker
		if nextButton then
			nextButton:SetPoint("LEFT", button, nextAnchor, nextOffset, 0)
		end
	end
	
	-- show label if no tracking is enabled
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


function addon:ToggleVar(var_id)
	TitanToggleVar(TITAN_REAGENTTRACKER_ID, var_id)
	addon:UpdateButton()
end


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
			info.disabled = buff.disabled
			info.keepShownOnClick = 1
			info.func = function()
				TitanToggleVar(TITAN_REAGENTTRACKER_ID, "TrackReagent"..index);
				addon:UpdateButton();
			end
			L_UIDropDownMenu_AddButton(info);
		end
	end

	TitanPanelRightClickMenu_AddSpacer()

	if TitanGetVar(TITAN_REAGENTTRACKER_ID, "ShowSpellIcons") then
		TitanPanelRightClickMenu_AddCommand("Show Reagent Icons", TITAN_REAGENTTRACKER_ID,"TitanPanelReagentTrackerSpellIcon_Toggle");
	else
		TitanPanelRightClickMenu_AddCommand("Show Spell Icons", TITAN_REAGENTTRACKER_ID,"TitanPanelReagentTrackerSpellIcon_Toggle");
	end

	TitanPanelRightClickMenu_AddSpacer()
	
	TitanPanelRightClickMenu_AddCommand("Hide", TITAN_REAGENTTRACKER_ID, TITAN_PANEL_MENU_FUNC_HIDE);

end
function TitanPanelReagentTrackerSpellIcon_Toggle()
	TitanToggleVar(TITAN_REAGENTTRACKER_ID, "ShowSpellIcons")
	addon:UpdateButton()
end

function TitanPanelReagentTracker_GetTooltipText()
	local tooltipText = " "
	
	-- reagent info in tooltip
	for index, buff in ipairs(possessed) do
		local reagent = buff.reagentName
		if reagent and not buff.disabled and TitanGetVar(TITAN_REAGENTTRACKER_ID, "TrackReagent"..index) then
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
   tableIndex = 1 -- because LUA handles tables poorly, deciding that a table/list which has 2 sequential nil values in it
                    -- has no values after those nils, we have to use a manual counter to correctly store items in a list


    -- first up, let's fill our shopping cart
    -- for every spell we have
    for i = 1, table.getn(possessed) do
        local totalCountOfReagent = 0
        local desiredCountOfReagent = 0
        if possessed[i].reagentName ~= nil then
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
            DEFAULT_CHAT_FRAME:AddMessage("Found "..totalCountOfReagent.." "..possessed[i].reagentName.." in bags");
            if totalCountOfReagent >= desiredCountOfReagent then
                -- we got enough not gonna buy any more
            elseif totalCountOfReagent < desiredCountOfReagent then
                -- we don't have enough, let's buy some more
                shoppingCart[tableIndex] = {possessed[i].reagentName, desiredCountOfReagent-totalCountOfReagent}
                tableIndex = tableIndex+1
                if debug == true then 
                    DEFAULT_CHAT_FRAME:AddMessage("Added "..desiredCountOfReagent-totalCountOfReagent.." of "..possessed[i].reagentName.." to cart.");
                end
            end
        end
    end
 
    -- this is where we do the actual shopping
    -- at this point, shoppingCart looks like this:
    -- shoppingCart[x][1] = the reagent name
    -- shoppingCart[x][2] = how many reagents to buy
    
    local purchasingMessage = false;

    -- for each item in shoppingCart
    for i = 1, table.getn(shoppingCart) do
    -- check for each of the merchant's items to see if it's what we want
        for index = 0, GetMerchantNumItems() do
            local name, texture, price, quantity = GetMerchantItemInfo(index)
            -- if the merchant's item name matches the name of the item in the shopping cart
            if name == shoppingCart[i][1] then
                -- buy the item that we're currently looking at, and the amount that's in the shoppingCart
                BuyMerchantItem(index, shoppingCart[i][2])
                -- tell the user we're bought stuff for them
                if purchasingMessage ~= true then
                    DEFAULT_CHAT_FRAME:AddMessage("|cffffff00<TitanPanelReagents> Extra reagents bought.|r");        
                    purchasingMessage = true    -- only want to tell them once 
                end
            end
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