#include <sourcemod>
#include <tf2_stocks>

#pragma semicolon 1
#pragma newdecls required

#define PLUGIN_VERSION			"DM-Alpha"
#define PLUGIN_VERSION_REVISION	"custom"
#define PLUGIN_VERSION_FULL		PLUGIN_VERSION ... "." ... PLUGIN_VERSION_REVISION

#define CONFIG_FILE	"configs/propkill/specials.cfg"

#define FAR_FUTURE		100000000.0

enum struct Effect
{
	char Name[64];
	Function Func;
	int Slot;

	void Setup(KeyValues kv)
	{
		kv.GetString("func", this.Name, sizeof(this.Name));
		this.Func = GetFunctionByName(null, this.Name);

		this.Slot = kv.GetNum("slot", -1);

		kv.GetSectionName(this.Name, sizeof(this.Name));
	}
}

ConVar ForceEnable;
ConVar SpecialRounds;
ArrayList SpecialEffects;
ArrayList SpawnConditions;
bool GamemodeEnabled;
bool ForceSpecial;
Function Active1 = INVALID_FUNCTION;
Function Active2 = INVALID_FUNCTION;

public Plugin myinfo =
{
	name		=	"Prop Kill",
	author		=	"Batfoxkid",
	description	=	"Based on the BvB version!",
	version		=	PLUGIN_VERSION_FULL
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	CreateNative("PK_ForceSpecialRound", ForceSpecialRound);
	return APLRes_Success;
}

public void OnPluginStart()
{
	SpawnConditions = new ArrayList();

	ForceEnable = CreateConVar("pk_forceenable", "0", "If to force the gamemode enabled regardless of map", _, true, 0.0, true, 1.0);
	SpecialRounds = CreateConVar("pk_specialrounds", "0.25", "Special round chance in %", _, true, 0.0, true, 1.00001);
}

public void OnMapInit()
{
	char buffer[PLATFORM_MAX_PATH];
	int length = EntityLump.Length();
	for(int i; i < length; i++)
	{
		EntityLumpEntry entry = EntityLump.Get(i);

		int index = entry.FindKey("vscripts");
		if(index != -1)
		{
			entry.Get(index, _, _, buffer, sizeof(buffer));
			if(StrEqual(buffer, "propkill.nut", false))
			{
				GamemodeEnabled = true;

				// Replace with the server's version of the script
				if(FileExists("scripts/vscripts/propkill.nut", false))
				{
					DeleteFile("scripts/vscripts/_temppropkill.nut");
					if(RenameFile("scripts/vscripts/_temppropkill.nut", "scripts/vscripts/propkill.nut"))
					{
						entry.Update(index, NULL_STRING, "_temppropkill.nut");
						i = length;
					}
					else
					{
						LogError("Could not access scripts/vscripts/propkill.nut");
					}
				}
			}
		}

		delete entry;
	}

	if(!GamemodeEnabled && ForceEnable.BoolValue)
	{
		int index = EntityLump.Append();

		EntityLumpEntry entry = EntityLump.Get(index);
		entry.Append("classname", "logic_relay");
		entry.Append("vscripts", "propkill.nut");
		delete entry;

		GamemodeEnabled = true;
	}

	if(GamemodeEnabled)
	{
		HookEvent("teamplay_round_start", RoundStart, EventHookMode_PostNoCopy);
		HookEvent("teamplay_round_win", RoundEnd, EventHookMode_Post);
		HookEvent("player_spawn", PlayerSpawn, EventHookMode_Post);

		delete SpecialEffects;
		SpecialEffects = new ArrayList(sizeof(Effect));

		BuildPath(Path_SM, buffer, sizeof(buffer), CONFIG_FILE);

		KeyValues kv = new KeyValues("Effects");
		kv.ImportFromFile(buffer);
		kv.GotoFirstSubKey();

		Effect effect;

		do
		{
			effect.Setup(kv);
			SpecialEffects.PushArray(effect);
		}
		while(kv.GotoNextKey());

		delete kv;
	}
}

