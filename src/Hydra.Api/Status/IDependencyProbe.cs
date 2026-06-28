namespace Hydra.Api.Status;

public interface IDependencyProbe
{
    string Name { get; }

    Task CheckAsync(CancellationToken cancellationToken);
}
