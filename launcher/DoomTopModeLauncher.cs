using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.RegularExpressions;
using System.Windows.Forms;

internal static class DoomTopModeLauncher
{
    private const string Title = "Tuin's Top Doom";

    [DllImport("user32.dll")]
    private static extern bool ShowWindow(IntPtr window, int command);
    [DllImport("user32.dll")]
    private static extern bool SetForegroundWindow(IntPtr window);

    [STAThread]
    private static int Main(string[] args)
    {
        Application.EnableVisualStyles();
        try
        {
            string root = AppDomain.CurrentDomain.BaseDirectory;
            string engine = FirstExisting(
                Path.Combine(root, "engine", "uzdoom.exe"),
                Path.Combine(root, "uzdoom.exe"),
                Path.Combine(root, "runtime", "uzdoom-experimental", "uzdoom.exe"));
            string mod = FirstExisting(
                Path.Combine(root, "DoomTopMode.pk3"),
                Path.Combine(root, "build", "DoomTopMode.pk3"));

            if (engine == null)
                return Fail("The customized UZDoom runtime is missing. Re-extract the complete release ZIP.");
            if (mod == null)
                return Fail("DoomTopMode.pk3 is missing. Re-extract the complete release ZIP.");

            bool quick = HasArgument(args, "--quick");
            bool chooseIwad = HasArgument(args, "--choose-iwad");
            string iwad = chooseIwad ? null : FindIwad(root);
            string voxels = FindVoxelPack(root);
            bool useVoxels = voxels != null && !HasArgument(args, "--no-voxels") &&
                ReadVoxelPreference(root);

            if (!quick)
            {
                using (LauncherForm launcher = new LauncherForm(iwad, voxels, useVoxels))
                {
                    if (launcher.ShowDialog() != DialogResult.OK) return 0;
                    iwad = launcher.SelectedIwad;
                    useVoxels = launcher.UseVoxels;
                }
            }
            else if (iwad == null)
            {
                iwad = AskForIwad();
            }
            if (iwad == null) return 1;
            SaveSettings(root, iwad, useVoxels);

            List<string> launch = new List<string>();
            string config = Path.Combine(root, "DoomTopMode.ini");
            launch.Add("-config"); launch.Add(config);
            launch.Add("-iwad"); launch.Add(iwad);
            launch.Add("-file");

            if (useVoxels && voxels != null) launch.Add(voxels);
            launch.Add(mod);
            launch.Add("+r_ortho_cutaway"); launch.Add("0");
            launch.Add("+r_ortho_wallcutout"); launch.Add("104");
            launch.Add("+r_ortho_hidesky"); launch.Add("1");
            launch.Add("+gl_no_skyclear"); launch.Add("1");
            launch.Add("+crosshair"); launch.Add("0");
            launch.Add("+map");
            launch.Add(Path.GetFileName(iwad).Equals("DOOM.WAD", StringComparison.OrdinalIgnoreCase)
                ? "E1M1" : "MAP01");

            ProcessStartInfo start = new ProcessStartInfo();
            start.FileName = engine;
            start.Arguments = JoinArguments(launch);
            start.WorkingDirectory = Path.GetDirectoryName(engine);
            start.UseShellExecute = false;
            Process game = Process.Start(start);
            if (!quick)
            {
                using (LoadingForm loading = new LoadingForm(game, useVoxels))
                    loading.ShowDialog();
            }
            return 0;
        }
        catch (Exception ex)
        {
            return Fail(ex.Message);
        }
    }

