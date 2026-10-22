var builder = WebApplication.CreateBuilder(args);

builder.Services.AddHealthChecks();

var app = builder.Build();

app.MapGet("/", () => "Beacon is running.");
app.MapHealthChecks("/health");

app.Run();

public partial class Program { }
