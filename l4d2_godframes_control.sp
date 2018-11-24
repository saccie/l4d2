/*
    SourcePawn is Copyright (C) 2006-2015 AlliedModders LLC.  All rights reserved.
    SourceMod is Copyright (C) 2006-2015 AlliedModders LLC.  All rights reserved.
    Pawn and SMALL are Copyright (C) 1997-2015 ITB CompuPhase.
    Source is Copyright (C) Valve Corporation.
    All trademarks are property of their respective owners.

    This program is free software: you can redistribute it and/or modify it
    under the terms of the GNU General Public License as published by the
    Free Software Foundation, either version 3 of the License, or (at your
    option) any later version.

    This program is distributed in the hope that it will be useful, but
    WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
    General Public License for more details.

    You should have received a copy of the GNU General Public License along
    with this program.  If not, see <http://www.gnu.org/licenses/>.
*/
#pragma semicolon 1
#pragma newdecls required
/*
 * To-do:
 * Add flag cvar to control damage from different SI separately.
 * Add cvar to control whether tanks should reset frustration with hittable hits. Maybe.
 * 0.3.2b
 * Disable Transparance state and timer during godframes, this is proven to case invisible clients under certain circumstances
 */

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <left4downtown>
#include <l4d2_direct>
//#include <l4d2util> unneeded

#define CLASSNAME_LENGTH 64


//cvars
Handle hRageRock;
Handle hRageHittables;
Handle hHittable;
Handle hWitch;
Handle hFF;
Handle hSpit;
Handle hCommon;
Handle hHunter;
Handle hSmoker;
Handle hJockey;
Handle hCharger;
Handle hSpitFlags;
Handle hCommonFlags;
Handle hGodframeGlows;

//fake godframes
float  fFakeGodframeEnd[MAXPLAYERS + 1];
int iLastSI[MAXPLAYERS + 1];

//frustration
int frustrationOffset[MAXPLAYERS + 1];

public Plugin myinfo =
{
    name = "L4D2 Godframes Control (starring Austin Powers, Baby Yeah!)",
    author = "Stabby, CircleSquared, Tabun, Saccie",
    version = "0.3.2b",
    description = "Allows for control of what gets godframed and what doesnt.",
    url = "https://github.com/jacob404/Pro-Mod-4.0/releases/latest"
};

