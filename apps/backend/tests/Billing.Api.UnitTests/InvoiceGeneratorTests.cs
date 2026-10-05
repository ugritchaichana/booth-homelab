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
}
