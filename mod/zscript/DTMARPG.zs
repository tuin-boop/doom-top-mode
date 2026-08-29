// Monster rarity, affixes, weapon loot, and the late-level boss promotion.

class DTMMonsterVariant : Inventory
{
    int Rarity;
    int MonsterLevel;
    int MaximumHealth;
    bool AffixFast;
    bool AffixTough;
    bool AffixBrutal;
    bool AffixVampiric;
    bool AffixExplosive;
    bool UsesFastChase;
    bool IsPromotedBoss;
    String DisplayName;
    Actor BossAura;

    Default
    {
        Inventory.MaxAmount 1;
        +INVENTORY.UNDROPPABLE
        +INVENTORY.UNCLEARABLE
    }

    clearscope String RarityName()
    {
        if (Rarity == 1) return "RARE";
        if (Rarity == 2) return "EPIC";
        if (Rarity == 3) return "MYTHIC";
        if (Rarity >= 4) return "GODLY";
        return "COMMON";
    }

    String AffixText()
    {
        String result = "";
        if (AffixFast) result = "SWIFT";
        if (AffixTough) result = result == "" ? "TITANIC" : result .. "  TITANIC";
        if (AffixBrutal) result = result == "" ? "BRUTAL" : result .. "  BRUTAL";
        if (AffixVampiric) result = result == "" ? "VAMPIRIC" : result .. "  VAMPIRIC";
        if (AffixExplosive) result = result == "" ? "VOLATILE" : result .. "  VOLATILE";
        if (UsesFastChase) result = result == "" ? "RELENTLESS" : result .. "  RELENTLESS";
        return result;
    }

    override void ModifyDamage(int damage, Name damageType, out int newDamage,
        bool passive, Actor inflictor, Actor source, int flags, double angle)
    {
        if (passive || damage <= 0) return;

        double multiplier = (1.0 + Rarity * 0.10) *
            (1.0 + max(0, MonsterLevel - 1) * 0.06);
        if (AffixBrutal) multiplier *= 1.28;
        newDamage = max(1, int(damage * multiplier + 0.5));
    }

    States
    {
    Spawn:
        TNT1 A -1;
        Stop;
    }
}

// Persistent, automatic player progression.  It owns the level-derived
// damage multiplier and refreshes the engine's health/armor/ammo limits.
class DTMPlayerProgress : Inventory
{
    int PlayerLevel;
    int Experience;
    int ExperienceToNext;
    int LifetimeKills;
    int AppliedHealthBonus;

    Default
    {
        Inventory.MaxAmount 1;
        +INVENTORY.UNDROPPABLE
        +INVENTORY.UNCLEARABLE
    }

    void Initialize()
    {
        if (PlayerLevel > 0) return;
        PlayerLevel = 1;
        Experience = 0;
        ExperienceToNext = XPForLevel(PlayerLevel);
    }

    clearscope int XPForLevel(int levelNumber)
    {
        return 100 + max(0, levelNumber - 1) * 65;
    }

    clearscope int MaxHealthForLevel()
    {
        return 100 + max(0, PlayerLevel - 1) * 6;
    }

    clearscope int MaxArmorForLevel()
    {
        return 200 + max(0, PlayerLevel - 1) * 8;
    }

    clearscope int DamagePercent()
    {
        return max(0, PlayerLevel - 1) * 25 / 10;
    }

    clearscope int AmmoPercent()
    {
        return max(0, PlayerLevel - 1) * 5;
    }

    void RestoreAmmoType(Actor pawn, Class<Ammo> ammoType)
    {
        Ammo ammo = Ammo(pawn.FindInventory(ammoType));
        if (!ammo) return;
        ammo.Amount = min(ammo.MaxAmount,
            ammo.Amount + max(1, ammo.MaxAmount / 50));
    }

    void RestoreKillAmmo()
    {
        if (!Owner) return;
        RestoreAmmoType(Owner, 'Clip');
        RestoreAmmoType(Owner, 'Shell');
        RestoreAmmoType(Owner, 'RocketAmmo');
        RestoreAmmoType(Owner, 'Cell');
    }

    void SetAmmoCapacity(Actor pawn, Class<Ammo> ammoType)
    {
        Ammo ammo = Ammo(pawn.FindInventory(ammoType));
        if (!ammo) return;
        int baseMaximum = GetDefaultByType(ammoType).MaxAmount;
        int normalCap = max(1, int(baseMaximum *
            (1.0 + AmmoPercent() / 100.0) + 0.5));
        ammo.BackpackMaxAmount = normalCap * 2;
        ammo.MaxAmount = pawn.FindInventory('BackpackItem', true)
            ? ammo.BackpackMaxAmount : normalCap;
    }

    void ApplyBenefits(Actor pawn, bool refillGrowth = false)
    {
        if (!pawn || !pawn.player) return;
        Initialize();
        PlayerPawn playerPawn = PlayerPawn(pawn);
        int wantedHealthBonus = max(0, PlayerLevel - 1) * 6;
        int gainedHealth = max(0, wantedHealthBonus - AppliedHealthBonus);
        if (wantedHealthBonus > AppliedHealthBonus)
        {
            playerPawn.BonusHealth += wantedHealthBonus - AppliedHealthBonus;
            AppliedHealthBonus = wantedHealthBonus;
        }
        if (refillGrowth && gainedHealth > 0)
            pawn.health = min(pawn.GetMaxHealth(true), pawn.health + gainedHealth);

        BasicArmor armor = BasicArmor(pawn.FindInventory('BasicArmor', true));
        if (armor)
        {
            int armorCap = MaxArmorForLevel();
            armor.MaxAllowedAmount = armorCap;
            armor.MaxAmount = max(armor.MaxAmount, armorCap);
            if (refillGrowth)
                armor.Amount = min(armorCap, armor.Amount + 8);
        }

        SetAmmoCapacity(pawn, 'Clip');
        SetAmmoCapacity(pawn, 'Shell');
        SetAmmoCapacity(pawn, 'RocketAmmo');
        SetAmmoCapacity(pawn, 'Cell');
    }