public void OnPluginStart()
{
    hGodframeGlows = CreateConVar("gfc_godframe_glows",         "0",   "Changes the rendering of survivors while godframed (red/transparent).",                                            FCVAR_DONTRECORD, true, 0.0, true, 1.0 );
    hRageHittables = CreateConVar("gfc_hittable_rage_override", "0",   "Allow tank to gain rage from hittable hits. 0 blocks rage gain.",                                                  FCVAR_DONTRECORD, true, 0.0, true, 1.0 );
    hRageRock      = CreateConVar("gfc_rock_rage_override",     "1",   "Allow tank to gain rage from godframed hits. 0 blocks rage gain.",                                                 FCVAR_DONTRECORD, true, 0.0, true, 1.0 );
    hHittable      = CreateConVar("gfc_hittable_override",      "0",   "Allow hittables to always ignore godframes.",                                                                      FCVAR_DONTRECORD, true, 0.0, true, 1.0 );
    hWitch         = CreateConVar("gfc_witch_override",         "0",   "Allow witches to always ignore godframes.",                                                                        FCVAR_DONTRECORD, true, 0.0, true, 1.0 );
    hFF            = CreateConVar("gfc_ff_min_time",            "0.0", "Minimum time before FF damage is allowed.",                                                                        FCVAR_DONTRECORD, true, 0.0, true, 3.0 );
    hSpit          = CreateConVar("gfc_spit_extra_time",        "0.0", "Additional godframe time before spit damage is allowed.",                                                          FCVAR_DONTRECORD, true, 0.0, true, 3.0 );
    hCommon        = CreateConVar("gfc_common_extra_time",      "0.0", "Additional godframe time before common damage is allowed.",                                                        FCVAR_DONTRECORD, true, 0.0, true, 3.0 );
    hHunter        = CreateConVar("gfc_hunter_duration",        "2.0", "How long should godframes after a pounce last?",                                                                   FCVAR_DONTRECORD, true, 0.0, true, 3.0 );
    hJockey        = CreateConVar("gfc_jockey_duration",        "2.0", "How long should godframes after a ride last?",                                                                     FCVAR_DONTRECORD, true, 0.0, true, 3.0 );
    hSmoker        = CreateConVar("gfc_smoker_duration",        "2.0", "How long should godframes after a pull or choke last?",                                                            FCVAR_DONTRECORD, true, 0.0, true, 3.0 );
    hCharger       = CreateConVar("gfc_charger_duration",       "2.0", "How long should godframes after a pummel last?",                                                                   FCVAR_DONTRECORD, true, 0.0, true, 3.0 );
    hSpitFlags     = CreateConVar("gfc_spit_zc_flags",          "0",   "Which classes will be affected by extra spit protection time. 1 - Hunter. 2 - Smoker. 4 - Jockey. 8 - Charger.",   FCVAR_DONTRECORD, true, 0.0, true, 15.0 );
    hCommonFlags   = CreateConVar("gfc_common_zc_flags",        "0",   "Which classes will be affected by extra common protection time. 1 - Hunter. 2 - Smoker. 4 - Jockey. 8 - Charger.", FCVAR_DONTRECORD, true, 0.0, true, 15.0 );

    HookEvent("tongue_release", PostSurvivorRelease);
    HookEvent("pounce_end", PostSurvivorRelease);
    HookEvent("jockey_ride_end", PostSurvivorRelease);
    HookEvent("charger_pummel_end", PostSurvivorRelease);
    HookEvent("round_start",            view_as<EventHook>(OnRoundStarted), EventHookMode_PostNoCopy);
    //HookEvent("round_end",              view_as<EventHook>(RoundEndedPre), EventHookMode_PostNoCopy);
    //HookEvent("player_left_start_area", view_as<EventHook>(OnLeaveSaferoom), EventHookMode_PostNoCopy);
}

public Action OnRoundStarted() // Checked
{
    for (int i = 1; i <= MaxClients; i++) //clear both fake and real just because
    {
        fFakeGodframeEnd[i] = 0.0;
    }
}

public Action PostSurvivorRelease(Handle event, const char[] name, bool dontBroadcast) // Checked
{
    int victim = GetClientOfUserId(GetEventInt(event,"victim"));

    if (!IsClientAndInGame(victim)) { return; } //just in case

    //sets fake godframe time based on cvars for each ZC
    if (StrContains(name, "tongue") != -1)
    {
        fFakeGodframeEnd[victim] = GetGameTime() + GetConVarFloat(hSmoker);
        iLastSI[victim] = 2;
    } else
    if (StrContains(name, "pounce") != -1)
    {
        fFakeGodframeEnd[victim] = GetGameTime() + GetConVarFloat(hHunter);
        iLastSI[victim] = 1;
    } else
    if (StrContains(name, "jockey") != -1)
    {
        fFakeGodframeEnd[victim] = GetGameTime() + GetConVarFloat(hJockey);
        iLastSI[victim] = 4;
    } else
    if (StrContains(name, "charger") != -1)
    {
        fFakeGodframeEnd[victim] = GetGameTime() + GetConVarFloat(hCharger);
        iLastSI[victim] = 8;
    }
    
    if (fFakeGodframeEnd[victim] > GetGameTime() && GetConVarBool(hGodframeGlows)) {
        //SetGodframedGlow(victim);
        //CreateTimer(fFakeGodframeEnd[victim] - GetGameTime(), Timed_ResetGlow, victim);
    }
    
    return;
}

public void OnClientPutInServer(int client)
{
    SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage);
}

public Action Timed_SetFrustration(Handle timer, any client) { // Checked
    if (IsClientConnected(client) && IsPlayerAlive(client) && GetClientTeam(client) == 3 && GetEntProp(client, Prop_Send, "m_zombieClass") == 8) {
        int frust = GetEntProp(client, Prop_Send, "m_frustration");
        frust += frustrationOffset[client];
        
        if (frust > 100) frust = 100;
        else if (frust < 0) frust = 0;
        
        SetEntProp(client, Prop_Send, "m_frustration", frust);
        frustrationOffset[client] = 0;
    }
}

