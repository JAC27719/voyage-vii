using Hydra.Api.Status;

var builder = WebApplication.CreateBuilder(args);

builder.Services.Configure<StatusCheckOptions>(
    builder.Configuration.GetSection(StatusCheckOptions.SectionName));
builder.Services.Configure<TigerBeetleOptions>(
    builder.Configuration.GetSection(TigerBeetleOptions.SectionName));

builder.Services.AddSingleton<IDependencyProbe, PostgresProbe>();
builder.Services.AddSingleton<IDependencyProbe, TigerBeetleProbe>();
builder.Services.AddSingleton<DependencyStatusService>();

var app = builder.Build();

app.MapGet("/health/live", () => Results.Ok(new { status = "Healthy" }));

app.MapGet("/status", async (
    DependencyStatusService statusService,
    CancellationToken cancellationToken) =>
{
    var response = await statusService.CheckAsync(cancellationToken);
    return response.IsHealthy
        ? Results.Ok(response)
        : Results.Json(response, statusCode: StatusCodes.Status503ServiceUnavailable);
});

app.Run();

public partial class Program;
