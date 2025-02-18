/*
	Prop Kill DM 2/17 Build by Batfoxkid
	Gravity Gun edits by ficool2

	Map Requirements:
	- logic_relay using "vscripts" "propkill.nut"
	- Custom gravity gun worldmodel & viewmodel packed
	- prop_physics for players to use

	Recommended:
	- Atleast 5 or more seconds of setup time
	- At most 5 minutes round timer
	- Keep large-scale objects count low (they're power weapons)

	TODO:
	- Add details
	- TF2-ify Gravity Gun?
	- Fake GUI for Scores
*/

// Localization
::HINTCONTROL <- "%+attack% LAUNCH OBJECT %+attack2% GRAB OBJECT %+reload% ZAP OBJECT"
::WONROUND <- "got the most kills!"
::HINTSCOUT <- "Scout runs the fastest and can double jump"
::HINTSOLDIER <- "Soldier can rotate objects faster"
::HINTPYRO <- "Pyro ignites thrown and zapped objects"
::HINTDEMOMAN <- "Demoman takes no damage from self-inflicted explosives"
::HINTHEAVY <- "Heavy takes less damage from all objects"
::HINTENGINEER <- "Engineer can freeze objects by throwing them while rotating"
::HINTMEDIC <- "Medic regenerates health quickly"
::HINTSNIPER <- "Sniper can zap objects more often"
::HINTSPY <- "Spy won't collide with held objects"
::PLAYINGTO <- "Playing to "
::FIRST <- "1st: "
::SECOND <- "2nd: "
::THIRD <- "3rd: "
::YOU <- "You: "

// Settings
local PlayerPickup = false;	// Allow players to pick up each other
local PickupRange = 500.0;	// Pickup item range
local ZapRange = 10000.0;	// Zap item range
local ThrowPower = 1000.0;	// Throw prop power
local RotateSpeed = 75.0;	// Holding rotate speed
local SpinSpeed = 300.0;	// Throwing rotate speed
local GhostRange = 300.0;	// Ghost push range
local GhostPush = 0.25;		// Ghost push power
local ClassChanges = true;	// Class description text
local KillLimit = 5;		// Lowest game kill objective
::WGRAVITYGUN <- "models/propkill/w_physcannon.mdl";	// Gravity Gun worldmodel
::VGRAVITYGUN <- "models/propkill/v_physcannon.mdl";	// Gravity Gun viewmodel
VCLASSHANDS <-	// Gravity Gun viewmodel
[
    "models/weapons/c_models/c_scout_arms.mdl",
    "models/weapons/c_models/c_sniper_arms.mdl",
    "models/weapons/c_models/c_soldier_arms.mdl",
    "models/weapons/c_models/c_demo_arms.mdl",
    "models/weapons/c_models/c_medic_arms.mdl",
    "models/weapons/c_models/c_heavy_arms.mdl",
    "models/weapons/c_models/c_pyro_arms.mdl",
    "models/weapons/c_models/c_spy_arms.mdl",
    "models/weapons/c_models/c_engineer_arms.mdl",
];
PlayerKills <- {};
GameTextEntity <- {};

// Precache
Convars.SetValue("mp_autoteambalance", "0");	// Not needed to keep teams balanced
Convars.SetValue("mp_disable_respawn_times", "1");	// Short respawn times
Convars.SetValue("mp_forcecamera", "0");			// Allows spectating all players
Convars.SetValue("mp_friendlyfire", "1");				// Allows props to damage on impact
Convars.SetValue("mp_scrambleteams_auto", "1");				// Scrambles players every round
Convars.SetValue("mp_scrambleteams_auto_windifference", "1");	// Scrambles players every round
Convars.SetValue("tf_avoidteammates", "1");					// Disable teammate collision
Convars.SetValue("tf_spawn_glows_duration", "0.0");		// No friendly outlines
Convars.SetValue("tf_spec_xray", "2");				// Allows spectating all players
Convars.SetValue("sv_turbophysics", "0");		// Expensive physics
PrecacheScriptSound("Breakable.Computer");
PrecacheScriptSound("Halloween.GhostBoo");
PrecacheSound("weapons/physcannon/superphys_launch1.wav");
PrecacheSound("weapons/physcannon/superphys_launch2.wav");
PrecacheSound("weapons/physcannon/superphys_launch4.wav");
PrecacheSound("weapons/physcannon/physcannon_charge.wav");
PrecacheSound("weapons/physcannon/physcannon_dryfire.wav");
PrecacheSound("weapons/physcannon/physcannon_pickup.wav");
PrecacheSound("weapons/physcannon/physcannon_claws_open.wav");
PrecacheSound("weapons/physcannon/physcannon_drop.wav");
PrecacheSound("weapons/physcannon/hold_loop.wav");
PrecacheSound("weapons/physcannon/physcannon_tooheavy.wav");
PrecacheModel("sprites/laserbeam.spr");
local GravityGunWorldmodel = PrecacheModel(WGRAVITYGUN);
local GravityGunViewmodel = PrecacheModel(VGRAVITYGUN);
HandViewmodel <- [];
foreach(model in VCLASSHANDS)
{
    HandViewmodel.append(PrecacheModel(model));
}

