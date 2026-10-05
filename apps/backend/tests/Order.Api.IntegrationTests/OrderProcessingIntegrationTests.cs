using Billing.Api;
using Order.Api;
using Xunit;

namespace Order.Api.IntegrationTests;

public class OrderProcessingIntegrationTests
{
    private readonly OrderController _orderController = new();
    private readonly InvoiceGenerator _invoiceGenerator = new();

    [Fact]
    public void FullCheckout_WithVoucherAndInvoiceGeneration_Succeeds()
    {
        const decimal subtotal = 1000.00m;
        const decimal voucherDiscount = 100.00m;
        const long orderId = 1042;

        var orderTotal = _orderController.CheckoutWithVoucher(subtotal, voucherDiscount);
        var invoiceNumber = _invoiceGenerator.GenerateInvoiceNumber(orderId);
        var tax = _invoiceGenerator.CalculateTax(subtotal - voucherDiscount, 0.07m);

        Assert.Equal("USD", orderTotal.Currency);
        Assert.Equal(963.00m, orderTotal.Amount);
        Assert.Equal(63.00m, tax);
        Assert.Equal("INV-001042", invoiceNumber);
    }

    [Fact]
    public void StandardCheckout_WithoutVoucher_GeneratesCorrectTaxAndTotal()
    {
        const decimal subtotal = 500.00m;
        const long orderId = 88;

        var orderTotal = _orderController.Checkout(subtotal);
        var invoiceNumber = _invoiceGenerator.GenerateInvoiceNumber(orderId);

        Assert.Equal(535.00m, orderTotal.Amount);
        Assert.Equal("INV-000088", invoiceNumber);
    }
}
