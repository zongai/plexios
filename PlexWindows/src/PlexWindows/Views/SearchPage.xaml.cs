using Microsoft.Extensions.DependencyInjection;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Navigation;
using PlexWindows.Helpers;
using PlexWindows.ViewModels;
using Windows.System;

namespace PlexWindows.Views;

public sealed partial class SearchPage : Page
{
    public SearchViewModel ViewModel { get; }

    public SearchPage()
    {
        ViewModel = App.Services.GetRequiredService<SearchViewModel>();
        InitializeComponent();
        DataContext = ViewModel;
    }

    protected override void OnNavigatedTo(NavigationEventArgs e)
    {
        base.OnNavigatedTo(e);
        if (e.Parameter is string q && !string.IsNullOrWhiteSpace(q))
        {
            ViewModel.Query = q;
            _ = ViewModel.SearchAsync();
        }
        QueryBox.Focus(FocusState.Programmatic);
    }

    private async void QueryBox_KeyUp(object sender, KeyRoutedEventArgs e)
    {
        await ViewModel.SearchAsync();
        if (e.Key == VirtualKey.Enter)
            e.Handled = true;
    }

    private void Result_Click(object sender, RoutedEventArgs e)
    {
        if (sender is FrameworkElement { Tag: MediaCardItem card })
            Frame.Navigate(typeof(DetailPage), card.RatingKey);
    }
}
