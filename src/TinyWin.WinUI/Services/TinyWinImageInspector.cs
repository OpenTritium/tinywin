using System.Diagnostics;
using System.Text.Json;
using TinyWin.WinUI.Models;

namespace TinyWin.WinUI.Services;

public sealed class TinyWinImageInspector
{
    public async Task<IReadOnlyList<TinyWinImageInfo>> InspectAsync(string sourcePath, CancellationToken cancellationToken)
    {
        var repositoryRoot = RepositoryLocator.FindRoot();
        var inspectionScript = Path.Combine(repositoryRoot, "scripts", "inspect-image.ps1");
        if (!File.Exists(inspectionScript))
        {
            throw new FileNotFoundException("TinyWin image inspection script was not found.", inspectionScript);
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
        startInfo.ArgumentList.Add(inspectionScript);
        startInfo.ArgumentList.Add("-SourcePath");
        startInfo.ArgumentList.Add(sourcePath);

        using var process = new Process { StartInfo = startInfo };
        if (!process.Start())
        {
            throw new InvalidOperationException("Unable to start TinyWin image inspection.");
        }

        var standardOutputTask = process.StandardOutput.ReadToEndAsync(cancellationToken);
        var standardErrorTask = process.StandardError.ReadToEndAsync(cancellationToken);
        await process.WaitForExitAsync(cancellationToken);
        var standardOutput = await standardOutputTask;
        var standardError = await standardErrorTask;
        if (process.ExitCode != 0)
        {
            throw new InvalidOperationException(string.IsNullOrWhiteSpace(standardError)
                ? $"Image inspection failed with exit code {process.ExitCode}."
                : standardError.Trim());
        }

        using var document = JsonDocument.Parse(standardOutput);
        TinyWinImageInfo[]? images;
        if (document.RootElement.ValueKind == JsonValueKind.Array)
        {
            images = JsonSerializer.Deserialize(document.RootElement, TinyWinJsonContext.Default.TinyWinImageInfoArray);
        }
        else
        {
            var image = JsonSerializer.Deserialize(document.RootElement, TinyWinJsonContext.Default.TinyWinImageInfo)
                ?? throw new InvalidDataException("The selected media exposes an invalid Windows image record.");
            images = [image];
        }
        if (images is null || images.Length == 0)
        {
            throw new InvalidDataException("The selected media does not expose any installable Windows images.");
        }

        return images.OrderBy(image => image.ImageIndex).ToArray();
    }
}
