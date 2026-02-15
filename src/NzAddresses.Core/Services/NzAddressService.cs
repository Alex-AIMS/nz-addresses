using Dapper;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;
using Npgsql;
using NzAddresses.Core.Parsing;
using NzAddresses.Data;
using NzAddresses.Domain.Dtos;

namespace NzAddresses.Core.Services;

public class NzAddressService : INzAddressService
{
    private readonly NzAddressesDbContext _context;
    private readonly string _connectionString;
    private readonly LibpostalNormalizer _normalizer;
    private readonly ILogger<NzAddressService> _logger;

    public NzAddressService(
        NzAddressesDbContext context,
        string connectionString,
        ILogger<NzAddressService> logger)
    {
        _context = context;
        _connectionString = connectionString;
        _normalizer = new LibpostalNormalizer();
        _logger = logger;
    }

    public async Task<IEnumerable<RegionDto>> GetRegionsAsync()
    {
        using var connection = new NpgsqlConnection(_connectionString);
        
        var sql = @"
            SELECT 
                region_id AS RegionId,
                name AS Name,
                COALESCE(district_count, 0) AS DistrictCount
            FROM nz_addresses.v_regions
            ORDER BY name";

        var regions = await connection.QueryAsync<RegionDto>(sql);
        return regions;
    }

    public async Task<IEnumerable<DistrictDto>> GetDistrictsAsync(string regionId)
    {
        using var connection = new NpgsqlConnection(_connectionString);
        
        var sql = @"
            SELECT 
                district_id AS DistrictId,
                region_id AS RegionId,
                display_name AS Name,
                COALESCE(suburb_count, 0) AS SuburbCount
            FROM nz_addresses.v_districts
            WHERE region_id = @RegionId
            ORDER BY display_name";

        var districts = await connection.QueryAsync<DistrictDto>(sql, new { RegionId = regionId });
        return districts;
    }

    public async Task<IEnumerable<SuburbDto>> GetSuburbsAsync(string districtId)
    {
        using var connection = new NpgsqlConnection(_connectionString);
        
        var sql = @"
            SELECT 
                suburb_id AS SuburbId,
                district_id AS DistrictId,
                name AS Name,
                NULL AS NameAscii,
                name AS MajorName,
                COALESCE(street_count, 0) AS StreetCount,
                is_major_suburb AS IsMajorSuburb,
                population_category AS PopulationCategory
            FROM nz_addresses.v_suburbs
            WHERE district_id = @DistrictId
            ORDER BY sort_priority, name";

        var suburbs = await connection.QueryAsync<SuburbDto>(sql, new { DistrictId = districtId });
        return suburbs;
    }

    public async Task<IEnumerable<StreetDto>> GetStreetsAsync(string suburbId)
    {
        using var connection = new NpgsqlConnection(_connectionString);
        
        var sql = @"
            SELECT 
                street_name AS StreetName
            FROM nz_addresses.streets_by_suburb
            WHERE suburb_id = @SuburbId
            ORDER BY street_name";

        var streets = await connection.QueryAsync<StreetDto>(sql, new { SuburbId = suburbId });
        return streets;
    }

    public async Task<AddressVerificationResult> VerifyAsync(string rawAddress)
    {
        if (string.IsNullOrWhiteSpace(rawAddress))
        {
            return new AddressVerificationResult
            {
                ExistsInLinz = false,
                AddressId = null,
                FullAddress = null,
                X = null,
                Y = null,
                RegionId = null,
                DistrictId = null,
                SuburbId = null,
                Message = "Address cannot be empty"
            };
        }

        try
        {
            // Normalize the input address
            var normalized = _normalizer.Normalize(rawAddress);
            
            _logger.LogInformation("Verifying address: '{RawAddress}' -> normalized: '{Normalized}'", 
                rawAddress, normalized);

            // Count tokens to determine strategy
            var tokens = normalized.Split(' ', StringSplitOptions.RemoveEmptyEntries);
            var hasMultipleWords = tokens.Length >= 3; // e.g. "61 Otonga Rotorua"

            // If we have number + street + city (3+ tokens), try smart partial match first
            // This ensures city-based filtering works properly
            if (hasMultipleWords)
            {
                var smartMatch = await TrySmartPartialMatch(normalized, rawAddress);
                if (smartMatch != null)
                {
                    return smartMatch;
                }
            }

            // Try exact match
            var exactMatch = await TryExactMatch(normalized);
            if (exactMatch != null)
            {
                return exactMatch;
            }

            // Try smart partial match if we haven't already
            if (!hasMultipleWords)
            {
                var smartMatch = await TrySmartPartialMatch(normalized, rawAddress);
                if (smartMatch != null)
                {
                    return smartMatch;
                }
            }

            // Fallback to fuzzy match
            var fuzzyMatch = await TryFuzzyMatch(normalized);
            if (fuzzyMatch != null)
            {
                return fuzzyMatch;
            }

            return new AddressVerificationResult
            {
                ExistsInLinz = false,
                AddressId = null,
                FullAddress = null,
                X = null,
                Y = null,
                RegionId = null,
                DistrictId = null,
                SuburbId = null,
                Message = "Address not found in LINZ data"
            };
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error verifying address: {RawAddress}", rawAddress);
            
            return new AddressVerificationResult
            {
                ExistsInLinz = false,
                AddressId = null,
                FullAddress = null,
                X = null,
                Y = null,
                RegionId = null,
                DistrictId = null,
                SuburbId = null,
                Message = $"Verification error: {ex.Message}"
            };
        }
    }

