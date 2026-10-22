using Microsoft.AspNetCore.Mvc.Testing;
using System.Net;
using System.Text.Json;

public class RootEndpointTests : IClassFixture<WebApplicationFactory<Program>>
{
    private readonly WebApplicationFactory<Program> _factory;

    public RootEndpointTests(WebApplicationFactory<Program> factory)
    {
        _factory = factory;
    }

    [Fact]
    public async Task GetRoot_ReturnsOk_AndContainsExpectedFields()
    {
        var client = _factory.CreateClient();

        var response = await client.GetAsync("/");

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);

        var json = await response.Content.ReadAsStringAsync();
        using var doc = JsonDocument.Parse(json);
        var root = doc.RootElement;

        Assert.True(root.TryGetProperty("message", out _));
        Assert.True(root.TryGetProperty("version", out _));
        Assert.True(root.TryGetProperty("instanceId", out _));
        Assert.True(root.TryGetProperty("availabilityZone", out _));
    }

    [Fact]
    public async Task GetRoot_WithoutAppVersion_VersionDefaultsToLocal()
    {
        var client = _factory.CreateClient();

        var response = await client.GetAsync("/");
        var json = await response.Content.ReadAsStringAsync();
        using var doc = JsonDocument.Parse(json);

        Assert.Equal("local", doc.RootElement.GetProperty("version").GetString());
    }

    [Fact]
    public async Task GetRoot_WithAppVersionConfigured_ReturnsConfiguredVersion()
    {
        var client = _factory
            .WithWebHostBuilder(b => b.UseSetting("APP_VERSION", "v1.2.3"))
            .CreateClient();

        var response = await client.GetAsync("/");
        var json = await response.Content.ReadAsStringAsync();
        using var doc = JsonDocument.Parse(json);

        Assert.Equal("v1.2.3", doc.RootElement.GetProperty("version").GetString());
    }
}
