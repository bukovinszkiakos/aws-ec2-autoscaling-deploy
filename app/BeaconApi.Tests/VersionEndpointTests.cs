using Microsoft.AspNetCore.Mvc.Testing;
using System.Net;
using System.Text.Json;

public class VersionEndpointTests : IClassFixture<WebApplicationFactory<Program>>
{
    private readonly WebApplicationFactory<Program> _factory;

    public VersionEndpointTests(WebApplicationFactory<Program> factory)
    {
        _factory = factory;
    }

    [Fact]
    public async Task GetVersion_ReturnsOk()
    {
        var client = _factory.CreateClient();

        var response = await client.GetAsync("/version");

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
    }

    [Fact]
    public async Task GetVersion_ResponseContainsVersionProperty()
    {
        var client = _factory.CreateClient();

        var response = await client.GetAsync("/version");
        var json = await response.Content.ReadAsStringAsync();
        using var doc = JsonDocument.Parse(json);

        Assert.True(doc.RootElement.TryGetProperty("version", out _));
    }

    [Fact]
    public async Task GetVersion_WithoutAppVersion_DefaultsToLocal()
    {
        var client = _factory.CreateClient();

        var response = await client.GetAsync("/version");
        var json = await response.Content.ReadAsStringAsync();
        using var doc = JsonDocument.Parse(json);

        Assert.Equal("local", doc.RootElement.GetProperty("version").GetString());
    }

    [Fact]
    public async Task GetVersion_WithAppVersionConfigured_ReturnsConfiguredVersion()
    {
        var client = _factory
            .WithWebHostBuilder(b => b.UseSetting("APP_VERSION", "v2.0.0"))
            .CreateClient();

        var response = await client.GetAsync("/version");
        var json = await response.Content.ReadAsStringAsync();
        using var doc = JsonDocument.Parse(json);

        Assert.Equal("v2.0.0", doc.RootElement.GetProperty("version").GetString());
    }
}
