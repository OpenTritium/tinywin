using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Text;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using TinyWin.WinUI.Models;
using TinyWin.WinUI.Services;

namespace TinyWin.WinUI.ViewModels;

public partial class MainPageViewModel : ObservableObject
{
    private readonly EntryCatalog entryCatalog;
    private readonly TinyWinBuildRunner buildRunner;
    private readonly StringBuilder log = new();

    public ObservableCollection<TinyWinEntry> Entries { get; } = new();

    [ObservableProperty]
    [NotifyCanExecuteChangedFor(nameof(BuildCommand))]
    public partial string SourcePath { get; set; } = string.Empty;

    [ObservableProperty]
    [NotifyCanExecuteChangedFor(nameof(BuildCommand))]
    public partial string ImageIndexText { get; set; } = "1";

    [ObservableProperty]
    public partial bool CreateIso { get; set; }

    [ObservableProperty]
    [NotifyCanExecuteChangedFor(nameof(BuildCommand))]
    public partial bool IsBuilding { get; set; }

    [ObservableProperty]
    public partial string Status { get; set; } = "正在加载精简条目…";

    [ObservableProperty]
    public partial string BuildLog { get; set; } = string.Empty;

    public MainPageViewModel()
        : this(new EntryCatalog(), new TinyWinBuildRunner())
    {
    }

    internal MainPageViewModel(EntryCatalog entryCatalog, TinyWinBuildRunner buildRunner)
    {
        this.entryCatalog = entryCatalog;
        this.buildRunner = buildRunner;
        buildRunner.OutputReceived += OnBuildOutput;
    }

    public Task InitializeAsync() => LoadEntriesAsync();

    [RelayCommand]
    private async Task RefreshEntriesAsync()
    {
        await LoadEntriesAsync();
    }

    [RelayCommand(CanExecute = nameof(CanBuild))]
    private async Task BuildAsync()
    {
        if (!int.TryParse(ImageIndexText, out var imageIndex) || imageIndex < 1)
        {
            Status = "镜像索引必须是正整数。";
            return;
        }

        if (!File.Exists(SourcePath) && !Directory.Exists(SourcePath))
        {
            Status = "找不到输入 ISO 或介质目录。";
            return;
        }

        var selectedEntryIds = Entries.Where(entry => entry.IsSelected).Select(entry => entry.Id).ToArray();
        if (selectedEntryIds.Length == 0)
        {
            Status = "请至少选择一个精简条目。";
            return;
        }

        IsBuilding = true;
        log.Clear();
        BuildLog = string.Empty;
        Status = $"已选择 {selectedEntryIds.Length} 个条目，正在通过 PowerShell 构建…";
        try
        {
            var request = new BuildRequest(SourcePath, imageIndex, selectedEntryIds, CreateIso);
            var result = await buildRunner.RunAsync(request, CancellationToken.None);
            Status = result.WasCancelled
                ? "构建已取消。"
                : result.ExitCode == 0 ? "构建完成。请查看 out/ 下的清单。" : $"构建失败，退出码 {result.ExitCode}。";
        }
        catch (Exception exception)
        {
            AppendLog(exception.Message, true);
            Status = "启动构建失败。";
        }
        finally
        {
            IsBuilding = false;
        }
    }

    private bool CanBuild() => !IsBuilding && !string.IsNullOrWhiteSpace(SourcePath) && Entries.Any(entry => entry.IsSelected);

    private async Task LoadEntriesAsync()
    {
        try
        {
            var entries = await Task.Run(entryCatalog.Load);
            foreach (var entry in Entries)
            {
                entry.PropertyChanged -= OnEntryPropertyChanged;
            }

            Entries.Clear();
            foreach (var entry in entries)
            {
                entry.PropertyChanged += OnEntryPropertyChanged;
                Entries.Add(entry);
            }

            BuildCommand.NotifyCanExecuteChanged();
            Status = Entries.Count == 0 ? "没有找到精简条目。" : $"已加载 {Entries.Count} 个精简条目，请勾选要执行的项目。";
        }
        catch (Exception exception)
        {
            AppendLog(exception.Message, true);
            Status = "加载精简条目失败。";
        }
    }

    private void OnEntryPropertyChanged(object? sender, PropertyChangedEventArgs args)
    {
        if (args.PropertyName == nameof(TinyWinEntry.IsSelected))
        {
            BuildCommand.NotifyCanExecuteChanged();
        }
    }

    private void OnBuildOutput(object? sender, BuildOutputEventArgs args)
    {
        App.DispatcherQueue.TryEnqueue(() => AppendLog(args.Line, args.IsError));
    }

    private void AppendLog(string message, bool isError)
    {
        log.Append(isError ? "[error] " : string.Empty).AppendLine(message);
        BuildLog = log.ToString();
    }
}
