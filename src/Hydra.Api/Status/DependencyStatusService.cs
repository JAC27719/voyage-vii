using System.Diagnostics;
using Microsoft.Extensions.Options;

namespace Hydra.Api.Status;

public sealed class DependencyStatusService(
    IEnumerable<IDependencyProbe> probes,
    IOptions<StatusCheckOptions> options,
    ILogger<DependencyStatusService> logger)
{
    private readonly IDependencyProbe[] _probes = probes.ToArray();
    private readonly TimeSpan _timeout = TimeSpan.FromSeconds(
        Math.Max(1, options.Value.TimeoutSeconds));

    public async Task<DependencyStatusResponse> CheckAsync(
        CancellationToken cancellationToken = default)
    {
        var results = await Task.WhenAll(
            _probes.Select(probe => RunProbeAsync(probe, cancellationToken)));

        var checks = results.ToDictionary(
            result => result.Name,
            result => new DependencyCheckResponse(result.Status, result.DurationMilliseconds),
            StringComparer.Ordinal);

        var status = results.All(result => result.Status == "Healthy")
            ? "Healthy"
            : "Unhealthy";

        return new DependencyStatusResponse(status, checks);
    }

    private async Task<ProbeResult> RunProbeAsync(
        IDependencyProbe probe,
        CancellationToken cancellationToken)
    {
        var stopwatch = Stopwatch.StartNew();

        try
        {
            using var timeoutSource = CancellationTokenSource.CreateLinkedTokenSource(
                cancellationToken);
            timeoutSource.CancelAfter(_timeout);

            await probe.CheckAsync(timeoutSource.Token).WaitAsync(
                _timeout,
                cancellationToken);

            return new ProbeResult(probe.Name, "Healthy", stopwatch.ElapsedMilliseconds);
        }
        catch (Exception exception) when (
            exception is not OperationCanceledException ||
            !cancellationToken.IsCancellationRequested)
        {
            logger.LogWarning(
                "Dependency status check failed for {DependencyType}",
                probe.Name);

            return new ProbeResult(probe.Name, "Unhealthy", stopwatch.ElapsedMilliseconds);
        }
    }

    private sealed record ProbeResult(
        string Name,
        string Status,
        long DurationMilliseconds);
}
