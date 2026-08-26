class DTMCombatFlash : Actor
{
    int RemainingTics;

    Default
    {
        +NOINTERACTION
        +NOGRAVITY
        +BRIGHT
    }

    override void PostBeginPlay()
    {
        Super.PostBeginPlay();
        RemainingTics = 3;
        A_AttachLight('DTMMuzzleLight', DynamicLight.PointLight,
            Color(255, 205, 105), 112, 112,
            DynamicLight.LF_ATTENUATE | DynamicLight.LF_DONTLIGHTSELF);
    }

    override void Tick()
    {
        Super.Tick();
        if (--RemainingTics <= 0) Destroy();
    }

    States
    {
    Spawn:
        TNT1 A -1;
        Stop;
    }
}

class DTMFlyingTracer : Actor
{
    int RemainingSteps;

    Default
    {
        +NOINTERACTION
        +NOGRAVITY
        +BRIGHT
        RenderStyle "Add";
        Alpha 0.95;
        Scale 1.0;
    }

    void InitTracer(Vector3 start, Vector3 finish)
    {
        Vector3 delta = level.Vec3Diff(start, finish);
        double distance = delta.length();
        // A real moving sprite, modelled after aircraft-style tracer rounds.
        // Velocity gives the renderer smooth interpolation between game tics.
        RemainingSteps = clamp(int(distance / 150.0) + 1, 2, 12);
        SetOrigin(start, false);
        Vel = delta / double(RemainingSteps);
        A_SetAngle(atan2(delta.y, delta.x));
        if (distance > 0.01)
            A_SetPitch(-asin(delta.z / distance));
        SetupTracerLight();
    }

    virtual void SetupTracerLight()
    {
        // A compact moving glow keeps an end-on tracer readable when its long
        // axis points almost directly toward the isometric camera.
        A_AttachLight('DTMTracerGlow', DynamicLight.PointLight,
            Color(255, 205, 90), 30, 30,
            DynamicLight.LF_ATTENUATE | DynamicLight.LF_DONTLIGHTSELF);
    }

    override void Tick()
    {
        Super.Tick();
        if (RemainingSteps <= 0)
        {
            Destroy();
            return;
        }

        RemainingSteps--;
    }

    States
    {
    Spawn:
        TRAC A 1 Bright;
        Loop;
    }
}

class DTMEnemyFlyingTracer : DTMFlyingTracer
{
    Default
    {
        RenderStyle "AddStencil";
        StencilColor "FF 38 18";
        Alpha 0.90;
    }

    override void SetupTracerLight()
    {
        A_AttachLight('DTMEnemyTracerGlow', DynamicLight.PointLight,
            Color(255, 55, 20), 34, 34,
            DynamicLight.LF_ATTENUATE | DynamicLight.LF_DONTLIGHTSELF);
    }
}

class DTMPistolTracer : DTMFlyingTracer {}
class DTMChaingunTracer : DTMFlyingTracer {}
class DTMShotgunTracer : DTMFlyingTracer {}
class DTMSuperShotgunTracer : DTMFlyingTracer {}

class DTMImpactSpark : Actor
{
    int RemainingTics;

    Default
    {
        +NOINTERACTION
        +NOGRAVITY
        +BRIGHT
    }

    void InitImpact(bool hostile)
    {
        RemainingTics = 3;
        Color sparkColor = hostile ? Color(255, 58, 22) : Color(255, 208, 92);

        for (int i = 0; i < 6; i++)
        {
            double sparkAngle = i * 60.0 + Random(-14, 14);
            double sparkSpeed = Random(25, 55) / 10.0;
            A_SpawnParticle(sparkColor,
                SPF_FULLBRIGHT | SPF_FACECAMERA,
                7, Random(20, 34) / 10.0, 0,
                0, 0, Random(2, 8) / 10.0,
                cos(sparkAngle) * sparkSpeed,
                sin(sparkAngle) * sparkSpeed,
                Random(8, 28) / 10.0,
                0, 0, -0.35,
                1.0, 0.14, -0.20);
        }

        A_AttachLight(hostile ? 'DTMEnemyImpactLight' : 'DTMImpactLight',
            DynamicLight.PointLight, sparkColor, 54, 54,
            DynamicLight.LF_ATTENUATE | DynamicLight.LF_DONTLIGHTSELF);
    }

    override void Tick()
    {
        Super.Tick();
        if (--RemainingTics <= 0) Destroy();
    }

    States
    {
    Spawn:
        TNT1 A -1;
        Stop;
    }
}

