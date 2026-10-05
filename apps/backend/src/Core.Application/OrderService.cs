using Core.Domain;

namespace Core.Application;

public class OrderService
{
    public Money CalculateTotal(decimal baseAmount, decimal taxRate)
    {
        return new Money(baseAmount + (baseAmount * taxRate), "USD");
    }
}
