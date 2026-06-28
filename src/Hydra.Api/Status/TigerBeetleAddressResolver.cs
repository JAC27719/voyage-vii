using System.Net;
using System.Net.Sockets;

namespace Hydra.Api.Status;

internal static class TigerBeetleAddressResolver
{
    public static async Task<string[]> ResolveAsync(
        string configuredAddresses,
        CancellationToken cancellationToken)
    {
        var entries = configuredAddresses.Split(
            ',',
            StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);

        var resolved = new string[entries.Length];
        for (var index = 0; index < entries.Length; index++)
        {
            resolved[index] = await ResolveEntryAsync(entries[index], cancellationToken);
        }

        return resolved;
    }

    private static async Task<string> ResolveEntryAsync(
        string address,
        CancellationToken cancellationToken)
    {
        var separatorIndex = address.LastIndexOf(':');
        if (separatorIndex < 0 || int.TryParse(address, out _))
        {
            return address;
        }

        var host = address[..separatorIndex];
        var port = address[(separatorIndex + 1)..];
        if (IPAddress.TryParse(host, out _))
        {
            return address;
        }

        var addresses = await Dns.GetHostAddressesAsync(host, cancellationToken);
        var ipv4Address = addresses.FirstOrDefault(
            candidate => candidate.AddressFamily == AddressFamily.InterNetwork);

        if (ipv4Address is null)
        {
            throw new InvalidOperationException(
                $"TigerBeetle host '{host}' did not resolve to an IPv4 address.");
        }

        return $"{ipv4Address}:{port}";
    }
}
