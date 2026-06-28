namespace Hydra.Api.Status;

public sealed class StatusCheckOptions
{
    public const string SectionName = "StatusChecks";

    public int TimeoutSeconds { get; init; } = 3;
}