    void AddExperience(int amount)
    {
        Initialize();
        Experience += max(0, amount);
        LifetimeKills++;
        RestoreKillAmmo();
        bool levelled = false;
        while (Experience >= ExperienceToNext)
        {
            Experience -= ExperienceToNext;
            PlayerLevel++;
            ExperienceToNext = XPForLevel(PlayerLevel);
            levelled = true;
        }
        if (levelled && Owner)
        {
            ApplyBenefits(Owner, true);
            Console.MidPrint(null,
                String.Format("LEVEL %d  //  POWER INCREASED", PlayerLevel), true);
            Owner.A_Log(String.Format(
                "LEVEL %d: %d HP, +%d%% damage, %d armor, +%d%% ammo",
                PlayerLevel, MaxHealthForLevel(), DamagePercent(),
                MaxArmorForLevel(), AmmoPercent()), true);
        }
    }

    override void ModifyDamage(int damage, Name damageType, out int newDamage,
        bool passive, Actor inflictor, Actor source, int flags, double angle)
    {
        if (passive || damage <= 0) return;
        newDamage = max(1, int(damage *
            (1.0 + DamagePercent() / 100.0) + 0.5));
    }

    States
    {
    Spawn:
        TNT1 A -1;
        Stop;
    }
}

// First experimental weapon variant. It trades ammunition efficiency for a
// wider, more forceful stream: two weaker green bolts for two cells.
class DTMTwinPlasmaBolt : ArachnotronPlasma
{
    Default
    {
        Damage 3;
        SeeSound "weapons/plasmaf";
        DeathSound "baby/shotx";
        Obituary "$OB_MPPLASMARIFLE";
    }
}

class DTMTwinPlasmaRifle : PlasmaRifle
{
    Default
    {
        Weapon.SelectionOrder 101;
        Weapon.AmmoUse 2;
        Weapon.AmmoGive 40;
        Weapon.AmmoType "Cell";
        Inventory.PickupMessage "Twin green plasma rifle acquired.";
        Tag "TWIN PLASMA RIFLE";
    }

    action void A_FireTwinGreenPlasma()
    {
        if (player == null) return;
        Weapon weap = player.ReadyWeapon;
        if (weap != null && invoker == weap && stateinfo != null &&
            stateinfo.mStateType == STATE_Psprite)
        {
            if (!weap.DepleteAmmo(weap.bAltFire, true)) return;
            State flash = weap.FindState('Flash');
            if (flash != null) player.SetSafeFlash(weap, flash, 0);
        }
        SpawnPlayerMissile('DTMTwinPlasmaBolt', angle - 2.0);
        SpawnPlayerMissile('DTMTwinPlasmaBolt', angle + 2.0);
    }

    States
    {
    Fire:
        PLSG A 3 A_FireTwinGreenPlasma;
        PLSG B 20 A_ReFire;
        Goto Ready;
    }
}

class DTMWeaponStats : Inventory
{
    // Legacy single-roll fields remain for save compatibility. New pickups
    // are stored per weapon so collecting another gun never erases an older
    // gun's rolled quality.
    int Rarity;
    int DamageBonus;
    int CritChance;
    String WeaponLabel;
    Class<Weapon> WeaponType;
    bool HasWeaponRoll[7];
    int WeaponRarity[7];
    int WeaponDamageBonus[7];
    int WeaponCritChance[7];
    int WeaponLevel[7];

    Default
    {
        Inventory.MaxAmount 1;
        +INVENTORY.UNDROPPABLE
        +INVENTORY.UNCLEARABLE
    }

    clearscope int IndexFor(Class<Weapon> type)
    {
        if (type == 'Shotgun') return 0;
        if (type == 'Chaingun') return 1;
        if (type == 'SuperShotgun') return 2;
        if (type == 'RocketLauncher') return 3;
        if (type == 'PlasmaRifle') return 4;
        if (type == 'BFG9000') return 5;
        if (type == 'DTMTwinPlasmaRifle') return 6;
        return -1;
    }

    void SetWeaponRoll(Class<Weapon> type, int rarity, int damage, int critical,
        int itemLevel = 1)
    {
        int index = IndexFor(type);
        if (index >= 0)
        {
            HasWeaponRoll[index] = true;
            WeaponRarity[index] = rarity;
            WeaponDamageBonus[index] = damage;
            WeaponCritChance[index] = critical;
            WeaponLevel[index] = max(1, itemLevel);
        }
        Rarity = rarity;
        DamageBonus = damage;
        CritChance = critical;
        WeaponType = type;
    }

    clearscope int LevelFor(Class<Weapon> type)
    {
        int index = IndexFor(type);
        if (index >= 0 && HasWeaponRoll[index]) return max(1, WeaponLevel[index]);
        return 1;
    }

    clearscope bool HasStatsFor(Class<Weapon> type)
    {
        int index = IndexFor(type);
        return (index >= 0 && HasWeaponRoll[index]) || WeaponType == type;
    }

