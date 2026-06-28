using Npgsql;

namespace Hydra.Api.Status;

public sealed class PostgresProbe(IConfiguration configuration) : IDependencyProbe
{
    public string Name => "postgres";

    public async Task CheckAsync(CancellationToken cancellationToken)
    {
        var connectionString = GetConnectionString();
        if (string.IsNullOrWhiteSpace(connectionString))
        {
            throw new InvalidOperationException("PostgreSQL is not configured.");
        }

        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);

        await using var command = new NpgsqlCommand("SELECT 1", connection);
        var result = await command.ExecuteScalarAsync(cancellationToken);

        if (!Equals(result, 1))
        {
            throw new InvalidOperationException("PostgreSQL connectivity check failed.");
        }
    }

    private string? GetConnectionString()
    {
        var configured = configuration.GetConnectionString("Postgres");
        if (!string.IsNullOrWhiteSpace(configured))
        {
            return configured;
        }

        var host = configuration["Postgres:Host"];
        var username = configuration["Postgres:Username"];
        var password = configuration["Postgres:Password"];
        if (string.IsNullOrWhiteSpace(host) ||
            string.IsNullOrWhiteSpace(username) ||
            string.IsNullOrWhiteSpace(password))
        {
            return null;
        }

        return new NpgsqlConnectionStringBuilder
        {
            Host = host,
            Port = configuration.GetValue("Postgres:Port", 5432),
            Database = configuration["Postgres:Database"] ?? "hydra",
            Username = username,
            Password = password,
            SslMode = SslMode.Require,
        }.ConnectionString;
    }
}
