using Microsoft.UI.Xaml;
using Windows.Graphics;

namespace TinyWin.WinUI;

public sealed partial class MainWindow : Window
{
    public MainWindow()
    {
        InitializeComponent();
        ExtendsContentIntoTitleBar = true;
        SetTitleBar(AppTitleBar);
        AppWindow.SetIcon("Assets/AppIcon.ico");
        AppWindow.Resize(new SizeInt32(1240, 820));
        RootFrame.Navigate(typeof(MainPage));
    }
}