    clearscope int RarityFor(Class<Weapon> type)
    {
        int index = IndexFor(type);
        if (index >= 0 && HasWeaponRoll[index]) return WeaponRarity[index];
        return WeaponType == type ? Rarity : 0;
    }

    clearscope int DamageFor(Class<Weapon> type)
    {
        int index = IndexFor(type);
        if (index >= 0 && HasWeaponRoll[index]) return WeaponDamageBonus[index];
        return WeaponType == type ? DamageBonus : 0;
    }

    clearscope int CriticalFor(Class<Weapon> type)
    {
        int index = IndexFor(type);
        if (index >= 0 && HasWeaponRoll[index]) return WeaponCritChance[index];
        return WeaponType == type ? CritChance : 0;
    }

    clearscope String RarityNameFor(Class<Weapon> type)
    {
        int rarity = RarityFor(type);
        if (rarity == 1) return "RARE";
        if (rarity == 2) return "EPIC";
        if (rarity == 3) return "MYTHIC";
        if (rarity >= 4) return "GODLY";
        return "COMMON";
    }

    bool AppliesToReadyWeapon()
    {
        return Owner && Owner.player && Owner.player.ReadyWeapon &&
            HasStatsFor(Owner.player.ReadyWeapon.GetClass());
    }

    override void ModifyDamage(int damage, Name damageType, out int newDamage,
        bool passive, Actor inflictor, Actor source, int flags, double angle)
    {
        if (passive || damage <= 0 || !AppliesToReadyWeapon()) return;

        Class<Weapon> readyType = Owner.player.ReadyWeapon.GetClass();
        int rolledDamage = DamageFor(readyType);
        int rolledCritical = CriticalFor(readyType);
        newDamage = max(1, int(damage * (1.0 + rolledDamage / 100.0) + 0.5));
        if (Random(1, 100) <= rolledCritical) newDamage *= 2;
    }

    States
    {
    Spawn:
        TNT1 A -1;
        Stop;
    }
}

class DTMWeaponDrop : Inventory
{
    int Rarity;
    int ItemLevel;
    int DamageBonus;
    int CritChance;
    String WeaponLabel;
    Class<Weapon> WeaponType;

    Default
    {
        Radius 18;
        Height 14;
        Inventory.MaxAmount 1;
        Inventory.PickupSound "misc/w_pkup";
        // Rolled weapons are choices, not ordinary Doom pickups.  Removing
        // SPECIAL makes touching one completely inert; EquipTo is the sole
        // path that can consume it.
        -SPECIAL
        +FLOATBOB
        +NOGRAVITY
    }

    clearscope String RarityName()
    {
        if (Rarity == 1) return "RARE";
        if (Rarity == 2) return "EPIC";
        if (Rarity == 3) return "MYTHIC";
        if (Rarity >= 4) return "GODLY";
        return "COMMON";
    }

    void SelectWeapon(bool bossDrop)
    {
        int roll = Random(0, 99);
        if (bossDrop && Rarity >= 3 && roll >= 97)
        {
            WeaponType = 'BFG9000';
            WeaponLabel = "BFG 9000";
            SetStateLabel("BFG");
        }
        else if (Rarity >= 2 && roll >= 89)
        {
            WeaponType = 'DTMTwinPlasmaRifle';
            WeaponLabel = "TWIN PLASMA RIFLE";
            SetStateLabel("Plasma");
        }
        else if (Rarity >= 2 && roll >= 72)
        {
            WeaponType = 'PlasmaRifle';
            WeaponLabel = "PLASMA RIFLE";
            SetStateLabel("Plasma");
        }
        else if (Rarity >= 1 && roll >= 54)
        {
            WeaponType = 'RocketLauncher';
            WeaponLabel = "ROCKET LAUNCHER";
            SetStateLabel("Rocket");
        }
        else if (Rarity >= 1 && roll >= 35)
        {
            WeaponType = 'SuperShotgun';
            WeaponLabel = "SUPER SHOTGUN";
            SetStateLabel("SuperShotgun");
        }
        else if (roll >= 20)
        {
            WeaponType = 'Chaingun';
            WeaponLabel = "CHAINGUN";
            SetStateLabel("Chaingun");
        }
        else
        {
            WeaponType = 'Shotgun';
            WeaponLabel = "SHOTGUN";
            SetStateLabel("Shotgun");
        }
    }

    void InitTwinPlasma(int quality, int dropLevel)
    {
        Rarity = clamp(quality, 0, 4);
        ItemLevel = max(1, dropLevel);
        DamageBonus = Rarity * 14 + (ItemLevel - 1) * 2 +
            Random(4, 12 + Rarity * 7);
        CritChance = Rarity * 3 + Random(0, 2 + Rarity * 2);
        WeaponType = 'DTMTwinPlasmaRifle';
        WeaponLabel = "TWIN PLASMA RIFLE";
        SetStateLabel("Plasma");
        if (Rarity >= 2)
            A_AttachLight('DTMLootGlow', DynamicLight.PointLight,
                Color(65, 255, 105), 68, 68, DynamicLight.LF_ATTENUATE);
    }

