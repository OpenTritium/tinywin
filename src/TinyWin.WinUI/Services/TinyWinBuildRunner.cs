using System.Diagnostics;
using TinyWin.WinUI.Models;

namespace TinyWin.WinUI.Services;

public sealed class BuildOutputEventArgs(string line, bool isError) : EventArgs
{
    public string Line { get; } = line;
    public bool IsError { get; } = isError;
}

public sealed class TinyWinBuildRunner
{
    public event EventHandler<BuildOutputEventArgs>? OutputReceived;

    public async Task<BuildResult> RunAsync(BuildRequest request, CancellationToken cancellationToken)
    {
        var repositoryRoot = RepositoryLocator.FindRoot();
        var buildScript = Path.Combine(repositoryRoot, "scripts", "build.ps1");
        if (!File.Exists(buildScript))
        {
            throw new FileNotFoundException("TinyWin build script was not found.", buildScript);
        }

        var startInfo = new ProcessStartInfo
        {
            FileName = Environment.GetEnvironmentVariable("PWSH_PATH") ?? "pwsh.exe",
            UseShellExecute = false,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            CreateNoWindow = true,
            WorkingDirectory = repositoryRoot
        };
        startInfo.ArgumentList.Add("-NoLogo");
        startInfo.ArgumentList.Add("-NoProfile");
        startInfo.ArgumentList.Add("-File");
        startInfo.ArgumentList.Add(buildScript);
        startInfo.ArgumentList.Add("-SourcePath");
        startInfo.ArgumentList.Add(request.SourcePath);
        startInfo.ArgumentList.Add("-ImageIndex");
        startInfo.ArgumentList.Add(request.ImageIndex.ToString());
        startInfo.ArgumentList.Add("-EntryId");
        startInfo.ArgumentList.Add(string.Join(",", request.EntryIds));
        if (request.CreateIso)
        {
            startInfo.ArgumentList.Add("-CreateIso");
        }

        using var process = new Process { StartInfo = startInfo, EnableRaisingEvents = true };
        process.OutputDataReceived += (_, eventArgs) => Publish(eventArgs.Data, false);
        process.ErrorDataReceived += (_, eventArgs) => Publish(eventArgs.Data, true);
        if (!process.Start())
        {
            throw new InvalidOperationException("Unable to start the TinyWin host.");
        }

        process.BeginOutputReadLine();
        process.BeginErrorReadLine();
        var wasCancelled = false;
        using var cancellationRegistration = cancellationToken.Register(() =>
        {
            wasCancelled = true;
            if (!process.HasExited)
            {
                process.Kill(true);
            }
        });

        await process.WaitForExitAsync(CancellationToken.None);
        return new BuildResult(process.ExitCode, wasCancelled);
    }

    private void Publish(string? line, bool isError)
    {
        if (!string.IsNullOrWhiteSpace(line))
        {
            OutputReceived?.Invoke(this, new BuildOutputEventArgs(line, isError));
        }
    }
}
