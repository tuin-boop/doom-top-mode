class DTMCameraHandler : StaticEventHandler
{
    override void WorldLoaded(WorldEvent e)
    {
        if (!e.IsSaveGame) return;

        for (int i = 0; i < MAXPLAYERS; i++)
        {
            if (!PlayerInGame[i] || !players[i].mo) continue;
            DTMPlayer pawn = DTMPlayer(players[i].mo);
            if (pawn && pawn.StoredCamera)
            {
                players[i].camera = pawn.StoredCamera;
                pawn.SetupTopDownCamera();
            }
        }
    }

    override void PlayerDisconnected(PlayerEvent e)
    {
        if (players[e.PlayerNumber].camera &&
            players[e.PlayerNumber].camera.GetClassName() == 'SpectatorCamera')
            players[e.PlayerNumber].camera.Destroy();
    }

    override void WorldUnloaded(WorldEvent e)
    {
        for (int i = 0; i < MAXPLAYERS; i++)
        {
            if (PlayerInGame[i] && players[i].camera &&
                players[i].camera.GetClassName() == 'SpectatorCamera')
                players[i].camera.Destroy();
        }
    }
}

class DTMInputHandler : EventHandler
{
    override void NetworkProcess(ConsoleEvent e)
    {
        if (!PlayerInGame[e.Player] || !players[e.Player].mo) return;
        DTMPlayer pawn = DTMPlayer(players[e.Player].mo);
        if (!pawn) return;

        if (e.Name == "DTM_CAM_LEFT") pawn.RotateCamera(-2);
        else if (e.Name == "DTM_CAM_RIGHT") pawn.RotateCamera(2);
        else if (e.Name == "DTM_CAM_PITCH")
        {
            pawn.CycleCameraPitch();
            if (e.Player == consoleplayer)
                Console.Printf("Preferred camera pitch: %d degrees", int(pawn.PreferredCameraPitch));
        }
        else if (e.Name == "DTM_ZOOM_IN") pawn.ChangeZoom(-40);
        else if (e.Name == "DTM_ZOOM_OUT") pawn.ChangeZoom(40);
        else if (e.Name == "DTM_TOGGLE_AUTO_CAMERA")
        {
            CVar autoCamera = CVar.GetCVar("DTM_AutoCamera", players[e.Player]);
            autoCamera.SetBool(!autoCamera.GetBool());
            pawn.AutoCameraSetting = autoCamera;
            pawn.AutoCameraCooldown = 35;
            if (e.Player == consoleplayer)
                Console.Printf(autoCamera.GetBool()
                    ? "Automatic camera avoidance: ON"
                    : "Automatic camera avoidance: OFF");
        }
        else if (e.Name == "DTM_CAM_CENTER" && players[e.Player].camera)
        {
            if (players[e.Player].camera.tracer)
                players[e.Player].camera.SetOrigin(players[e.Player].camera.tracer.pos, true);
        }
        else if (e.Name == "DTM_TOGGLE_AIM")
        {
            CVar assist = CVar.GetCVar("DTM_AimAssist", players[e.Player]);
            assist.SetBool(!assist.GetBool());
            if (e.Player == consoleplayer)
                Console.Printf(assist.GetBool() ? "Top-Down aim assist: ON" : "Top-Down aim assist: OFF");
        }
        else if (e.Name == "DTM_TOGGLE_FLASHLIGHT")
        {
            CVar flashlight = CVar.GetCVar("DTM_Flashlight", players[e.Player]);
            flashlight.SetBool(!flashlight.GetBool());
            pawn.ApplyFlashlight(true);
            if (e.Player == consoleplayer)
                Console.Printf(flashlight.GetBool() ? "Flashlight: ON" : "Flashlight: OFF");
        }
    }
}

class DTMAimHandler : StaticEventHandler
{
    CVar AimEnabled[MAXPLAYERS];
    CVar AimDistance[MAXPLAYERS];
    CVar AimCone[MAXPLAYERS];
    CVar AimTurnSpeed[MAXPLAYERS];
    Actor LockedTarget[MAXPLAYERS];
    Actor AimMarker[MAXPLAYERS];

    override void WorldLoaded(WorldEvent e)
    {
        for (int i = 0; i < MAXPLAYERS; i++)
        {
            if (PlayerInGame[i])
            {
                AimEnabled[i] = CVar.GetCVar("DTM_AimAssist", players[i]);
                AimDistance[i] = CVar.GetCVar("DTM_AimDistance", players[i]);
                AimCone[i] = CVar.GetCVar("DTM_AimCone", players[i]);
                AimTurnSpeed[i] = CVar.GetCVar("DTM_AimTurnSpeed", players[i]);
                LockedTarget[i] = null;
                if (AimMarker[i]) AimMarker[i].Destroy();
                AimMarker[i] = null;
                DTMPlayer pawn = DTMPlayer(players[i].mo);
                if (pawn) pawn.AimTarget = null;
            }
        }
    }

    bool IsValidTarget(PlayerPawn pawn, Actor target, double maximumDistance)
    {
        return target && target.health > 0 && target.bISMONSTER &&
            !target.bFRIENDLY && !target.bCORPSE &&
            pawn.Distance3D(target) <= maximumDistance && pawn.CheckSight(target);
    }

