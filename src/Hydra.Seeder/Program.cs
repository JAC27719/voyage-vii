using Npgsql;
using System.Net;
using System.Net.Sockets;
using TigerBeetle;

var debitAccountId = (UInt128)1001;
var creditAccountId = (UInt128)1002;
var transferId = (UInt128)2001;

var postgresConnectionString = GetPostgresConnectionString();

await using (var connection = new NpgsqlConnection(postgresConnectionString))
{
    await connection.OpenAsync();
    await using var command = new NpgsqlCommand("SELECT 1", connection);
    await command.ExecuteScalarAsync();
    Console.WriteLine("PostgreSQL is reachable; no relational seed data exists yet.");
}

var clusterIdText = Environment.GetEnvironmentVariable("TigerBeetle__ClusterId") ?? "0";
var addressesText =
    Environment.GetEnvironmentVariable("TigerBeetle__Addresses")
    ?? "127.0.0.1:3000";

if (!UInt128.TryParse(clusterIdText, out var clusterId))
{
    throw new InvalidOperationException("TigerBeetle__ClusterId must be an unsigned integer.");
}

var addresses = await ResolveTigerBeetleAddressesAsync(addressesText);

using var client = new Client(clusterId, addresses);

var accountResults = client.CreateAccounts(
[
    new Account
    {
        Id = debitAccountId,
        Ledger = 1,
        Code = 1,
        Flags = AccountFlags.None,
    },
    new Account
    {
        Id = creditAccountId,
        Ledger = 1,
        Code = 1,
        Flags = AccountFlags.None,
    },
]);

EnsureAccountsSucceeded(accountResults);

var transferResults = client.CreateTransfers(
[
    new Transfer
    {
        Id = transferId,
        DebitAccountId = debitAccountId,
        CreditAccountId = creditAccountId,
        Amount = 100,
        Ledger = 1,
        Code = 1,
        Flags = TransferFlags.None,
    },
]);

EnsureTransfersSucceeded(transferResults);
Console.WriteLine("TigerBeetle sample accounts and transfer are present.");

static void EnsureAccountsSucceeded(CreateAccountResult[] results)
{
    foreach (var result in results)
    {
        if (result.Status is not (CreateAccountStatus.Created or CreateAccountStatus.Exists))
        {
            throw new InvalidOperationException(
                $"TigerBeetle account seed failed: {result.Status}");
        }
    }
}

static void EnsureTransfersSucceeded(CreateTransferResult[] results)
{
    foreach (var result in results)
    {
        if (result.Status is not (CreateTransferStatus.Created or CreateTransferStatus.Exists))
        {
            throw new InvalidOperationException(
                $"TigerBeetle transfer seed failed: {result.Status}");
        }
    }
}

static string GetPostgresConnectionString()
{
    var configured = Environment.GetEnvironmentVariable("ConnectionStrings__Postgres");
    if (!string.IsNullOrWhiteSpace(configured))
    {
        return configured;
    }

    var host = Environment.GetEnvironmentVariable("Postgres__Host");
    var username = Environment.GetEnvironmentVariable("Postgres__Username");
    var password = Environment.GetEnvironmentVariable("Postgres__Password");
    if (string.IsNullOrWhiteSpace(host) ||
        string.IsNullOrWhiteSpace(username) ||
        string.IsNullOrWhiteSpace(password))
    {
        throw new InvalidOperationException(
            "PostgreSQL requires ConnectionStrings__Postgres or Postgres__Host, " +
            "Postgres__Username, and Postgres__Password.");
    }

    return new NpgsqlConnectionStringBuilder
    {
        Host = host,
        Port = int.TryParse(
            Environment.GetEnvironmentVariable("Postgres__Port"),
            out var port)
            ? port
            : 5432,
        Database = Environment.GetEnvironmentVariable("Postgres__Database") ?? "hydra",
        Username = username,
        Password = password,
        SslMode = SslMode.Require,
    }.ConnectionString;
}

static async Task<string[]> ResolveTigerBeetleAddressesAsync(string configuredAddresses)
{
    var entries = configuredAddresses.Split(
        ',',
        StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);

    var resolved = new string[entries.Length];
    for (var index = 0; index < entries.Length; index++)
    {
        var address = entries[index];
        var separatorIndex = address.LastIndexOf(':');
        if (separatorIndex < 0 || int.TryParse(address, out _))
        {
            resolved[index] = address;
            continue;
        }

        var host = address[..separatorIndex];
        var port = address[(separatorIndex + 1)..];
        if (IPAddress.TryParse(host, out _))
        {
            resolved[index] = address;
            continue;
        }

        var hostAddresses = await Dns.GetHostAddressesAsync(host);
        var ipv4Address = hostAddresses.FirstOrDefault(
            candidate => candidate.AddressFamily == AddressFamily.InterNetwork);
        if (ipv4Address is null)
        {
            throw new InvalidOperationException(
                $"TigerBeetle host '{host}' did not resolve to an IPv4 address.");
        }

        resolved[index] = $"{ipv4Address}:{port}";
    }

    return resolved;
}
