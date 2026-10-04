namespace Billing.Api;

public class InvoiceGenerator
{
    public string GenerateInvoiceNumber(long orderId) => $"INV-{orderId:D6}";
}
