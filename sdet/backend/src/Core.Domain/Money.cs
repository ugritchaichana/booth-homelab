namespace Core.Domain;

public record Money(decimal Amount, string Currency)
{
    public static Money Zero(string currency = "USD") => new(0m, currency);
}
