using System.Globalization;
using System.Text.Json;
using System.Text.Json.Serialization;
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

    public static IEnumerable<object[]> SharedTaxRoundingRows()
    {
        var path = Path.Combine(AppContext.BaseDirectory, "fixtures/tax-rounding.json");
        var rows = JsonSerializer.Deserialize<List<TaxRoundingRow>>(File.ReadAllText(path))!;
        foreach (var row in rows)
        {
            yield return new object[]
            {
                decimal.Parse(row.Amount, CultureInfo.InvariantCulture),
                decimal.Parse(row.Rate, CultureInfo.InvariantCulture),
                decimal.Parse(row.ExpectedTax, CultureInfo.InvariantCulture),
            };
        }
    }

    [Theory]
    [MemberData(nameof(SharedTaxRoundingRows))]
    public void CalculateTax_MatchesSharedFixture(decimal amount, decimal rate, decimal expectedTax)
    {
        var generator = new InvoiceGenerator();
        Assert.Equal(expectedTax, generator.CalculateTax(amount, rate));
    }

    [Fact]
    public void CalculateTax_NegativeAmount_ReturnsZero()
    {
        var generator = new InvoiceGenerator();
        Assert.Equal(0m, generator.CalculateTax(-50m, 0.07m));
    }

    private sealed record TaxRoundingRow(
        [property: JsonPropertyName("amount")] string Amount,
        [property: JsonPropertyName("rate")] string Rate,
        [property: JsonPropertyName("expectedTax")] string ExpectedTax);
}
