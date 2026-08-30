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
        SpawnPlayerMissile('BaronBall');
        PowerDTMBaronForm power = PowerDTMBaronForm(
            player.mo.FindInventory('PowerDTMBaronForm'));
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
    double PreviousSpeed;
    bool HealthBonusApplied;

    Default
    {
        Powerup.Duration -30;
    }

    override void InitEffect()
    {
        Super.InitEffect();
        if (!Owner || !Owner.player) return;

        PreviousAlpha = Owner.Alpha;
        PreviousSpeed = Owner.Speed;
        PreviousWeapon = Owner.player.ReadyWeapon
            ? Owner.player.ReadyWeapon.GetClass() : null;
        Owner.Alpha = 0.0;
        Owner.Speed *= 1.10;

        PlayerPawn pawn = PlayerPawn(Owner);
        pawn.BonusHealth += 100;
        Owner.health += 100;
        HealthBonusApplied = true;

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
        Owner.Alpha = 0.0;
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

        Owner.Alpha = PreviousAlpha;
        Owner.Speed = PreviousSpeed;
        if (HealthBonusApplied)
        {
            PlayerPawn pawn = PlayerPawn(Owner);
            pawn.BonusHealth = max(0, pawn.BonusHealth - 100);
            Owner.health = min(Owner.health, Owner.GetMaxHealth(true));
            HealthBonusApplied = false;
        }
        Owner.TakeInventory('DTMBaronWeapon', 1);
        if (PreviousWeapon)
        {
            Weapon prior = Weapon(Owner.FindInventory(PreviousWeapon));
            if (prior) Owner.player.PendingWeapon = prior;
        }
        Console.MidPrint(null, "BARON FORM FADES", true);
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