public void OnConfigsExecuted()
{
	if(GamemodeEnabled)
	{
		ConVar cvar = FindConVar("sv_enablebunnyhopping");
		if(cvar)
			cvar.BoolValue = true;

		cvar = FindConVar("sv_autobunnyhopping");
		if(cvar)
			cvar.BoolValue = true;

		cvar = FindConVar("sv_duckbunnyhopping");
		if(cvar)
			cvar.BoolValue = true;
	}
}

public void OnMapEnd()
{
	if(GamemodeEnabled)
	{
		GamemodeEnabled = false;

		CleanEffects();
		UnhookEvent("teamplay_round_start", RoundStart, EventHookMode_PostNoCopy);
		UnhookEvent("teamplay_round_win", RoundEnd, EventHookMode_PostNoCopy);
		UnhookEvent("player_spawn", PlayerSpawn, EventHookMode_Post);

		ConVar cvar = FindConVar("sv_enablebunnyhopping");
		if(cvar)
			cvar.BoolValue = false;

		cvar = FindConVar("sv_autobunnyhopping");
		if(cvar)
			cvar.BoolValue = false;

		cvar = FindConVar("sv_duckbunnyhopping");
		if(cvar)
			cvar.BoolValue = false;

		if(FileExists("scripts/vscripts/_temppropkill.nut", false))
		{
			RenameFile("scripts/vscripts/propkill.nut", "scripts/vscripts/_temppropkill.nut");
		}
	}
}

void RoundStart(Event event, const char[] name, bool dontBroadcast)
{
	CleanEffects();

	if(GameRules_GetProp("m_bInWaitingForPlayers") || !SpecialEffects.Length)
		return;

	if(ForceSpecial || SpecialRounds.FloatValue > GetURandomFloat())
	{
		ForceSpecial = false;
		CreateTimer(0.1, SpecialRoundTimer, 50, TIMER_FLAG_NO_MAPCHANGE);
	}
}

void RoundEnd(Event event, const char[] name, bool dontBroadcast)
{
	CleanEffects();
}

void PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if(client)
	{
		int length = SpawnConditions.Length;
		for(int i; i < length; i++)
		{
			TF2_AddCondition(client, SpawnConditions.Get(i));
		}
	}
}

void CleanEffects()
{
	if(Active2 != INVALID_FUNCTION)
	{
		Call_StartFunction(null, Active2);
		Call_PushCell(false);
		Call_Finish();

		Active2 = INVALID_FUNCTION;
	}

	if(Active1 != INVALID_FUNCTION)
	{
		Call_StartFunction(null, Active1);
		Call_PushCell(false);
		Call_Finish();

		Active1 = INVALID_FUNCTION;
	}

	SpawnConditions.Clear();
}

void AddSpawnCondition(TFCond cond)
{
	SpawnConditions.Push(cond);

	for(int client = 1; client <= MaxClients; client++)
	{
		if(IsClientInGame(client) && IsPlayerAlive(client))
			TF2_AddCondition(client, cond);
	}
}

void RemoveSpawnCondition(TFCond cond)
{
	int pos = SpawnConditions.FindValue(cond);
	if(pos != -1)
		SpawnConditions.Erase(pos);

	for(int client = 1; client <= MaxClients; client++)
	{
		if(IsClientInGame(client) && IsPlayerAlive(client))
			TF2_RemoveCondition(client, cond);
	}
}

void CallScriptFunction(const char[] name)
{
	char buffer[64];

	int entity = -1;
	while((entity=FindEntityByClassname(entity, "*")) != -1)
	{
		GetEntPropString(entity, Prop_Data, "m_iszVScripts", buffer, sizeof(buffer));
		if(StrEqual(buffer, "propkill.nut") || StrEqual(buffer, "_temppropkill.nut"))
		{
			SetVariantString(name);
			AcceptEntityInput(entity, "CallScriptFunction", entity, entity);
			return;
		}
	}

	LogError("Could not find VScript hosted entity");
}