function PlayerThink()
{
	// Round is not running
	if(IsInSetup())
		return;

	local ghost = self.InCond(Constants.ETFCond.TF_COND_HALLOWEEN_GHOST_MODE);
	local alive = IsPlayerAlive(self) && !ghost;
	local buttons = alive ? NetProps.GetPropInt(self, "m_nButtons") : 0;
	local attack1 = !(LastButtons & Constants.FButtons.IN_ATTACK) && (buttons & Constants.FButtons.IN_ATTACK);
	local attack2 = !attack1 && !(LastButtons & Constants.FButtons.IN_ATTACK2) && (buttons & Constants.FButtons.IN_ATTACK2);
	local reload = !attack1 && !attack2 && !(LastButtons & Constants.FButtons.IN_RELOAD) && (buttons & Constants.FButtons.IN_RELOAD);

	if(ghost)
	{
		// Ghost AOE push
		local origin = self.GetOrigin();
		local entity = null;
		while(entity = Entities.FindInSphere(entity, origin, GhostRange))
		{
			if(!IsProp(entity)  || PropHeldByPlayer(entity))
			{
				// Don't push non-props or held props
				continue;
			}

			local velocity = (entity.GetOrigin() - origin);
			velocity *= ((GhostRange - velocity.Length()) / GhostRange) * GhostPush;
			entity.ApplyAbsVelocityImpulse(velocity);

			NetProps.SetPropEntity(entity, "m_hPhysicsAttacker", self);
		}
	}

	if(reload)
	{
		// Zap attack cooldown
		if(NetProps.GetPropFloat(self, "m_flNextAttack") > Time())
			reload = false;
	}

	if(attack1 || attack2 || reload)
	{
		if(HeldProp.IsValid() && HeldProp != self)
		{
			if(attack2)	// Drop Prop
			{
				if(!HeldProp.IsPlayer())
				{
					if(HeldProp.GetOwner() == self)
					{
						// Remove Spy owner status
						HeldProp.SetOwner(null);
					}
				}

				HeldProp = self;

				self.StopSound("weapons/physcannon/hold_loop.wav");
				self.StopSound("weapons/physcannon/physcannon_pickup.wav");
				EmitSoundEx(
				{
					sound_name = "weapons/physcannon/physcannon_drop.wav",
					channel = 6,
					sound_level = 80,
					entity = self
				});
			}
		}
		else
		{
			local trace =
			{
				start = self.EyePosition(),
				end = self.EyePosition() + self.EyeAngles().Forward() * (reload ? ZapRange : PickupRange),
				ignore = self,
				hullmin = Vector(-5.0, -5.0, -5.0),
				hullmax = Vector(5.0, 5.0, 5.0),
			}

			TraceHull(trace);

			if(reload)
			{
				DrawZapEffectPosition(self, trace.endpos);

				if(GetPlayerClass(self) == Constants.ETFClass.TF_CLASS_SNIPER)
				{
					// Sniper has a decreased cooldown
					NetProps.SetPropFloat(self, "m_flNextAttack", Time() + 0.75);
				}
				else
				{
					NetProps.SetPropFloat(self, "m_flNextAttack", Time() + 2.0);
				}
			}

			if(trace.hit && CanPickupProp(trace.enthit, reload))
			{
				// If "Prevent pickup" flag is enabled, don't allow holding
				if(!attack2 || !(NetProps.GetPropInt(trace.enthit, "m_spawnflags") & 512))
				{
					if(trace.enthit.IsPlayer())
					{
						trace.enthit.ValidateScriptScope();
						trace.enthit.GetScriptScope().LastGrabbedBy = self;
					}
					else
					{
						EntFireByHandle(trace.enthit, "EnableMotion", "", -1.0, self, self);
						NetProps.SetPropInt(trace.enthit, "m_fEffects", 0);

						if(IsProp(trace.enthit))
						{
							NetProps.SetPropEntity(trace.enthit, "m_hPhysicsAttacker", self);
						}

						if(attack2 &&
							GetPlayerClass(self) == Constants.ETFClass.TF_CLASS_SPY &&
							trace.enthit.GetOwner() == null)
						{
							// Spy can go through holidng props
							trace.enthit.SetOwner(self);
						}
					}

					if(attack2)
					{
						EmitSoundEx(
						{
							sound_name = "weapons/physcannon/physcannon_pickup.wav",
							channel = 6,
							sound_level = 80,
							entity = self
						});

						// TODO: Call OnPlayerPickup, etc.
					}

					if(reload)	// Zap Prop
					{
						if(GetPlayerClass(self) == Constants.ETFClass.TF_CLASS_PYRO)
						{
							// Pyro ignites props
							EntFireByHandle(trace.enthit, "Ignite", "", -1.0, self, self);
						}

						trace.enthit.TakeDamage(1000.0, 0, self);	// TODO: Fix prop gibs
						EmitSoundOn("Breakable.Computer", self);
					}
					else
					{
						HeldProp = trace.enthit;
					}
				}
			}
			else if(reload)
			{
				EmitSoundOn("Breakable.Computer", self);
			}
			else
			{
				EmitSoundEx(
				{
					sound_name = "weapons/physcannon/physcannon_dryfire.wav",
					channel = 6,
					sound_level = 60,
					entity = self
				});
			}
		}

		// Throw Prop
		if(attack1 && HeldProp.IsValid() && HeldProp != self)
		{
			if(GetPlayerClass(self) == Constants.ETFClass.TF_CLASS_ENGINEER &&
				!HeldProp.IsPlayer() &&
				(buttons & (Constants.FButtons.IN_RELOAD|Constants.FButtons.IN_ATTACK3)))
			{
				// Engineer freezes props if holding reload/attack3
				EntFireByHandle(HeldProp, "DisableMotion", "", -1.0, self, self);
				NetProps.SetPropInt(HeldProp, "m_fEffects", Constants.FEntityEffects.EF_ITEM_BLINK);
				self.StopSound("weapons/physcannon/physcannon_pickup.wav");
				EmitSoundEx(
				{
					sound_name = "weapons/physcannon/physcannon_tooheavy.wav",
					channel = 6,
					sound_level = 80,
					entity = self
				});
			}
			else
			{
				local eyepos = self.EyePosition();
				local eyeang = self.EyeAngles();
				local proppos = HeldProp.GetOrigin();
				local propang = HeldProp.GetAbsAngles();

				local forward = eyeang.Forward() * ThrowPower;

				local velocity = eyepos + forward - proppos;
				velocity = velocity * 10.0;

				HeldProp.Teleport(false, proppos, false, propang, true, velocity);

				local swing = Vector(0.0, 0.0, 0.0);

				local speed = SpinSpeed;

				if(GetPlayerClass(self) == Constants.ETFClass.TF_CLASS_SOLDIER)
				{
					speed *= 2.5;
				}

				if(buttons & Constants.FButtons.IN_ATTACK3)
				{
					swing.y += speed;
				}

				if(buttons & Constants.FButtons.IN_RELOAD)
				{
					swing.z -= speed;
				}

				if(!HeldProp.IsPlayer())
				{
					if(GetPlayerClass(self) == Constants.ETFClass.TF_CLASS_PYRO)
					{
						// Pyro ignites props
						EntFireByHandle(HeldProp, "Ignite", "", -1.0, self, self);
					}

					if(HeldProp.GetOwner() == self)
					{
						// Remove Spy owner status
						HeldProp.SetOwner(null);
					}
				}

				HeldProp.SetPhysAngularVelocity(swing);
				self.StopSound("weapons/physcannon/physcannon_pickup.wav");
				EmitSoundEx(
				{
					sound_name = "weapons/physcannon/superphys_launch2.wav",
					channel = 6,
					sound_level = 90,
					entity = self
				});
			}

			HeldProp = self;
			self.StopSound("weapons/physcannon/hold_loop.wav");
		}
	}

	if(HeldProp != self && HeldProp.IsValid())
	{
		local eyepos = self.EyePosition();
		local eyeang = self.EyeAngles();
		local proppos = HeldProp.GetOrigin();
		local propang = HeldProp.GetAbsAngles();
		local maxs = HeldProp.GetBoundingMaxs();
		local mins = HeldProp.GetBoundingMins();

		local sideways = (90.0 - fabs(eyeang.x)) / 90.0;	// Looking up moves towards your center
		local upwards = 1.0 - (eyeang.x / 45.0);	// Looking downwards atleast at 45 allows you to prop surf
		if(upwards > 1.0)
		{
			upwards = 1.0;
		}
		else if(upwards < 0.0)
		{
			upwards = 0.0;
		}

		local distance = (maxs.x - mins.x) * sideways;
		if(distance < (maxs.y - mins.y) * sideways)
		{
			distance = (maxs.y - mins.y) * sideways;
		}

		if(distance < (maxs.z - mins.z) * upwards)
		{
			distance = (maxs.z - mins.z) * upwards;
		}

		distance = distance + (100.0 * upwards);

		local forward = eyeang.Forward() * distance;

		local velocity = eyepos + forward - proppos;
		velocity = velocity * 10.0;

		HeldProp.Teleport(false, proppos, false, propang, true, velocity);

		if(!HeldProp.IsPlayer())
		{
			local swing = Vector(0.0, 0.0, 0.0);

			local speed = RotateSpeed;

			if(GetPlayerClass(self) == Constants.ETFClass.TF_CLASS_SOLDIER)
			{
				speed *= 2.5;
			}

			if(buttons & Constants.FButtons.IN_ATTACK3)
			{
				swing.y += speed;
			}

			if(buttons & Constants.FButtons.IN_RELOAD)
			{
				swing.z -= speed;
			}

			HeldProp.SetPhysAngularVelocity(swing);
		}
	}

	if(RespawnTime !=  0.0)
	{
		if(GetRoundState() != Constants.ERoundState.GR_STATE_RND_RUNNING)
		{
			// Round already ended
			RespawnTime = 0.0;
		}
		else if(RespawnTime < Time())
		{
			// Respawn timer
			RespawnTime = 0.0;
			self.ForceRespawn();
		}
	}

	if(!(buttons & Constants.FButtons.IN_SCORE))
	{
		// Display scores
		local place1 = null;
		local score1 = 0;
		local place2 = null;
		local score2 = 0;
		local place3 = null;
		local score3 = 0;
		for(local i = 1; i <= MaxClients().tointeger(); i++)
		{
			local player = PlayerInstanceFromIndex(i);
			if(player == null)
				continue;

			local score = GetPlayerScore(player);
			if(score > score1)
			{
				place3 = place2;
				score3 = score2;
				place2 = place1;
				score2 = score1;
				place1 = player;
				score1 = score;
			}
			else if(score > score2)
			{
				place3 = place2;
				score3 = score2;
				place2 = player;
				score2 = score;
			}
			else if(score > score3)
			{
				place3 = player;
				score3 = score;
			}
		}

		local gameText = GetPlayerGameText(self);
		if(gameText == null)
		{
			// Setup entity and kill goal
			gameText = SpawnEntityFromTable("game_text",
			{
				x = 0.01,
				y = 0.01,
				color = "255 255 255 255",
				holdtime = 0.5,
				channel = 1,
				spawnflags = 0
			});

			// Setup cvars
			Convars.SetValue("tf_avoidteammates", "0");

			local playerCount = 0;
			for(local i = 1; i <= MaxClients().tointeger(); i++)
			{
				local player = PlayerInstanceFromIndex(i);
				if(player != null && player.GetTeam() > 1)
				{
					playerCount++;
				}
			}

			playerCount = playerCount * 3 / 2;	// x1.5 of player count

			if(playerCount > 20)	// Upper limit of 20
			{
				playerCount = 20;
			}

			if(playerCount > KillLimit)
			{
				KillLimit = playerCount;
			}

			SetPlayerGameText(self, gameText);
		}

		local name1 = place1 == null ? "N/A" : NetProps.GetPropString(place1, "m_szNetname");
		local name2 = place2 == null ? "N/A" : NetProps.GetPropString(place2, "m_szNetname");
		local name3 = place3 == null ? "N/A" : NetProps.GetPropString(place3, "m_szNetname");
		local score = GetPlayerScore(self);

		NetProps.SetPropString(gameText, "m_iszMessage", PLAYINGTO + KillLimit + "\n \n" + FIRST + name1 + " - " + score1 + "\n" + SECOND + name2 + " - " + score2 + "\n" + THIRD + name3 + " - " + score3 + "\n \n" + YOU + score);
		EntFireByHandle(gameText, "Display", "", -1.0, self, self);
	}

	LastButtons = buttons;
	return -1;
}

