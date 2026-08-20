namespace TinyWin.WinUI.Models;

public sealed record BuildResult(int ExitCode, bool WasCancelled, string LogPath);