Action SpecialRoundTimer(Handle timer, int anim)
{
	Effect effect1;

	if(anim < 1)
	{
		Effect effect2;
		effect2.Func = INVALID_FUNCTION;

		int choosen = GetURandomInt() % SpecialEffects.Length;
		SpecialEffects.GetArray(choosen, effect1);

		if(SpecialRounds.FloatValue > GetURandomFloat())
		{
			ArrayList list = new ArrayList();

			int length = SpecialEffects.Length;
			for(int i; i < length; i++)
			{
				if(i == choosen)
					continue;

				SpecialEffects.GetArray(i, effect2);
				if(effect1.Slot == -1 || effect1.Slot != effect2.Slot)
					list.Push(i);
			}

			length = list.Length;
			if(length)
			{
				SpecialEffects.GetArray(list.Get(GetURandomInt() % length), effect2);
			}
			else
			{
				effect2.Name[0] = 0;
				effect2.Func = INVALID_FUNCTION;
			}
		}

		if(effect1.Func != INVALID_FUNCTION)
		{
			Call_StartFunction(null, effect1.Func);
			Call_PushCell(true);
			Call_Finish();

			Active1 = effect1.Func;
		}

		if(effect2.Func != INVALID_FUNCTION)
		{
			Call_StartFunction(null, effect2.Func);
			Call_PushCell(true);
			Call_Finish();

			Active2 = effect2.Func;
		}

		PrintCenterTextAll("SPECIAL ROUND\n \n%s\n%s", effect1.Name, effect2.Name);
	}
	else
	{
		SpecialEffects.GetArray(anim % SpecialEffects.Length, effect1);

		PrintCenterTextAll("SPECIAL ROUND\n \n%s\n ", effect1.Name);
		CreateTimer(0.1, SpecialRoundTimer, anim - 1, TIMER_FLAG_NO_MAPCHANGE);
	}
	return Plugin_Continue;
}

any ForceSpecialRound(Handle plugin, int numParams)
{
	ForceSpecial = GetNativeCell(1);
	return 0;
}

public void Effect_PlayerPickup(bool enable)
{
	if(enable)
		CallScriptFunction("EnablePickupPlayers");
}

public void Effect_SuperPickup(bool enable)
{
	if(enable)
		CallScriptFunction("SetSuperPickup");
}

public void Effect_SuperGhost(bool enable)
{
	if(enable)
	{
		CallScriptFunction("SetSuperGhost");
		FindConVar("tf_ghost_up_speed").SetString("1200.0f");
		FindConVar("tf_ghost_xy_speed").SetString("1200.0f");
	}
}

public void Effect_SuperSpin(bool enable)
{
	if(enable)
		CallScriptFunction("SetSuperSpin");
}

public void Effect_HighTimescale(bool enable)
{
	if(enable)
	{
		FindConVar("phys_timescale").FloatValue = 2.0;
	}
	else
	{
		FindConVar("phys_timescale").FloatValue = 1.0;
	}
}

public void Effect_LowTimescale(bool enable)
{
	if(enable)
	{
		FindConVar("phys_timescale").FloatValue = 0.5;
	}
	else
	{
		FindConVar("phys_timescale").FloatValue = 1.0;
	}
}

public void Effect_Invisible(bool enable)
{
	if(enable)
	{
		AddSpawnCondition(TFCond_StealthedUserBuffFade);
	}
	else
	{
		RemoveSpawnCondition(TFCond_StealthedUserBuffFade);
	}
}

public void Effect_SmallPlayer(bool enable)
{
	if(enable)
	{
		AddSpawnCondition(TFCond_HalloweenTiny);
	}
	else
	{
		RemoveSpawnCondition(TFCond_HalloweenTiny);
	}
}

public void Effect_BigPlayer(bool enable)
{
	if(enable)
	{
		AddSpawnCondition(TFCond_HalloweenGiant);
	}
	else
	{
		RemoveSpawnCondition(TFCond_HalloweenGiant);
	}
}

public void Effect_SwimPlayer(bool enable)
{
	if(enable)
	{
		AddSpawnCondition(TFCond_SwimmingCurse);
	}
	else
	{
		RemoveSpawnCondition(TFCond_SwimmingCurse);
	}
}

public void Effect_RNGDodge(bool enable)
{
	if(enable)
	{
		AddSpawnCondition(TFCond_ObscuredSmoke);
	}
	else
	{
		RemoveSpawnCondition(TFCond_ObscuredSmoke);
	}
}
