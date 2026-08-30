// Experimental third-person Baron form. The real DTMPlayer remains in place
// for camera, aiming, progression, and interaction; this actor supplies the
// visible body while the powerup supplies combat and defensive changes.

class DTMBaronFormVisual : BaronOfHell
{
    Default
    {
        -SOLID
        -SHOOTABLE
        -ISMONSTER
        -COUNTKILL
        -BOSSDEATH
        -E1M8BOSS
        +NOINTERACTION
        +NOBLOCKMAP
        +NOGRAVITY
        +ISOMETRICSPRITES
        RenderStyle "Normal";
        Alpha 1.0;
    }

    override void Tick()
    {
        Super.Tick();
        if (!tracer || tracer.health <= 0)
        {
            Destroy();
            return;
        }
        SetOrigin(tracer.pos, false);
        Angle = tracer.Angle;
        Pitch = 0;
        Vel = (0, 0, 0);
    }

    States
    {
    Spawn:
    See:
        BOSS AABBCCDD 3;
        Loop;
    Missile:
        BOSS EF 8;
        BOSS G 8;
        Goto See;
    Melee:
        BOSS EF 8;
        BOSS G 8;
        Goto See;
    }
}

class DTMBaronWeapon : DoomWeapon
{
    Default
    {
        Weapon.SelectionOrder 10;
        Weapon.AmmoUse 0;
        Tag "BARON CLAWS";
    }

    action void A_StartBaronFormAttack()
    {
        if (!player) return;
        PowerDTMBaronForm power = PowerDTMBaronForm(
            player.mo.FindInventory('PowerDTMBaronForm'));
        if (!power || !power.VisualBody) return;

        FTranslatedLineTarget victim;
        player.mo.AimLineAttack(player.mo.Angle, 104.0, victim,
            0.0, ALF_CHECK3D);
        if (victim.linetarget)
            power.VisualBody.SetStateLabel('Melee');
        else
            power.VisualBody.SetStateLabel('Missile');
    }

    action void A_FireBaronForm()
    {
        if (!player) return;

        // At claw range, strike immediately instead of awkwardly launching a
        // fireball through the enemy occupying the same space.
        FTranslatedLineTarget victim;
        double meleePitch = player.mo.AimLineAttack(
            player.mo.Angle, 104.0, victim, 0.0, ALF_CHECK3D);
        if (victim.linetarget)
        {
            player.mo.LineAttack(player.mo.Angle, 104.0, meleePitch, 80,
                'Melee', 'BulletPuff', LAF_ISMELEEATTACK, victim);
            player.mo.A_StartSound("baron/melee", CHAN_WEAPON);
            return;
        }

        SpawnPlayerMissile('BaronBall');
    }

    States
    {
    Ready:
        TNT1 A 1 A_WeaponReady;
        Loop;
    Deselect:
        TNT1 A 1 A_Lower;
        Loop;
    Select:
        TNT1 A 1 A_Raise;
        Loop;
    Fire:
        // Vanilla Baron timing: eight-tic windup, attack, eight-tic recovery.
        TNT1 A 8 A_StartBaronFormAttack;
        TNT1 A 8 A_FireBaronForm;
        TNT1 A 0 A_ReFire;
        Goto Ready;
    Spawn:
        BAL7 A -1 Bright;
        Stop;
    }
}

class PowerDTMBaronForm : Powerup
{
    Actor VisualBody;
    Class<Weapon> PreviousWeapon;
    double PreviousAlpha;
    int PreviousRenderStyle;
    double PreviousSpeed;
    int FormHealth;
    int FormMaxHealth;

    Default
    {
        Powerup.Duration -30;
    }

