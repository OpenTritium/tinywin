namespace TinyWin.WinUI.Services;

public static class RepositoryLocator
{
    public static string FindRoot()
    {
        foreach (var startPath in new[] { Environment.CurrentDirectory, AppContext.BaseDirectory })
        {
            var directory = new DirectoryInfo(startPath);
            while (directory is not null)
            {
                var solutionPath = Path.Combine(directory.FullName, "TinyWin.slnx");
                var buildScriptPath = Path.Combine(directory.FullName, "scripts", "build.ps1");
                var entriesPath = Path.Combine(directory.FullName, "entries");
                var modulePath = Path.Combine(directory.FullName, "src", "TinyWin", "TinyWin.psd1");
                if ((File.Exists(solutionPath) && File.Exists(buildScriptPath))
                    || (File.Exists(buildScriptPath) && Directory.Exists(entriesPath) && File.Exists(modulePath)))
                {
                    return directory.FullName;
                }

                directory = directory.Parent;
            }
        }

        throw new DirectoryNotFoundException("TinyWin source checkout was not found.");
    }

    public static string ResolveOutputRoot(string repositoryRoot)
    {
        var repositoryOutput = Path.Combine(repositoryRoot, "out");
        if (CanWriteToDirectory(repositoryOutput))
        {
            return repositoryOutput;
        }

        var userOutput = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "TinyWin",
            "out");
        Directory.CreateDirectory(userOutput);
        return userOutput;
    }

    private static bool CanWriteToDirectory(string directoryPath)
    {
        try
        {
            Directory.CreateDirectory(directoryPath);
            var probePath = Path.Combine(directoryPath, $".write-probe-{Guid.NewGuid():N}");
            using (File.Create(probePath))
            {
            }

            File.Delete(probePath);
            return true;
        }
        catch (IOException)
        {
            return false;
        }
        catch (UnauthorizedAccessException)
        {
            return false;
        }
    }
}
