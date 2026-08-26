using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Text;
using System.Text.RegularExpressions;
using System.Windows.Forms;

internal static class DoomTopModeLauncher
{
    private const string Title = "Tuin's Top Doom";

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

            bool chooseIwad = HasArgument(args, "--choose-iwad");
            string iwad = chooseIwad ? null : FindIwad(root);
            if (iwad == null) iwad = AskForIwad();
            if (iwad == null) return 1;
            SaveIwad(root, iwad);

            List<string> launch = new List<string>();
            string config = Path.Combine(root, "DoomTopMode.ini");
            launch.Add("-config"); launch.Add(config);
            launch.Add("-iwad"); launch.Add(iwad);
            launch.Add("-file");

            if (!HasArgument(args, "--no-voxels"))
            {
                string voxels = FindVoxelPack(root);
                if (voxels != null) launch.Add(voxels);
            }
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
            Process.Start(start);
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

    private static void SaveIwad(string root, string iwad)
    {
        try { File.WriteAllText(Path.Combine(root, "DoomTopModeLauncher.ini"), "iwad=" + iwad); }
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
}