public Action OnTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype, int &weapon, float damageForce[3], float damagePosition[3]) // Checked
{
    if (GetClientTeam(victim) != 2 || !IsValidEdict(victim) || !IsValidEdict(attacker) || !IsValidEdict(inflictor) || !IsClientAndInGame(victim)) { return Plugin_Continue; }

    CountdownTimer cTimerGod = L4D2Direct_GetInvulnerabilityTimer(victim);
    if (cTimerGod != CTimer_Null) { CTimer_Invalidate(cTimerGod); }

    char sClassname[CLASSNAME_LENGTH];
    GetEntityClassname(inflictor, sClassname, CLASSNAME_LENGTH);

    float fTimeLeft = fFakeGodframeEnd[victim] - GetGameTime();

    if (StrEqual(sClassname, "infected") && (iLastSI[victim] & GetConVarInt(hCommonFlags))) //commons
    {
        fTimeLeft += GetConVarFloat(hCommon);
    }
    if (StrEqual(sClassname, "insect_swarm") && (iLastSI[victim] & GetConVarInt(hSpitFlags))) //spit
    {
        fTimeLeft += GetConVarFloat(hSpit);
    }
    if (IsClientAndInGame(attacker) && GetClientTeam(victim) == GetClientTeam(attacker)) //friendly fire
    {
        if (fTimeLeft < GetConVarFloat(hFF) && fTimeLeft > 0.0) {
            fTimeLeft = GetConVarFloat(hFF);
        }
    }

    if (IsClientAndInGame(attacker) && GetClientTeam(attacker) == 3 && GetEntProp(attacker, Prop_Send, "m_zombieClass") == 8) {
        if (StrEqual(sClassname, "prop_physics")) {
            if (GetConVarBool(hRageHittables)) {
                frustrationOffset[attacker] = -100;
            } else {
                frustrationOffset[attacker] = 0;
            }
            CreateTimer(0.1, Timed_SetFrustration, attacker);
        } else
        if (weapon == 52) { //tank rock
            if (GetConVarBool(hRageRock)) {
                frustrationOffset[attacker] = -100;
            } else {
                frustrationOffset[attacker] = 0;
            }
            CreateTimer(0.1, Timed_SetFrustration, attacker);
        } else {
        
        }
    }

    if (fTimeLeft > 0) //means fake god frames are in effect
    {
        if (StrEqual(sClassname, "prop_physics")) //hittables
        {
            if (GetConVarBool(hHittable)) { return Plugin_Continue; }
        }
        else
        {
            if (StrEqual(sClassname, "witch")) //witches
            {
                if (GetConVarBool(hWitch)) { return Plugin_Continue; }
            }
        }
        return Plugin_Handled;
    }
    else
    {
        iLastSI[victim] = 0;
    }
    return Plugin_Continue;
}

stock bool IsClientAndInGame(const int client) // Checked
{
    return ((0 < client && client < MaxClients) ? (IsClientInGame(client)) : (false));
}

/* removed due to invisible client issue
public Action Timed_ResetGlow(Handle timer, any client) {
    ResetGlow(client);
}

void ResetGlow(const int client) {
    if (IsClientAndInGame(client)) {
        // remove transparency/color
        SetEntityRenderMode(client, RenderMode:0);
        SetEntityRenderColor(client, 255,255,255,255);
    }
}

void SetGodframedGlow(const int client) {   //there might be issues with realism
    if (IsClientAndInGame(client) && IsPlayerAlive(client) && GetClientTeam(client) == 2) {
        // make player transparent/red while godframed
        SetEntityRenderMode( client, RenderMode:3 );
        SetEntityRenderColor (client, 255,0,0,200 );
    }
}

public void OnMapStart() {
    for (int i = 0; i <= MaxClients; i++) {
        ResetGlow(i);
    }
}

*/