    override void InitEffect()
    {
        Super.InitEffect();
        if (!Owner || !Owner.player) return;

        // Monster forms are mutually exclusive. Removing the old form first
        // lets it restore the pawn before this form records that state.
        if (Owner.FindInventory('PowerDTMCyberForm'))
            Owner.TakeInventory('PowerDTMCyberForm', 1);
        if (Owner.FindInventory('PowerDTMRevenantForm'))
            Owner.TakeInventory('PowerDTMRevenantForm', 1);

        PreviousAlpha = Owner.Alpha;
        PreviousRenderStyle = Owner.GetRenderStyle();
        PreviousSpeed = Owner.Speed;
        PreviousWeapon = Owner.player.ReadyWeapon
            ? Owner.player.ReadyWeapon.GetClass() : null;
        Owner.A_SetRenderStyle(0.0, STYLE_None);
        Owner.Speed *= 1.10;
        FormMaxHealth = 1000;
        FormHealth = FormMaxHealth;

        VisualBody = Actor.Spawn('DTMBaronFormVisual', Owner.pos, ALLOW_REPLACE);
        if (VisualBody)
        {
            VisualBody.tracer = Owner;
            VisualBody.Angle = Owner.Angle;
        }

        Owner.GiveInventory('DTMBaronWeapon', 1);
        Weapon formWeapon = Weapon(Owner.FindInventory('DTMBaronWeapon'));
        if (formWeapon) Owner.player.PendingWeapon = formWeapon;
        Owner.A_StartSound("baron/sight", CHAN_BODY);
        Console.MidPrint(null, "BARON FORM AWAKENED", true);
    }

    override void DoEffect()
    {
        Super.DoEffect();
        if (!Owner) return;
        // STYLE_None also hides voxel/model representations; alpha alone does
        // not reliably suppress the top-down marine in every renderer path.
        Owner.A_SetRenderStyle(0.0, STYLE_None);
        if (FormHealth <= 0)
        {
            EffectTics = min(EffectTics, 1);
            return;
        }
        if (!VisualBody)
        {
            VisualBody = Actor.Spawn('DTMBaronFormVisual', Owner.pos, ALLOW_REPLACE);
            if (VisualBody) VisualBody.tracer = Owner;
        }
    }

    override void ModifyDamage(int damage, Name damageType, out int newDamage,
        bool passive, Actor inflictor, Actor source, int flags, double angle)
    {
        if (damage <= 0) return;
        if (!passive)
        {
            newDamage = max(1, int(damage * 1.25 + 0.5));
            return;
        }

        int absorbedDamage = max(1, int(damage * 0.70 + 0.5));
        int overflow = max(0, absorbedDamage - FormHealth);
        FormHealth = max(0, FormHealth - absorbedDamage);
        // The dedicated pool cannot be clamped by normal player-health code.
        // Only damage beyond the exhausted form reaches the real marine.
        newDamage = overflow;
        if (FormHealth <= 0) EffectTics = min(EffectTics, 1);
    }

    override void EndEffect()
    {
        Super.EndEffect();
        if (VisualBody)
        {
            VisualBody.Destroy();
            VisualBody = null;
        }
        if (!Owner) return;

        Owner.A_SetRenderStyle(PreviousAlpha, PreviousRenderStyle);
        Owner.Speed = PreviousSpeed;
        Owner.TakeInventory('DTMBaronWeapon', 1);
        if (PreviousWeapon)
        {
            Weapon prior = Weapon(Owner.FindInventory(PreviousWeapon));
            if (prior) Owner.player.PendingWeapon = prior;
        }
        Console.MidPrint(null, "BARON FORM FADES", true);
    }
}

class DTMCyberFormVisual : Cyberdemon
{
    Default
    {
        -SOLID
        -SHOOTABLE
        -ISMONSTER
        -COUNTKILL
        -BOSSDEATH
        -E2M8BOSS
        -E4M6BOSS
        +NOINTERACTION
        +NOBLOCKMAP
        +NOGRAVITY
        +ISOMETRICSPRITES
        RenderStyle "Normal";
        Alpha 1.0;
    }

    override void Tick()
    {
        Super.Tick();
        if (!tracer || tracer.health <= 0)
        {
            Destroy();
            return;
        }
        SetOrigin(tracer.pos, false);
        Angle = tracer.Angle;
        Pitch = 0;
        Vel = (0, 0, 0);
    }

    States
    {
    Spawn:
    See:
        CYBR A 3;
        CYBR ABBCC 3;
        CYBR DD 3;
        Loop;
    Missile:
        // Match the vanilla Cyberdemon's complete three-rocket animation.
        CYBR E 6;
        CYBR F 12 Bright;
        CYBR E 12;
        CYBR F 12 Bright;
        CYBR E 12;
        CYBR F 12 Bright;
        Goto See;
    }
}

