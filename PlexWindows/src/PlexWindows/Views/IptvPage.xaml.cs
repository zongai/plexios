using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.Extensions.DependencyInjection;
using PlexWindows.Iptv;
using PlexWindows.ViewModels;

namespace PlexWindows.Views;

public sealed partial class IptvPage : Page
{
    public IptvViewModel ViewModel { get; }

    public IptvPage()
    {
        ViewModel = App.Services.GetRequiredService<IptvViewModel>();
        InitializeComponent();
    }

    private async void Add_Click(object sender, RoutedEventArgs e) =>
        await ViewModel.AddAndRefreshAsync();

    private async void RefreshPl_Click(object sender, RoutedEventArgs e)
    {
        if (sender is FrameworkElement { Tag: IptvPlaylist pl })
            await ViewModel.RefreshPlaylistAsync(pl);
    }

    private void DeletePl_Click(object sender, RoutedEventArgs e)
    {
        if (sender is FrameworkElement { Tag: IptvPlaylist pl })
            ViewModel.DeletePlaylist(pl);
    }

    private void Channel_Click(object sender, ItemClickEventArgs e)
    {
        if (e.ClickedItem is not IptvChannel ch) return;
        try
        {
            var req = IptvViewModel.BuildStreamRequest(ch);
            Frame?.Navigate(typeof(PlayerPage), req);
        }
        catch (Exception ex)
        {
            ViewModel.StatusMessage = ex.Message;
        }
    }
}
