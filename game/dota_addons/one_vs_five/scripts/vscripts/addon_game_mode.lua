-------------------------------
--   Default 1v5 Settings    --
-------------------------------

GameSettings = {
    ["starting_gold"] = 625*5, -- Initial gold on spawn of the single radiant player
    ["lasthit_mult"] = 5, -- Hero kill gold will be multiplied by this factor
    ["herokill_mult"] = 2, -- Hero kill gold will be multiplied by this factor
    ["gold_tick_bonus"] = 4, -- Extra gold gained every tick
    ["only_mid"] = 1, -- 1 enabled, 0 disabled
    ["disable_neutrals"] = 0, -- 1 disabled, 0 enabled
    ["win_at_tier"] = 2, -- 5 for barracks, 0 for ancient
}

GOLD_TICK_TIME = 0.6 -- Default dota tick time, 1 per second

-------------------------------

require('timers')

if GameMode == nil then
    GameMode = class({})
end

function Precache( context ) end

function Activate()
    GameRules.GameMode = GameMode()
    GameRules.GameMode:InitGameMode()
end

function GameMode:InitGameMode()
    GameRules:SetCustomGameTeamMaxPlayers(DOTA_TEAM_GOODGUYS, 1)
    GameRules:SetCustomGameTeamMaxPlayers(DOTA_TEAM_BADGUYS, 5)
    GameRules:SetGoldPerTick(0)

    ListenToGameEvent( "game_rules_state_change", Dynamic_Wrap( GameMode, 'OnGameRulesStateChange' ), self )
    ListenToGameEvent( "npc_spawned", Dynamic_Wrap( GameMode, "OnNPCSpawned" ), self )
    ListenToGameEvent( "entity_killed", Dynamic_Wrap( GameMode, "OnEntityKilled" ), self )
    GameRules:GetGameModeEntity():SetModifyGoldFilter( Dynamic_Wrap( GameMode, "FilterGold" ), self )
    GameRules:GetGameModeEntity():SetDamageFilter( Dynamic_Wrap( GameMode, "FilterDamage" ), self )

    for k,v in pairs(GameSettings) do
        CustomNetTables:SetTableValue("settings", k, {value=v})
    end    

    CustomGameEventManager:RegisterListener("setting_change", Dynamic_Wrap(GameMode, "OnSettingChange"))

    SendToServerConsole("dota_surrender_on_disconnect 0")
    SendToServerConsole("dota_wait_for_players_to_load_timeout 240")

    print('[1v5] Activated')
end

function GameMode:OnSettingChange(event)
    local setting = event.setting
    local value = tonumber(event.value)

    print("Setting Change: ",setting,value)

    -- Update nettable
    CustomNetTables:SetTableValue("settings", setting, {value=value})

    -- Update the lua value
    GameSettings[setting] = value
end

function GameMode:OnGameRulesStateChange( ... )
    local nNewState = GameRules:State_Get()
    if nNewState == DOTA_GAMERULES_STATE_GAME_IN_PROGRESS then
        if GameSettings["only_mid"]  == 1 then
            GameMode:OnlyMidTowers()
        end

        -- Gold tick custom
        Timers(GOLD_TICK_TIME, function()
            if GameRules:State_Get() == DOTA_GAMERULES_STATE_GAME_IN_PROGRESS then
                for playerID=0,5 do
                    if PlayerResource:IsValidPlayer(playerID) then
                        if PlayerResource:GetTeam(playerID) == DOTA_TEAM_GOODGUYS then
                            PlayerResource:ModifyGold(playerID, 1+GameSettings["gold_tick_bonus"] , false, 0)
                        else
                            PlayerResource:ModifyGold(playerID, 1, false, 0)
                        end
                    end
                end
                return GOLD_TICK_TIME
            end
        end)
    elseif nNewState == DOTA_GAMERULES_STATE_HERO_SELECTION then
        if GameSettings["only_mid"] == 1 then
            GameMode:OnlyMid()
        end
    end
end