class DTMCyberWeapon : DoomWeapon
{
    Default
    {
        Weapon.SelectionOrder 10;
        Weapon.AmmoUse 0;
        Tag "CYBER ROCKET ARM";
    }

    action void A_StartCyberFormBurst()
    {
        if (!player) return;
        PowerDTMCyberForm power = PowerDTMCyberForm(
            player.mo.FindInventory('PowerDTMCyberForm'));
        if (power && power.VisualBody)
            power.VisualBody.SetStateLabel('Missile');
    }

    action void A_FireCyberFormRocket()
    {
        if (!player) return;
        SpawnPlayerMissile('Rocket');
        player.mo.A_StartSound("weapons/rocklf", CHAN_WEAPON);
    }

    States
    {
    Ready:
        TNT1 A 1 A_WeaponReady;
        Loop;
    Deselect:
        TNT1 A 1 A_Lower;
        Loop;
    Select:
        TNT1 A 1 A_Raise;
        Loop;
    Fire:
        // Authentic Cyberdemon burst: rockets at tics 6, 30, and 54, with
        // the same 66-tic total attack cycle as the original monster.
        TNT1 A 6 A_StartCyberFormBurst;
        TNT1 A 12 A_FireCyberFormRocket;
        TNT1 A 12;
        TNT1 A 12 A_FireCyberFormRocket;
        TNT1 A 12;
        TNT1 A 12 A_FireCyberFormRocket;
        TNT1 A 0 A_ReFire;
        Goto Ready;
    Spawn:
        MISL A -1 Bright;
        Stop;
    }
}

class PowerDTMCyberForm : Powerup
{
    Actor VisualBody;
    Class<Weapon> PreviousWeapon;
    double PreviousAlpha;
    int PreviousRenderStyle;
    double PreviousSpeed;
    int FormHealth;
    int FormMaxHealth;

    Default
    {
        Powerup.Duration -30;
    }

    override void InitEffect()
    {
        Super.InitEffect();
        if (!Owner || !Owner.player) return;

        if (Owner.FindInventory('PowerDTMBaronForm'))
            Owner.TakeInventory('PowerDTMBaronForm', 1);
        if (Owner.FindInventory('PowerDTMRevenantForm'))
            Owner.TakeInventory('PowerDTMRevenantForm', 1);

        PreviousAlpha = Owner.Alpha;
        PreviousRenderStyle = Owner.GetRenderStyle();
        PreviousSpeed = Owner.Speed;
        PreviousWeapon = Owner.player.ReadyWeapon
            ? Owner.player.ReadyWeapon.GetClass() : null;
        Owner.A_SetRenderStyle(0.0, STYLE_None);
        Owner.Speed *= 0.95;
        FormMaxHealth = 4000;
        FormHealth = FormMaxHealth;

        VisualBody = Actor.Spawn('DTMCyberFormVisual', Owner.pos, ALLOW_REPLACE);
        if (VisualBody)
        {
            VisualBody.tracer = Owner;
            VisualBody.Angle = Owner.Angle;
        }

        Owner.GiveInventory('DTMCyberWeapon', 1);
        Weapon formWeapon = Weapon(Owner.FindInventory('DTMCyberWeapon'));
        if (formWeapon) Owner.player.PendingWeapon = formWeapon;
        Owner.A_StartSound("cyber/sight", CHAN_BODY);
        Console.MidPrint(null, "CYBERDEMON FORM ONLINE", true);
    }

    override void DoEffect()
    {
        Super.DoEffect();
        if (!Owner) return;
        Owner.A_SetRenderStyle(0.0, STYLE_None);
        if (FormHealth <= 0)
        {
            EffectTics = min(EffectTics, 1);
            return;
        }
        if (!VisualBody)
        {
            VisualBody = Actor.Spawn('DTMCyberFormVisual', Owner.pos, ALLOW_REPLACE);
            if (VisualBody) VisualBody.tracer = Owner;
        }
    }

