namespace TinyWin.WinUI.Models;

public sealed record TinyWinImageInfo(
    int ImageIndex,
    string? ImageName,
    string? ImageDescription,
    string? Architecture,
    string? Version,
    string? EditionId,
    string? InstallationType)
{
    public string DisplayName
    {
        get
        {
            var name = string.IsNullOrWhiteSpace(ImageName) ? "未命名映像" : ImageName;
            var edition = string.IsNullOrWhiteSpace(EditionId) ? null : EditionId;
            var architecture = string.IsNullOrWhiteSpace(Architecture) ? null : Architecture;
            var details = new[] { edition, architecture }.Where(value => value is not null);
            var suffix = string.Join(" · ", details!);
            return string.IsNullOrWhiteSpace(suffix)
                ? $"索引 {ImageIndex} · {name}"
                : $"索引 {ImageIndex} · {name} · {suffix}";
        }
    }
}
