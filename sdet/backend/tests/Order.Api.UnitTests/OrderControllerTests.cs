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
}
