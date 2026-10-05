using Billing.Api;
using Xunit;

namespace Billing.Api.UnitTests;

public class InvoiceGeneratorTests
{
    [Fact]
    public void GenerateInvoiceNumber_FormatsCorrectly()
    {
        var generator = new InvoiceGenerator();
        var invoice = generator.GenerateInvoiceNumber(42);
        Assert.Equal("INV-000042", invoice);
    }

    [Fact]
    public void CalculateTax_CalculatesCorrectly()
    {
        var generator = new InvoiceGenerator();
        Assert.Equal(7.0m, generator.CalculateTax(100.0m, 0.07m));
    }

    [Theory]
    [InlineData(12.34, 0.86)]
    [InlineData(12.36, 0.87)]
    [InlineData(1.50, 0.11)]
    [InlineData(99.95, 7.00)]
    public void CalculateTax_RoundsHalfUpAwayFromZero(decimal amount, decimal expectedTax)
    {
        var generator = new InvoiceGenerator();
        Assert.Equal(expectedTax, generator.CalculateTax(amount, 0.07m));
    }
}