    void InitDrop(int quality, bool bossDrop, int dropLevel = 1)
    {
        Rarity = clamp(quality, 0, 4);
        ItemLevel = max(1, dropLevel);
        DamageBonus = Rarity * 14 + (ItemLevel - 1) * 2 +
            Random(4, 12 + Rarity * 7);
        CritChance = Rarity * 3 + Random(0, 2 + Rarity * 2);
        SelectWeapon(bossDrop);

        if (Rarity == 2)
            A_AttachLight('DTMLootGlow', DynamicLight.PointLight,
                Color(180, 70, 255), 56, 56, DynamicLight.LF_ATTENUATE);
        else if (Rarity == 3)
            A_AttachLight('DTMLootGlow', DynamicLight.PointLight,
                Color(255, 105, 25), 72, 72, DynamicLight.LF_ATTENUATE);
        else if (Rarity >= 4)
            A_AttachLight('DTMLootGlow', DynamicLight.PointLight,
                Color(80, 235, 255), 92, 92, DynamicLight.LF_ATTENUATE);
    }

    bool EquipTo(Actor toucher)
    {
        if (!toucher || !toucher.player || !WeaponType) return false;

        toucher.GiveInventory(WeaponType, 1);
        Weapon newWeapon = Weapon(toucher.FindInventory(WeaponType));
        if (!newWeapon) return false;

        // Rolled loot equips its weapon but never destroys another gun.  This
        // preserves normal pickups and cheat-given weapons in the arsenal.

        toucher.GiveInventory('DTMWeaponStats', 1);
        DTMWeaponStats stats = DTMWeaponStats(toucher.FindInventory('DTMWeaponStats'));
        if (stats)
        {
            stats.WeaponLabel = WeaponLabel;
            stats.SetWeaponRoll(WeaponType, Rarity, DamageBonus, CritChance,
                ItemLevel);
        }

        toucher.player.PendingWeapon = newWeapon;
        toucher.A_Log(String.Format("EQUIPPED LEVEL %d %s %s: +%d%% damage, %d%% critical chance",
            ItemLevel, RarityName(), WeaponLabel, DamageBonus, CritChance), true);
        GoAwayAndDie();
        return true;
    }

    override bool TryPickup(in out Actor toucher)
    {
        // Ground loot is inspected and accepted with Use. Merely walking over
        // it must never change the player's loadout.
        return false;
    }

    override String PickupMessage()
    {
        return String.Format("%s %s", RarityName(), WeaponLabel);
    }

    States
    {
    Spawn:
    Shotgun:
        SHOT A -1 Bright;
        Stop;
    Chaingun:
        MGUN A -1 Bright;
        Stop;
    SuperShotgun:
        SGN2 A -1 Bright;
        Stop;
    Rocket:
        LAUN A -1 Bright;
        Stop;
    Plasma:
        PLAS A -1 Bright;
        Stop;
    BFG:
        BFUG A -1 Bright;
        Stop;
    }
}

class DTMTwinPlasmaTestDrop : DTMWeaponDrop
{
    override void PostBeginPlay()
    {
        Super.PostBeginPlay();
        int testLevel = 1;
        for (int i = 0; i < MAXPLAYERS; i++)
        {
            if (!PlayerInGame[i] || !players[i].mo) continue;
            DTMPlayerProgress progress = DTMPlayerProgress(
                players[i].mo.FindInventory('DTMPlayerProgress'));
            if (progress) testLevel = max(testLevel, progress.PlayerLevel);
        }
        InitTwinPlasma(2, testLevel);
    }
}

class DTMVariantExplosion : Actor
{
    Default
    {
        Radius 1;
        Height 1;
        RenderStyle "Add";
        Alpha 0.95;
        Scale 1.65;
        +NOBLOCKMAP
        +NOGRAVITY
        +FORCEXYBILLBOARD
    }

    override void PostBeginPlay()
    {
        Super.PostBeginPlay();
        A_AttachLight('DTMVolatileBlastLight', DynamicLight.PointLight,
            Color(255, 95, 20), 150, 150, DynamicLight.LF_ATTENUATE);
        A_StartSound("weapons/rocklx", CHAN_BODY, CHANF_DEFAULT, 1.0, ATTN_NORM);
    }

    States
    {
    Spawn:
        MISL B 0 Bright A_Explode(56, 112, XF_NOSPLASH, true);
        MISL BCD 4 Bright;
        Stop;
    }
}

// A translucent duplicate of the boss' current sprite/voxel. Dynamic lights
// alone can vanish in bright outdoor sectors; this overlay remains visible and
// makes the promoted monster itself read as the boss from every camera angle.
class DTMBossAura : Actor
{
    Default
    {
        Radius 1;
        Height 1;
        RenderStyle "AddStencil";
        StencilColor "FF 18 08";
        Alpha 0.34;
        +NOBLOCKMAP
        +NOGRAVITY
        +NOINTERACTION
    }

    override void Tick()
    {
        Super.Tick();
        if (!tracer || tracer.health <= 0 || tracer.bCORPSE)
        {
            Destroy();
            return;
        }

        SetOrigin(tracer.pos, false);
        Angle = tracer.Angle;
        Pitch = tracer.Pitch;
        Roll = tracer.Roll;
        sprite = tracer.sprite;
        frame = tracer.frame;
        Scale = tracer.Scale * 1.12;
        Alpha = (level.time & 8) ? 0.28 : 0.38;
    }

    States
    {
    Spawn:
        TNT1 A -1 Bright;
        Stop;
    }
}

class DTMVariantHandler : StaticEventHandler
{
    int InitialMonsterCount;
    bool BossPromoted;

    DTMMonsterVariant VariantFor(Actor monster)
    {
        if (!monster) return null;
        return DTMMonsterVariant(monster.FindInventory('DTMMonsterVariant'));
    }

    DTMPlayerProgress ProgressFor(Actor pawn)
    {
        if (!pawn) return null;
        return DTMPlayerProgress(pawn.FindInventory('DTMPlayerProgress'));
    }