function PostInventory()
{
	// Note: HIDEHUD_METAL also hides damage numbers, so don't use that
	self.AddHudHideFlags(Constants.FHideHUD.HIDEHUD_WEAPONSELECTION |
		Constants.FHideHUD.HIDEHUD_BUILDING_STATUS |
		Constants.FHideHUD.HIDEHUD_CLOAK_AND_FEIGN |
		Constants.FHideHUD.HIDEHUD_PIPES_AND_CHARGE |
		Constants.FHideHUD.HIDEHUD_TARGET_ID);

	// Some cases where Spy could be cloaked
	self.RemoveCond(Constants.ETFCond.TF_COND_STEALTHED);

	local size = NetProps.GetPropArraySize(self, "m_hMyWeapons")
	for(local i = 0; i < size; i++)
	{
		local weapon = NetProps.GetPropEntityArray(self, "m_hMyWeapons", i);

		// Ignore spellbooks (cosmetic)
		if(weapon == null || startswith(weapon.GetClassname(), "tf_weapon_spellbook"))
			continue;

		RemoveWeapon(weapon);
	}

	for(local i = self.FirstMoveChild(); i != null; i = i.NextMovePeer())
	{
		if(!startswith(i.GetClassname(), "tf_wearable"))
			continue

		// Remove wearable weapons
		// (Current method is bad in the case of a new wearable weapon)
		switch(NetProps.GetPropInt(i, "m_AttributeManager.m_Item.m_iItemDefinitionIndex"))
		{
			case 133:	// Gunboats
			case 444:	// Mantreads
			case 405:	// Ali Baba's Wee Booties
			case 608:	// Bootlegger
			case 131:	// Chargin' Targe
			case 406:	// Splendid Screen
			case 1099:	// Tide Turner
			case 1144:	// Festive Targe
			case 57:	// Razorback
			case 231:	// Darwin's Danger Shield
			case 642:	// Cozy Camper
				EntFireByHandle(i, "Kill", "", -1.0, null, null);
				break;
		}
	}

	// Give Gravity Gun display weapon
	if(!self.InCond(Constants.ETFCond.TF_COND_HALLOWEEN_GHOST_MODE))
	{
		DisplayHudHint(self, HINTCONTROL);

		local healthRegen = 0.0;
		local speedChange = 0.8;
		local classname = "tf_weapon_shotgun_soldier";
		switch(GetPlayerClass(self))
		{
			case Constants.ETFClass.TF_CLASS_SCOUT:
				classname = "tf_weapon_scattergun";
				speedChange = 1.3;	// 520 HU
				break;

			case Constants.ETFClass.TF_CLASS_SOLDIER:
				classname = "tf_weapon_shotgun_soldier";
				speedChange = 1.916667;	// 460 HU
				break;

			case Constants.ETFClass.TF_CLASS_PYRO:
				classname = "tf_weapon_shotgun_pyro";
				speedChange = 1.6;	// 480 HU
				break;

			case Constants.ETFClass.TF_CLASS_DEMOMAN:
				classname = "tf_weapon_grenadelauncher";
				speedChange = 1.678571;	// 470 HU
				break;

			case Constants.ETFClass.TF_CLASS_HEAVYWEAPONS:
				classname = "tf_weapon_shotgun_hwg";
				speedChange = 2.0;	// 460 HU
				break;

			case Constants.ETFClass.TF_CLASS_ENGINEER:
				classname = "tf_weapon_shotgun_primary";
				speedChange = 1.6;	// 480 HU
				break;

			case Constants.ETFClass.TF_CLASS_MEDIC:
				classname = "tf_weapon_syringegun_medic";
				speedChange = 1.5;	// 480 HU
				healthRegen = 50.0;
				break;

			case Constants.ETFClass.TF_CLASS_SNIPER:
				classname = "tf_weapon_smg";
				speedChange = 1.6;	// 480 HU
				break;

			case Constants.ETFClass.TF_CLASS_SPY:
				classname = "tf_weapon_revolver";
				speedChange = 1.5;	// 480 HU
				break;
		}

		// Spawn our dummy weapon for animations
		local weapon = Entities.CreateByClassname(classname);
		NetProps.SetPropInt(weapon, "m_AttributeManager.m_Item.m_iItemDefinitionIndex", 267);	// Haunted Metal Scrap (as our dummy index)
		NetProps.SetPropInt(weapon, "m_AttributeManager.m_Item.m_iAccountID", GetPlayerAccount(self));	// Hides the name in the HUD
		NetProps.SetPropBool(weapon, "m_AttributeManager.m_Item.m_bInitialized", true);
		NetProps.SetPropBool(weapon, "m_bValidatedAttachedEntity", true);
		weapon.SetTeam(self.GetTeam());
		Entities.DispatchSpawn(weapon);

		NetProps.SetPropInt(weapon, "m_iPrimaryAmmoType", 3);	// Hides the ammo counter
		weapon.AddAttribute("move speed bonus", speedChange, -1.0);
		weapon.AddAttribute("health drain medic", healthRegen, -1.0);
		weapon.AddAttribute("cancel falling damage", 1.0, -1.0);
		weapon.AddAttribute("dmg taken from fire reduced", 0.25, -1.0);

		NetProps.SetPropInt(weapon, "m_iWorldModelIndex", GravityGunWorldmodel);

		for(local i = 0; i < 4; i++)
		{
			NetProps.SetPropIntArray(weapon, "m_nModelIndexOverrides", GravityGunWorldmodel, i);
		}

		weapon.SetModelSimple(VGRAVITYGUN);
		weapon.SetCustomViewModelModelIndex(GravityGunViewmodel);
		NetProps.SetPropInt(weapon, "m_iViewModelIndex", GravityGunViewmodel);

		local viewmodel = Entities.CreateByClassname("tf_wearable_vm");
		NetProps.SetPropInt(viewmodel, "m_nModelIndex", HandViewmodel[self.GetPlayerClass() - 1]);
		NetProps.SetPropBool(viewmodel, "m_bValidatedAttachedEntity", true);
		NetProps.SetPropEntity(viewmodel, "m_hWeaponAssociatedWith", weapon);
		NetProps.SetPropEntity(weapon, "m_hExtraWearableViewModel", viewmodel);
		viewmodel.SetTeam(self.GetTeam());
		viewmodel.DispatchSpawn();
		viewmodel.KeyValueFromString("classname", "killme");
		self.EquipWearableViewModel(viewmodel);

		self.Weapon_Equip(weapon);
		NetProps.SetPropEntityArray(self, "m_hMyWeapons", weapon, 0);
		self.Weapon_Switch(weapon);

		NetProps.SetPropFloat(weapon, "m_flNextPrimaryAttack", Time() + 9999.9);	// Prevent weapon fire
		EmitSoundEx(
		{
			sound_name = "weapons/physcannon/physcannon_claws_open.wav",
			channel = 6,
			sound_level = 60,
			entity = self
		});
	}
}