    void ClearTarget(int playerNumber, PlayerPawn pawn)
    {
        LockedTarget[playerNumber] = null;
        DTMPlayer topDownPawn = DTMPlayer(pawn);
        if (topDownPawn) topDownPawn.AimTarget = null;
        if (AimMarker[playerNumber])
        {
            AimMarker[playerNumber].Destroy();
            AimMarker[playerNumber] = null;
        }
    }

    void SetTarget(int playerNumber, PlayerPawn pawn, Actor target)
    {
        LockedTarget[playerNumber] = target;
        DTMPlayer topDownPawn = DTMPlayer(pawn);
        if (topDownPawn) topDownPawn.AimTarget = target;

        if (!AimMarker[playerNumber] || AimMarker[playerNumber].tracer != target)
        {
            if (AimMarker[playerNumber]) AimMarker[playerNumber].Destroy();
            AimMarker[playerNumber] = Actor.Spawn("DTMAimMarker",
                target.pos + (0, 0, target.height * 0.52));
            if (AimMarker[playerNumber]) AimMarker[playerNumber].tracer = target;
        }
    }

    static double, double LookAt(Vector3 from, Vector3 to)
    {
        Vector3 delta = level.Vec3Diff(from, to);
        return atan2(delta.y, delta.x), -asin(delta.z / delta.length());
    }

    bool ApplyAim(int playerNumber)
    {
        PlayerPawn pawn = players[playerNumber].mo;
        DTMPlayer topDownPawn = DTMPlayer(pawn);
        double cursorAngle = topDownPawn ? topDownPawn.GetCursorAimAngle() : pawn.angle;
        double maximumDistance = AimDistance[playerNumber].GetFloat();
        double maximumCone = AimCone[playerNumber]
            ? clamp(AimCone[playerNumber].GetFloat(), 5.0, 90.0) : 55.0;
        Actor closest = null;
        double bestScore = 1.0e30;
        ThinkerIterator iterator = ThinkerIterator.Create('Actor');
        Actor candidate;
        while (candidate = Actor(iterator.Next()))
        {
            if (!IsValidTarget(pawn, candidate, maximumDistance)) continue;
            Vector3 targetDelta = level.Vec3Diff(pawn.pos, candidate.pos);
            double targetYaw = atan2(targetDelta.y, targetDelta.x);
            // Select around the mouse guide, not around the direction the pawn
            // happened to face on the previous tic.
            double angleError = abs(pawn.DeltaAngle(cursorAngle, targetYaw));
            if (angleError > maximumCone) continue;

            double distance = pawn.Distance3D(candidate);
            double score = angleError * 18.0 + distance * 0.12;
            if (candidate == LockedTarget[playerNumber]) score *= 0.55;
            if (score < bestScore)
            {
                bestScore = score;
                closest = candidate;
            }
        }

        if (!closest)
        {
            ClearTarget(playerNumber, pawn);
            return false;
        }

        double eyeHeight = pawn.viewheight * pawn.player.crouchfactor;
        Vector3 viewPosition = pawn.pos + (0, 0, eyeHeight);
        Vector3 targetPosition = closest.pos + (0, 0, closest.height * 0.55);
        double targetAngle, targetPitch;
        [targetAngle, targetPitch] = LookAt(viewPosition, targetPosition);

        FLineTraceData sightTrace;
        pawn.LineTrace(targetAngle, maximumDistance, targetPitch,
            TRF_NOSKY, eyeHeight, data: sightTrace);
        if (sightTrace.hitType != TRACE_HitActor || sightTrace.hitActor != closest)
        {
            ClearTarget(playerNumber, pawn);
            return false;
        }

        SetTarget(playerNumber, pawn, closest);
        double turnSpeed = AimTurnSpeed[playerNumber]
            ? clamp(AimTurnSpeed[playerNumber].GetFloat(), 1.0, 20.0) : 7.0;
        double angleDifference = pawn.DeltaAngle(pawn.angle, targetAngle);
        double pitchDifference = pawn.DeltaAngle(pawn.pitch, targetPitch);

        pawn.A_SetAngle(
            abs(angleDifference) <= turnSpeed ? targetAngle
                : pawn.angle + clamp(angleDifference, -turnSpeed, turnSpeed),
            SPF_INTERPOLATE);
        pawn.A_SetPitch(
            abs(pitchDifference) <= turnSpeed ? targetPitch
                : pawn.pitch + clamp(pitchDifference, -turnSpeed, turnSpeed),
            SPF_INTERPOLATE);
        return true;
    }

    override void WorldTick()
    {
        for (int i = 0; i < MAXPLAYERS; i++)
        {
            if (!PlayerInGame[i] || !players[i].mo || players[i].mo.health <= 0) continue;
            if (!AimEnabled[i])
            {
                AimEnabled[i] = CVar.GetCVar("DTM_AimAssist", players[i]);
                AimDistance[i] = CVar.GetCVar("DTM_AimDistance", players[i]);
                AimCone[i] = CVar.GetCVar("DTM_AimCone", players[i]);
                AimTurnSpeed[i] = CVar.GetCVar("DTM_AimTurnSpeed", players[i]);
            }

            if (!AimEnabled[i].GetBool() || !ApplyAim(i))
            {
                ClearTarget(i, players[i].mo);
                DTMPlayer pawn = DTMPlayer(players[i].mo);
                if (pawn)
                    pawn.A_SetAngle(pawn.GetCursorAimAngle(), SPF_INTERPOLATE);
                players[i].mo.A_SetPitch(0, SPF_INTERPOLATE);
            }
        }
    }
}
