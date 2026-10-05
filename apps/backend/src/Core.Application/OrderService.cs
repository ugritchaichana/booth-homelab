using Core.Domain;

namespace Core.Application;

public class OrderService
{
    public Money CalculateTotal(decimal baseAmount, decimal taxRate)
    {
        var tax = Math.Round(baseAmount * taxRate, 2, MidpointRounding.AwayFromZero);
        return new Money(baseAmount + tax, "USD");
    }
}
