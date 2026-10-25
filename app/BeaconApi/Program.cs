var builder = WebApplication.CreateBuilder(args);

builder.Services.AddHealthChecks();

var app = builder.Build();

app.MapGet("/", (IConfiguration config) => new InstanceResponse(
    Message:          "Hello from Beacon!",
    Version:          config["APP_VERSION"] ?? "local",
    InstanceId:       config["INSTANCE_ID"] ?? "local",
    AvailabilityZone: config["AVAILABILITY_ZONE"] ?? "local",
    Hostname:         Environment.MachineName,
    Timestamp:        DateTime.UtcNow));

app.MapGet("/version", (IConfiguration config) =>
    new { version = config["APP_VERSION"] ?? "local" });

app.MapHealthChecks("/health");

app.Run();

public partial class Program { }

record InstanceResponse(
    string Message,
    string Version,
    string InstanceId,
    string AvailabilityZone,
    string Hostname,
    DateTime Timestamp);
