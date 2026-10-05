using Order.Api;
using Xunit;

namespace Order.Api.UnitTests;

public class OrderControllerTests
{
    [Fact]
    public void Checkout_Applies7PercentTax()
    {
        var controller = new OrderController();
        var total = controller.Checkout(100m);
        Assert.Equal(107m, total.Amount);
        Assert.Equal("USD", total.Currency);
    }

    [Fact]
    public void CheckoutWithVoucher_AppliesDiscountBeforeTax()
    {
        var controller = new OrderController();
        var total = controller.CheckoutWithVoucher(100m, 10m);
        Assert.Equal(96.3m, total.Amount);
    }

    [Fact]
    public void Checkout_AppliesAwayFromZeroRounding_MatchesFrontend()
    {
        var controller = new OrderController();
        var total = controller.Checkout(1.50m);
        Assert.Equal(1.61m, total.Amount);
    }

    [Fact]
    public void CheckoutWithVoucher_DiscountExceedsSubtotal_ReturnsZero()
    {
        var controller = new OrderController();
        var total = controller.CheckoutWithVoucher(5m, 10m);
        Assert.Equal(0.00m, total.Amount);
    }
}
