var builder = WebApplication.CreateBuilder(args);
var app = builder.Build();

app.MapGet("/", () => "Beacon is running.");

app.Run();

public partial class Program { }
