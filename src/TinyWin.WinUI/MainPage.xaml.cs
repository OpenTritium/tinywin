using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using TinyWin.WinUI.ViewModels;
using Windows.Storage.Pickers;
using WinRT.Interop;

namespace TinyWin.WinUI;

public sealed partial class MainPage : Page
{
    public MainPageViewModel ViewModel { get; } = new();
    private bool initialized;

    public MainPage()
    {
        InitializeComponent();
    }

    private async void Page_Loaded(object sender, RoutedEventArgs e)
    {
        if (!initialized)
        {
            initialized = true;
            await ViewModel.InitializeAsync();
        }
    }

    private async void SelectIsoButton_Click(object sender, RoutedEventArgs e)
    {
        var picker = new FileOpenPicker();
        picker.FileTypeFilter.Add(".iso");
        InitializeWithWindow.Initialize(picker, WindowNative.GetWindowHandle(App.Window));
        var selectedFile = await picker.PickSingleFileAsync();
        if (selectedFile is not null)
        {
            await ViewModel.LoadImageAsync(selectedFile.Path);
        }
    }
}