function GameMode:OnNPCSpawned(event)
    local spawnedUnit = EntIndexToHScript(event.entindex)
    if spawnedUnit:IsRealHero() then
        if not spawnedUnit.bFirstSpawned then
            spawnedUnit.bFirstSpawned = true
            GameMode:OnHeroInGame(spawnedUnit)
            RADIANT_HERO = spawnedUnit
        end
    elseif spawnedUnit:IsNeutralUnitType() then
        if GameSettings["disable_neutrals"] == 1 then
            UTIL_Remove(spawnedUnit)
        end
    end
end

function GameMode:OnlyMid()
    local bot1 = Entities:FindByClassname(nil, "npc_dota_spawner_good_bot")
    local bot2 = Entities:FindByClassname(nil, "npc_dota_spawner_bad_bot")
    local top1 = Entities:FindByClassname(nil, "npc_dota_spawner_good_top")
    local top2 = Entities:FindByClassname(nil, "npc_dota_spawner_bad_top")
    if bot1 then bot1:RemoveSelf() end
    if bot2 then bot2:RemoveSelf() end
    if top1 then top1:RemoveSelf() end
    if top2 then top2:RemoveSelf() end
end

function GameMode:OnlyMidTowers()
    local towers = Entities:FindAllByClassname("npc_dota_tower")
    for _,ent in pairs(towers) do
        local name = ent:GetUnitName()
        if name:match("_tower1_bot") or name:match("_tower1_top") then
            ent:AddNewModifier(ent, nil, "modifier_invulnerable", {})
        end
    end
end

function GameMode:OnHeroInGame(hero)
    -- Bonus gold for radiant hero
    if hero:GetTeamNumber() == DOTA_TEAM_GOODGUYS then
        hero:SetGold(GameSettings["starting_gold"], false)
    end
end

function GameMode:OnEntityKilled(event)
    local killedUnit = EntIndexToHScript(event.entindex_killed)
    local killer = EntIndexToHScript(event.entindex_attacker or 0)
    local unitName = killedUnit:GetUnitName()
    local teamNumber = killedUnit:GetOpposingTeamNumber()

    -- Reduce respawn time of the radiant hero
    if killedUnit:IsRealHero() and killedUnit:GetTeamNumber() == DOTA_TEAM_GOODGUYS then
        killedUnit:SetTimeUntilRespawn(killedUnit:GetRespawnTime()/2)
    end

    -- Kill feed message and popup based on what the gold filter modified earlier
    if killedUnit:IsRealHero() and RADIANT_HERO and killer:GetTeamNumber() == DOTA_TEAM_GOODGUYS then
        local killGold = RADIANT_HERO.KillGold
        local assistGold = RADIANT_HERO.AssistGold
        local gold = killGold + assistGold
        local killerID = killer:GetPlayerID()
        GameRules:SendCustomMessage("%s1 killed a hero for <font color='#F0BA36'>"..gold.."</font> gold!", 0, killerID)

        RADIANT_HERO.KillGold = nil
        RADIANT_HERO.AssistGold = nil

        -- Fake Hero gold popup
        EmitSoundOnLocationForAllies(killedUnit:GetAbsOrigin(), "Gold.Coins", killer)
        local digits = #tostring(gold) + 1
        local particleName = "particles/msg_fx/msg_goldbounty.vpcf" --"particles/msg_fx/msg_gold.vpcf"
        local particle = ParticleManager:CreateParticleForTeam(particleName, PATTACH_OVERHEAD_FOLLOW, killedUnit, DOTA_TEAM_GOODGUYS)
        ParticleManager:SetParticleControl(particle, 0, killedUnit:GetAbsOrigin())
        ParticleManager:SetParticleControl(particle, 1, Vector(0, tonumber(gold), 0))
        ParticleManager:SetParticleControl(particle, 2, Vector(2.0, digits, 0))
        ParticleManager:SetParticleControl(particle, 3, Vector(255, 200, 33))

        print(unitName.." recieved a total of "..gold.." gold for killing "..killedUnit:GetUnitName())

        PlayerResource:ModifyGold(killerID, gold, true, DOTA_ModifyGold_Unspecified)
    elseif killedUnit:IsTower() and GameSettings["win_at_tier"] then
        local tier = unitName:gsub('%D','')
        print("Tower Killed: "..unitName.." - Tier "..tier)

        if GameSettings["win_at_tier"] == tonumber(tier) then
            print("Winner Team: "..teamNumber)
            GameRules:SetGameWinner(teamNumber)
        end
    elseif killedUnit:IsBarracks() and GameSettings["win_at_tier"] == 5 then
        print("Barracks Killed. Winner Team: "..teamNumber)
        GameRules:SetGameWinner(teamNumber)
    end
