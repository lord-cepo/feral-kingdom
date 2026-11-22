using System;
using System.ComponentModel;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Net;
using System.Security.Cryptography;
using System.Threading;
using System.Web.Script.Serialization;
using System.Windows.Forms;

internal static class Launcher
{
    private const string ReleasesApi = "https://api.github.com/repos/lord-cepo/feral-kingdom/releases?per_page=30";
    private const string DownloadRoot = "https://github.com/lord-cepo/feral-kingdom/releases/download/";
    private const string GameExe = "FeralKingdom.exe";
    private const string Platform = "windows-x86_64";
    private const string Title = "Feral Kingdom Launcher";

    private static readonly string InstallRoot = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "FeralKingdomLauncher", "versions");
    private static readonly JavaScriptSerializer Json = new JavaScriptSerializer();

    [STAThread]
    private static void Main()
    {
        bool acquired;
        using (var mutex = new Mutex(true, @"Local\FeralKingdomLauncher", out acquired))
        {
            if (!acquired) return;
            ServicePointManager.SecurityProtocol = SecurityProtocolType.Tls12;
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);
            using (var window = new Form())
            using (var worker = new BackgroundWorker())
            {
                window.Text = Title;
                window.ClientSize = new System.Drawing.Size(430, 105);
                window.StartPosition = FormStartPosition.CenterScreen;
                window.FormBorderStyle = FormBorderStyle.FixedDialog;
                window.MaximizeBox = false;

                var status = new Label { Left = 18, Top = 19, Width = 390, Text = "Checking for updates…" };
                var progress = new ProgressBar { Left = 18, Top = 52, Width = 390, Style = ProgressBarStyle.Marquee };
                window.Controls.Add(status);
                window.Controls.Add(progress);

                worker.WorkerReportsProgress = true;
                worker.ProgressChanged += (sender, e) => status.Text = (string)e.UserState;
                worker.DoWork += (sender, e) => e.Result = PrepareGame(worker);
                window.Shown += (sender, e) => worker.RunWorkerAsync();
                window.FormClosing += (sender, e) => e.Cancel = worker.IsBusy;
                worker.RunWorkerCompleted += (sender, e) =>
                {
                    try
                    {
                        if (e.Error != null) throw e.Error;
                        var result = (LaunchResult)e.Result;
                        if (result.UpdateError != null)
                            MessageBox.Show(window, "The update is unavailable. Opening the installed version.\n\n" +
                                result.UpdateError, Title, MessageBoxButtons.OK, MessageBoxIcon.Information);
                        Process.Start(new ProcessStartInfo(Path.Combine(result.Folder, GameExe))
                        {
                            WorkingDirectory = result.Folder,
                            UseShellExecute = false
                        });
                    }
                    catch (Exception error)
                    {
                        MessageBox.Show(window, error.Message, Title, MessageBoxButtons.OK, MessageBoxIcon.Error);
                    }
                    window.Close();
                };
                Application.Run(window);
            }
        }
    }

    private static LaunchResult PrepareGame(BackgroundWorker worker)
    {
        Directory.CreateDirectory(InstallRoot);
        var installed = Directory.EnumerateDirectories(InstallRoot)
            .Select(path => new { Path = path, Version = ParseVersion(Path.GetFileName(path)) })
            .Where(item => item.Version != null && IsComplete(item.Path, item.Version))
            .OrderByDescending(item => item.Version).FirstOrDefault();
        try
        {
            using (var client = new ReleaseClient())
            {
                client.Headers[HttpRequestHeader.UserAgent] = "FeralKingdomLauncher/1";
                var releases = Json.Deserialize<Release[]>(client.DownloadString(ReleasesApi));
                var latest = releases.Where(release => !release.draft)
                    .Select(release => new { Release = release, Version = ParseVersion(release.tag_name) })
                    .Where(item => item.Version != null && FindArchive(item.Release, item.Version) != null)
                    .OrderByDescending(item => item.Version).FirstOrDefault();
                if (latest == null) throw new InvalidDataException("No Windows release was found on GitHub.");
                if (installed != null && installed.Version >= latest.Version)
                    return new LaunchResult { Folder = installed.Path };

                worker.ReportProgress(0, "Downloading Feral Kingdom v" + latest.Version + "…");
                string folder = Install(client, latest.Release, latest.Version, worker);
                return new LaunchResult { Folder = folder };
            }
        }
        catch (Exception error)
        {
            if (installed == null)
                throw new InvalidOperationException("Could not install Feral Kingdom. Connect to the internet and try again.\n\n" + error.Message);
            return new LaunchResult { Folder = installed.Path, UpdateError = error.Message };
        }
    }

    private static string Install(ReleaseClient client, Release release, Version version, BackgroundWorker worker)
    {
        var asset = FindArchive(release, version);
        string assetUrl = DownloadRoot + release.tag_name + "/" + asset.name;
        string destination = Path.Combine(InstallRoot, version.ToString());
        if (IsComplete(destination, version)) return destination;

        string staging = Path.Combine(InstallRoot, ".download-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(staging);
        try
        {
            string archive = Path.Combine(staging, asset.name);
            string expected = asset.digest != null && asset.digest.StartsWith("sha256:", StringComparison.Ordinal)
                ? asset.digest.Substring(7)
                : client.DownloadString(assetUrl + ".sha256").Split((char[])null, StringSplitOptions.RemoveEmptyEntries).FirstOrDefault();
            if (expected == null || expected.Length != 64 || !expected.All(Uri.IsHexDigit))
                throw new InvalidDataException("The release has no valid SHA-256 checksum.");

            client.DownloadFile(assetUrl, archive);
            worker.ReportProgress(0, "Verifying and installing the update…");
            using (var stream = File.OpenRead(archive))
            using (var sha = SHA256.Create())
            {
                string actual = String.Concat(sha.ComputeHash(stream).Select(b => b.ToString("x2", CultureInfo.InvariantCulture)));
                if (!String.Equals(actual, expected, StringComparison.OrdinalIgnoreCase))
                    throw new InvalidDataException("The downloaded archive failed its checksum.");
            }

            string extracted = Path.Combine(staging, "unpacked");
            ZipFile.ExtractToDirectory(archive, extracted);
            string game = Path.Combine(extracted, "FeralKingdom-v" + version);
            if (!IsComplete(game, version))
                throw new InvalidDataException("The verified archive is missing required Windows game files.");
            if (Directory.Exists(destination))
                Directory.Move(destination, Path.Combine(InstallRoot, ".incomplete-" + Guid.NewGuid().ToString("N")));
            Directory.Move(game, destination);
            return destination;
        }
        finally
        {
            try { Directory.Delete(staging, true); }
            catch (IOException) { }
            catch (UnauthorizedAccessException) { }
        }
    }

    private static Asset FindArchive(Release release, Version version)
    {
        string name = "FeralKingdom-v" + version + "-" + Platform + ".zip";
        return (release.assets ?? new Asset[0]).FirstOrDefault(asset => asset.name == name);
    }

    private static Version ParseVersion(string value)
    {
        if (String.IsNullOrEmpty(value)) return null;
        if (value[0] == 'v') value = value.Substring(1);
        Version version;
        return Version.TryParse(value, out version) && version.Build >= 0 && version.Revision < 0 &&
            version.ToString() == value ? version : null;
    }

    private static bool IsComplete(string folder, Version version)
    {
        try
        {
            if (new[] { GameExe, "FeralKingdom.pck", "icudt_godot.dat", "BUILD.json" }
                .Any(file => !File.Exists(Path.Combine(folder, file)))) return false;
            var build = Json.Deserialize<Build>(File.ReadAllText(Path.Combine(folder, "BUILD.json")));
            return build != null && build.version == version.ToString() && build.platform == Platform;
        }
        catch (IOException) { return false; }
        catch (UnauthorizedAccessException) { return false; }
        catch (ArgumentException) { return false; }
        catch (InvalidOperationException) { return false; }
    }

    private sealed class ReleaseClient : WebClient
    {
        protected override WebRequest GetWebRequest(Uri address)
        {
            var request = (HttpWebRequest)base.GetWebRequest(address);
            request.Timeout = 15000;
            request.ReadWriteTimeout = 30000;
            return request;
        }
    }

    private sealed class LaunchResult
    {
        public string Folder;
        public string UpdateError;
    }

    public sealed class Release
    {
        public string tag_name { get; set; }
        public bool draft { get; set; }
        public Asset[] assets { get; set; }
    }

    public sealed class Asset
    {
        public string name { get; set; }
        public string digest { get; set; }
    }

    public sealed class Build
    {
        public string version { get; set; }
        public string platform { get; set; }
    }
}