    override void ModifyDamage(int damage, Name damageType, out int newDamage,
        bool passive, Actor inflictor, Actor source, int flags, double angle)
    {
        if (damage <= 0) return;
        if (!passive)
        {
            newDamage = max(1, int(damage * 1.35 + 0.5));
            return;
        }

        int absorbedDamage = max(1, int(damage * 0.50 + 0.5));
        int overflow = max(0, absorbedDamage - FormHealth);
        FormHealth = max(0, FormHealth - absorbedDamage);
        newDamage = overflow;
        if (FormHealth <= 0) EffectTics = min(EffectTics, 1);
    }

    override void EndEffect()
    {
        Super.EndEffect();
        if (VisualBody)
        {
            VisualBody.Destroy();
            VisualBody = null;
        }
        if (!Owner) return;

        Owner.A_SetRenderStyle(PreviousAlpha, PreviousRenderStyle);
        Owner.Speed = PreviousSpeed;
        Owner.TakeInventory('DTMCyberWeapon', 1);
        if (PreviousWeapon)
        {
            Weapon prior = Weapon(Owner.FindInventory(PreviousWeapon));
            if (prior) Owner.player.PendingWeapon = prior;
        }
        Console.MidPrint(null, "CYBERDEMON FORM OFFLINE", true);
    }
}

class DTMRevenantFormVisual : Revenant
{
    Default
    {
        -SOLID
        -SHOOTABLE
        -ISMONSTER
        -COUNTKILL
        +NOINTERACTION
        +NOBLOCKMAP
        +NOGRAVITY
        +ISOMETRICSPRITES
        RenderStyle "Normal";
        Alpha 1.0;
    }

    override void Tick()
    {
        Super.Tick();
        if (!tracer || tracer.health <= 0)
        {
            Destroy();
            return;
        }
        SetOrigin(tracer.pos, false);
        Angle = tracer.Angle;
        Pitch = 0;
        Vel = (0, 0, 0);
    }

    States
    {
    Spawn:
    See:
        SKEL AABBCCDDEEFF 2;
        Loop;
    Melee:
        SKEL G 6;
        SKEL H 6;
        SKEL I 6;
        Goto See;
    Missile:
        SKEL J 10 Bright;
        SKEL K 20;
        Goto See;
    }
}

class DTMRevenantFormWeapon : DoomWeapon
{
    Default
    {
        Weapon.SelectionOrder 10;
        Weapon.AmmoUse 0;
        Tag "REVENANT ARMS";
    }

    action void A_SelectRevenantFormAttack()
    {
        if (!player) return;
        DTMRevenantFormWeapon weapon = DTMRevenantFormWeapon(invoker);
        PowerDTMRevenantForm power = PowerDTMRevenantForm(
            player.mo.FindInventory('PowerDTMRevenantForm'));
        if (!weapon) return;

        FTranslatedLineTarget victim;
        player.mo.AimLineAttack(player.mo.Angle, 96.0, victim,
            0.0, ALF_CHECK3D);
        if (victim.linetarget)
        {
            if (power && power.VisualBody)
                power.VisualBody.SetStateLabel('Melee');
            player.SetPsprite(PSP_WEAPON,
                weapon.FindState('MeleeFire'), true);
        }
        else
        {
            if (power && power.VisualBody)
                power.VisualBody.SetStateLabel('Missile');
            player.SetPsprite(PSP_WEAPON,
                weapon.FindState('MissileFire'), true);
        }
    }

    action void A_RevenantFormPunch()
    {
        if (!player) return;
        FTranslatedLineTarget victim;
        double meleePitch = player.mo.AimLineAttack(
            player.mo.Angle, 96.0, victim, 0.0, ALF_CHECK3D);
        if (victim.linetarget)
        {
            player.mo.LineAttack(player.mo.Angle, 96.0, meleePitch, 45,
                'Melee', 'BulletPuff', LAF_ISMELEEATTACK, victim);
            player.mo.A_StartSound("skeleton/melee", CHAN_WEAPON);
        }
    }

    action void A_FireRevenantFormMissile()
    {
        if (!player) return;
        Actor missile, realMissile;
        [missile, realMissile] = SpawnPlayerMissile(
            'DTMSuperRevenantMissile');
        DTMPlayer tacticalPawn = DTMPlayer(player.mo);
        if (missile && tacticalPawn && tacticalPawn.AimTarget &&
            tacticalPawn.AimTarget.health > 0)
            missile.tracer = tacticalPawn.AimTarget;
        player.mo.A_StartSound("skeleton/attack", CHAN_WEAPON);
    }

