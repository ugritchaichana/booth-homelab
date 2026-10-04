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
}