    private async Task<AddressVerificationResult?> TryExactMatch(string normalized)
    {
        using var connection = new NpgsqlConnection(_connectionString);

        // Extract address number from normalized string
        var tokens = normalized.Split(' ', StringSplitOptions.RemoveEmptyEntries);
        int? addressNumber = null;
        string? roadName = null;

        foreach (var token in tokens)
        {
            if (int.TryParse(token, out var num))
            {
                addressNumber = num;
                break;
            }
        }

        if (addressNumber == null)
        {
            return null;
        }

        // Build road name from remaining tokens
        // Only take first word as street name to avoid including city/suburb names
        // This makes exact match very conservative - smartmatch will handle the rest
        var roadTokens = tokens.Where(t => !int.TryParse(t, out _)).Take(1).ToArray();
        roadName = string.Join(" ", roadTokens);

        var sql = @"
            SELECT 
                address_id AS ""AddressId"",
                full_address AS ""FullAddress"",
                x_coord AS ""X"",
                y_coord AS ""Y"",
                ST_X(geom) AS ""GeomX"",
                ST_Y(geom) AS ""GeomY""
            FROM nz_addresses.addresses
            WHERE address_number = @AddressNumber
                AND (
                    full_road_name_ascii ILIKE '%' || @RoadName || '%'
                    OR full_road_name ILIKE '%' || @RoadName || '%'
                )
            LIMIT 1";

        var result = await connection.QueryFirstOrDefaultAsync<dynamic>(
            sql, 
            new { AddressNumber = addressNumber, RoadName = roadName }
        );

        if (result == null)
        {
            return null;
        }

        // Check if geometry coordinates are available
        if (result.GeomX == null || result.GeomY == null)
        {
            _logger.LogWarning("Address found but missing geometry in exact match: {AddressId}", (int?)result.AddressId);
            return new AddressVerificationResult
            {
                ExistsInLinz = true,
                AddressId = result.AddressId,
                FullAddress = result.FullAddress,
                X = result.X,
                Y = result.Y,
                RegionId = null,
                DistrictId = null,
                SuburbId = null,
                Message = "Address found but missing spatial data"
            };
        }

        // Resolve hierarchy
        var hierarchy = await ResolveHierarchy(connection, (double)result.GeomX, (double)result.GeomY);

        return new AddressVerificationResult
        {
            ExistsInLinz = true,
            AddressId = result.AddressId,
            FullAddress = result.FullAddress,
            X = result.X,
            Y = result.Y,
            RegionId = hierarchy.RegionId,
            DistrictId = hierarchy.DistrictId,
            SuburbId = hierarchy.SuburbId,
            Message = "Match found"
        };
    }