class DTMProjectileTrailEmitter : Actor
{
    Name TrailType;
    Vector3 LastPosition;

    Default
    {
        +NOINTERACTION
        +NOGRAVITY
        +NOSECTOR
        +NOBLOCKMAP
    }

    void InitTrail(Actor projectile, Name trailType)
    {
        master = projectile;
        TrailType = trailType;
        LastPosition = projectile.Pos;
        SetOrigin(projectile.Pos, false);
    }

    void EmitAt(Vector3 worldPosition)
    {
        Vector3 offset = worldPosition - Pos;

        if (TrailType == 'Rocket')
        {
            A_SpawnParticle(Color(92, 82, 72), SPF_FACECAMERA,
                16, 5.0, 0, offset.x, offset.y, offset.z,
                Random(-6, 6) / 20.0, Random(-6, 6) / 20.0,
                Random(4, 12) / 10.0, 0, 0, 0.03,
                0.62, 0.035, 0.15);
            A_SpawnParticle(Color(255, 105, 22), SPF_FULLBRIGHT | SPF_FACECAMERA,
                5, 2.4, 0, offset.x, offset.y, offset.z,
                0, 0, 0, 0, 0, 0,
                0.90, 0.18, -0.28);
        }
        else if (TrailType == 'Plasma')
        {
            A_SpawnParticle(Color(65, 155, 255), SPF_FULLBRIGHT | SPF_FACECAMERA,
                7, 3.6, 0, offset.x, offset.y, offset.z,
                0, 0, 0, 0, 0, 0,
                0.78, 0.11, -0.22);
        }
        else if (TrailType == 'BFG')
        {
            A_SpawnParticle(Color(75, 255, 105), SPF_FULLBRIGHT | SPF_FACECAMERA,
                10, 5.2, 0, offset.x, offset.y, offset.z,
                0, 0, Random(-3, 3) / 20.0, 0, 0, 0,
                0.82, 0.08, -0.18);
        }
    }

    override void Tick()
    {
        Super.Tick();
        if (!master)
        {
            Destroy();
            return;
        }

        Vector3 currentPosition = master.Pos;
        SetOrigin(currentPosition, false);
        Vector3 movement = level.Vec3Diff(LastPosition, currentPosition);
        int samples = clamp(int(movement.length() / 8.0) + 1, 1, 8);

        for (int i = 0; i < samples; i++)
        {
            double fraction = double(i) / double(samples);
            EmitAt(currentPosition - movement * fraction);
        }
        LastPosition = currentPosition;
    }

    States
    {
    Spawn:
        TNT1 A -1;
        Stop;
    }
}

class DTMCombatFXHandler : StaticEventHandler
{
    int LastShotTic[MAXPLAYERS];
    int TracersThisTic[MAXPLAYERS];
    Actor LastMonsterShooter;
    int LastMonsterShotTic;
    int MonsterTracersThisTic;

    override void WorldLoaded(WorldEvent e)
    {
        for (int i = 0; i < MAXPLAYERS; i++)
        {
            LastShotTic[i] = -1;
            TracersThisTic[i] = 0;
        }
        LastMonsterShooter = null;
        LastMonsterShotTic = -1;
        MonsterTracersThisTic = 0;
    }

    int FindPlayer(Actor source)
    {
        for (int i = 0; i < MAXPLAYERS; i++)
            if (PlayerInGame[i] && players[i].mo == source) return i;
        return -1;
    }

    bool EffectsEnabled(int playerNumber)
    {
        CVar setting = CVar.GetCVar("DTM_CombatFX", players[playerNumber]);
        return !setting || setting.GetBool();
    }

    bool AnyPlayerEffectsEnabled()
    {
        for (int i = 0; i < MAXPLAYERS; i++)
            if (PlayerInGame[i] && EffectsEnabled(i)) return true;
        return false;
    }

    Name PlayerTracerClass(int playerNumber)
    {
        Weapon weapon = players[playerNumber].ReadyWeapon;
        if (!weapon) return 'DTMFlyingTracer';
        if (weapon is 'SuperShotgun') return 'DTMSuperShotgunTracer';
        if (weapon is 'Shotgun') return 'DTMShotgunTracer';
        if (weapon is 'Chaingun') return 'DTMChaingunTracer';
        if (weapon is 'Pistol') return 'DTMPistolTracer';
        return 'DTMFlyingTracer';
    }

