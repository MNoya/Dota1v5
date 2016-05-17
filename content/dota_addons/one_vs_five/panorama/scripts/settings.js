"use strict";

//--------------------------------------------------------------------------------------------------
// CUSTOM HOST PANEL
//--------------------------------------------------------------------------------------------------
var IsHost = false;

$("#only_mid").checked = true;
$("#disable_neutrals").checked = false;
$("#tier2").checked = true;
var gold = "3125"

function SetStartingGold() {
    if (!IsHost)
    {
        $("#starting_gold").text = gold
        return
    }

    if (gold == $("#starting_gold").text)
        return

    $("#starting_gold").text = $('#starting_gold').text.replace(/\D/g,'');

    if ($('#starting_gold').text.length > 4)
        $('#starting_gold').text = $('#starting_gold').text.substring(0, 4);

    if ($('#starting_gold').text != gold)
    {
        gold = $('#starting_gold').text
        GameEvents.SendCustomGameEventToServer("setting_change", {setting: "starting_gold", value: $("#starting_gold").text}); 
    }
}

var max_level = 10;
var min_level = 0;
function ValueChange(name, amount)
{
    if (!IsHost) return

    var panel = $("#"+name);
    if (panel !== null){
        var current_level = parseInt(panel.text)
        var new_level = current_level + parseInt(amount)
        if (new_level <= max_level && new_level >= min_level)
            panel.text = new_level
        else
            if (new_level < min_level)
                panel.text = min_level
            else
                panel.text = max_level
    }

    GameEvents.SendCustomGameEventToServer("setting_change", {setting: name, value: panel.text});
}

var currentRadioOption = '2'
var radios = {}
radios['1'] = $("#tier1")
radios['2'] = $("#tier2")
radios['5'] = $("#barracks")
radios['0'] = $("#ancient")

function SelectRadio(option) {
    if (!IsHost)
    {
        for (var i in radios)
        {
            var panel = radios[i]
            panel.checked = i == currentRadioOption
        }
    }
    else
    {
        currentRadioOption = option
        GameEvents.SendCustomGameEventToServer("setting_change", {setting: "win_at_tier", value: option}); 
    }
}

function Toggle(setting) {
    if (!IsHost)
        $("#"+setting).checked = !$("#"+setting).checked;
    else    
        GameEvents.SendCustomGameEventToServer("setting_change", {setting: setting, value: $("#"+setting).checked}); 
}

var number_settings = ["starting_gold","lasthit_mult","herokill_mult","gold_tick_bonus"]
var bool_settings = ["only_mid","disable_neutrals"]
function UpdateSettings() {
    if (!IsHost)
    {
        $.Msg("Host Changed Settings: ", CustomNetTables.GetAllTableValues("settings"))

        gold = CustomNetTables.GetTableValue("settings", "starting_gold").value
        for (var k of number_settings)
        {
            $("#"+k).text = CustomNetTables.GetTableValue("settings", k).value
        }
        
        //bools
        for (var k of bool_settings)
        {
            $("#"+k).checked = CustomNetTables.GetTableValue("settings", k).value == 1;
        }

        //radio
        currentRadioOption = CustomNetTables.GetTableValue("settings", "win_at_tier").value
        for (var i in radios)
        {
            var panel = radios[i]
            panel.checked = i == currentRadioOption
        }
    }
}

//--------------------------------------------------------------------------------------------------
// Check to see if the local player has host privileges and set the 'player_has_host_privileges' on
// the root panel if so, this allows buttons to only be displayed for the host.
//--------------------------------------------------------------------------------------------------
function CheckForHostPrivileges()
{
    SetStartingGold()
    var playerInfo = Game.GetLocalPlayerInfo();
    if ( !playerInfo )
        return;

    // Set the "player_has_host_privileges" class on the panel, this can be used 
    // to have some sub-panels on display or be enabled for the host player.
    IsHost = playerInfo.player_has_host_privileges;
    $.GetContextPanel().SetHasClass( "player_has_host_privileges", IsHost );

    // Update the Host name
    var playerIDs = Game.GetAllPlayerIDs()
    for (var i = 0; i < playerIDs.length; i++) {
        var pInfo = Game.GetPlayerInfo( i );
        if ( pInfo && pInfo.player_has_host_privileges){
            var HostName = Players.GetPlayerName( i )
            $('#Host').text = "HOST: "+HostName
        }
    }
    $.Schedule(0.1, CheckForHostPrivileges)
}

//--------------------------------------------------------------------------------------------------
// Entry point called when the team select panel is created
//--------------------------------------------------------------------------------------------------
(function()
{   
    CheckForHostPrivileges();
    CustomNetTables.SubscribeNetTableListener("settings", UpdateSettings)
})();
