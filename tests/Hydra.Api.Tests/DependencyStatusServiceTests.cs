using Hydra.Api.Status;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Options;
using Xunit;

namespace Hydra.Api.Tests;

public sealed class DependencyStatusServiceTests
{
    [Fact]
    public async Task ReportsHealthyWhenEveryProbeSucceeds()
    {
        var service = CreateService(
            new FakeProbe("postgres", _ => Task.CompletedTask),
            new FakeProbe("tigerbeetle", _ => Task.CompletedTask));

        var response = await service.CheckAsync();

        Assert.True(response.IsHealthy);
        Assert.All(response.Checks.Values, check => Assert.Equal("Healthy", check.Status));
    }

    [Fact]
    public async Task SanitizesProbeExceptions()
    {
        var service = CreateService(
            new FakeProbe(
                "postgres",
                _ => throw new InvalidOperationException("password=do-not-leak")));

        var response = await service.CheckAsync();
        var serialized = System.Text.Json.JsonSerializer.Serialize(response);

        Assert.False(response.IsHealthy);
        Assert.DoesNotContain("do-not-leak", serialized, StringComparison.Ordinal);
        Assert.Equal("Unhealthy", response.Checks["postgres"].Status);
    }

    [Fact]
    public async Task MarksOnlyTheFailingDependencyUnhealthy()
    {
        var service = CreateService(
            new FakeProbe("postgres", _ => Task.CompletedTask),
            new FakeProbe("tigerbeetle", _ => Task.FromException(new Exception())));

        var response = await service.CheckAsync();

        Assert.Equal("Healthy", response.Checks["postgres"].Status);
        Assert.Equal("Unhealthy", response.Checks["tigerbeetle"].Status);
    }

    [Fact]
    public async Task TimesOutSlowProbes()
    {
        var service = CreateService(
            new FakeProbe("postgres", _ => Task.Delay(TimeSpan.FromSeconds(5))),
            timeoutSeconds: 1);

        var response = await service.CheckAsync();

        Assert.False(response.IsHealthy);
        Assert.Equal("Unhealthy", response.Checks["postgres"].Status);
    }

    private static DependencyStatusService CreateService(
        FakeProbe probe,
        int timeoutSeconds = 3) =>
        CreateService([probe], timeoutSeconds);

    private static DependencyStatusService CreateService(
        FakeProbe first,
        FakeProbe second) =>
        CreateService([first, second], 3);

    private static DependencyStatusService CreateService(
        IEnumerable<IDependencyProbe> probes,
        int timeoutSeconds) =>
        new(
            probes,
            Options.Create(new StatusCheckOptions { TimeoutSeconds = timeoutSeconds }),
            NullLogger<DependencyStatusService>.Instance);

    private sealed class FakeProbe(
        string name,
        Func<CancellationToken, Task> action) : IDependencyProbe
    {
        public string Name => name;

        public Task CheckAsync(CancellationToken cancellationToken) =>
            action(cancellationToken);
    }
}
