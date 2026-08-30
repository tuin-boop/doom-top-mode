// Rocket-ammo sidegrade using Doom's real Revenant projectile art. It trades
// raw blast damage for extremely reliable pursuit and target reacquisition.

class DTMSuperRevenantMissile : RevenantTracer
{
    Default
    {
        Speed 14;
        Damage 9;
        +SEEKERMISSILE
        +RANDOMIZE
        RenderStyle "Add";
        Alpha 1.0;
    }

    override void PostBeginPlay()
    {
        Super.PostBeginPlay();
        A_AttachLight('DTMRevenantMissileGlow', DynamicLight.PointLight,
            Color(255, 82, 28), 82, 82, DynamicLight.LF_ATTENUATE);
    }

    action void A_SuperRevenantSeek()
    {
        // Precise 45-degree correction every tic is dramatically stronger
        // than vanilla tracking. LOOK reacquires after a target dies.
        A_SeekerMissile(0, 45, SMF_PRECISE | SMF_LOOK, 100, 16);
        if (!(level.maptime & 1))
        {
            Actor smoke = Spawn('RevenantTracerSmoke',
                Vec3Offset(-Vel.X * 0.55, -Vel.Y * 0.55, -2), ALLOW_REPLACE);
            if (smoke)
            {
                smoke.Vel.Z = 0.8;
                smoke.Scale = (0.75, 0.75);
            }
        }
    }

    States
    {
    Spawn:
        FATB AB 1 Bright A_SuperRevenantSeek;
        Loop;
    Death:
        FBXP A 8 Bright;
        FBXP B 6 Bright;
        FBXP C 4 Bright;
        Stop;
    }
}

class DTMRevenantLauncher : RocketLauncher
{
    Default
    {
        Weapon.SelectionOrder 450;
        Weapon.AmmoUse 1;
        Weapon.AmmoGive 2;
        Weapon.AmmoType "RocketAmmo";
        Inventory.PickupMessage "Revenant launcher acquired.";
        Tag "REVENANT LAUNCHER";
    }

    action void A_FireSuperRevenantMissile()
    {
        if (!player) return;
        Actor missile, realMissile;
        [missile, realMissile] = A_FireProjectile(
            'DTMSuperRevenantMissile', 0, true, 0, 8);
        if (!missile) return;

        DTMPlayer tacticalPawn = DTMPlayer(player.mo);
        if (tacticalPawn && tacticalPawn.AimTarget &&
            tacticalPawn.AimTarget.health > 0)
            missile.tracer = tacticalPawn.AimTarget;
        player.mo.A_StartSound("skeleton/attack", CHAN_WEAPON);
        player.mo.PlayAttacking2();
    }

    States
    {
    Fire:
        MISG B 4;
        MISG B 6 A_FireSuperRevenantMissile;
        MISG B 20 A_ReFire;
        Goto Ready;
    Spawn:
        LAUN A -1 Bright;
        Stop;
    }
}

class DTMRevenantLauncherTestDrop : DTMWeaponDrop
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
        InitRevenantLauncher(2, testLevel);
    }

    States
    {
    Spawn:
        LAUN A -1 Bright;
        Stop;
    }
}
