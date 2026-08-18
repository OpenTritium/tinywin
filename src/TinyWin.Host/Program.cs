using System.Diagnostics;

namespace TinyWin.Host;

internal static class Program
{
    private static int Main(string[] args)
    {
        var repositoryRoot = FindRepositoryRoot(AppContext.BaseDirectory);
        if (repositoryRoot is null)
        {
            Console.Error.WriteLine("Could not locate TinyWin.slnx. Run from a TinyWin checkout.");
            return 2;
        }

        var scriptPath = Path.Combine(repositoryRoot, "scripts", "build.ps1");
        var processStartInfo = new ProcessStartInfo
        {
            FileName = Environment.GetEnvironmentVariable("PWSH_PATH") ?? "pwsh.exe",
            UseShellExecute = false,
            WorkingDirectory = repositoryRoot
        };
        processStartInfo.ArgumentList.Add("-NoLogo");
        processStartInfo.ArgumentList.Add("-NoProfile");
        processStartInfo.ArgumentList.Add("-File");
        processStartInfo.ArgumentList.Add(scriptPath);
        foreach (var argument in args)
        {
            processStartInfo.ArgumentList.Add(argument);
        }

        try
        {
            using var process = Process.Start(processStartInfo);
            if (process is null)
            {
                Console.Error.WriteLine("Unable to start PowerShell.");
                return 2;
            }

            process.WaitForExit();
            return process.ExitCode;
        }
        catch (Exception exception)
        {
            Console.Error.WriteLine($"Unable to start PowerShell: {exception.Message}");
            return 2;
        }
    }

    private static string? FindRepositoryRoot(string startPath)
    {
        var directory = new DirectoryInfo(startPath);
        while (directory is not null)
        {
            if (File.Exists(Path.Combine(directory.FullName, "TinyWin.slnx")))
            {
                return directory.FullName;
            }

            directory = directory.Parent;
        }

        return null;
    }
}
