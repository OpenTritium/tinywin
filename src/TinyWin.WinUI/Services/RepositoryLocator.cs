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
                if (File.Exists(solutionPath) && File.Exists(buildScriptPath))
                {
                    return directory.FullName;
                }

                directory = directory.Parent;
            }
        }

        throw new DirectoryNotFoundException("TinyWin source checkout was not found.");
    }
}