function OnScriptHook_OnTakeDamage(params)
{
	local victim = params.const_entity;
	if(victim.IsPlayer())
	{
		if(params.inflictor.IsValid() && IsProp(params.inflictor))
		{
			// Set the attacker as the thrower
			local attacker = NetProps.GetPropEntity(params.inflictor, "m_hPhysicsAttacker");
			if(attacker != null)
				params.attacker = attacker;
		}
		else if(!params.attacker.IsPlayer())
		{
			// Set the attacker to the grabber
			victim.ValidateScriptScope();
			local attacker = victim.GetScriptScope().LastGrabbedBy;
			if(attacker != null && attacker != victim)
				params.attacker = attacker;
		}

		if((params.damage_type & (Constants.FDmgType.DMG_BLAST|Constants.FDmgType.DMG_BLAST_SURFACE)) == (Constants.FDmgType.DMG_BLAST|Constants.FDmgType.DMG_BLAST_SURFACE))
		{
			// x60 explosive barrel damage
			params.damage *= 20.0;
			params.damage_type += Constants.FDmgType.DMG_ACID;
			params.crit_type = 2;

			if(GetPlayerClass(victim) == Constants.ETFClass.TF_CLASS_DEMOMAN &&
				params.inflictor.IsValid() && IsProp(params.inflictor))
			{
				local thrower = NetProps.GetPropEntity(params.inflictor, "m_hPhysicsAttacker");
				if(thrower == null || thrower == victim)
				{
					// Demoman takes no self-damage
					params.damage = 0.0;
					EmitSoundOnClient("Player.ResistanceHeavy", victim);
				}
			}
		}
		else if(params.damage_type & Constants.FDmgType.DMG_CRUSH)
		{
			// x10 prop damage
			params.damage *= 10.0;

			if(params.inflictor.IsValid() && IsProp(params.inflictor))
			{
				local thrower = NetProps.GetPropEntity(params.inflictor, "m_hPhysicsAttacker");
				if(thrower != null)
				{
					// No self-damage from own props
					if(thrower == victim)
					{
						params.damage = 0.0;
					}
					// Nerf just holding large props
					else if(PropHeldByPlayer(params.inflictor))
					{
						if(params.damage > 5.0)
							params.damage = 5.0;
					}
					else if(GetPlayerClass(thrower) == Constants.ETFClass.TF_CLASS_PYRO)
					{
						if(GetPlayerClass(victim) != Constants.ETFClass.TF_CLASS_PYRO)
						{
							victim.AddCondEx(Constants.ETFCond.TF_COND_GAS, 0.1, thrower);
						}

						victim.IgnitePlayer();
					}
				}
			}

			if(GetPlayerClass(victim) == Constants.ETFClass.TF_CLASS_HEAVYWEAPONS)
			{
				// Heavy damage resistance is 3/4
				params.damage *= 0.75;
				EmitSoundOnClient("Player.ResistanceLight", victim);
			}
		}
	}
}

