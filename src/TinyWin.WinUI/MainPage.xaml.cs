using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using TinyWin.WinUI.ViewModels;

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
}
