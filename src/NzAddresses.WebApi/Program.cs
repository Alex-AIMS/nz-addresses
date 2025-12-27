using Microsoft.EntityFrameworkCore;
using NetTopologySuite;
using NzAddresses.Core.Services;
using NzAddresses.Data;

var builder = WebApplication.CreateBuilder(args);

// Add services to the container
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen(options =>
{
    options.SwaggerDoc("v1", new Microsoft.OpenApi.Models.OpenApiInfo
    {
        Title = "NZ Addresses API",
        Version = "v1",
        Description = "New Zealand address verification and hierarchical browse service"
    });
});

// Configure database context with NetTopologySuite
// Connection string supports environment variable substitution
var connectionString = builder.Configuration.GetConnectionString("Postgres") 
    ?? Environment.GetEnvironmentVariable("CONNECTION_STRING")
    ?? "Host=localhost;Port=5432;Database=nz_addresses_db;Username=nzuser;Password=nzpass";

// Expand environment variables in connection string
connectionString = Environment.ExpandEnvironmentVariables(connectionString);

builder.Services.AddDbContext<NzAddressesDbContext>(options =>
{
    options.UseNpgsql(
        connectionString,
        npgsqlOptions => npgsqlOptions.UseNetTopologySuite()
    );
});

// Register address service
builder.Services.AddScoped<INzAddressService>(provider =>
{
    var context = provider.GetRequiredService<NzAddressesDbContext>();
    var logger = provider.GetRequiredService<ILogger<NzAddressService>>();
    return new NzAddressService(context, connectionString!, logger);
});

// Configure CORS
builder.Services.AddCors(options =>
{
    options.AddDefaultPolicy(policy =>
    {
        policy.AllowAnyOrigin()
              .AllowAnyMethod()
              .AllowAnyHeader();
    });
});

var app = builder.Build();

// Configure the HTTP request pipeline
app.UseSwagger();
app.UseSwaggerUI(options =>
{
    options.SwaggerEndpoint("/swagger/v1/swagger.json", "NZ Addresses API v1");
    options.RoutePrefix = "swagger";
});

app.UseCors();

// API Endpoints

// GET /regions - List all regions
app.MapGet("/regions", async (INzAddressService service) =>
{
    var regions = await service.GetRegionsAsync();
    return Results.Ok(regions);
})
.WithName("GetRegions")
.WithDescription("Get all regions with district counts")
.WithOpenApi();

// GET /regions/{regionId}/districts - List districts within a region
app.MapGet("/regions/{regionId}/districts", async (string regionId, INzAddressService service) =>
{
    var districts = await service.GetDistrictsAsync(regionId);
    return Results.Ok(districts);
})
.WithName("GetDistricts")
.WithDescription("Get all districts within a specific region")
.WithOpenApi();

// GET /districts/{districtId}/suburbs - List suburbs within a district
app.MapGet("/districts/{districtId}/suburbs", async (string districtId, INzAddressService service) =>
{
    var suburbs = await service.GetSuburbsAsync(districtId);
    return Results.Ok(suburbs);
})
.WithName("GetSuburbs")
.WithDescription("Get all suburbs within a specific district")
.WithOpenApi();

// GET /suburbs/{suburbId}/streets - List streets within a suburb
app.MapGet("/suburbs/{suburbId}/streets", async (string suburbId, INzAddressService service) =>
{
    var streets = await service.GetStreetsAsync(suburbId);
    return Results.Ok(streets);
})
.WithName("GetStreets")
.WithDescription("Get all streets within a specific suburb")
.WithOpenApi();

// GET /verify?rawAddress=... - Verify an address
app.MapGet("/verify", async (string rawAddress, INzAddressService service) =>
{
    var result = await service.VerifyAsync(rawAddress);
    return Results.Ok(result);
})
.WithName("VerifyAddress")
.WithDescription("Verify if an address exists in LINZ data and return its details")
.WithOpenApi();

// GET /addressForCoordinates?latitude=...&longitude=... - Get address for coordinates
app.MapGet("/addressForCoordinates", async (double latitude, double longitude, INzAddressService service) =>
{
    var result = await service.GetAddressForCoordinatesAsync(latitude, longitude);
    return Results.Ok(result);
})
.WithName("GetAddressForCoordinates")
.WithDescription("Find the nearest address for given latitude and longitude coordinates")
.WithOpenApi();

// GET /coordinatesForAddress?rawAddress=... - Get coordinates for address
app.MapGet("/coordinatesForAddress", async (string rawAddress, INzAddressService service) =>
{
    var result = await service.GetCoordinatesForAddressAsync(rawAddress);
    return Results.Ok(result);
})
.WithName("GetCoordinatesForAddress")
.WithDescription("Get latitude and longitude for a verified address")
.WithOpenApi();

// Health check endpoint
app.MapGet("/health", () => Results.Ok(new { status = "healthy", timestamp = DateTime.UtcNow }))
.WithName("HealthCheck")
.WithDescription("API health check endpoint")
.WithOpenApi();

app.Run();