function OnGameEvent_player_changeclass(params)
{
	if(ClassChanges)
	{
		local player = GetPlayerFromUserID(params.userid);
		if(player != null)
		{
			switch(NetProps.GetPropInt(player, "m_Shared.m_iDesiredPlayerClass"))
			{
				case Constants.ETFClass.TF_CLASS_SCOUT:
					ClientPrint(player, 3, HINTSCOUT);
					break;

				case Constants.ETFClass.TF_CLASS_SOLDIER:
					ClientPrint(player, 3, HINTSOLDIER);
					break;

				case Constants.ETFClass.TF_CLASS_PYRO:
					ClientPrint(player, 3, HINTPYRO);
					break;

				case Constants.ETFClass.TF_CLASS_DEMOMAN:
					ClientPrint(player, 3, HINTDEMOMAN);
					break;

				case Constants.ETFClass.TF_CLASS_HEAVYWEAPONS:
					ClientPrint(player, 3, HINTHEAVY);
					break;

				case Constants.ETFClass.TF_CLASS_ENGINEER:
					ClientPrint(player, 3, HINTENGINEER);
					break;

				case Constants.ETFClass.TF_CLASS_MEDIC:
					ClientPrint(player, 3, HINTMEDIC);
					break;

				case Constants.ETFClass.TF_CLASS_SNIPER:
					ClientPrint(player, 3, HINTSNIPER);
					break;

				case Constants.ETFClass.TF_CLASS_SPY:
					ClientPrint(player, 3, HINTSPY);
					break;
			}
		}
	}
}

