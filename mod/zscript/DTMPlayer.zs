class DTMPlayer : DoomPlayer
{
    static const double CameraYaw[] = {180, 225, 270, 315, 0, 45, 90, 135};
    static const double CameraPitchLevels[] = {35, 48, 60};

    int CameraView;
    int CameraPitchLevel;
    int AutoCameraCooldown;
    int ClearCameraChecks;
    int CameraFlags;
    int FacingCameraMultiplier;
    double CameraYawCurrent;
    double CameraDistance;
    double CameraPitch;
    bool CameraTurning;
    bool EmergencyOverhead;
    double PreferredCameraPitch;
    Actor StoredCamera;
    Actor AimTarget;
    Actor NearbyWeaponDrop;
    bool ShowCharacterPanel;
    CVar AutoCameraSetting;
    int AppliedFlashlightRange;
    int AppliedFlashlightIntensity;
    int AppliedFlashlightPitch;
    bool AppliedFlashlightEnabled;
    double AimCursorX;
    double AimCursorY;
    double PreviousAimCursorX;
    double PreviousAimCursorY;

    Default
    {
        Player.ViewBob 0;
        Player.FlyBob 0;
        // A modest top-down mobility boost while preserving the controller's
        // strong ground braking and equal movement in every screen direction.
        Player.ForwardMove 1.25, 1.25;
        Player.SideMove 1.25, 1.25;
        Player.WeaponSlot 3, "Shotgun", "DTMRiotShotgun", "SuperShotgun";
        Player.WeaponSlot 4, "Chaingun", "DTMUzi";
        Player.WeaponSlot 5, "RocketLauncher", "DTMRevenantLauncher";
        // Normal and experimental plasma rifles share slot 6; repeated presses
        // cycle between owned variants.
        Player.WeaponSlot 6, "ID24Incinerator", "PlasmaRifle", "DTMTwinPlasmaRifle";
        +ISOMETRICSPRITES
    }

    void SetupTopDownCamera()
    {
        if (player.camera == player.mo ||
            (player.camera && player.camera.GetClassName() != 'SpectatorCamera'))
        {
            player.camera = SpectatorCamera(Actor.Spawn("SpectatorCamera", pos));
            player.camera.player = player;
            player.camera.tracer = player.mo;
        StoredCamera = player.camera;
        }

        if (player.camera && player.camera.GetClassName() == 'SpectatorCamera')
        {
            SpectatorCamera(player.camera).Init(
                CameraDistance, CameraYawCurrent, CameraPitch, CameraFlags);
        }
    }

    override void PostBeginPlay()
    {
        Super.PostBeginPlay();
        CameraView = 1;
        CameraYawCurrent = 225;
        CameraDistance = 500;
        CameraPitchLevel = 1;
        CameraPitch = CameraPitchLevels[CameraPitchLevel];
        PreferredCameraPitch = CameraPitch;
        CameraFlags = VPSF_ABSOLUTEOFFSET | VPSF_ALLOWOUTOFBOUNDS | VPSF_ORTHOGRAPHIC;
        FacingCameraMultiplier = 1;
        CameraTurning = false;
        EmergencyOverhead = false;
        ClearCameraChecks = 0;
        AutoCameraCooldown = 35;
        AutoCameraSetting = CVar.GetCVar("DTM_AutoCamera", player);
        AimTarget = null;
        NearbyWeaponDrop = null;
        ShowCharacterPanel = false;
        AppliedFlashlightRange = -1;
        AppliedFlashlightIntensity = -1;
        AppliedFlashlightPitch = 999;
        AppliedFlashlightEnabled = false;
        // Virtual 1920x1080 HUD-space offset from screen center.
        AimCursorX = 220;
        AimCursorY = 0;
        PreviousAimCursorX = AimCursorX;
        PreviousAimCursorY = AimCursorY;
        SetupTopDownCamera();
        ApplyFlashlight(true);
    }

    void ApplyFlashlight(bool force = false)
    {
        CVar enabledSetting = CVar.GetCVar("DTM_Flashlight", player);
        CVar rangeSetting = CVar.GetCVar("DTM_FlashlightRange", player);
        CVar intensitySetting = CVar.GetCVar("DTM_FlashlightIntensity", player);
        bool shouldEnable = enabledSetting && enabledSetting.GetBool() && health > 0;
        int lightRange = rangeSetting ? clamp(rangeSetting.GetInt(), 128, 1024) : 512;
        int lightIntensity = intensitySetting
            ? clamp(int(intensitySetting.GetFloat() * 100.0 + 0.5), 25, 200) : 100;
        int lightPitch = int(pitch);

        if (!force && AppliedFlashlightRange == lightRange &&
            AppliedFlashlightIntensity == lightIntensity &&
            AppliedFlashlightPitch == lightPitch &&
            AppliedFlashlightEnabled == shouldEnable)
            return;

        A_RemoveLight('DTMPlayerFlashlight');
        AppliedFlashlightRange = lightRange;
        AppliedFlashlightIntensity = lightIntensity;
        AppliedFlashlightPitch = lightPitch;
        AppliedFlashlightEnabled = shouldEnable;

        if (shouldEnable)
        {
            int flags = DynamicLight.LF_SPOT | DynamicLight.LF_ATTENUATE |
                DynamicLight.LF_DONTLIGHTSELF;
            int effectiveRadius = clamp(
                int(lightRange * lightIntensity * 0.01), 64, 1536);
            A_AttachLight('DTMPlayerFlashlight', DynamicLight.PointLight,
                Color(255, 244, 214), effectiveRadius, effectiveRadius, flags,
                (12, 0, height * 0.72), 0.0, 22.0, 56.0, lightPitch);
        }
    }

    void RotateCamera(int amount)
    {
        CameraView = (CameraView + amount + 8) % 8;
        CameraTurning = true;
        AutoCameraCooldown = 140;
    }

    void CycleCameraPitch()
    {
        CameraPitchLevel = (CameraPitchLevel + 1) % 3;
        PreferredCameraPitch = CameraPitchLevels[CameraPitchLevel];
        CameraPitch = PreferredCameraPitch;
        EmergencyOverhead = false;
        ClearCameraChecks = 0;
        SetupTopDownCamera();
    }

    void ChangeZoom(double amount)
    {
        CameraDistance = clamp(CameraDistance + amount, 340.0, 700.0);
        SetupTopDownCamera();
    }

    double GetCursorAimAngle()
    {
        // Convert the HUD-space mouse direction into a world-space angle.
        // Screen-right points across the camera and screen-down points back
        // toward it, so this stays correct while the isometric camera rotates.
        if (abs(AimCursorX) < 0.01 && abs(AimCursorY) < 0.01)
            return angle;

        double rightAngle = CameraYawCurrent + 90.0;
        double worldX = cos(rightAngle) * AimCursorX +
            cos(CameraYawCurrent) * AimCursorY;
        double worldY = sin(rightAngle) * AimCursorX +
            sin(CameraYawCurrent) * AimCursorY;
        // CameraYawCurrent describes the camera's position around the pawn;
        // the rendered view looks back along the opposite world direction.
        return atan2(worldY, worldX) + 180.0;
    }

    double, double ScoreCameraView(int viewIndex)
    {
        // Probe at the normal tactical pitch even while emergency overhead is active.
        double traceDistance = CameraDistance * cos(48);
        double score = 0;
        double closestClearance = traceDistance;
        double eyeHeight = viewheight * player.crouchfactor;

        // Five horizontal probes approximate the width of the orthographic view.
        for (int sample = -2; sample <= 2; sample++)
        {
            FLineTraceData trace;
            double traceYaw = CameraYaw[viewIndex] + 180 + sample * 10;
            double clearance = traceDistance;

            if (LineTrace(traceYaw, traceDistance, 0,
                TRF_NOSKY | TRF_THRUACTORS, eyeHeight, data: trace))
            {
                Vector3 hitDelta = level.Vec3Diff(
                    pos + (0, 0, eyeHeight), trace.hitLocation);
                clearance = hitDelta.xy.length();
            }

            // Give the center probe more influence than the edges.
            score += clearance * (sample == 0 ? 1.5 : 1.0);
            closestClearance = min(closestClearance, clearance);
        }
        return score, closestClearance;
    }

    void FindClearCameraView()
    {
        double probeDistance = CameraDistance * cos(48);
        double maximumScore = probeDistance * 5.5;
        double currentScore, currentClearance;
        [currentScore, currentClearance] = ScoreCameraView(CameraView);
        double bestScore = currentScore;
        double bestClearance = currentClearance;
        int bestView = CameraView;

        for (int viewIndex = 1; viewIndex < 8; viewIndex += 2)
        {
            if (viewIndex == CameraView) continue;
            double candidateScore, candidateClearance;
            [candidateScore, candidateClearance] = ScoreCameraView(viewIndex);
            if (candidateClearance > bestClearance * 1.1 ||
                (candidateClearance >= bestClearance * 0.9 && candidateScore > bestScore))
            {
                bestScore = candidateScore;
                bestClearance = candidateClearance;
                bestView = viewIndex;
            }
        }

        bool allViewsCramped = bestScore < maximumScore * 0.68 ||
            bestClearance < probeDistance * 0.22;

        if (allViewsCramped)
        {
            ClearCameraChecks = 0;
            if (!EmergencyOverhead)
            {
                EmergencyOverhead = true;
                CameraPitch = 82;
                SetupTopDownCamera();
            }
        }
        else if (EmergencyOverhead)
        {
            ClearCameraChecks++;
            if (ClearCameraChecks >= 3)
            {
                EmergencyOverhead = false;
                ClearCameraChecks = 0;
                CameraPitch = PreferredCameraPitch;
                SetupTopDownCamera();
            }
        }

        // Rotate only for a clear improvement, avoiding needless camera churn.
        if (!EmergencyOverhead && bestView != CameraView && currentScore < maximumScore * 0.82 &&
            bestScore > currentScore * 1.18)
        {
            CameraView = bestView;
            CameraTurning = true;
            AutoCameraCooldown = 105;
        }
    }

    override void Tick()
    {
        if (player.camera == player.mo)
        {
            if (StoredCamera) player.camera = StoredCamera;
            SetupTopDownCamera();
        }

        if (CameraTurning && player.camera && player.camera.GetClassName() == 'SpectatorCamera')
        {
            double targetYaw = CameraYaw[CameraView];
            double difference = DeltaAngle(CameraYawCurrent, targetYaw);

            if (abs(difference) <= 3.0)
            {
                CameraYawCurrent = targetYaw;
                CameraTurning = false;
            }
            else
            {
                CameraYawCurrent += clamp(difference, -6.0, 6.0);
            }

            SpectatorCamera(player.camera).Init(
                CameraDistance, CameraYawCurrent, CameraPitch, -1);
        }

        if (AutoCameraCooldown > 0) AutoCameraCooldown--;
        else
        {
            if (!AutoCameraSetting)
                AutoCameraSetting = CVar.GetCVar("DTM_AutoCamera", player);
            if (AutoCameraSetting.GetBool() && !CameraTurning)
                FindClearCameraView();
            AutoCameraCooldown = 35;
        }

        double differenceToCamera = DeltaAngle(angle, CameraYawCurrent);
        FacingCameraMultiplier = abs(differenceToCamera) > 90 ? -1 : 1;

        Super.Tick();

        ApplyFlashlight();

        if ((Pos.Z == FloorZ) || bONMOBJ)
        {
            Vel.X *= 0.6;
            Vel.Y *= 0.6;
        }
    }

    override void MovePlayer()
    {
        UserCmd cmd = player.cmd;
        double differenceToCamera = DeltaAngle(angle, CameraYawCurrent);

        // Convert UZDoom's captured relative mouse motion back into a visible
        // virtual cursor. Keeping this in the player avoids native OS cursor
        // mode, so normal mouse buttons and weapon firing continue to work.
        PreviousAimCursorX = AimCursorX;
        PreviousAimCursorY = AimCursorY;
        AimCursorX = clamp(AimCursorX - GetPlayerInput(INPUT_YAW) / 12.0,
            -850.0, 850.0);
        // UZDoom's pitch command is positive for mouse-down; HUD Y is also
        // positive downward, so invert it for natural screen-space movement.
        AimCursorY = clamp(AimCursorY - GetPlayerInput(INPUT_PITCH) / 12.0,
            -450.0, 300.0);

        cmd.yaw -= GetPlayerInput(INPUT_YAW);
        if (differenceToCamera >= 0) cmd.yaw += GetPlayerInput(INPUT_PITCH);
        else cmd.yaw -= GetPlayerInput(INPUT_PITCH);

        if (differenceToCamera > 45 && differenceToCamera < 135)
            cmd.yaw += 2 * GetPlayerInput(INPUT_PITCH);
        else if (differenceToCamera > -135 && differenceToCamera < -45)
            cmd.yaw -= 2 * GetPlayerInput(INPUT_PITCH);

        if (abs(differenceToCamera) < 80 || abs(differenceToCamera) > 100)
            cmd.yaw += 2 * FacingCameraMultiplier * GetPlayerInput(INPUT_YAW);

        int side = cmd.sidemove;
        int forward = cmd.forwardmove;

        if (differenceToCamera > 67.5 && differenceToCamera < 112.5)
        {
            cmd.sidemove = -forward;
            cmd.forwardmove = side;
        }
        else if (differenceToCamera > -112.5 && differenceToCamera < -67.5)
        {
            cmd.sidemove = forward;
            cmd.forwardmove = -side;
        }
        else if (differenceToCamera > 22.5 && differenceToCamera <= 67.5)
        {
            cmd.sidemove = int(0.707 * (side - forward));
            cmd.forwardmove = int(0.707 * (side + forward));
        }
        else if (differenceToCamera < -22.5 && differenceToCamera >= -67.5)
        {
            cmd.sidemove = int(0.707 * (side + forward));
            cmd.forwardmove = int(0.707 * (-side + forward));
        }
        else if (differenceToCamera >= 112.5 && differenceToCamera < 157.5)
        {
            cmd.sidemove = int(0.707 * (-side - forward));
            cmd.forwardmove = int(0.707 * (side - forward));
        }
        else if (differenceToCamera <= -112.5 && differenceToCamera > -157.5)
        {
            cmd.sidemove = int(0.707 * (-side + forward));
            cmd.forwardmove = int(0.707 * (-side - forward));
        }
        else
        {
            cmd.sidemove *= FacingCameraMultiplier;
            cmd.forwardmove *= FacingCameraMultiplier;
        }

        Super.MovePlayer();
    }
}