    States
    {
    Ready:
        TNT1 A 1 A_WeaponReady;
        Loop;
    Deselect:
        TNT1 A 1 A_Lower;
        Loop;
    Select:
        TNT1 A 1 A_Raise;
        Loop;
    Fire:
        TNT1 A 0 A_SelectRevenantFormAttack;
        Wait;
    MeleeFire:
        TNT1 A 12;
        TNT1 A 6 A_RevenantFormPunch;
        TNT1 A 0 A_ReFire;
        Goto Ready;
    MissileFire:
        TNT1 A 10;
        TNT1 A 20 A_FireRevenantFormMissile;
        TNT1 A 0 A_ReFire;
        Goto Ready;
    Spawn:
        FATB A -1 Bright;
        Stop;
    }
}

class PowerDTMRevenantForm : Powerup
{
    Actor VisualBody;
    Class<Weapon> PreviousWeapon;
    double PreviousAlpha;
    int PreviousRenderStyle;
    double PreviousSpeed;
    int FormHealth;
    int FormMaxHealth;

    Default
    {
        Powerup.Duration -30;
    }

    override void InitEffect()
    {
        Super.InitEffect();
        if (!Owner || !Owner.player) return;
        if (Owner.FindInventory('PowerDTMBaronForm'))
            Owner.TakeInventory('PowerDTMBaronForm', 1);
        if (Owner.FindInventory('PowerDTMCyberForm'))
            Owner.TakeInventory('PowerDTMCyberForm', 1);

        PreviousAlpha = Owner.Alpha;
        PreviousRenderStyle = Owner.GetRenderStyle();
        PreviousSpeed = Owner.Speed;
        PreviousWeapon = Owner.player.ReadyWeapon
            ? Owner.player.ReadyWeapon.GetClass() : null;
        Owner.A_SetRenderStyle(0.0, STYLE_None);
        Owner.Speed *= 1.15;
        FormMaxHealth = 300;
        FormHealth = FormMaxHealth;

        VisualBody = Actor.Spawn('DTMRevenantFormVisual',
            Owner.pos, ALLOW_REPLACE);
        if (VisualBody)
        {
            VisualBody.tracer = Owner;
            VisualBody.Angle = Owner.Angle;
        }
        Owner.GiveInventory('DTMRevenantFormWeapon', 1);
        Weapon formWeapon = Weapon(
            Owner.FindInventory('DTMRevenantFormWeapon'));
        if (formWeapon) Owner.player.PendingWeapon = formWeapon;
        Owner.A_StartSound("skeleton/sight", CHAN_BODY);
        Console.MidPrint(null, "REVENANT FORM RISEN", true);
    }

    override void DoEffect()
    {
        Super.DoEffect();
        if (!Owner) return;
        Owner.A_SetRenderStyle(0.0, STYLE_None);
        if (FormHealth <= 0)
        {
            EffectTics = min(EffectTics, 1);
            return;
        }
        if (!VisualBody)
        {
            VisualBody = Actor.Spawn('DTMRevenantFormVisual',
                Owner.pos, ALLOW_REPLACE);
            if (VisualBody) VisualBody.tracer = Owner;
        }
    }

    override void ModifyDamage(int damage, Name damageType, out int newDamage,
        bool passive, Actor inflictor, Actor source, int flags, double angle)
    {
        if (damage <= 0) return;
        if (!passive)
        {
            newDamage = max(1, int(damage * 1.15 + 0.5));
            return;
        }
        int absorbedDamage = max(1, int(damage * 0.80 + 0.5));
        int overflow = max(0, absorbedDamage - FormHealth);
        FormHealth = max(0, FormHealth - absorbedDamage);
        newDamage = overflow;
        if (FormHealth <= 0) EffectTics = min(EffectTics, 1);
    }