function OnGameEvent_teamplay_round_start(params)
{
	for(local i = 1; i <= MaxClients().tointeger(); i++)
	{
		local player = PlayerInstanceFromIndex(i);
		if(player == null)
			continue;

		SetPlayerScore(player, 0);
	}
}

function OnGameEvent_player_spawn(params)
{
	local player = GetPlayerFromUserID(params.userid);
	if(player != null)
	{
		player.ValidateScriptScope();
		player.GetScriptScope().LastButtons <- 0;
		player.GetScriptScope().HeldProp <- player;
		player.GetScriptScope().RespawnTime <- 0.0;
		player.GetScriptScope().LastGrabbedBy <- null;
		AddThinkToEnt(player, "PlayerThink");

		if(IsPlayerAlive(player) && !IsInSetup())
		{
			player.AddCondEx(Constants.ETFCond.TF_COND_INVULNERABLE, 2.0, player);
		}
	}
}

function OnGameEvent_post_inventory_application(params)
{
	local player = GetPlayerFromUserID(params.userid);
	if(player != null)
	{
		RequestFrame(player, "PostInventory");
	}
}

function OnGameEvent_player_death(params)
{
	local player = GetPlayerFromUserID(params.userid);
	if(player != null)
	{
		player.ValidateScriptScope();

		if(!player.GetScriptScope().HeldProp.IsPlayer())
		{
			if(player.GetScriptScope().HeldProp.GetOwner() == player)
			{
				// Remove Spy owner status
				player.GetScriptScope().HeldProp.SetOwner(null);
			}
		}

		player.GetScriptScope().HeldProp = player;
		player.StopSound("weapons/physcannon/hold_loop.wav");

		local attacker = GetPlayerFromUserID(params.attacker);
		if(attacker != null && attacker != player && GetRoundState() == Constants.ERoundState.GR_STATE_RND_RUNNING)
		{
			SetPlayerScore(attacker, GetPlayerScore(attacker) + 1);

			// Respawn quickly when not a self-death
			player.GetScriptScope().RespawnTime = Time() + 1.0;
		}

		RequestFrame(player, "CheckGameScore");
	}
}

