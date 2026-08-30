class DTMStatusBar : BaseStatusBar
{
    HUDFont NumberFont;
    HUDFont LabelFont;

    override void Init()
    {
        Super.Init();
        SetSize(0, 1920, 1080);
        Font number = "HUDFONT_DOOM";
        NumberFont = HUDFont.Create(
            number, number.GetCharWidth("0"), Mono_CellLeft, 1, 1);
        LabelFont = HUDFont.Create("SmallFont");
    }

    override void Draw(int state, double ticFrac)
    {
        Super.Draw(state, ticFrac);
        if (state == HUD_None || !CPlayer || !CPlayer.mo) return;

        // Fractional scaling keeps the HUD anchored correctly at any 16:9
        // resolution instead of choosing an undersized integer clean scale.
        BeginHUD(1.0, false, 1920, 1080);

        // Anchor every panel element to the true bottom-center of the screen.
        // Negative Y coordinates are measured upward from the bottom edge.
        DrawImage("DTMHUDL", (-520, -247),
            DI_SCREEN_CENTER_BOTTOM | DI_ITEM_LEFT_TOP, 0.92,
            scale: (0.82, 0.82));
        DrawImage("DTMHUDR", (20, -247),
            DI_SCREEN_CENTER_BOTTOM | DI_ITEM_LEFT_TOP, 0.92,
            scale: (0.82, 0.82));

        int health = max(0, CPlayer.health);
        int armor = GetArmorAmount();
        DTMPlayerProgress playerProgress = DTMPlayerProgress(
            CPlayer.mo.FindInventory('DTMPlayerProgress'));
        int healthMaximum = max(1, CPlayer.mo.GetMaxHealth(true));
        int armorMaximum = playerProgress
            ? playerProgress.MaxArmorForLevel() : 200;
        double healthRatio = clamp(health / double(healthMaximum), 0.0, 1.0);
        double armorRatio = clamp(armor / double(armorMaximum), 0.0, 1.0);

        DrawString(LabelFont, "VITALS", (-403, -143),
            DI_SCREEN_CENTER_BOTTOM | DI_TEXT_ALIGN_CENTER,
            Font.CR_CYAN, 0.9, scale: (1.3, 1.3));
        DrawString(NumberFont, FormatNumber(health, 3), (-403, -108),
            DI_SCREEN_CENTER_BOTTOM | DI_TEXT_ALIGN_CENTER,
            health < 30 ? Font.CR_RED : Font.CR_GREEN, 1.0,
            scale: (2.2, 2.2));

        // Upper auxiliary screen: keep the label and value as one readout so
        // short values do not float away from their label.
        DrawString(LabelFont, String.Format("ARMOR  %d", armor), (-270, -157),
            DI_SCREEN_CENTER_BOTTOM,
            armor > 0 ? Font.CR_LIGHTBLUE : Font.CR_CYAN,
            0.95, scale: (1.15, 1.15));

        CVar aimSetting = CVar.GetCVar("DTM_AimAssist", CPlayer);
        CVar lightSetting = CVar.GetCVar("DTM_Flashlight", CPlayer);
        bool aimOn = aimSetting && aimSetting.GetBool();
        bool lightOn = lightSetting && lightSetting.GetBool();

        // Lower auxiliary screen: two compact status rows.
        DrawString(LabelFont, aimOn ? "AIM  TRACK" : "AIM  FREE", (-270, -114),
            DI_SCREEN_CENTER_BOTTOM, aimOn ? Font.CR_CYAN : Font.CR_GRAY, 0.95,
            scale: (1.15, 1.15));
        DrawString(LabelFont, lightOn ? "LIGHT  ON" : "LIGHT  OFF", (-270, -96),
            DI_SCREEN_CENTER_BOTTOM, lightOn ? Font.CR_GOLD : Font.CR_GRAY, 0.95,
            scale: (1.15, 1.15));

        Fill(Color(20, 205, 90), -294, -66, 180 * healthRatio, 10,
            DI_SCREEN_CENTER_BOTTOM);
        Fill(Color(30, 175, 255), -294, -32, 180 * armorRatio, 8,
            DI_SCREEN_CENTER_BOTTOM);

        Ammo ammo1, ammo2;
        [ammo1, ammo2] = GetCurrentAmmo();
        int ammoAmount = ammo1 ? ammo1.Amount : 0;
        String weaponName = CPlayer.ReadyWeapon ? CPlayer.ReadyWeapon.GetTag() : "UNARMED";

        DrawString(LabelFont, weaponName, (387, -143),
            DI_SCREEN_CENTER_BOTTOM | DI_TEXT_ALIGN_CENTER,
            Font.CR_CYAN, 0.9, scale: (1.1, 1.1));
        DrawString(NumberFont, ammo1 ? FormatNumber(ammoAmount, 3) : "--",
            (387, -111), DI_SCREEN_CENTER_BOTTOM | DI_TEXT_ALIGN_CENTER,
            ammo1 && ammoAmount <= max(1, ammo1.MaxAmount / 10)
                ? Font.CR_ORANGE : Font.CR_GOLD,
            1.0, scale: (1.85, 1.85));

        DTMUzi readyUzi = DTMUzi(CPlayer.ReadyWeapon);
        if (readyUzi)
        {
            DrawString(LabelFont,
                String.Format("MAG  %02d / 30", readyUzi.MagazineAmmo),
                (387, -166), DI_SCREEN_CENTER_BOTTOM | DI_TEXT_ALIGN_CENTER,
                readyUzi.Reloading ? Font.CR_ORANGE : Font.CR_CYAN,
                0.95, scale: (0.92, 0.92));
            if (readyUzi.Reloading)
            {
                double reloadRatio = clamp(
                    (30 - readyUzi.ReloadTicks) / 30.0, 0.0, 1.0);
                Fill(Color(245, 0, 0, 0), 334, -188, 106, 12,
                    DI_SCREEN_CENTER_BOTTOM);
                Fill(Color(255, 26, 36, 40), 337, -185, 100, 6,
                    DI_SCREEN_CENTER_BOTTOM);
                Fill(Color(255, 255, 155, 25), 337, -185,
                    100 * reloadRatio, 6, DI_SCREEN_CENTER_BOTTOM);
                DrawString(LabelFont, "RELOADING", (387, -207),
                    DI_SCREEN_CENTER_BOTTOM | DI_TEXT_ALIGN_CENTER,
                    Font.CR_ORANGE, 0.9, scale: (0.86, 0.86));
            }
        }

        DTMWeaponStats weaponStats = DTMWeaponStats(
            CPlayer.mo.FindInventory('DTMWeaponStats'));
        Class<Weapon> readyWeaponType = CPlayer.ReadyWeapon
            ? CPlayer.ReadyWeapon.GetClass() : null;
        if (weaponStats && CPlayer.ReadyWeapon &&
            weaponStats.HasStatsFor(readyWeaponType))
        {
            int readyRarity = weaponStats.RarityFor(readyWeaponType);
            int readyDamage = weaponStats.DamageFor(readyWeaponType);
            int readyCritical = weaponStats.CriticalFor(readyWeaponType);
            int qualityColor = readyRarity == 1 ? Font.CR_LIGHTBLUE
                : readyRarity == 2 ? Font.CR_PURPLE
                : readyRarity == 3 ? Font.CR_ORANGE
                : readyRarity >= 4 ? Font.CR_CYAN : Font.CR_GRAY;
            String weaponQuality = String.Format("%s  LVL %d",
                weaponStats.RarityNameFor(readyWeaponType),
                weaponStats.LevelFor(readyWeaponType));
            // Keep quality and rolled stats on separate rows.  The old single
            // tiny line was difficult to read and crowded the panel edge.
            Fill(readyRarity == 1 ? Color(255, 75, 165, 255)
                : readyRarity == 2 ? Color(255, 185, 65, 255)
                : readyRarity == 3 ? Color(255, 255, 150, 20)
                : readyRarity >= 4 ? Color(255, 40, 225, 255)
                : Color(255, 105, 115, 125),
                348, -84, 78, 2, DI_SCREEN_CENTER_BOTTOM);
            DrawString(LabelFont, weaponQuality,
                (387, -76), DI_SCREEN_CENTER_BOTTOM | DI_TEXT_ALIGN_CENTER,
                qualityColor, 1.0, scale: (0.95, 0.95));
            DrawString(LabelFont,
                String.Format("DMG +%d%%     CRIT %d%%",
                    readyDamage, readyCritical),
                (387, -58), DI_SCREEN_CENTER_BOTTOM | DI_TEXT_ALIGN_CENTER,
                Font.CR_GRAY, 0.95, scale: (0.78, 0.78));
        }

        if (ammo1 && ammo1.Icon.IsValid())
            DrawTexture(ammo1.Icon, (128, -164),
                DI_SCREEN_CENTER_BOTTOM | DI_ITEM_CENTER, 0.95,
                (68, 68));

        if (ammo2 && ammo2 != ammo1)
        {
            DrawString(LabelFont, ammo2.GetTag(), (110, -70),
                DI_SCREEN_CENTER_BOTTOM,
                Font.CR_CYAN, 0.8, scale: (1.25, 1.25));
            DrawString(NumberFont, FormatNumber(ammo2.Amount, 3), (235, -73),
                DI_SCREEN_CENTER_BOTTOM | DI_TEXT_ALIGN_RIGHT,
                Font.CR_GOLD, 1.0,
                scale: (1.4, 1.4));
        }

        DTMPlayer tacticalPawn = DTMPlayer(CPlayer.mo);
        Actor target = tacticalPawn ? tacticalPawn.AimTarget : null;

        DTMWeaponDrop nearbyDrop = tacticalPawn
            ? DTMWeaponDrop(tacticalPawn.NearbyWeaponDrop) : null;
        if (nearbyDrop)
        {
            int dropColor = nearbyDrop.Rarity == 1 ? Font.CR_LIGHTBLUE
                : nearbyDrop.Rarity == 2 ? Font.CR_PURPLE
                : nearbyDrop.Rarity == 3 ? Font.CR_ORANGE
                : nearbyDrop.Rarity >= 4 ? Font.CR_CYAN : Font.CR_GRAY;
            Fill(Color(225, 4, 11, 15), -270, -390, 540, 122,
                DI_SCREEN_CENTER_BOTTOM);
            Fill(Color(255, 0, 205, 245), -270, -390, 540, 4,
                DI_SCREEN_CENTER_BOTTOM);
            DrawString(LabelFont, "WEAPON DROP  //  PRESS E OR USE TO EQUIP",
                (-248, -376), DI_SCREEN_CENTER_BOTTOM,
                Font.CR_CYAN, 1.0, scale: (1.25, 1.25));
            DrawString(LabelFont,
                String.Format("LVL %d  %s  %s", nearbyDrop.ItemLevel,
                    nearbyDrop.RarityName(), nearbyDrop.WeaponLabel),
                (-248, -348), DI_SCREEN_CENTER_BOTTOM,
                dropColor, 1.0, scale: (1.35, 1.35));
            DrawString(LabelFont,
                String.Format("DROP     DMG +%d%%     CRIT %d%%",
                    nearbyDrop.DamageBonus, nearbyDrop.CritChance),
                (-248, -320), DI_SCREEN_CENTER_BOTTOM,
                Font.CR_UNTRANSLATED, 0.95, scale: (1.12, 1.12));

            DTMWeaponStats ownedStats = DTMWeaponStats(
                CPlayer.mo.FindInventory('DTMWeaponStats'));
            bool ownsType = CPlayer.mo.FindInventory(nearbyDrop.WeaponType) != null;
            String ownedLine;
            int ownedColor = Font.CR_GRAY;
            if (ownedStats && ownedStats.HasStatsFor(nearbyDrop.WeaponType))
            {
                int ownedDamage = ownedStats.DamageFor(nearbyDrop.WeaponType);
                int ownedCritical = ownedStats.CriticalFor(nearbyDrop.WeaponType);
                int ownedLevel = ownedStats.LevelFor(nearbyDrop.WeaponType);
                int damageDelta = nearbyDrop.DamageBonus - ownedDamage;
                int critDelta = nearbyDrop.CritChance - ownedCritical;
                String verdict = damageDelta >= 0 && critDelta >= 0
                    ? "UPGRADE" : damageDelta <= 0 && critDelta <= 0
                    ? "DOWNGRADE" : "SIDEGRADE";
                ownedLine = String.Format(
                    "%s  //  OWNED LVL %d  DMG +%d%% (DELTA %d)  CRIT %d%% (DELTA %d)",
                    verdict, ownedLevel,
                    ownedDamage, damageDelta,
                    ownedCritical, critDelta);
                ownedColor = damageDelta >= 0 && critDelta >= 0
                    ? Font.CR_GREEN : Font.CR_ORANGE;
            }
            else if (ownsType)
            {
                ownedLine = "OWNED    STANDARD VERSION  //  DROP IS AN UPGRADE";
                ownedColor = Font.CR_GREEN;
            }
            else
            {
                ownedLine = "NOT OWNED  //  NEW WEAPON TYPE";
                ownedColor = Font.CR_LIGHTBLUE;
            }
            DrawString(LabelFont, ownedLine, (-248, -294),
                DI_SCREEN_CENTER_BOTTOM, ownedColor, 0.95,
                scale: (1.04, 1.04));
        }

        // Captured-mouse direction line. Slight extrapolation between 35 Hz
        // player tics makes the visual respond more like a frame-rate cursor.
        if (tacticalPawn)
        {
            double cursorX = clamp(tacticalPawn.AimCursorX +
                (tacticalPawn.AimCursorX - tacticalPawn.PreviousAimCursorX) *
                    ticFrac * 0.7, -850.0, 850.0);
            double cursorY = clamp(tacticalPawn.AimCursorY +
                (tacticalPawn.AimCursorY - tacticalPawn.PreviousAimCursorY) *
                    ticFrac * 0.7, -450.0, 300.0);
            int cursorColor = target && target.health > 0
                ? Color(225, 55, 255, 105) : Color(205, 0, 220, 255);
            double cursorLength = max(1.0, sqrt(cursorX * cursorX + cursorY * cursorY));
            int lineSteps = clamp(int(cursorLength / 13.0), 6, 64);
            double lineStart = min(0.72, 58.0 / cursorLength);
            for (int lineStep = 0; lineStep <= lineSteps; lineStep++)
            {
                // Small gaps produce a clean tactical guide without reading as
                // another crosshair or obscuring monsters beneath it.
                if ((lineStep % 3) == 2) continue;
                double fraction = lineStart +
                    (1.0 - lineStart) * lineStep / double(lineSteps);
                Fill(cursorColor, cursorX * fraction - 2,
                    cursorY * fraction - 2, 4, 4, DI_SCREEN_CENTER);
            }
            // Compact endpoint diamond.
            Fill(cursorColor, cursorX - 3, cursorY - 5, 6, 10,
                DI_SCREEN_CENTER);
            Fill(cursorColor, cursorX - 5, cursorY - 3, 10, 6,
                DI_SCREEN_CENTER);
        }

        if (target && target.health > 0)
        {
            DTMMonsterVariant targetVariant = DTMMonsterVariant(
                target.FindInventory('DTMMonsterVariant'));
            int targetMaximum = targetVariant
                ? max(1, targetVariant.MaximumHealth)
                : max(1, target.SpawnHealth());
            double targetRatio = clamp(target.health / double(targetMaximum), 0.0, 1.0);
            bool isBoss = targetVariant && targetVariant.IsPromotedBoss;
            int targetColor = isBoss ? Font.CR_RED
                : targetRatio > 0.6 ? Font.CR_GREEN
                : targetRatio > 0.25 ? Font.CR_ORANGE : Font.CR_RED;
            int rarityColor = !targetVariant ? Font.CR_GRAY
                : targetVariant.Rarity == 1 ? Font.CR_LIGHTBLUE
                : targetVariant.Rarity == 2 ? Font.CR_PURPLE
                : targetVariant.Rarity == 3 ? Font.CR_ORANGE
                : targetVariant.Rarity >= 4 ? Font.CR_CYAN : Font.CR_GRAY;
            String targetQuality = !targetVariant ? "COMMON"
                : targetVariant.Rarity == 1 ? "RARE"
                : targetVariant.Rarity == 2 ? "EPIC"
                : targetVariant.Rarity == 3 ? "MYTHIC"
                : targetVariant.Rarity >= 4 ? "GODLY" : "COMMON";

            // Bosses receive a taller, red-framed panel; ordinary variants
            // retain the cyan tactical treatment.  Extra vertical room keeps
            // the name, quality, affixes and HP from colliding.
            Fill(isBoss ? Color(225, 24, 3, 3) : Color(205, 4, 11, 15),
                -270, 24, 540, 138,
                DI_SCREEN_CENTER_TOP);
            Fill(isBoss ? Color(255, 255, 35, 20) : Color(255, 0, 205, 245),
                -270, 24, 540, isBoss ? 5 : 3,
                DI_SCREEN_CENTER_TOP);
            Fill(isBoss ? Color(210, 145, 10, 5) : Color(150, 0, 110, 135),
                -270, 157, 540, 4,
                DI_SCREEN_CENTER_TOP);
            DrawString(LabelFont, isBoss ? "BOSS TARGET" : "LOCKED TARGET",
                (-248, 39),
                DI_SCREEN_CENTER_TOP,
                isBoss ? Font.CR_RED : Font.CR_CYAN, 1.0,
                scale: (1.45, 1.45));
            String displayedTargetName = targetVariant && targetVariant.DisplayName != ""
                ? targetVariant.DisplayName : target.GetTag().MakeUpper();
            DrawString(LabelFont, displayedTargetName,
                (-248, 65), DI_SCREEN_CENTER_TOP,
                isBoss ? Font.CR_ORANGE : Font.CR_UNTRANSLATED, 1.0,
                scale: (1.3, 1.3));
            if (targetVariant)
            {
                String qualityLine = isBoss
                    ? String.Format("LVL %d  //  BOSS  //  %s",
                        targetVariant.MonsterLevel, targetQuality)
                    : String.Format("LVL %d  //  %s",
                        targetVariant.MonsterLevel, targetQuality);
                DrawString(LabelFont, qualityLine,
                    (-248, 88), DI_SCREEN_CENTER_TOP,
                    rarityColor, 1.0, scale: (1.2, 1.2));
                String affixes = "";
                if (targetVariant.AffixFast) affixes = "SWIFT";
                if (targetVariant.AffixTough)
                    affixes = affixes == "" ? "TITANIC" : affixes .. "  TITANIC";
                if (targetVariant.AffixBrutal)
                    affixes = affixes == "" ? "BRUTAL" : affixes .. "  BRUTAL";
                if (targetVariant.AffixVampiric)
                    affixes = affixes == "" ? "VAMPIRIC" : affixes .. "  VAMPIRIC";
                if (targetVariant.AffixExplosive)
                    affixes = affixes == "" ? "VOLATILE" : affixes .. "  VOLATILE";
                if (targetVariant.UsesFastChase)
                    affixes = affixes == "" ? "RELENTLESS" : affixes .. "  RELENTLESS";
                if (affixes != "")
                    DrawString(LabelFont, affixes, (-248, 109),
                        DI_SCREEN_CENTER_TOP, rarityColor, 0.88,
                        scale: (1.05, 1.05));
            }
            DrawString(NumberFont,
                String.Format("%d / %d HP", target.health, targetMaximum),
                (248, 38), DI_SCREEN_CENTER_TOP | DI_TEXT_ALIGN_RIGHT,
                targetColor, 1.0,
                scale: (1.15, 1.15));
            Fill(Color(255, 22, 30, 34), -248, 135, 496, 13,
                DI_SCREEN_CENTER_TOP);
            Fill(isBoss ? Color(255, 245, 30, 15)
                : targetRatio > 0.6 ? Color(255, 30, 220, 105)
                : targetRatio > 0.25 ? Color(255, 255, 145, 25)
                : Color(255, 245, 35, 35),
                -248, 135, 496 * targetRatio, 13, DI_SCREEN_CENTER_TOP);
        }

        // Small always-visible, black-edged tab plus a full character sheet.
        Fill(Color(235, 0, 0, 0), -82, -58, 164, 30,
            DI_SCREEN_CENTER_BOTTOM);
        Fill(Color(235, 8, 25, 31), -78, -55, 156, 23,
            DI_SCREEN_CENTER_BOTTOM);
        DrawString(LabelFont, "L  CHARACTER", (0, -51),
            DI_SCREEN_CENTER_BOTTOM | DI_TEXT_ALIGN_CENTER,
            Font.CR_CYAN, 0.95, scale: (0.95, 0.95));

        if (tacticalPawn && tacticalPawn.ShowCharacterPanel && playerProgress)
        {
            double xpRatio = clamp(playerProgress.Experience /
                double(max(1, playerProgress.ExperienceToNext)), 0.0, 1.0);
            Fill(Color(245, 0, 0, 0), -326, -244, 660, 500,
                DI_SCREEN_CENTER);
            Fill(Color(242, 5, 13, 18), -316, -234, 640, 476,
                DI_SCREEN_CENTER);
            Fill(Color(255, 0, 215, 255), -316, -234, 640, 5,
                DI_SCREEN_CENTER);
            Fill(Color(190, 0, 100, 125), -316, 237, 640, 5,
                DI_SCREEN_CENTER);
            DrawString(LabelFont, "MARINE PROGRESSION", (0, -205),
                DI_SCREEN_CENTER | DI_TEXT_ALIGN_CENTER,
                Font.CR_CYAN, 1.0, scale: (1.65, 1.65));
            DrawString(NumberFont,
                String.Format("LEVEL %d", playerProgress.PlayerLevel),
                (0, -155), DI_SCREEN_CENTER | DI_TEXT_ALIGN_CENTER,
                Font.CR_GOLD, 1.0, scale: (1.65, 1.65));
            DrawString(LabelFont,
                String.Format("XP  %d / %d", playerProgress.Experience,
                    playerProgress.ExperienceToNext),
                (0, -105), DI_SCREEN_CENTER | DI_TEXT_ALIGN_CENTER,
                Font.CR_UNTRANSLATED, 1.0, scale: (1.2, 1.2));
            Fill(Color(255, 18, 28, 32), -250, -75, 500, 18,
                DI_SCREEN_CENTER);
            Fill(Color(255, 30, 215, 115), -250, -75,
                500 * xpRatio, 18, DI_SCREEN_CENTER);
            DrawString(LabelFont,
                String.Format("MAX HEALTH                 %d",
                    playerProgress.MaxHealthForLevel()),
                (-225, -25), DI_SCREEN_CENTER, Font.CR_GREEN, 1.0,
                scale: (1.25, 1.25));
            DrawString(LabelFont,
                String.Format("DAMAGE BONUS              +%d%%",
                    playerProgress.DamagePercent()),
                (-225, 20), DI_SCREEN_CENTER, Font.CR_ORANGE, 1.0,
                scale: (1.25, 1.25));
            DrawString(LabelFont,
                String.Format("MAX ARMOR                  %d",
                    playerProgress.MaxArmorForLevel()),
                (-225, 65), DI_SCREEN_CENTER, Font.CR_LIGHTBLUE, 1.0,
                scale: (1.25, 1.25));
            DrawString(LabelFont,
                String.Format("AMMO CAPACITY             +%d%%",
                    playerProgress.AmmoPercent()),
                (-225, 110), DI_SCREEN_CENTER, Font.CR_GOLD, 1.0,
                scale: (1.25, 1.25));
            DrawString(LabelFont,
                String.Format("MONSTERS DEFEATED           %d",
                    playerProgress.LifetimeKills),
                (-225, 155), DI_SCREEN_CENTER, Font.CR_GRAY, 1.0,
                scale: (1.25, 1.25));
            DrawString(LabelFont, "PRESS L TO CLOSE", (0, 207),
                DI_SCREEN_CENTER | DI_TEXT_ALIGN_CENTER,
                Font.CR_CYAN, 0.9, scale: (1.0, 1.0));
        }

        PowerDTMBaronForm baronPower = PowerDTMBaronForm(
            CPlayer.mo.FindInventory('PowerDTMBaronForm'));
        if (baronPower)
        {
            double formRatio = clamp(baronPower.EffectTics /
                double(max(1, baronPower.MaxEffectTics)), 0.0, 1.0);
            int formSeconds = max(0, (baronPower.EffectTics + 34) / 35);
            Fill(Color(235, 0, 0, 0), -132, -104, 264, 38,
                DI_SCREEN_CENTER_BOTTOM);
            Fill(Color(230, 32, 8, 4), -128, -100, 256, 30,
                DI_SCREEN_CENTER_BOTTOM);
            DrawString(LabelFont,
                String.Format("BARON FORM  //  %d SEC", formSeconds),
                (0, -95), DI_SCREEN_CENTER_BOTTOM | DI_TEXT_ALIGN_CENTER,
                Font.CR_GREEN, 1.0, scale: (1.02, 1.02));
            Fill(Color(255, 18, 28, 25), -116, -75, 232, 6,
                DI_SCREEN_CENTER_BOTTOM);
            Fill(Color(255, 65, 245, 90), -116, -75,
                232 * formRatio, 6, DI_SCREEN_CENTER_BOTTOM);
        }

        PowerDTMCyberForm cyberPower = PowerDTMCyberForm(
            CPlayer.mo.FindInventory('PowerDTMCyberForm'));
        if (cyberPower)
        {
            double formRatio = clamp(cyberPower.EffectTics /
                double(max(1, cyberPower.MaxEffectTics)), 0.0, 1.0);
            int formSeconds = max(0, (cyberPower.EffectTics + 34) / 35);
            Fill(Color(235, 0, 0, 0), -132, -104, 264, 38,
                DI_SCREEN_CENTER_BOTTOM);
            Fill(Color(230, 16, 10, 6), -128, -100, 256, 30,
                DI_SCREEN_CENTER_BOTTOM);
            DrawString(LabelFont,
                String.Format("CYBERDEMON FORM  //  %d SEC", formSeconds),
                (0, -95), DI_SCREEN_CENTER_BOTTOM | DI_TEXT_ALIGN_CENTER,
                Font.CR_ORANGE, 1.0, scale: (1.02, 1.02));
            Fill(Color(255, 18, 28, 25), -116, -75, 232, 6,
                DI_SCREEN_CENTER_BOTTOM);
            Fill(Color(255, 255, 120, 35), -116, -75,
                232 * formRatio, 6, DI_SCREEN_CENTER_BOTTOM);
        }
    }
}
