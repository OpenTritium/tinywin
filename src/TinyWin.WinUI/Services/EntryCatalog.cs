using System.Text.Json;
using TinyWin.WinUI.Models;

namespace TinyWin.WinUI.Services;

public sealed class EntryCatalog
{
    public IReadOnlyList<TinyWinEntry> Load()
    {
        var rootPath = RepositoryLocator.FindRoot();
        var entryDirectory = Path.Combine(rootPath, "entries");
        if (!Directory.Exists(entryDirectory))
        {
            throw new DirectoryNotFoundException($"Entry directory was not found: {entryDirectory}");
        }

        var entries = new List<TinyWinEntry>();
        foreach (var entryPath in Directory.EnumerateFiles(entryDirectory, "*.json", SearchOption.AllDirectories).OrderBy(Path.GetFileName))
        {
            using var document = JsonDocument.Parse(File.ReadAllText(entryPath));
            var root = document.RootElement;
            var id = GetRequiredString(root, "id", entryPath);
            var version = GetRequiredString(root, "version", entryPath);
            var title = GetRequiredString(root, "title", entryPath);
            var description = GetRequiredString(root, "description", entryPath);
            var category = GetRequiredString(root, "category", entryPath);
            var risk = GetRequiredString(root, "risk", entryPath);
            entries.Add(new TinyWinEntry(id, version, title, description, category, risk));
        }

        return entries.OrderBy(entry => entry.Category).ThenBy(entry => entry.Title).ToArray();
    }

    private static string GetRequiredString(JsonElement root, string propertyName, string path)
    {
        if (!root.TryGetProperty(propertyName, out var property) || property.ValueKind != JsonValueKind.String || string.IsNullOrWhiteSpace(property.GetString()))
        {
            throw new InvalidDataException($"Entry '{path}' has no valid {propertyName}.");
        }

        return property.GetString()!;
    }
}