    DTMPlayerProgress EnsureProgress(Actor pawn)
    {
        if (!pawn || !pawn.player) return null;
        DTMPlayerProgress progress = ProgressFor(pawn);
        if (!progress)
        {
            pawn.GiveInventory('DTMPlayerProgress', 1);
            progress = ProgressFor(pawn);
        }
        if (progress)
        {
            progress.Initialize();
            progress.ApplyBenefits(pawn);
        }
        return progress;
    }

    int CurrentPlayerLevel()
    {
        int highestLevel = 1;
        for (int i = 0; i < MAXPLAYERS; i++)
        {
            if (!PlayerInGame[i] || !players[i].mo) continue;
            DTMPlayerProgress progress = EnsureProgress(players[i].mo);
            if (progress) highestLevel = max(highestLevel, progress.PlayerLevel);
        }
        return highestLevel;
    }

    int RollRarity()
    {
        int roll = Random(1, 1000);
        if (roll <= 10) return 4;
        if (roll <= 60) return 3;
        if (roll <= 160) return 2;
        if (roll <= 400) return 1;
        return 0;
    }

    String RollMonsterName(Actor monster, int rarity)
    {
        int roll = Random(0, 5);

        if (monster is 'ZombieMan')
        {
            if (roll == 0) return "SERGEANT GRAVES";
            if (roll == 1) return "CORPORAL HOLLOW";
            if (roll == 2) return "DEADEYE DAWSON";
            if (roll == 3) return "PRIVATE DEADMEAT";
            if (roll == 4) return "OFFICER OOPS";
            return "STEVE FROM SECURITY";
        }
        if (monster is 'ShotgunGuy')
        {
            if (roll == 0) return "BUCKSHOT BARNES";
            if (roll == 1) return "SERGEANT SCATTER";
            if (roll == 2) return "WARDEN SHELL";
            if (roll == 3) return "BOOMSTICK BILL";
            if (roll == 4) return "PELLET PETE";
            return "MISTER TWO BARRELS";
        }
        if (monster is 'ChaingunGuy')
        {
            if (roll == 0) return "GUNNER ROURKE";
            if (roll == 1) return "MAJOR BRASS";
            if (roll == 2) return "BULLET WARDEN";
            if (roll == 3) return "DAKKA DAN";
            if (roll == 4) return "BRASSMOUTH";
            return "THE AMMO BUDGET";
        }
        if (monster is 'DoomImp')
        {
            if (roll == 0) return "ASHCLAW";
            if (roll == 1) return "EMBERFANG";
            if (roll == 2) return "CINDER WRETCH";
            if (roll == 3) return "SPICY GERALD";
            if (roll == 4) return "FIREBALL FRED";
            return "THE ANGRY RAISIN";
        }
        if (monster is 'Spectre')
        {
            if (roll == 0) return "THE PALE MAW";
            if (roll == 1) return "SHADOWFANG";
            if (roll == 2) return "THE UNSEEN HUNGER";
            if (roll == 3) return "INVISIBLE GARY";
            if (roll == 4) return "MISTER SNEAKY TEETH";
            return "WHERE DID HE GO";
        }
        if (monster is 'Demon')
        {
            if (roll == 0) return "BLOODMAW";
            if (roll == 1) return "GOREHOUND";
            if (roll == 2) return "THE RED HUNGER";
            if (roll == 3) return "BITEY MCBITEFACE";
            if (roll == 4) return "CHOMPERS";
            return "THE FORBIDDEN POTATO";
        }
        if (monster is 'Cacodemon')
        {
            if (roll == 0) return "THE CRIMSON ORACLE";
            if (roll == 1) return "ORB OF AGONY";
            if (roll == 2) return "SKY TYRANT";
            if (roll == 3) return "MEATBALL SUPREME";
            if (roll == 4) return "FLOATY MCFACE";
            return "THE ANGRY TOMATO";
        }
        if (monster is 'LostSoul')
        {
            if (roll == 0) return "WAILING EMBER";
            if (roll == 1) return "SKULLSPARK";
            if (roll == 2) return "THE BURNING DEAD";
            if (roll == 3) return "HEAD EMPTY";
            if (roll == 4) return "FLAMING STEVE";
            return "NO BODY REQUIRED";
        }
        if (monster is 'PainElemental')
        {
            if (roll == 0) return "THE BROOD MAW";
            if (roll == 1) return "WARDEN OF SKULLS";
            if (roll == 2) return "THE SPAWNING HORROR";
            if (roll == 3) return "ANGRY MEATBALL SENIOR";
            if (roll == 4) return "SKULL DISPENSER";
            return "THE BAD PARENT";
        }
        if (monster is 'Revenant')
        {
            if (roll == 0) return "THE BONE MARSHAL";
            if (roll == 1) return "GRAVE RATTLER";
            if (roll == 2) return "MISSILE WRAITH";
            if (roll == 3) return "SKULLIAM";
            if (roll == 4) return "MISTER BONES";
            return "THE SKELETON CREW";
        }
        if (monster is 'HellKnight' || monster is 'BaronOfHell')
        {
            if (roll == 0) return "LORD BRIMSTONE";
            if (roll == 1) return "DUKE OF ASH";
            if (roll == 2) return "THE HELLWARDEN";
            if (roll == 3) return "BARON VON BONK";
            if (roll == 4) return "BEEF SUPREME";
            return "SIR PUNCHES-A-LOT";
        }
        if (monster is 'Fatso')
        {
            if (roll == 0) return "THE SIEGE MAW";
            if (roll == 1) return "FURNACE KING";
            if (roll == 2) return "LORD OF BARRAGES";
            if (roll == 3) return "CHUNK NORRIS";
            if (roll == 4) return "MISTER SIX CANNONS";
            return "THE HEAVY ARTILLERY";
        }
        if (monster is 'Arachnotron')
        {
            if (roll == 0) return "THE STEEL WEAVER";
            if (roll == 1) return "PLASMA WIDOW";
            if (roll == 2) return "THE CRAWLING ENGINE";
            if (roll == 3) return "WEB DEVELOPER";
            if (roll == 4) return "SPIDER BYTE";
            return "EIGHT LEGS LAGGING";
        }
        if (monster is 'Archvile')
        {
            if (roll == 0) return "THE PYRE SAINT";
            if (roll == 1) return "ASH PRIEST";
            if (roll == 2) return "THE RISEN FLAME";
            if (roll == 3) return "HUMAN RESOURCES";
            if (roll == 4) return "DOCTOR UNDEATH";
            return "THE FIRE INSPECTOR";
        }
        if (monster is 'Cyberdemon')
        {
            if (roll == 0) return "THE WAR TYRANT";
            if (roll == 1) return "IRON RUIN";
            if (roll == 2) return "THE ROCKET EMPEROR";
            if (roll == 3) return "OSHA VIOLATION PRIME";
            if (roll == 4) return "BIG DAVE";
            return "THE UNSKIPPABLE CUTSCENE";
        }
        if (monster is 'SpiderMastermind')
        {
            if (roll == 0) return "THE IRON MATRIARCH";
            if (roll == 1) return "BRAIN OF THE SWARM";
            if (roll == 2) return "THE WAR WEAVER";
            if (roll == 3) return "MOTHER MANAGEMENT";
            if (roll == 4) return "THE MEETING THAT COULD EMAIL";
            return "BIG BRAIN ENERGY";
        }

        if (rarity >= 3)
        {
            if (roll == 0) return "DREAD MARSHAL";
            if (roll == 1) return "NIGHT'S HERALD";
            if (roll == 2) return "THE LAST OMEN";
            if (roll == 3) return "LORD OUCHINGTON";
            if (roll == 4) return "THE FINAL INTERN";
            return "DENNIS";
        }
        if (roll == 0) return "GRIMWARD";
        if (roll == 1) return "ASHEN ONE";
        if (roll == 2) return "DREADLING";
        if (roll == 3) return "GARY";
        if (roll == 4) return "MISTER BAD IDEA";
        return "KEVIN";
    }