    private async Task<AddressVerificationResult?> TrySmartPartialMatch(string normalized, string rawAddress)
    {
        using var connection = new NpgsqlConnection(_connectionString);

        // Extract components from the input
        var tokens = normalized.Split(' ', StringSplitOptions.RemoveEmptyEntries);
        int? addressNumber = null;
        var nonNumberTokens = new List<string>();

        foreach (var token in tokens)
        {
            if (addressNumber == null && int.TryParse(token, out var num))
            {
                addressNumber = num;
            }
            else if (addressNumber.HasValue)
            {
                nonNumberTokens.Add(token);
            }
        }

        if (addressNumber == null || nonNumberTokens.Count == 0)
        {
            return null;
        }

        // Common road type suffixes that should be included in street name
        var roadTypes = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
        {
            "street", "st", "road", "rd", "avenue", "ave", "drive", "dr",
            "lane", "ln", "place", "pl", "terrace", "tce", "way", "crescent",
            "cres", "grove", "court", "ct", "parade", "highway", "hwy"
        };

        // Try 1-word street first, then 2-word if first fails
        // Example: "61 Otonga Rotorua" → try street="Otonga", city="Rotorua" first
        // Example: "1 Queen Street Auckland" → try street="Queen Street", city="Auckland"
        string streetName;
        string? cityName;

        if (nonNumberTokens.Count == 1)
        {
            // Only street name, no city
            streetName = nonNumberTokens[0];
            cityName = null;
        }
        else if (nonNumberTokens.Count == 2)
        {
            // Check if second word is a road type
            if (roadTypes.Contains(nonNumberTokens[1]))
            {
                // "Queen Street" - both words are the street
                streetName = string.Join(" ", nonNumberTokens);
                cityName = null;
            }
            else
            {
                // "Otonga Rotorua" - first is street, second is city
                streetName = nonNumberTokens[0];
                cityName = nonNumberTokens[1];
            }
        }
        else
        {
            // 3+ words: check if second word is a road type
            if (roadTypes.Contains(nonNumberTokens[1]))
            {
                // "Queen Street Auckland" - first two are street, rest is city
                streetName = string.Join(" ", nonNumberTokens.Take(2));
                cityName = string.Join(" ", nonNumberTokens.Skip(2));
            }
            else
            {
                // "Otonga Road Rotorua" or "Chaytors Spring Creek"
                // Try 1-word street first
                streetName = nonNumberTokens[0];
                cityName = string.Join(" ", nonNumberTokens.Skip(1));
            }
        }

        var result = await TryPartialMatchWithParts(connection, rawAddress, addressNumber.Value, streetName, cityName);
        
        // If no result and we have 3+ words without a road type, try 2-word street name as fallback
        // This handles cases like "Chaytors Spring Creek" → try "Chaytors Spring" as street
        if (result == null && nonNumberTokens.Count >= 3 && !roadTypes.Contains(nonNumberTokens[1]))
        {
            streetName = string.Join(" ", nonNumberTokens.Take(2));
            cityName = string.Join(" ", nonNumberTokens.Skip(2));
            result = await TryPartialMatchWithParts(connection, rawAddress, addressNumber.Value, streetName, cityName);
        }

        return result;
    }

    private async Task<AddressVerificationResult?> TryPartialMatchWithParts(
        NpgsqlConnection connection, 
        string rawAddress, 
        int addressNumber, 
        string streetName, 
        string? cityName)
    {
        string sql;
        object parameters;

        if (string.IsNullOrEmpty(cityName))
        {
            // No city - find any match
            sql = @"
                SELECT 
                    address_id AS ""AddressId"",
                    full_address AS ""FullAddress"",
                    x_coord AS ""X"",
                    y_coord AS ""Y"",
                    ST_X(geom) AS ""GeomX"",
                    ST_Y(geom) AS ""GeomY""
                FROM nz_addresses.addresses
                WHERE address_number = @AddressNumber
                    AND (
                        full_road_name_ascii ILIKE '%' || @StreetName || '%'
                        OR full_road_name ILIKE '%' || @StreetName || '%'
                    )
                LIMIT 5";
            
            parameters = new { AddressNumber = addressNumber, StreetName = streetName };
        }
        else
        {
            // City provided - prioritize matches
            sql = @"
                SELECT 
                    address_id AS ""AddressId"",
                    full_address AS ""FullAddress"",
                    x_coord AS ""X"",
                    y_coord AS ""Y"",
                    ST_X(geom) AS ""GeomX"",
                    ST_Y(geom) AS ""GeomY"",
                    CASE 
                        WHEN suburb_locality ILIKE '%' || @CityName || '%' 
                            OR town_city ILIKE '%' || @CityName || '%' THEN 1
                        ELSE 2
                    END AS ""Priority"",
                    CASE
                        WHEN full_road_name = @StreetName THEN 1
                        WHEN full_road_name ILIKE @StreetName || '%' THEN 2
                        ELSE 3
                    END AS ""StreetMatchQuality""
                FROM nz_addresses.addresses
                WHERE address_number = @AddressNumber
                    AND (
                        full_road_name_ascii ILIKE '%' || @StreetName || '%'
                        OR full_road_name ILIKE '%' || @StreetName || '%'
                    )
                ORDER BY ""Priority"", ""StreetMatchQuality"", address_id
                LIMIT 5";
            
            parameters = new { AddressNumber = addressNumber, StreetName = streetName, CityName = cityName };
        }

        var results = await connection.QueryAsync<dynamic>(sql, parameters);
        var resultList = results.ToList();

        if (resultList.Count == 0)
        {
            return null;
        }

        // Pick the best result
        dynamic selectedResult;
        if (resultList.Count == 1)
        {
            selectedResult = resultList[0];
        }
        else if (!string.IsNullOrEmpty(cityName))
        {
            // Prefer priority 1 (city match)
            var cityMatches = resultList.Where(r => r.Priority == 1).ToList();
            selectedResult = cityMatches.Any() ? cityMatches.First() : resultList[0];
        }
        else
        {
            selectedResult = resultList[0];
        }

        // Check geometry
        if (selectedResult.GeomX == null || selectedResult.GeomY == null)
        {
            return new AddressVerificationResult
            {
                ExistsInLinz = true,
                AddressId = selectedResult.AddressId,
                FullAddress = selectedResult.FullAddress,
                X = selectedResult.X,
                Y = selectedResult.Y,
                RegionId = null,
                DistrictId = null,
                SuburbId = null,
                Message = resultList.Count == 1 ? "Unique match found" : $"Match found ({resultList.Count} matches)"
            };
        }

        // Resolve hierarchy
        var hierarchy = await ResolveHierarchy(connection, (double)selectedResult.GeomX, (double)selectedResult.GeomY);

        return new AddressVerificationResult
        {
            ExistsInLinz = true,
            AddressId = selectedResult.AddressId,
            FullAddress = selectedResult.FullAddress,
            X = selectedResult.X,
            Y = selectedResult.Y,
            RegionId = hierarchy.RegionId,
            DistrictId = hierarchy.DistrictId,
            SuburbId = hierarchy.SuburbId,
            Message = resultList.Count == 1 ? "Unique match found" : $"Match found ({resultList.Count} matches)"
        };
    }

