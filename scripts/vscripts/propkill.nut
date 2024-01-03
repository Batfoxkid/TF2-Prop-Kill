/*
	Prop Kill Alpha Build by Batfoxkid
	Gravity Gun edits by ficool2

	Map Requirements:
	- logic_relay using "vscripts" "propkill.nut"
	- Custom gravity gun worldmodel & viewmodel packed
	- prop_physics for players to use

	Recommended:
	- 5 second setup time to display the freeze time period
	- 90 second game period, more or less
	- Large use of explosive props (eg. Explosive Barrels)
	- Keep large-scale objects count low (they're power weapons)

	TODO:
	- Fix janky ghost collision between world/props
	- Remove ammo packs on death
	- Ofc add details
*/

// Localization
::HINTCONTROL <- "%+attack% LAUNCH OBJECT %+attack2% GRAB OBJECT %+reload% ZAP OBJECT"
::WONROUND <- "is the last player alive!"
::HINTSCOUT <- "Scout runs the fastest and can double jump"
::HINTSOLDIER <- "Soldier takes less damage from self-inflicted objects"
::HINTPYRO <- "Pyro ignites thrown and zapped objects"
::HINTDEMOMAN <- "Demoman takes less damage from self-inflicted explosives"
::HINTHEAVY <- "Heavy takes less damage from all objects"
::HINTENGINEER <- "Engineer can freeze objects by throwing them while rotating"
::HINTMEDIC <- "Medic regenerates health quickly"
::HINTSNIPER <- "Sniper can zap objects more often"
::HINTSPY <- "Spy won't collide with held objects"

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