function OnGameEvent_tf_game_over(params)
{
	local player = GetPlayerFromUserID(params.userid);
	if(player != null)
	{
		RequestFrame(player, "PostInventory");
	}
}

__CollectGameEventCallbacks(this);

function CheckGameScore()
{
	if(IsInSetup() || IsInWaitingForPlayers() || GetRoundState() == Constants.ERoundState.GR_STATE_TEAM_WIN || GetRoundState() == Constants.ERoundState.GR_STATE_GAME_OVER)
		return;

	local winner = null;
	for(local i = 1; i <= MaxClients().tointeger(); i++)
	{
		local player = PlayerInstanceFromIndex(i);
		if(player == null)
			continue;

		if(GetPlayerScore(player) >= KillLimit)
		{
			winner = player;
			break;
		}
	}

	if(winner == null)
		return;

	local team = winner.GetTeam();

	local name = NetProps.GetPropString(winner, "m_szNetname");
	ClientPrint(null, 3, (team == Constants.ETFTeam.TF_TEAM_RED ? "\x07FF3F3F" : "\x0799CCFF") + name + " " + WONROUND);

	local entity = Entities.FindByClassname(null, "game_round_win");
	if(entity == null)
	{
		entity = SpawnEntityFromTable("game_round_win",
		{
			force_map_reset = 1,
			TeamNum = team,
			switch_teams = 0
		});
	}
	else
	{
		EntFireByHandle(entity, "SetTeam", team.tostring(), -1.0, null, null);
	}

	NetProps.SetPropInt(entity, "m_iWinReason", 12);	// "won by collecting enough points"

	EntFireByHandle(entity, "RoundWin", "", -1.0, null, null);
}

function IsPlayerAlive(player)
{
	return NetProps.GetPropInt(player, "m_lifeState") == 0;
}

function GetPlayerClass(player)
{
	return NetProps.GetPropInt(player, "m_PlayerClass.m_iClass");
}