    private async Task<AddressVerificationResult?> TryFuzzyMatch(string normalized)
    {
        using var connection = new NpgsqlConnection(_connectionString);

        var sql = @"
            SELECT 
                address_id AS ""AddressId"",
                full_address AS ""FullAddress"",
                full_address_ascii AS ""FullAddressAscii"",
                x_coord AS ""X"",
                y_coord AS ""Y"",
                ST_X(geom) AS ""GeomX"",
                ST_Y(geom) AS ""GeomY"",
                similarity(full_address_ascii, @Normalized) AS ""sim""
            FROM nz_addresses.addresses
            WHERE full_address_ascii IS NOT NULL
                AND similarity(full_address_ascii, @Normalized) > 0.6
            ORDER BY sim DESC
            LIMIT 1";

        var result = await connection.QueryFirstOrDefaultAsync<dynamic>(
            sql,
            new { Normalized = normalized }
        );

        if (result == null)
        {
            return null;
        }

        // Check if geometry coordinates are available
        if (result.GeomX == null || result.GeomY == null)
        {
            _logger.LogWarning("Address found but missing geometry in fuzzy match: {AddressId}", (int?)result.AddressId);
            return new AddressVerificationResult
            {
                ExistsInLinz = true,
                AddressId = result.AddressId,
                FullAddress = result.FullAddress,
                X = result.X,
                Y = result.Y,
                RegionId = null,
                DistrictId = null,
                SuburbId = null,
                Message = $"Address found (similarity: {result.sim:F2}) but missing spatial data"
            };
        }

        // Resolve hierarchy
        var hierarchy = await ResolveHierarchy(connection, (double)result.GeomX, (double)result.GeomY);

        return new AddressVerificationResult
        {
            ExistsInLinz = true,
            AddressId = result.AddressId,
            FullAddress = result.FullAddress,
            X = result.X,
            Y = result.Y,
            RegionId = hierarchy.RegionId,
            DistrictId = hierarchy.DistrictId,
            SuburbId = hierarchy.SuburbId,
            Message = $"Fuzzy match found (similarity: {result.sim:F2})"
        };
    }

    private async Task<(string? RegionId, string? DistrictId, string? SuburbId)> ResolveHierarchy(
        NpgsqlConnection connection,
        double x,
        double y)
    {
        var sql = @"
            SELECT 
                region_id AS ""RegionId"",
                district_id AS ""DistrictId"",
                suburb_id AS ""SuburbId""
            FROM nz_addresses.resolve_hierarchy(
                ST_SetSRID(ST_MakePoint(@X, @Y), 2193)
            )";

        var result = await connection.QueryFirstOrDefaultAsync<dynamic>(
            sql,
            new { X = x, Y = y }
        );

        return (result?.RegionId, result?.DistrictId, result?.SuburbId);
    }