    private static string FindIwad(string root)
    {
        string remembered = ReadRememberedIwad(root);
        if (File.Exists(remembered)) return remembered;

        List<string> folders = new List<string>();
        AddFolder(folders, root);
        AddFolder(folders, Path.Combine(root, "iwads"));
        AddFolder(folders, Path.Combine(root, "runtime"));
        AddFolder(folders, Environment.GetEnvironmentVariable("DOOMWADDIR"));

        string wadPath = Environment.GetEnvironmentVariable("DOOMWADPATH");
        if (!String.IsNullOrEmpty(wadPath))
            foreach (string folder in wadPath.Split(Path.PathSeparator)) AddFolder(folders, folder);

        string programFiles = Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles);
        string programFilesX86 = Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86);
        AddSteamFolders(folders, Path.Combine(programFilesX86, "Steam"));
        AddSteamFolders(folders, Path.Combine(programFiles, "Steam"));
        AddFolder(folders, Path.Combine(programFilesX86, "GOG Galaxy", "Games", "DOOM 2"));
        AddFolder(folders, Path.Combine(programFiles, "GOG Galaxy", "Games", "DOOM 2"));

        foreach (string folder in folders)
        {
            string found = FindWadInFolder(folder);
            if (found != null) return found;
        }
        return null;
    }

    private static void AddSteamFolders(List<string> folders, string steamRoot)
    {
        if (!Directory.Exists(steamRoot)) return;
        List<string> libraries = new List<string>();
        libraries.Add(steamRoot);
        string vdf = Path.Combine(steamRoot, "steamapps", "libraryfolders.vdf");
        if (File.Exists(vdf))
        {
            foreach (Match match in Regex.Matches(File.ReadAllText(vdf),
                "\\\"path\\\"\\s+\\\"([^\\\"]+)\\\"", RegexOptions.IgnoreCase))
                libraries.Add(match.Groups[1].Value.Replace("\\\\", "\\"));
        }

        foreach (string library in libraries)
        {
            string common = Path.Combine(library, "steamapps", "common");
            AddFolder(folders, Path.Combine(common, "Ultimate Doom", "rerelease"));
            AddFolder(folders, Path.Combine(common, "Ultimate Doom", "base", "doom2"));
            AddFolder(folders, Path.Combine(common, "DOOM 2", "base"));
            AddFolder(folders, Path.Combine(common, "DOOM 2", "rerelease"));
        }
    }

    private static string FindWadInFolder(string folder)
    {
        if (String.IsNullOrEmpty(folder) || !Directory.Exists(folder)) return null;
        string[] preferred = { "DOOM2.WAD", "doom2.wad", "DOOM.WAD", "doom.wad" };
        foreach (string name in preferred)
        {
            string candidate = Path.Combine(folder, name);
            if (File.Exists(candidate)) return Path.GetFullPath(candidate);
        }
        return null;
    }

    private static string AskForIwad()
    {
        MessageBox.Show(
            "DoomTopMode needs a legally owned DOOM2.WAD or DOOM.WAD. " +
            "It was not found automatically, so please select it now.",
            Title, MessageBoxButtons.OK, MessageBoxIcon.Information);
        using (OpenFileDialog picker = new OpenFileDialog())
        {
            picker.Title = "Locate your Doom IWAD";
            picker.Filter = "Doom IWAD (DOOM2.WAD;DOOM.WAD)|DOOM2.WAD;DOOM.WAD|WAD files (*.wad)|*.wad";
            picker.CheckFileExists = true;
            return picker.ShowDialog() == DialogResult.OK ? picker.FileName : null;
        }
    }

    private static string FindVoxelPack(string root)
    {
        List<string> folders = new List<string>();
        AddFolder(folders, root);
        AddFolder(folders, Path.Combine(root, "addons"));
        AddFolder(folders, Path.Combine(root, "runtime"));
        AddFolder(folders, Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), "Downloads"));
        foreach (string folder in folders)
        {
            if (!Directory.Exists(folder)) continue;
            string[] matches = Directory.GetFiles(folder, "VoxelDoom*.pk3", SearchOption.TopDirectoryOnly);
            if (matches.Length > 0) return matches[0];
        }
        return null;
    }

    private static string ReadRememberedIwad(string root)
    {
        try
        {
            string path = Path.Combine(root, "DoomTopModeLauncher.ini");
            if (!File.Exists(path)) return null;
            foreach (string line in File.ReadAllLines(path))
                if (line.StartsWith("iwad=", StringComparison.OrdinalIgnoreCase))
                    return line.Substring(5).Trim();
        }
        catch { }
        return null;
    }

    private static bool ReadVoxelPreference(string root)
    {
        try
        {
            string path = Path.Combine(root, "DoomTopModeLauncher.ini");
            if (!File.Exists(path)) return true;
            foreach (string line in File.ReadAllLines(path))
                if (line.StartsWith("voxels=", StringComparison.OrdinalIgnoreCase))
                    return line.Substring(7).Trim() != "0";
        }
        catch { }
        return true;
    }

    private static void SaveSettings(string root, string iwad, bool useVoxels)
    {
        try
        {
            File.WriteAllText(Path.Combine(root, "DoomTopModeLauncher.ini"),
                "iwad=" + iwad + Environment.NewLine +
                "voxels=" + (useVoxels ? "1" : "0") + Environment.NewLine);
        }
        catch { }
    }

    private static void AddFolder(List<string> folders, string folder)
    {
        if (String.IsNullOrWhiteSpace(folder)) return;
        if (!folders.Exists(delegate(string f) { return f.Equals(folder, StringComparison.OrdinalIgnoreCase); }))
            folders.Add(folder);
    }

    private static bool HasArgument(string[] args, string wanted)
    {
        foreach (string arg in args)
            if (arg.Equals(wanted, StringComparison.OrdinalIgnoreCase)) return true;
        return false;
    }

    private static string FirstExisting(params string[] paths)
    {
        foreach (string path in paths) if (File.Exists(path)) return Path.GetFullPath(path);
        return null;
    }

    private static string JoinArguments(List<string> args)
    {
        StringBuilder result = new StringBuilder();
        foreach (string arg in args)
        {
            if (result.Length > 0) result.Append(' ');
            result.Append('"').Append(arg.Replace("\"", "\\\"")).Append('"');
        }
        return result.ToString();
    }

    private static int Fail(string message)
    {
        MessageBox.Show(message, Title, MessageBoxButtons.OK, MessageBoxIcon.Error);
        return 1;
    }

    private sealed class LauncherForm : Form
    {
        private readonly TextBox iwadBox;
        private readonly CheckBox voxelBox;
        private readonly Button launchButton;
        public string SelectedIwad { get; private set; }
        public bool UseVoxels { get; private set; }

        public LauncherForm(string iwad, string voxelPack, bool useVoxels)
        {
            Text = Title;
            ClientSize = new Size(620, 280);
            FormBorderStyle = FormBorderStyle.FixedDialog;
            MaximizeBox = false;
            MinimizeBox = true;
            StartPosition = FormStartPosition.CenterScreen;
            BackColor = Color.FromArgb(14, 18, 22);
            ForeColor = Color.WhiteSmoke;
            try { Icon = Icon.ExtractAssociatedIcon(Application.ExecutablePath); } catch { }

            Label title = NewLabel("TUIN'S TOP DOOM", 22, 18, 570, 34, 18, Color.FromArgb(255, 92, 32));
            Label subtitle = NewLabel("Experimental isometric Doom", 24, 52, 570, 24, 10, Color.FromArgb(70, 220, 255));
            Label iwadLabel = NewLabel("DOOM IWAD", 24, 92, 130, 22, 9, Color.FromArgb(70, 220, 255));
            iwadBox = new TextBox();
            iwadBox.SetBounds(24, 116, 470, 25);
            iwadBox.ReadOnly = true;
            iwadBox.Text = iwad ?? "Not found — click Browse";
            iwadBox.BackColor = Color.FromArgb(28, 35, 42);
            iwadBox.ForeColor = iwad == null ? Color.Orange : Color.White;
            Button browse = new Button();
            browse.Text = "Browse...";
            browse.SetBounds(504, 114, 92, 29);
            browse.Click += delegate
            {
                string selected = AskForIwad();
                if (selected == null) return;
                iwadBox.Text = selected;
                iwadBox.ForeColor = Color.White;
                launchButton.Enabled = true;
            };

            voxelBox = new CheckBox();
            voxelBox.SetBounds(24, 166, 570, 25);
            voxelBox.ForeColor = Color.WhiteSmoke;
            voxelBox.BackColor = BackColor;
            voxelBox.Checked = voxelPack != null && useVoxels;
            voxelBox.Enabled = voxelPack != null;
            voxelBox.Text = voxelPack == null
                ? "Voxel Doom not detected (optional)"
                : "Load Voxel Doom models — adds roughly 30–60 seconds to startup";

            Label voxelPath = NewLabel(voxelPack == null ?
                "Place VoxelDoom_v2.4.pk3 beside the launcher or in an addons folder."
                : voxelPack, 44, 193, 550, 35, 8, Color.Gray);

            launchButton = new Button();
            launchButton.Text = "LAUNCH";
            launchButton.SetBounds(438, 232, 158, 36);
            launchButton.BackColor = Color.FromArgb(166, 42, 20);
            launchButton.ForeColor = Color.White;
            launchButton.FlatStyle = FlatStyle.Flat;
            launchButton.Enabled = iwad != null && File.Exists(iwad);
            launchButton.Click += delegate
            {
                if (!File.Exists(iwadBox.Text)) return;
                SelectedIwad = iwadBox.Text;
                UseVoxels = voxelBox.Enabled && voxelBox.Checked;
                DialogResult = DialogResult.OK;
                Close();
            };

            Button cancel = new Button();
            cancel.Text = "Cancel";
            cancel.SetBounds(340, 232, 88, 36);
            cancel.Click += delegate { DialogResult = DialogResult.Cancel; Close(); };

            Controls.AddRange(new Control[] { title, subtitle, iwadLabel, iwadBox,
                browse, voxelBox, voxelPath, cancel, launchButton });
            AcceptButton = launchButton;
            CancelButton = cancel;
        }

        private Label NewLabel(string text, int x, int y, int width, int height,
            float size, Color color)
        {
            Label label = new Label();
            label.Text = text;
            label.SetBounds(x, y, width, height);
            label.ForeColor = color;
            label.BackColor = BackColor;
            label.Font = new Font("Segoe UI", size, FontStyle.Bold);
            return label;
        }
    }

    private sealed class LoadingForm : Form
    {
        private readonly Process game;
        private readonly Timer timer;
        private readonly Label status;
        private int ticks;

        public LoadingForm(Process process, bool voxels)
        {
            game = process;
            Text = Title + " — Loading";
            ClientSize = new Size(480, 142);
            FormBorderStyle = FormBorderStyle.FixedDialog;
            ControlBox = false;
            StartPosition = FormStartPosition.CenterScreen;
            BackColor = Color.FromArgb(14, 18, 22);
            try { Icon = Icon.ExtractAssociatedIcon(Application.ExecutablePath); } catch { }

            status = new Label();
            status.Text = voxels
                ? "Loading UZDoom and Voxel Doom… this can take 30–60 seconds."
                : "Loading UZDoom…";
            status.SetBounds(24, 22, 430, 42);
            status.ForeColor = Color.WhiteSmoke;
            status.Font = new Font("Segoe UI", 10, FontStyle.Bold);

            ProgressBar progress = new ProgressBar();
            progress.SetBounds(24, 78, 432, 24);
            progress.Style = ProgressBarStyle.Marquee;
            progress.MarqueeAnimationSpeed = 24;
            Controls.Add(status);
            Controls.Add(progress);

            timer = new Timer();
            timer.Interval = 250;
            timer.Tick += CheckGame;
            timer.Start();
        }

        private void CheckGame(object sender, EventArgs e)
        {
            ticks++;
            game.Refresh();
            if (game.HasExited)
            {
                timer.Stop();
                MessageBox.Show("UZDoom exited during startup. Error code: " + game.ExitCode,
                    Title, MessageBoxButtons.OK, MessageBoxIcon.Error);
                Close();
                return;
            }
            if (game.MainWindowHandle != IntPtr.Zero)
            {
                timer.Stop();
                ShowWindow(game.MainWindowHandle, 9);
                SetForegroundWindow(game.MainWindowHandle);
                Close();
                return;
            }
            if (ticks == 240)
                status.Text = "Still loading the voxel pack… almost there.";
        }
    }
}