    void SpawnTracer(Vector3 start, Vector3 finish, bool hostile = false,
        Name tracerType = 'DTMFlyingTracer')
    {
        Vector3 delta = level.Vec3Diff(start, finish);
        if (delta.length() < 12.0) return;

        DTMFlyingTracer tracer = DTMFlyingTracer(
            Actor.Spawn(hostile ? 'DTMEnemyFlyingTracer' : tracerType,
                start, ALLOW_REPLACE));
        if (tracer) tracer.InitTracer(start, finish);

        DTMImpactSpark impact = DTMImpactSpark(
            Actor.Spawn("DTMImpactSpark", finish, ALLOW_REPLACE));
        if (impact) impact.InitImpact(hostile);
    }

    void SpawnMuzzleFlash(Vector3 attackPosition)
    {
        Actor.Spawn("DTMCombatFlash", attackPosition, ALLOW_REPLACE);
    }

    override void WorldHitscanFired(WorldEvent e)
    {
        int playerNumber = FindPlayer(e.Thing);
        if (playerNumber < 0)
        {
            // Vanilla gun monsters also use hitscans. Give them the same real
            // tracer actor while leaving their original damage untouched.
            if (!e.Thing || !e.Thing.bISMONSTER || !AnyPlayerEffectsEnabled()) return;

            if (LastMonsterShooter != e.Thing || LastMonsterShotTic != level.maptime)
            {
                LastMonsterShooter = e.Thing;
                LastMonsterShotTic = level.maptime;
                MonsterTracersThisTic = 0;
                SpawnMuzzleFlash(e.AttackPos);
            }
            if (MonsterTracersThisTic < 3)
            {
                SpawnTracer(e.AttackPos, e.DamagePosition, true);
                MonsterTracersThisTic++;
            }
            return;
        }

        if (!EffectsEnabled(playerNumber)) return;

        if (LastShotTic[playerNumber] != level.maptime)
        {
            LastShotTic[playerNumber] = level.maptime;
            TracersThisTic[playerNumber] = 0;
            SpawnMuzzleFlash(e.AttackPos);
        }

        // Pistols and chainguns get one clean tracer; shotguns may show up to
        // three pellet paths, enough to communicate spread without particle lag.
        if (TracersThisTic[playerNumber] < 3)
        {
            SpawnTracer(e.AttackPos, e.DamagePosition, false,
                PlayerTracerClass(playerNumber));
            TracersThisTic[playerNumber]++;
        }
    }

    override void WorldThingSpawned(WorldEvent e)
    {
        Actor missile = e.Thing;
        if (!missile || !missile.bMISSILE || !missile.target) return;
        int playerNumber = FindPlayer(missile.target);
        if (playerNumber < 0 || !EffectsEnabled(playerNumber)) return;

        // Player projectiles receive restrained colored illumination. This is
        // deliberately light-only so it remains compatible with VoxelDoom and
        // weapon mods that replace their projectile sprites.
        Name missileType = missile.GetClassName();
        if (missileType == 'Rocket')
        {
            missile.A_AttachLight('DTMProjectileLight', DynamicLight.PointLight,
                Color(255, 135, 45), 104, 104, DynamicLight.LF_ATTENUATE);
            DTMProjectileTrailEmitter rocketTrail = DTMProjectileTrailEmitter(
                Actor.Spawn('DTMProjectileTrailEmitter', missile.Pos, ALLOW_REPLACE));
            if (rocketTrail) rocketTrail.InitTrail(missile, 'Rocket');
        }
        else if (missileType == 'PlasmaBall')
        {
            missile.A_AttachLight('DTMProjectileLight', DynamicLight.PointLight,
                Color(65, 145, 255), 76, 76, DynamicLight.LF_ATTENUATE);
            DTMProjectileTrailEmitter plasmaTrail = DTMProjectileTrailEmitter(
                Actor.Spawn('DTMProjectileTrailEmitter', missile.Pos, ALLOW_REPLACE));
            if (plasmaTrail) plasmaTrail.InitTrail(missile, 'Plasma');
        }
        else if (missileType == 'BFGBall')
        {
            missile.A_AttachLight('DTMProjectileLight', DynamicLight.PointLight,
                Color(80, 255, 95), 132, 132, DynamicLight.LF_ATTENUATE);
            DTMProjectileTrailEmitter bfgTrail = DTMProjectileTrailEmitter(
                Actor.Spawn('DTMProjectileTrailEmitter', missile.Pos, ALLOW_REPLACE));
            if (bfgTrail) bfgTrail.InitTrail(missile, 'BFG');
        }
    }
}
