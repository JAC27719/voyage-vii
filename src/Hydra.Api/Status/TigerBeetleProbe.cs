using Microsoft.Extensions.Options;
using TigerBeetle;

namespace Hydra.Api.Status;

public sealed class TigerBeetleProbe(IOptions<TigerBeetleOptions> options) : IDependencyProbe
{
    private static readonly UInt128 ProbeAccountId = UInt128.MaxValue;

    public string Name => "tigerbeetle";

    public async Task CheckAsync(CancellationToken cancellationToken)
    {
        if (!UInt128.TryParse(options.Value.ClusterId, out var clusterId))
        {
            throw new InvalidOperationException("TigerBeetle cluster ID is invalid.");
        }

        var addresses = await TigerBeetleAddressResolver.ResolveAsync(
            options.Value.Addresses,
            cancellationToken);
        if (addresses.Length == 0)
        {
            throw new InvalidOperationException("TigerBeetle has no configured addresses.");
        }

        using var client = new Client(clusterId, addresses);
        await Task.Run(
                () => client.LookupAccounts([ProbeAccountId]),
                CancellationToken.None)
            .WaitAsync(cancellationToken);
    }
}
