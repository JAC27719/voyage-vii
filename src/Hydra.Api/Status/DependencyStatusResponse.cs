using System.Text.Json.Serialization;

namespace Hydra.Api.Status;

public sealed record DependencyCheckResponse(string Status, long DurationMilliseconds);

public sealed record DependencyStatusResponse(
    string Status,
    IReadOnlyDictionary<string, DependencyCheckResponse> Checks)
{
    [JsonIgnore]
    public bool IsHealthy => string.Equals(Status, "Healthy", StringComparison.Ordinal);
}