function RequestFrame(entity, func)
{
	EntFireByHandle(entity, "CallScriptFunction", func, -1, null, null);
}

function IsProp(entity)
{
	// Has m_hPhysicsAttacker
	return startswith(entity.GetClassname(), "func_physbox") ||
		startswith(entity.GetClassname(), "func_pushable") ||
		startswith(entity.GetClassname(), "physics_cannister") ||
		startswith(entity.GetClassname(), "prop_phy") ||
		startswith(entity.GetClassname(), "prop_ragdoll") ||
		startswith(entity.GetClassname(), "prop_soccer_ball") ||
		startswith(entity.GetClassname(), "prop_sphere") ||
		startswith(entity.GetClassname(), "prop_vehicle");
}

function CanPickupProp(entity, reload)
{
	if(IsProp(entity) && (reload || !PropHeldByPlayer(entity)))
	{
		return true;
	}
	else if(PlayerPickup && !reload && entity.IsPlayer())
	{
		return true;
	}

	return false;
}

function PropHeldByPlayer(entity)
{
	for(local i = 1; i <= MaxClients().tointeger(); i++)
	{
		local player = PlayerInstanceFromIndex(i);
		if(player == null)
			continue;

		player.ValidateScriptScope();
		if(player.GetScriptScope().HeldProp == entity)
			return true;
	}

	return false;
}

function GetPlayerUserID(player)
{
	return NetProps.GetPropIntArray(Entities.FindByClassname(null, "tf_player_manager"), "m_iUserID", player.entindex());
}

function GetPlayerAccount(player)
{
	return NetProps.GetPropIntArray(Entities.FindByClassname(null, "tf_player_manager"), "m_iAccountID", player.entindex());
}

function GetPlayerScore(player)
{
	return player.entindex() in PlayerKills ? PlayerKills[player.entindex()] : 0;
}

function SetPlayerScore(player, score)
{
	PlayerKills[player.entindex()] <- score;
}

function GetPlayerGameText(player)
{
	return player.entindex() in GameTextEntity ? GameTextEntity[player.entindex()] : null;
}

function SetPlayerGameText(player, entity)
{
	GameTextEntity[player.entindex()] <- entity;
}

function IsInSetup()
{
	return GetRoundState() < Constants.ERoundState.GR_STATE_RND_RUNNING ||
		NetProps.GetPropBool(Entities.FindByClassname(null, "tf_gamerules"), "m_bInSetup");
}

function RemoveWeapon(entity)
{
	local wearable = NetProps.GetPropEntity(entity, "m_hExtraWearable");
	if(wearable != null)
	{
		EntFireByHandle(wearable, "Kill", "", -1.0, null, null);
	}

	wearable = NetProps.GetPropEntity(entity, "m_hExtraWearableViewModel");
	if(wearable != null)
	{
		EntFireByHandle(wearable, "Kill", "", -1.0, null, null);
	}

	EntFireByHandle(entity, "Kill", "", -1.0, null, null);
}

function DisplayHudHint(player, message)
{
	local entity = SpawnEntityFromTable("env_hudhint",
	{
		message = message,
		spawnflags = player == null ? 1 : 0
	});

	EntFireByHandle(entity, "ShowHudHint", "", -1.0, player, player);
	EntFireByHandle(entity, "Kill", "", 2.0, null, null);
}

function DrawZapEffectPosition(entity1, position)
{
	local name1 = UniqueString("s");
	local name2 = UniqueString("e");
	NetProps.SetPropString(entity1, "m_iName", name1);

	local entity2 = SpawnEntityFromTable("info_teleport_destination",
	{
		origin = position.ToKVString(),
		targetname = name2
	});

	local entity = SpawnEntityFromTable("env_beam",
	{
		rendercolor = entity1.GetTeam() == Constants.ETFTeam.TF_TEAM_RED ? "16 0 0" : "0 0 16",
		life = "0.3",
		BoltWidth = 3.0,
		texture = "sprites/laserbeam.spr",
		NoiseAmplitude = 3,
		LightningStart = name1,
		LightningEnd = name2
	});

	EntFireByHandle(entity, "TurnOn", "", -1.0, null, null);
	EntFireByHandle(entity, "Kill", "", 0.3, null, null);
	EntFireByHandle(entity2, "Kill", "", 0.5, null, null);
}

function EnablePickupPlayers()
{
	PlayerPickup = true;
}

function DisableClassDescription()
{
	ClassChanges = false;
}

function SetSuperPickup()
{
	PickupRange = 10000.0;
	GhostRange = 600.0;
}

function SetSuperGhost()
{
	GhostPush = 1.0;
	GhostRange = 600.0;
}

function SetSuperSpin()
{
	RotateSpeed = 750.0;
	SpinSpeed = 3000.0;
}