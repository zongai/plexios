using Microsoft.Extensions.DependencyInjection;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Navigation;
using PlexWindows.Helpers;
using PlexWindows.Models;
using PlexWindows.ViewModels;

namespace PlexWindows.Views;

public sealed partial class LibrariesPage : Page
{
    public LibrariesViewModel ViewModel { get; }

    public LibrariesPage()
    {
        ViewModel = App.Services.GetRequiredService<LibrariesViewModel>();
        InitializeComponent();
        DataContext = ViewModel;
    }

    protected override void OnNavigatedTo(NavigationEventArgs e)
    {
        base.OnNavigatedTo(e);
        if (e.Parameter is PlexLibraryType filter)
            ViewModel.FilterType = filter;
        else
            ViewModel.FilterType = null;
        _ = ViewModel.LoadLibrariesAsync();
    }

    private async void LibraryList_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (e.AddedItems.FirstOrDefault() is PlexLibrary lib)
            await ViewModel.SelectLibraryAsync(lib);
    }

    private void Item_Click(object sender, RoutedEventArgs e)
    {
        if (sender is FrameworkElement { Tag: MediaCardItem card })
            Frame.Navigate(typeof(DetailPage), card.RatingKey);
    }
}