    String BuildDisplayName(Actor monster, DTMMonsterVariant variant,
        bool promotedBoss = false)
    {
        String personalName = RollMonsterName(monster, variant.Rarity);
        String species = monster.GetTag().MakeUpper();
        if (promotedBoss)
            return String.Format("BOSS %s: %s", species, personalName);
        return String.Format("%s, %s %s", personalName,
            variant.RarityName(), species);
    }

    void AddAffixes(DTMMonsterVariant variant, int count)
    {
        int added = 0;
        int attempts = 0;
        while (added < count && attempts < 30)
        {
            attempts++;
            int choice = Random(0, 4);
            if (choice == 0 && !variant.AffixFast)
            {
                variant.AffixFast = true;
                added++;
            }
            else if (choice == 1 && !variant.AffixTough)
            {
                variant.AffixTough = true;
                added++;
            }
            else if (choice == 2 && !variant.AffixBrutal)
            {
                variant.AffixBrutal = true;
                added++;
            }
            else if (choice == 3 && !variant.AffixVampiric)
            {
                variant.AffixVampiric = true;
                added++;
            }
            else if (choice == 4 && !variant.AffixExplosive)
            {
                variant.AffixExplosive = true;
                added++;
            }
        }
    }

    void ApplyGlow(Actor monster, int rarity, bool boss = false)
    {
        int radius = clamp(int(monster.radius * 4.0), 52, 150);
        if (boss)
            monster.A_AttachLight('DTMRarityGlow', DynamicLight.PointLight,
                Color(255, 25, 10), radius + 110, radius + 110,
                DynamicLight.LF_ATTENUATE);
        else if (rarity == 2)
            monster.A_AttachLight('DTMRarityGlow', DynamicLight.PointLight,
                Color(175, 55, 255), radius, radius,
                DynamicLight.LF_ATTENUATE | DynamicLight.LF_DONTLIGHTSELF);
        else if (rarity == 3)
            monster.A_AttachLight('DTMRarityGlow', DynamicLight.PointLight,
                Color(255, 150, 20), radius + 28, radius + 28,
                DynamicLight.LF_ATTENUATE | DynamicLight.LF_DONTLIGHTSELF);
        else if (rarity >= 4)
            monster.A_AttachLight('DTMRarityGlow', DynamicLight.PointLight,
                Color(60, 225, 255), radius + 34, radius + 34,
                DynamicLight.LF_ATTENUATE | DynamicLight.LF_DONTLIGHTSELF);
    }

