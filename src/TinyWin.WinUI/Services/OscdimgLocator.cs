namespace TinyWin.WinUI.Services;

public static class OscdimgLocator
{
    public static bool TryFind(out string path)
    {
        foreach (var directory in EnumerateCandidateDirectories())
        {
            var candidatePath = Path.Combine(directory, "oscdimg.exe");
            if (File.Exists(candidatePath))
            {
                path = candidatePath;
                return true;
            }
        }

        path = string.Empty;
        return false;
    }

    private static IEnumerable<string> EnumerateCandidateDirectories()
    {
        var pathValue = Environment.GetEnvironmentVariable("PATH");
        if (!string.IsNullOrWhiteSpace(pathValue))
        {
            foreach (var directory in pathValue.Split(Path.PathSeparator, StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries))
            {
                yield return directory;
            }
        }

        foreach (var programFilesPath in new[]
                 {
                     Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86),
                     Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles)
                 }.Where(path => !string.IsNullOrWhiteSpace(path)).Distinct(StringComparer.OrdinalIgnoreCase))
        {
            yield return Path.Combine(programFilesPath, "Windows Kits", "10", "Assessment and Deployment Kit", "Deployment Tools", "amd64", "Oscdimg");
        }
    }
}