// Precache
Convars.SetValue("mp_autoteambalance", "0");	// Not needed to keep teams balanced
Convars.SetValue("mp_bonusroundtime", "6");	// Keeps downtime low with fast-pace rounds
Convars.SetValue("mp_disable_respawn_times", "1");	// Always respawn as a ghost
Convars.SetValue("mp_forcecamera", "0");	// Allows spectating all players
Convars.SetValue("mp_friendlyfire", "1");	// Allows props to damage on impact
Convars.SetValue("mp_scrambleteams_auto", "1");	// Scrambles players every round
Convars.SetValue("mp_scrambleteams_auto_windifference", "1");	// Scrambles players every round
Convars.SetValue("tf_avoidteammates", "1");	// Disabled previously
Convars.SetValue("tf_ghost_up_speed", "800.f");	// Speeds up ghosts
Convars.SetValue("tf_ghost_xy_speed", "800.f");	// Speeds up ghosts
Convars.SetValue("tf_spawn_glows_duration", "0.0");	// No friendly outlines
Convars.SetValue("tf_spec_xray", "2");	// Allows spectating all players
Convars.SetValue("sv_turbophysics", "0");	// Expensive physics
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
PrecacheModel("models/props_halloween/ghost.mdl");
PrecacheModel("models/props_halloween/ghost_no_hat.mdl");
PrecacheModel("models/props_halloween/ghost_no_hat_red.mdl");
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

	if(!IsInWaitingForPlayers() && !self.InCond(Constants.ETFCond.TF_COND_HALLOWEEN_IN_HELL))
	{
		// Turn into a ghost on death
		self.AddCond(Constants.ETFCond.TF_COND_HALLOWEEN_IN_HELL);
		Convars.SetValue("tf_avoidteammates", "0");	// Disable teammate collision
	}

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
		while(entity = Entities.FindByClassnameWithin(entity, "prop_physics*", origin, GhostRange))
		{
			if(PropHeldByPlayer(entity))
			{
				// Don't push held props
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
				if(IsProp(HeldProp))
				{
					NetProps.SetPropEntity(HeldProp, "m_hPhysicsAttacker", null);

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
			if(!reload && LastFreeze.IsValid() && LastFreeze != self)
			{
				// Remove Engineer frozen prop
				EntFireByHandle(LastFreeze, "EnableMotion", "", -1.0, self, self);
				NetProps.SetPropInt(LastFreeze, "m_fEffects", 0);
				LastFreeze = self;
			}

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
					NetProps.SetPropFloat(self, "m_flNextAttack", Time() + 1.25);
				}
				else
				{
					NetProps.SetPropFloat(self, "m_flNextAttack", Time() + 2.0);
				}
			}

			if(trace.hit && CanPickupProp(trace.enthit, reload))
			{
				if(IsProp(trace.enthit))
				{
					EntFireByHandle(trace.enthit, "EnableMotion", "", -1.0, self, self);
					NetProps.SetPropInt(trace.enthit, "m_fEffects", 0);
					NetProps.SetPropEntity(trace.enthit, "m_hPhysicsAttacker", self);

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
					//self.EmitSound("weapons/physcannon/hold_loop.wav");

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
				IsProp(HeldProp) &&
				(buttons & (Constants.FButtons.IN_RELOAD|Constants.FButtons.IN_ATTACK3)))
			{
				// Engineer freezes props if holding reload/attack3
				LastFreeze = HeldProp;
				EntFireByHandle(LastFreeze, "DisableMotion", "", -1.0, self, self);
				NetProps.SetPropInt(LastFreeze, "m_fEffects", Constants.FEntityEffects.EF_ITEM_BLINK);
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

				if(buttons & Constants.FButtons.IN_ATTACK3)
				{
					swing.y += SpinSpeed;
				}

				if(buttons & Constants.FButtons.IN_RELOAD)
				{
					swing.z -= SpinSpeed;
				}

				if(IsProp(HeldProp))
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

	if(HeldProp.IsValid() && HeldProp != self)
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

		if(IsProp(HeldProp))
		{
			local swing = Vector(0.0, 0.0, 0.0);

			if(buttons & Constants.FButtons.IN_ATTACK3)
			{
				swing.y += RotateSpeed;
			}

			if(buttons & Constants.FButtons.IN_RELOAD)
			{
				swing.z -= RotateSpeed;
			}

			HeldProp.SetPhysAngularVelocity(swing);
		}
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
				if(ClassChanges)
					ClientPrint(self, 3, HINTSCOUT);

				break;

			case Constants.ETFClass.TF_CLASS_SOLDIER:
				classname = "tf_weapon_shotgun_soldier";
				speedChange = 1.916667;	// 460 HU
				if(ClassChanges)
					ClientPrint(self, 3, HINTSOLDIER);

				break;

			case Constants.ETFClass.TF_CLASS_PYRO:
				classname = "tf_weapon_shotgun_pyro";
				speedChange = 1.6;	// 480 HU
				if(ClassChanges)
					ClientPrint(self, 3, HINTPYRO);

				break;

			case Constants.ETFClass.TF_CLASS_DEMOMAN:
				classname = "tf_weapon_grenadelauncher";
				speedChange = 1.678571;	// 470 HU
				if(ClassChanges)
					ClientPrint(self, 3, HINTDEMOMAN);

				break;

			case Constants.ETFClass.TF_CLASS_HEAVYWEAPONS:
				classname = "tf_weapon_shotgun_hwg";
				speedChange = 2.0;	// 460 HU
				if(ClassChanges)
					ClientPrint(self, 3, HINTHEAVY);

				break;

			case Constants.ETFClass.TF_CLASS_ENGINEER:
				classname = "tf_weapon_shotgun_primary";
				speedChange = 1.6;	// 480 HU
				if(ClassChanges)
					ClientPrint(self, 3, HINTENGINEER);

				break;

			case Constants.ETFClass.TF_CLASS_MEDIC:
				classname = "tf_weapon_syringegun_medic";
				speedChange = 1.5;	// 480 HU
				healthRegen = 25.0;
				if(ClassChanges)
					ClientPrint(self, 3, HINTMEDIC);

				break;

			case Constants.ETFClass.TF_CLASS_SNIPER:
				classname = "tf_weapon_smg";
				speedChange = 1.6;	// 480 HU
				if(ClassChanges)
					ClientPrint(self, 3, HINTSNIPER);

				break;

			case Constants.ETFClass.TF_CLASS_SPY:
				classname = "tf_weapon_revolver";
				speedChange = 1.5;	// 480 HU
				if(ClassChanges)
					ClientPrint(self, 3, HINTSPY);

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
		if(params.inflictor.IsValid() &&
			startswith(params.inflictor.GetClassname(), "prop_phy"))
		{
			// Set the attacker as the thrower
			local attacker = NetProps.GetPropEntity(params.inflictor, "m_hPhysicsAttacker");
			if(attacker != null)
				params.attacker = attacker;
		}

		if((params.damage_type & (Constants.FDmgType.DMG_BLAST|Constants.FDmgType.DMG_BLAST_SURFACE)) == (Constants.FDmgType.DMG_BLAST|Constants.FDmgType.DMG_BLAST_SURFACE))
		{
			// x60 explosive barrel damage
			params.damage *= 20.0;
			params.damage_type += Constants.FDmgType.DMG_ACID;
			params.crit_type = 2;

			if(GetPlayerClass(victim) == Constants.ETFClass.TF_CLASS_DEMOMAN &&
				params.inflictor.IsValid() &&
				startswith(params.inflictor.GetClassname(), "prop_phy"))
			{
				local thrower = NetProps.GetPropEntity(params.inflictor, "m_hPhysicsAttacker");
				if(thrower == null || thrower == victim)
				{
					// Demoman's self-damage is 1/40
					params.damage *= 0.025;
					EmitSoundOnClient("Player.ResistanceHeavy", victim);
				}
			}
		}
		else if(params.damage_type & Constants.FDmgType.DMG_CRUSH)
		{
			// x10 prop damage
			params.damage *= 10.0;

			if(GetPlayerClass(victim) == Constants.ETFClass.TF_CLASS_HEAVYWEAPONS)
			{
				// Heavy damage resistance is 3/4
				params.damage *= 0.75;
				EmitSoundOnClient("Player.ResistanceLight", victim);
			}
			else if(GetPlayerClass(victim) == Constants.ETFClass.TF_CLASS_SOLDIER &&
				params.inflictor.IsValid() &&
				startswith(params.inflictor.GetClassname(), "prop_phy"))
			{
				local thrower = NetProps.GetPropEntity(params.inflictor, "m_hPhysicsAttacker");
				if(thrower == null || thrower == victim)
				{
					// Soldier's self-damage is 1/4
					params.damage *= 0.25;
					EmitSoundOnClient("Player.ResistanceHeavy", victim);
				}
			}
		}
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
		player.GetScriptScope().LastFreeze <- player;
		AddThinkToEnt(player, "PlayerThink");

		if(IsPlayerAlive(player) && !IsInSetup() && !IsInWaitingForPlayers())
		{
			// Round is already in progress
			player.AddCond(Constants.ETFCond.TF_COND_HALLOWEEN_GHOST_MODE);
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

function OnGameEvent_player_disconnect(params)
{
	local player = GetPlayerFromUserID(params.userid);
	if(player != null)
	{
		CheckAlivePlayers(player);
	}
}

function OnGameEvent_player_death(params)
{
	local player = GetPlayerFromUserID(params.userid);
	if(player != null)
	{
		// Hide all the elements we don't want
		//player.AddHudHideFlags(Constants.FHideHUD.HIDEHUD_WEAPONSELECTION |
		//	Constants.FHideHUD.HIDEHUD_BUILDING_STATUS |
		//	Constants.FHideHUD.HIDEHUD_CLOAK_AND_FEIGN |
		//	Constants.FHideHUD.HIDEHUD_PIPES_AND_CHARGE |
		//	Constants.FHideHUD.HIDEHUD_METAL);

		player.ValidateScriptScope();

		if(IsProp(player.GetScriptScope().HeldProp))
		{
			if(player.GetScriptScope().HeldProp.GetOwner() == player)
			{
				// Remove Spy owner status
				player.GetScriptScope().HeldProp.SetOwner(null);
			}
		}

		if(player.GetScriptScope().LastFreeze.IsValid() && player.GetScriptScope().LastFreeze != player)
		{
			// Remove Engineer frozen prop
			EntFireByHandle(player.GetScriptScope().LastFreeze, "EnableMotion", "", -1.0, player, player);
			NetProps.SetPropInt(player.GetScriptScope().LastFreeze, "m_fEffects", 0);
			player.GetScriptScope().LastFreeze = player;
		}

		player.GetScriptScope().HeldProp <- player;
		player.StopSound("weapons/physcannon/hold_loop.wav");

		RequestFrame(player, "CheckAlivePlayersFrame");
	}
}

__CollectGameEventCallbacks(this);

function CheckAlivePlayersFrame()
{
	CheckAlivePlayers(self);
}

function CheckAlivePlayers(ignore)
{
	if(IsInSetup() || IsInWaitingForPlayers() || GetRoundState() == Constants.ERoundState.GR_STATE_TEAM_WIN)
		return;

	local lastAlive = null;
	for(local i = 1; i <= MaxClients().tointeger(); i++)
	{
		local player = PlayerInstanceFromIndex(i);
		if(player == null || player == ignore)
			continue;

		if(IsPlayerAlive(player) && !player.InCond(Constants.ETFCond.TF_COND_HALLOWEEN_GHOST_MODE))
		{
			// If two people are alive
			if(lastAlive != null)
				return;

			lastAlive = player;
		}
	}

	local team = 0;

	if(lastAlive != null)
	{
		team = lastAlive.GetTeam();

		local name = NetProps.GetPropString(lastAlive, "m_szNetname");
		ClientPrint(null, 3, (team == Constants.ETFTeam.TF_TEAM_RED ? "\x07FF3F3F" : "\x0799CCFF") + name + " " + WONROUND);
	}

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

	NetProps.SetPropInt(entity, "m_iWinReason", 2);	// Win by killing

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
	return startswith(entity.GetClassname(), "prop_phy");
}

function CanPickupProp(entity, reload)
{
	if(IsProp(entity) && (reload || !PropHeldByPlayer(entity)))
	{
		return true;
	}
	else if(PlayerPickup && !reload && startswith(entity.GetClassname(), "player"))
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