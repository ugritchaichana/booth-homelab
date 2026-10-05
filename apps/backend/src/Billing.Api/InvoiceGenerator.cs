namespace Billing.Api;

public class InvoiceGenerator
{
    public string GenerateInvoiceNumber(long orderId) => $"INV-{orderId:D6}";
    public decimal CalculateTax(decimal amount, decimal rate) => amount < 0m ? 0m : Math.Round(amount * rate, 2, MidpointRounding.AwayFromZero);
}
