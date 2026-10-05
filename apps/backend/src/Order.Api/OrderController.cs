using Core.Application;
using Core.Domain;

namespace Order.Api;

public class OrderController
{
    private readonly OrderService _service = new();

    public Money Checkout(decimal subtotal)
    {
        var baseAmount = Math.Max(0m, subtotal);
        return _service.CalculateTotal(baseAmount, 0.07m);
    }

    public Money CheckoutWithVoucher(decimal subtotal, decimal discount)
    {
        var clampedDiscount = Math.Max(0m, Math.Min(discount, subtotal));
        var baseAmount = Math.Max(0m, subtotal - clampedDiscount);
        return _service.CalculateTotal(baseAmount, 0.07m);
    }
}
