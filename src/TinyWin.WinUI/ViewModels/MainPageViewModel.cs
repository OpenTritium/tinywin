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
    private readonly TinyWinImageInspector imageInspector;
    private readonly StringBuilder log = new();
    private string? oscdimgPath;

    public ObservableCollection<TinyWinEntry> Entries { get; } = new();
    public ObservableCollection<TinyWinImageInfo> Images { get; } = new();

    [ObservableProperty]
    [NotifyCanExecuteChangedFor(nameof(BuildCommand))]
    public partial string SourcePath { get; set; } = string.Empty;

    [ObservableProperty]
    [NotifyCanExecuteChangedFor(nameof(BuildCommand))]
    public partial TinyWinImageInfo? SelectedImage { get; set; }

    [ObservableProperty]
    [NotifyCanExecuteChangedFor(nameof(BuildCommand))]
    public partial bool IsInspectingImage { get; set; }

    [ObservableProperty]
    [NotifyCanExecuteChangedFor(nameof(BuildCommand))]
    public partial bool CreateIso { get; set; }

    [ObservableProperty]
    [NotifyCanExecuteChangedFor(nameof(BuildCommand))]
    public partial bool IsBuilding { get; set; }

    [ObservableProperty]
    public partial string Status { get; set; } = "正在加载精简条目…";

    [ObservableProperty]
    public partial string BuildLog { get; set; } = string.Empty;

    [ObservableProperty]
    public partial int SelectedEntryCount { get; set; }

    public string EntryCountSummary => $"{Entries.Count} 个可用条目，其中 {Entries.Count(entry => entry.SelectionTier == "Standard")} 个为常规项";

    public string SelectionSummary => SelectedEntryCount == 0
        ? "尚未选择条目"
        : $"已选择 {SelectedEntryCount} 个条目";

    public bool HasLoadedImages => Images.Count > 0;

    public string ImageInspectionSummary => IsInspectingImage
        ? "正在读取映像索引…"
        : HasLoadedImages
            ? $"已发现 {Images.Count} 个安装映像。"
            : "选择 ISO 后读取可用映像。";

    public MainPageViewModel()
        : this(new EntryCatalog(), new TinyWinBuildRunner(), new TinyWinImageInspector())
    {
    }

    internal MainPageViewModel(EntryCatalog entryCatalog, TinyWinBuildRunner buildRunner, TinyWinImageInspector imageInspector)
    {
        this.entryCatalog = entryCatalog;
        this.buildRunner = buildRunner;
        this.imageInspector = imageInspector;
        buildRunner.OutputReceived += OnBuildOutput;
    }

    public Task InitializeAsync() => LoadEntriesAsync();

    [RelayCommand]
    private async Task RefreshEntriesAsync()
    {
        await LoadEntriesAsync();
    }

    [RelayCommand]
    private void ClearSelection()
    {
        foreach (var entry in Entries.Where(entry => entry.IsSelected))
        {
            entry.IsSelected = false;
        }
    }

    [RelayCommand]
    private void SelectAll()
    {
        foreach (var entry in Entries)
        {
            entry.IsSelected = entry.SelectionTier == "Standard";
        }
    }

    [RelayCommand]
    private void SelectAllEntries()
    {
        foreach (var entry in Entries.Where(entry => !entry.IsSelected))
        {
            entry.IsSelected = true;
        }
    }

    public async Task LoadImageAsync(string sourcePath)
    {
        IsInspectingImage = true;
        SourcePath = sourcePath;
        SelectedImage = null;
        Images.Clear();
        OnPropertyChanged(nameof(HasLoadedImages));
        OnPropertyChanged(nameof(ImageInspectionSummary));
        Status = "正在读取安装介质中的映像索引…";
        try
        {
            var images = await imageInspector.InspectAsync(sourcePath, CancellationToken.None);
            foreach (var image in images)
            {
                Images.Add(image);
            }

            SelectedImage = Images[0];
            OnPropertyChanged(nameof(HasLoadedImages));
            OnPropertyChanged(nameof(ImageInspectionSummary));
            Status = $"已加载 {Images.Count} 个映像，请选择要精简的索引。";
        }
        catch (Exception exception)
        {
            SourcePath = string.Empty;
            AppendLog(exception.Message, true);
            Status = "读取安装介质失败。";
        }
        finally
        {
            IsInspectingImage = false;
            OnPropertyChanged(nameof(ImageInspectionSummary));
        }
    }

    [RelayCommand(CanExecute = nameof(CanBuild))]
    private async Task BuildAsync()
    {
        if (SelectedImage is null)
        {
            Status = "请先选择安装介质并加载映像索引。";
            return;
        }

        var selectedEntryIds = Entries.Where(entry => entry.IsSelected).Select(entry => entry.Id).ToArray();
        if (selectedEntryIds.Length == 0)
        {
            Status = "请至少选择一个精简条目。";
            return;
        }

        if (CreateIso && !EnsureOscdimgAvailable())
        {
            return;
        }

        IsBuilding = true;
        log.Clear();
        BuildLog = string.Empty;
        Status = $"已选择 {selectedEntryIds.Length} 个条目，正在通过 PowerShell 构建…";
        try
        {
            var request = new BuildRequest(SourcePath, SelectedImage.ImageIndex, selectedEntryIds, CreateIso, oscdimgPath);
            var result = await buildRunner.RunAsync(request, CancellationToken.None);
            AppendLog($"完整构建日志已写入：{result.LogPath}", false);
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

    private bool CanBuild() => !IsBuilding && !IsInspectingImage && SelectedImage is not null && Entries.Any(entry => entry.IsSelected);

    partial void OnCreateIsoChanged(bool value)
    {
        if (!value)
        {
            oscdimgPath = null;
            return;
        }

        EnsureOscdimgAvailable();
    }

    private bool EnsureOscdimgAvailable()
    {
        if (OscdimgLocator.TryFind(out var discoveredPath))
        {
            oscdimgPath = discoveredPath;
            Status = "已启用可启动 ISO 输出。";
            AppendLog($"已找到 oscdimg.exe：{discoveredPath}", false);
            return true;
        }

        oscdimgPath = null;
        CreateIso = false;
        Status = "未找到 oscdimg.exe；已关闭可启动 ISO 输出。";
        AppendLog("未找到 oscdimg.exe。请安装 Windows ADK Deployment Tools 后再启用可启动 ISO 输出。", true);
        return false;
    }

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

            UpdateSelectionSummary();
            OnPropertyChanged(nameof(EntryCountSummary));
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
            UpdateSelectionSummary();
            BuildCommand.NotifyCanExecuteChanged();
        }
    }

    private void UpdateSelectionSummary()
    {
        SelectedEntryCount = Entries.Count(entry => entry.IsSelected);
        OnPropertyChanged(nameof(SelectionSummary));
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