    public async Task<AddressVerificationResult> GetAddressForCoordinatesAsync(double latitude, double longitude)
    {
        try
        {
            using var connection = new NpgsqlConnection(_connectionString);

            // Find the nearest address to the given coordinates using PostGIS
            var sql = @"
                SELECT 
                    address_id AS ""AddressId"",
                    full_address AS ""FullAddress"",
                    x_coord AS ""X"",
                    y_coord AS ""Y"",
                    ST_X(geom) AS ""GeomX"",
                    ST_Y(geom) AS ""GeomY"",
                    ST_Distance(
                        geom, 
                        ST_Transform(ST_SetSRID(ST_MakePoint(@Longitude, @Latitude), 4326), 2193)
                    ) AS distance_meters
                FROM nz_addresses.addresses
                WHERE geom IS NOT NULL
                ORDER BY geom <-> ST_Transform(ST_SetSRID(ST_MakePoint(@Longitude, @Latitude), 4326), 2193)
                LIMIT 1";

            var result = await connection.QueryFirstOrDefaultAsync<dynamic>(
                sql,
                new { Latitude = latitude, Longitude = longitude }
            );

            if (result == null)
            {
                return new AddressVerificationResult
                {
                    ExistsInLinz = false,
                    Message = "No address found near the specified coordinates"
                };
            }

            // Check distance - if more than 100 meters, it might not be accurate
            var distanceMeters = (double)result.distance_meters;
            var warning = distanceMeters > 100 
                ? $" (Warning: Nearest address is {distanceMeters:F0}m away)" 
                : "";

            // Resolve hierarchy
            var hierarchy = await ResolveHierarchy(connection, (double)result.GeomX, (double)result.GeomY);

            return new AddressVerificationResult
            {
                ExistsInLinz = true,
                AddressId = result.AddressId,
                FullAddress = result.FullAddress,
                X = result.X,
                Y = result.Y,
                RegionId = hierarchy.RegionId,
                DistrictId = hierarchy.DistrictId,
                SuburbId = hierarchy.SuburbId,
                Message = $"Nearest address found{warning}"
            };
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error finding address for coordinates: {Latitude}, {Longitude}", latitude, longitude);
            
            return new AddressVerificationResult
            {
                ExistsInLinz = false,
                Message = $"Error finding address: {ex.Message}"
            };
        }
    }

    public async Task<CoordinatesResult> GetCoordinatesForAddressAsync(string rawAddress)
    {
        try
        {
            // First verify the address
            var verification = await VerifyAsync(rawAddress);

            if (!verification.ExistsInLinz || verification.X == null || verification.Y == null)
            {
                return new CoordinatesResult
                {
                    Success = false,
                    Latitude = null,
                    Longitude = null,
                    AddressDetails = verification,
                    Message = verification.Message
                };
            }

            return new CoordinatesResult
            {
                Success = true,
                Latitude = verification.Y,
                Longitude = verification.X,
                AddressDetails = verification,
                Message = "Coordinates found successfully"
            };
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting coordinates for address: {RawAddress}", rawAddress);
            
            return new CoordinatesResult
            {
                Success = false,
                Message = $"Error getting coordinates: {ex.Message}"
            };
        }
    }

    public async Task<IEnumerable<AutocompleteResult>> AutocompleteAsync(string query, int limit = 10)
    {
        if (string.IsNullOrWhiteSpace(query) || query.Length < 3)
            return Enumerable.Empty<AutocompleteResult>();

        if (limit is < 1 or > 50)
            limit = 10;

        var normalised = query.Trim();

        const string sql = """
            SELECT address_id   AS AddressId,
                   full_address AS FullAddress,
                   full_road_name AS StreetName,
                   suburb_locality AS Suburb,
                   town_city    AS City
            FROM   nz_addresses.addresses
            WHERE  full_address_ascii ILIKE @Pattern
            ORDER  BY
                   CASE WHEN full_address_ascii ILIKE @StartsWith THEN 0 ELSE 1 END,
                   full_address_ascii
            LIMIT  @Limit
            """;

        await using var conn = new NpgsqlConnection(_connectionString);
        var results = await conn.QueryAsync<AutocompleteResult>(sql, new
        {
            Pattern = $"%{normalised}%",
            StartsWith = $"{normalised}%",
            Limit = limit
        });

        return results;
    }
}
