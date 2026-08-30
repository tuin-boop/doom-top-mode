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
        BOSS EF 4;
        BOSS G 6;
        Goto See;
    Melee:
        BOSS EF 3;
        BOSS G 5;
        Goto See;
    }
}

class DTMBaronWeapon : DoomWeapon
{
    Default
    {
        Weapon.SelectionOrder 10;
        Weapon.AmmoUse 0;
        +WEAPON.NOAUTOFIRE
        Tag "BARON CLAWS";
    }

    action void A_FireBaronForm()
    {
        if (!player) return;

        PowerDTMBaronForm power = PowerDTMBaronForm(
            player.mo.FindInventory('PowerDTMBaronForm'));

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
            if (power && power.VisualBody)
                power.VisualBody.SetStateLabel('Melee');
            return;
        }

        SpawnPlayerMissile('BaronBall');
        if (power && power.VisualBody)
            power.VisualBody.SetStateLabel('Missile');
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
        TNT1 A 6 A_FireBaronForm;
        TNT1 A 10 A_ReFire;
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
    int AppliedHealthBonus;
    int OriginalHealth;

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

        PreviousAlpha = Owner.Alpha;
        PreviousRenderStyle = Owner.GetRenderStyle();
        PreviousSpeed = Owner.Speed;
        OriginalHealth = Owner.health;
        PreviousWeapon = Owner.player.ReadyWeapon
            ? Owner.player.ReadyWeapon.GetClass() : null;
        Owner.A_SetRenderStyle(0.0, STYLE_None);
        Owner.Speed *= 1.10;

        PlayerPawn pawn = PlayerPawn(Owner);
        AppliedHealthBonus = max(0, 1000 - Owner.GetMaxHealth(true));
        pawn.BonusHealth += AppliedHealthBonus;
        Owner.health = max(Owner.health, 1000);

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
        newDamage = passive
            ? max(1, int(damage * 0.70 + 0.5))
            : max(1, int(damage * 1.25 + 0.5));
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
        if (AppliedHealthBonus > 0)
        {
            PlayerPawn pawn = PlayerPawn(Owner);
            pawn.BonusHealth = max(0, pawn.BonusHealth - AppliedHealthBonus);
            AppliedHealthBonus = 0;
        }
        // The form's large health pool is temporary, not a free full heal.
        Owner.health = max(1, min(Owner.health,
            min(OriginalHealth, Owner.GetMaxHealth(true))));
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
        CYBR E 5;
        CYBR F 10 Bright;
        Goto See;
    }
}

class DTMCyberWeapon : DoomWeapon
{
    Default
    {
        Weapon.SelectionOrder 10;
        Weapon.AmmoUse 0;
        +WEAPON.NOAUTOFIRE
        Tag "CYBER ROCKET ARM";
    }

    action void A_FireCyberForm()
    {
        if (!player) return;
        SpawnPlayerMissile('Rocket');
        player.mo.A_StartSound("weapons/rocklf", CHAN_WEAPON);
        PowerDTMCyberForm power = PowerDTMCyberForm(
            player.mo.FindInventory('PowerDTMCyberForm'));
        if (power && power.VisualBody)
            power.VisualBody.SetStateLabel('Missile');
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
        TNT1 A 6 A_FireCyberForm;
        TNT1 A 12 A_ReFire;
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
    int AppliedHealthBonus;
    int OriginalHealth;

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

        PreviousAlpha = Owner.Alpha;
        PreviousRenderStyle = Owner.GetRenderStyle();
        PreviousSpeed = Owner.Speed;
        OriginalHealth = Owner.health;
        PreviousWeapon = Owner.player.ReadyWeapon
            ? Owner.player.ReadyWeapon.GetClass() : null;
        Owner.A_SetRenderStyle(0.0, STYLE_None);
        Owner.Speed *= 0.95;

        PlayerPawn pawn = PlayerPawn(Owner);
        AppliedHealthBonus = max(0, 4000 - Owner.GetMaxHealth(true));
        pawn.BonusHealth += AppliedHealthBonus;
        Owner.health = max(Owner.health, 4000);

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
        newDamage = passive
            ? max(1, int(damage * 0.50 + 0.5))
            : max(1, int(damage * 1.35 + 0.5));
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
        if (AppliedHealthBonus > 0)
        {
            PlayerPawn pawn = PlayerPawn(Owner);
            pawn.BonusHealth = max(0, pawn.BonusHealth - AppliedHealthBonus);
            AppliedHealthBonus = 0;
        }
        Owner.health = max(1, min(Owner.health,
            min(OriginalHealth, Owner.GetMaxHealth(true))));
        Owner.TakeInventory('DTMCyberWeapon', 1);
        if (PreviousWeapon)
        {
            Weapon prior = Weapon(Owner.FindInventory(PreviousWeapon));
            if (prior) Owner.player.PendingWeapon = prior;
        }
        Console.MidPrint(null, "CYBERDEMON FORM OFFLINE", true);
    }
}

class DTMCyberFormPowerup : PowerupGiver
{
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
    }
    States
    {
    Spawn:
        MISL A 5 Bright;
        CYBR F 5 Bright;
        Loop;
    }
}

class DTMBaronFormPowerup : PowerupGiver
{
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
    }
    States
    {
    Spawn:
        BAL7 AB 5 Bright;
        Loop;
    }
}
