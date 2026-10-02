using Microsoft.Extensions.DependencyInjection;
using Microsoft.UI.Xaml.Controls;
using PlexWindows.Helpers;
using PlexWindows.ViewModels;

namespace PlexWindows.Views;

public sealed partial class FavoritesPage : Page
{
    public FavoritesViewModel ViewModel { get; }

    public FavoritesPage()
    {
        ViewModel = App.Services.GetRequiredService<FavoritesViewModel>();
        InitializeComponent();
        DataContext = ViewModel;
        Loaded += async (_, _) => await ViewModel.LoadAsync();
    }

    private void Item_Click(object sender, ItemClickEventArgs e)
    {
        if (e.ClickedItem is MediaCardItem card)
            Frame.Navigate(typeof(DetailPage), card.RatingKey);
    }
}
