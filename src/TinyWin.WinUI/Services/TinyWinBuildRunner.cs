using System.Diagnostics;
using System.Text;
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

        var outputRoot = RepositoryLocator.ResolveOutputRoot(repositoryRoot);
        var logDirectory = Path.Combine(outputRoot, "logs");
        Directory.CreateDirectory(logDirectory);
        var logPath = Path.Combine(logDirectory, $"tinywin-build-{DateTime.UtcNow:yyyyMMddTHHmmssZ}.log");

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
        startInfo.ArgumentList.Add("-NonInteractive");
        startInfo.ArgumentList.Add("-File");
        startInfo.ArgumentList.Add(buildScript);
        startInfo.ArgumentList.Add("-Confirm:$false");
        startInfo.ArgumentList.Add("-SourcePath");
        startInfo.ArgumentList.Add(request.SourcePath);
        startInfo.ArgumentList.Add("-ImageIndex");
        startInfo.ArgumentList.Add(request.ImageIndex.ToString());
        startInfo.ArgumentList.Add("-EntryId");
        startInfo.ArgumentList.Add(string.Join(",", request.EntryIds));
        startInfo.ArgumentList.Add("-OutputPath");
        startInfo.ArgumentList.Add(outputRoot);
        if (request.CreateIso)
        {
            if (string.IsNullOrWhiteSpace(request.OscdimgPath) || !File.Exists(request.OscdimgPath))
            {
                throw new InvalidOperationException("oscdimg.exe was not found. Install Windows ADK Deployment Tools before creating a bootable ISO.");
            }

            startInfo.ArgumentList.Add("-CreateIso");
            startInfo.ArgumentList.Add("-OscdimgPath");
            startInfo.ArgumentList.Add(request.OscdimgPath);
        }

        using var process = new Process { StartInfo = startInfo, EnableRaisingEvents = true };
        using var logWriter = new StreamWriter(logPath, false, Encoding.UTF8) { AutoFlush = true };
        var logLock = new object();
        var standardOutputCompleted = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var standardErrorCompleted = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        process.OutputDataReceived += (_, eventArgs) =>
        {
            if (eventArgs.Data is null)
            {
                standardOutputCompleted.TrySetResult();
                return;
            }

            Publish(eventArgs.Data, false, logWriter, logLock);
        };
        process.ErrorDataReceived += (_, eventArgs) =>
        {
            if (eventArgs.Data is null)
            {
                standardErrorCompleted.TrySetResult();
                return;
            }

            Publish(eventArgs.Data, true, logWriter, logLock);
        };
        Publish("Starting elevated PowerShell build process…", false, logWriter, logLock);
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
        await Task.WhenAll(standardOutputCompleted.Task, standardErrorCompleted.Task);
        return new BuildResult(process.ExitCode, wasCancelled, logPath);
    }

    private void Publish(string? line, bool isError, TextWriter logWriter, object logLock)
    {
        if (!string.IsNullOrWhiteSpace(line))
        {
            lock (logLock)
            {
                logWriter.WriteLine(isError ? $"[error] {line}" : line);
            }

            OutputReceived?.Invoke(this, new BuildOutputEventArgs(line, isError));
        }
    }
}
