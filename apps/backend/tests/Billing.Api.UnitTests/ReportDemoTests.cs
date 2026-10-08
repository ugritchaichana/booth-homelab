using Billing.Api;
using Xunit;

namespace Billing.Api.UnitTests;

public class ReportDemoTests
{
    [Fact]
    public void CalculateTax_DeliberatelyWrongExpectation()
    {
        var generator = new InvoiceGenerator();
        Assert.Equal(7.01m, generator.CalculateTax(100.0m, 0.07m));
    }
}
