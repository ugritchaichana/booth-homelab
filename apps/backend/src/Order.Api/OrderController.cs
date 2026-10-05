using Core.Application;
using Core.Domain;

namespace Order.Api;

public class OrderController
{
    private readonly OrderService _service = new();

    public Money Checkout(decimal subtotal)
    {
        return _service.CalculateTotal(subtotal, 0.07m);
    }

    public Money CheckoutWithVoucher(decimal subtotal, decimal discount)
    {
        return _service.CalculateTotal(subtotal - discount, 0.07m);
    }
}
