using CommunityToolkit.Mvvm.ComponentModel;

namespace TinyWin.WinUI.Models;

public sealed partial class TinyWinEntry : ObservableObject
{
    public TinyWinEntry(string id, string version, string title, string description, string category, string risk, string selectionTier)
    {
        Id = id;
        Version = version;
        Title = title;
        Description = description;
        Category = category;
        Risk = risk;
        SelectionTier = selectionTier;
    }

    public string Id { get; }
    public string Version { get; }
    public string Title { get; }
    public string Description { get; }
    public string Category { get; }
    public string Risk { get; }
    public string SelectionTier { get; }
    [ObservableProperty]
    public partial bool IsSelected { get; set; }
}
