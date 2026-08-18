using UiDispatcherQueue = Microsoft.UI.Dispatching.DispatcherQueue;
using Microsoft.UI.Xaml;

namespace TinyWin.WinUI;

public partial class App : Application
{
    public static Window Window { get; private set; } = null!;
    public static UiDispatcherQueue DispatcherQueue { get; private set; } = null!;

    public App()
    {
        InitializeComponent();
    }

    protected override void OnLaunched(LaunchActivatedEventArgs args)
    {
        Window = new MainWindow();
        DispatcherQueue = UiDispatcherQueue.GetForCurrentThread();
        Window.Activate();
    }
}
