namespace Hydra.Api.Status;

public sealed class TigerBeetleOptions
{
    public const string SectionName = "TigerBeetle";

    public string ClusterId { get; init; } = "0";

    public string Addresses { get; init; } = "127.0.0.1:3000";
}