    override void EndEffect()
    {
        Super.EndEffect();
        if (VisualBody)
        {
            VisualBody.Destroy();
            VisualBody = null;
        }
        if (!Owner) return;
        Owner.A_SetRenderStyle(PreviousAlpha, PreviousRenderStyle);
        Owner.Speed = PreviousSpeed;
        Owner.TakeInventory('DTMRevenantFormWeapon', 1);
        if (PreviousWeapon)
        {
            Weapon prior = Weapon(Owner.FindInventory(PreviousWeapon));
            if (prior) Owner.player.PendingWeapon = prior;
        }
        Console.MidPrint(null, "REVENANT FORM CRUMBLES", true);
    }
}

class DTMRevenantFormPowerup : PowerupGiver
{
    override void PostBeginPlay()
    {
        Super.PostBeginPlay();
        A_AttachLight('DTMRevenantPowerGlow', DynamicLight.PointLight,
            Color(255, 45, 15), 104, 104, DynamicLight.LF_ATTENUATE);
    }

    Default
    {
        +COUNTITEM
        +INVENTORY.AUTOACTIVATE
        +INVENTORY.ALWAYSPICKUP
        +INVENTORY.BIGPOWERUP
        Inventory.MaxAmount 0;
        Powerup.Type 'PowerDTMRevenantForm';
        Powerup.Duration -30;
        Inventory.PickupMessage "A Revenant soul rattles inside your bones!";
        Inventory.PickupSound "misc/p_pkup";
        Tag "REVENANT FORM";
        Radius 18;
        Height 24;
        +FLOATBOB
        +BRIGHT
        Translation "192:207=64:79";
    }
    States
    {
    Spawn:
        MEGA A 6 Bright;
        Loop;
    }
}

class DTMCyberFormPowerup : PowerupGiver
{
    override void PostBeginPlay()
    {
        Super.PostBeginPlay();
        A_AttachLight('DTMCyberPowerGlow', DynamicLight.PointLight,
            Color(255, 55, 18), 132, 132, DynamicLight.LF_ATTENUATE);
    }

    Default
    {
        +COUNTITEM
        +INVENTORY.AUTOACTIVATE
        +INVENTORY.ALWAYSPICKUP
        +INVENTORY.BIGPOWERUP
        Inventory.MaxAmount 0;
        Powerup.Type 'PowerDTMCyberForm';
        Powerup.Duration -30;
        Inventory.PickupMessage "Your flesh gives way to infernal machinery!";
        Inventory.PickupSound "misc/p_pkup";
        Tag "CYBERDEMON FORM";
        Radius 20;
        Height 24;
        +FLOATBOB
        +BRIGHT
        Translation "192:207=48:63";
    }
    States
    {
    Spawn:
        MEGA A 6 Bright;
        Loop;
    }
}

class DTMBaronFormPowerup : PowerupGiver
{
    override void PostBeginPlay()
    {
        Super.PostBeginPlay();
        A_AttachLight('DTMBaronPowerGlow', DynamicLight.PointLight,
            Color(205, 20, 20), 112, 112, DynamicLight.LF_ATTENUATE);
    }

    Default
    {
        +COUNTITEM
        +INVENTORY.AUTOACTIVATE
        +INVENTORY.ALWAYSPICKUP
        +INVENTORY.BIGPOWERUP
        Inventory.MaxAmount 0;
        Powerup.Type 'PowerDTMBaronForm';
        Powerup.Duration -30;
        Inventory.PickupMessage "The blood of a Baron consumes you!";
        Inventory.PickupSound "misc/p_pkup";
        Tag "BARON FORM";
        Radius 18;
        Height 24;
        +FLOATBOB
        +BRIGHT
        Translation "192:207=32:47";
    }
    States
    {
    Spawn:
        MEGA A 6 Bright;
        Loop;
    }
}

// Every placed Soulsphere remains a normal Soulsphere half the time. The
// other half becomes one uniformly random demon-form pickup.
class DTMNormalSoulsphere : Soulsphere {}

class DTMDemonSoulSpawner : RandomSpawner replaces Soulsphere
{
    override Name ChooseSpawn()
    {
        int roll = Random[DTMDemonSoul](0, 5);
        if (roll <= 2) return 'DTMNormalSoulsphere';
        if (roll == 3) return 'DTMBaronFormPowerup';
        if (roll == 4) return 'DTMCyberFormPowerup';
        return 'DTMRevenantFormPowerup';
    }
}
