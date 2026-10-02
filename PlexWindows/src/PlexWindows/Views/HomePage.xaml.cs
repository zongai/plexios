using Microsoft.Extensions.DependencyInjection;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using PlexWindows.Helpers;
using PlexWindows.ViewModels;

namespace PlexWindows.Views;

public sealed partial class HomePage : Page
{
    public HomeViewModel ViewModel { get; }

    public HomePage()
    {
        ViewModel = App.Services.GetRequiredService<HomeViewModel>();
        InitializeComponent();
        DataContext = ViewModel;
        Loaded += async (_, _) => await ViewModel.LoadAsync();
    }

    private void Item_Click(object sender, RoutedEventArgs e)
    {
        if (sender is FrameworkElement { Tag: MediaCardItem card })
            Frame.Navigate(typeof(DetailPage), card.RatingKey);
    }
}