    void AssignVariant(Actor monster)
    {
        if (!monster || !monster.bISMONSTER || monster.bFRIENDLY || monster.bCORPSE)
            return;
        if (VariantFor(monster)) return;

        monster.GiveInventory('DTMMonsterVariant', 1);
        DTMMonsterVariant variant = VariantFor(monster);
        if (!variant) return;

        variant.IsPromotedBoss = false;
        int playerLevel = CurrentPlayerLevel();
        variant.Rarity = RollRarity();
        // Epic and higher monsters may reach three levels farther above the
        // normal band, making their rarity visible in more than color alone.
        int upperLevelOffset = variant.Rarity >= 2 ? 7 : 4;
        variant.MonsterLevel = clamp(
            playerLevel + Random(-4, upperLevelOffset), 1,
            playerLevel + upperLevelOffset);
        int affixCount = variant.Rarity == 1 ? 1
            : variant.Rarity == 2 ? 2
            : variant.Rarity == 3 ? 2
            : variant.Rarity >= 4 ? 3 : 0;
        AddAffixes(variant, affixCount);

        if (variant.Rarity == 3 && Random(1, 100) <= 35)
            variant.UsesFastChase = true;
        else if (variant.Rarity >= 4 && Random(1, 100) <= 65)
            variant.UsesFastChase = true;

        double healthMultiplier = variant.Rarity == 1 ? 1.20
            : variant.Rarity == 2 ? 1.50
            : variant.Rarity == 3 ? 1.90
            : variant.Rarity >= 4 ? 2.50 : 1.0;
        healthMultiplier *= 1.0 + max(0, variant.MonsterLevel - 1) * 0.10;
        if (variant.AffixTough) healthMultiplier *= 1.35;
        monster.health = max(1, int(monster.health * healthMultiplier + 0.5));
        variant.MaximumHealth = monster.health;

        double speedMultiplier = 1.0 + variant.Rarity * 0.04;
        if (variant.AffixFast) speedMultiplier *= 1.28;
        monster.Speed *= speedMultiplier;
        variant.DisplayName = BuildDisplayName(monster, variant);
        ApplyGlow(monster, variant.Rarity);
    }

    void AssignExistingMonsters()
    {
        ThinkerIterator iterator = ThinkerIterator.Create('Actor');
        Actor monster;
        while (monster = Actor(iterator.Next())) AssignVariant(monster);
    }

    override void WorldLoaded(WorldEvent e)
    {
        for (int i = 0; i < MAXPLAYERS; i++)
            if (PlayerInGame[i] && players[i].mo) EnsureProgress(players[i].mo);
        AssignExistingMonsters();
        if (!e.IsSaveGame)
        {
            InitialMonsterCount = level.total_monsters;
            BossPromoted = false;
            if (PromoteCanonicalBosses()) BossPromoted = true;
        }
    }

    override void WorldThingSpawned(WorldEvent e)
    {
        AssignVariant(e.Thing);
    }

    void SpawnWeaponDrop(Actor monster, DTMMonsterVariant variant)
    {
        bool bossDrop = variant && variant.IsPromotedBoss;
        int quality = variant ? variant.Rarity : 0;
        if (bossDrop)
        {
            int bossRoll = Random(1, 100);
            quality = bossRoll <= 55 ? 1
                : bossRoll <= 82 ? 2
                : bossRoll <= 96 ? 3 : 4;
        }
        int chance = bossDrop ? 100 : 7 + quality * 12;
        if (Random(1, 100) > chance) return;

        DTMWeaponDrop drop = DTMWeaponDrop(Actor.Spawn('DTMWeaponDrop',
            (monster.pos.x, monster.pos.y, monster.floorz + 12), ALLOW_REPLACE));
        if (drop) drop.InitDrop(quality, bossDrop,
            variant ? variant.MonsterLevel : CurrentPlayerLevel());
    }

    void AwardMonsterExperience(Actor monster, DTMMonsterVariant variant)
    {
        int monsterLevel = variant ? max(1, variant.MonsterLevel) : 1;
        int rarity = variant ? variant.Rarity : 0;
        int reward = max(5, monster.SpawnHealth() / 10) + monsterLevel * 5 +
            rarity * 12;
        if (variant && variant.IsPromotedBoss) reward *= 5;
        for (int i = 0; i < MAXPLAYERS; i++)
        {
            if (!PlayerInGame[i] || !players[i].mo || players[i].mo.health <= 0)
                continue;
            DTMPlayerProgress progress = EnsureProgress(players[i].mo);
            if (progress) progress.AddExperience(reward);
        }
    }

    override void WorldThingDied(WorldEvent e)
    {
        if (!e.Thing || !e.Thing.bISMONSTER || e.Thing.bFRIENDLY) return;
        DTMMonsterVariant variant = VariantFor(e.Thing);
        if (!variant) return;

        if (variant.AffixExplosive)
        {
            Actor blast = Actor.Spawn('DTMVariantExplosion',
                e.Thing.pos + (0, 0, e.Thing.height * 0.35), ALLOW_REPLACE);
            if (blast) blast.target = e.Thing;
        }
        AwardMonsterExperience(e.Thing, variant);
        SpawnWeaponDrop(e.Thing, variant);
    }

    override void WorldThingDamaged(WorldEvent e)
    {
        if (!e.DamageSource || e.Damage <= 0) return;
        DTMMonsterVariant variant = VariantFor(e.DamageSource);
        if (!variant || !variant.AffixVampiric || e.DamageSource.health <= 0) return;

        int maximum = max(1, variant.MaximumHealth);
        e.DamageSource.health = min(maximum,
            e.DamageSource.health + max(1, e.Damage / 3));
    }

