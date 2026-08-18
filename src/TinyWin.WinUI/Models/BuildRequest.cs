namespace TinyWin.WinUI.Models;

public sealed record BuildRequest(
    string SourcePath,
    int ImageIndex,
    IReadOnlyList<string> EntryIds,
    bool CreateIso);