end

function GameMode:FilterGold(filterTable)
    local gold = filterTable["gold"]
    local playerID = filterTable["player_id_const"]
    local reason = filterTable["reason_const"]
    local reliable = filterTable["reliable"] == 1

    -- Special handling of hero kill gold (both bounty and assist gold goes through here first)
    if RADIANT_HERO and PlayerResource:GetTeam(playerID) == DOTA_TEAM_GOODGUYS and reason == DOTA_ModifyGold_HeroKill then
        local playerName = PlayerResource:GetPlayerName(playerID)
        if playerName == "" then playerName = "Player "..playerID end

        -- The Assist Gold is given first, then the Kill gold
        if not RADIANT_HERO.AssistGold then
            filterTable["gold"] = gold * GameSettings["herokill_mult"]
            RADIANT_HERO.AssistGold = filterTable["gold"]
            print(playerName.." recieved "..filterTable["gold"].." gold (bonus: "..filterTable["gold"]-gold..") due to a Hero Assist")
        elseif not RADIANT_HERO.KillGold then
            filterTable["gold"] = gold * GameSettings["herokill_mult"]
            RADIANT_HERO.KillGold = filterTable["gold"]
            print(playerName.." recieved "..filterTable["gold"].." gold (bonus: "..filterTable["gold"]-gold..") due to a Hero Kill")
        end
        return false --Denies the wrong popup gold, which is faked on OnEntityKilled
    end

    return true
end

function GameMode:FilterDamage(filterTable)
    local victim_index = filterTable["entindex_victim_const"]
    local attacker_index = filterTable["entindex_attacker_const"]
    if not victim_index or not attacker_index then
        return true
    end

    local victim = EntIndexToHScript( victim_index )
    local attacker = EntIndexToHScript( attacker_index )
    local damagetype = filterTable["damagetype_const"]
    local inflictor = filterTable["entindex_inflictor_const"]
    local damage = filterTable["damage"] --Post reduction

    -- Increase the gold bounty of kills done by the single player right before the units die
    if attacker:IsControllableByAnyPlayer() and attacker:GetTeamNumber() == DOTA_TEAM_GOODGUYS then
        if damage >= victim:GetHealth() then
            victim.baseMinBounty = victim.baseMinBounty or victim:GetMinimumGoldBounty() * GameSettings["lasthit_mult"] 
            victim.baseMaxBounty = victim.baseMaxBounty or victim:GetMaximumGoldBounty() * GameSettings["lasthit_mult"] 

            victim:SetMinimumGoldBounty(victim.baseMinBounty)
            victim:SetMaximumGoldBounty(victim.baseMaxBounty)
        end
    end

    return true
end

GOLD_REASONS = {
    [0] = "DOTA_ModifyGold_Unspecified",  
    [1] = "DOTA_ModifyGold_Death",  
    [2] = "DOTA_ModifyGold_Buyback",
    [3] = "DOTA_ModifyGold_PurchaseConsumable",
    [4] = "DOTA_ModifyGold_PurchaseItem",
    [5] = "DOTA_ModifyGold_AbandonedRedistribute",
    [6] = "DOTA_ModifyGold_SellItem",
    [7] = "DOTA_ModifyGold_AbilityCost",
    [8] = "DOTA_ModifyGold_CheatCommand",
    [9] = "DOTA_ModifyGold_SelectionPenalty",
    [10] = "DOTA_ModifyGold_GameTick",
    [11] = "DOTA_ModifyGold_Building",
    [12] = "DOTA_ModifyGold_HeroKill",
    [13] = "DOTA_ModifyGold_CreepKill",
    [14] = "DOTA_ModifyGold_RoshanKill",
    [15] = "DOTA_ModifyGold_CourierKill",
    [16] = "DOTA_ModifyGold_SharedGold",
}