    Actor FindBossCandidate()
    {
        Actor best = null;
        double bestDistance = -1.0;
        ThinkerIterator iterator = ThinkerIterator.Create('Actor');
        Actor candidate;
        while (candidate = Actor(iterator.Next()))
        {
            if (!candidate.bISMONSTER || candidate.bFRIENDLY || candidate.bCORPSE ||
                candidate.health <= 0 || candidate.special != 0 || candidate.tid != 0)
                continue;
            DTMMonsterVariant variant = VariantFor(candidate);
            if (variant && variant.IsPromotedBoss) continue;

            double nearestPlayer = 1.0e30;
            for (int i = 0; i < MAXPLAYERS; i++)
            {
                if (!PlayerInGame[i] || !players[i].mo) continue;
                nearestPlayer = min(nearestPlayer,
                    candidate.Distance3D(players[i].mo));
            }
            if (nearestPlayer > bestDistance)
            {
                bestDistance = nearestPlayer;
                best = candidate;
            }
        }
        return best;
    }

    DTMWeaponDrop FindNearbyWeaponDrop(Actor pawn)
    {
        if (!pawn) return null;
        DTMWeaponDrop closest = null;
        // Show the comparison before the player is standing on the item. Use
        // still requires this range, so walls and distant drops cannot be
        // accepted accidentally.
        double closestDistance = 144.0;
        ThinkerIterator iterator = ThinkerIterator.Create('DTMWeaponDrop');
        DTMWeaponDrop drop;
        while (drop = DTMWeaponDrop(iterator.Next()))
        {
            double distance = pawn.Distance3D(drop);
            if (distance > closestDistance || !pawn.CheckSight(drop)) continue;
            closestDistance = distance;
            closest = drop;
        }
        return closest;
    }

    void UpdatePlayerLootPrompts()
    {
        for (int i = 0; i < MAXPLAYERS; i++)
        {
            if (!PlayerInGame[i] || !players[i].mo || players[i].mo.health <= 0)
                continue;
            DTMPlayer pawn = DTMPlayer(players[i].mo);
            if (!pawn) continue;

            DTMWeaponDrop nearby = FindNearbyWeaponDrop(pawn);
            pawn.NearbyWeaponDrop = nearby;
            bool pressedUse = (players[i].cmd.buttons & BT_USE) &&
                !(players[i].oldbuttons & BT_USE);
            if (nearby && pressedUse)
            {
                if (nearby.EquipTo(pawn)) pawn.NearbyWeaponDrop = null;
            }
        }
    }

    void PromoteActorToBoss(Actor boss, bool announce = true)
    {
        if (!boss) return;
        DTMMonsterVariant variant = VariantFor(boss);
        if (!variant || variant.IsPromotedBoss) return;

        variant.IsPromotedBoss = true;
        variant.Rarity = 4;
        AddAffixes(variant, 3);
        variant.UsesFastChase = true;
        double bossHealthMultiplier = (boss is 'Cyberdemon' ||
            boss is 'SpiderMastermind') ? 2.5 : 5.0;
        boss.health = max(1,
            int(max(boss.health, variant.MaximumHealth) * bossHealthMultiplier + 0.5));
        variant.MaximumHealth = boss.health;
        boss.Speed *= 1.18;
        variant.DisplayName = BuildDisplayName(boss, variant, true);
        ApplyGlow(boss, 4, true);
        if (!variant.BossAura)
        {
            DTMBossAura aura = DTMBossAura(Actor.Spawn('DTMBossAura',
                boss.pos, ALLOW_REPLACE));
            if (aura)
            {
                aura.tracer = boss;
                variant.BossAura = aura;
            }
        }
        if (announce)
            Console.MidPrint(null,
                String.Format("%s HAS ASCENDED", variant.DisplayName), true);
    }

    bool PromoteCanonicalBosses()
    {
        String mapName = level.MapName.MakeUpper();
        if (mapName != "E1M8" && mapName != "E2M8" && mapName != "E3M8")
            return false;

        bool promotedAny = false;
        ThinkerIterator iterator = ThinkerIterator.Create('Actor');
        Actor monster;
        while (monster = Actor(iterator.Next()))
        {
            bool isCanonicalBoss = (mapName == "E1M8" && monster is 'BaronOfHell') ||
                (mapName == "E2M8" && monster is 'Cyberdemon') ||
                (mapName == "E3M8" && monster is 'SpiderMastermind');
            if (!isCanonicalBoss || monster.health <= 0) continue;
            PromoteActorToBoss(monster, false);
            promotedAny = true;
        }
        if (promotedAny)
            Console.MidPrint(null, "THE LEVEL BOSSES HAVE AWAKENED", true);
        return promotedAny;
    }

    void PromoteBoss()
    {
        Actor boss = FindBossCandidate();
        if (!boss) return;
        PromoteActorToBoss(boss, true);
        BossPromoted = true;
    }

    override void WorldTick()
    {
        if ((level.maptime % 35) == 0)
            for (int i = 0; i < MAXPLAYERS; i++)
                if (PlayerInGame[i] && players[i].mo)
                    EnsureProgress(players[i].mo);
        UpdatePlayerLootPrompts();

        if (!BossPromoted && InitialMonsterCount >= 2 &&
            level.killed_monsters * 100 >= InitialMonsterCount * 85)
            PromoteBoss();

        if ((level.maptime % 7) != 0) return;
        ThinkerIterator iterator = ThinkerIterator.Create('Actor');
        Actor monster;
        while (monster = Actor(iterator.Next()))
        {
            if (!monster.bISMONSTER || monster.health <= 0 || !monster.target) continue;
            DTMMonsterVariant variant = VariantFor(monster);
            if (variant && variant.UsesFastChase) monster.A_FastChase();
        }
    }
}
