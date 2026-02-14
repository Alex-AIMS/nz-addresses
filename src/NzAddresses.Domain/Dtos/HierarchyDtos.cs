namespace NzAddresses.Domain.Dtos;

public class RegionDto
{
    public string RegionId { get; set; } = string.Empty;
    public string Name { get; set; } = string.Empty;
    public int DistrictCount { get; set; }
}

public class DistrictDto
{
    public string DistrictId { get; set; } = string.Empty;
    public string RegionId { get; set; } = string.Empty;
    public string Name { get; set; } = string.Empty;
    public int SuburbCount { get; set; }
}

public class SuburbDto
{
    public string SuburbId { get; set; } = string.Empty;
    public string DistrictId { get; set; } = string.Empty;
    public string Name { get; set; } = string.Empty;
    public string? NameAscii { get; set; }
    public string? MajorName { get; set; }
    public int StreetCount { get; set; }
    public bool IsMajorSuburb { get; set; }
    public string PopulationCategory { get; set; } = "unknown";
}

public class StreetDto
{
    public string StreetName { get; set; } = string.Empty;
}

public class AddressVerificationResult
{
    public bool ExistsInLinz { get; set; }
    public long? AddressId { get; set; }
    public string? FullAddress { get; set; }
    public double? X { get; set; }
    public double? Y { get; set; }
    public string? RegionId { get; set; }
    public string? DistrictId { get; set; }
    public string? SuburbId { get; set; }
    public string Message { get; set; } = string.Empty;
}

public class CoordinatesResult
{
    public bool Success { get; set; }
    public double? Latitude { get; set; }
    public double? Longitude { get; set; }
    public AddressVerificationResult? AddressDetails { get; set; }
    public string Message { get; set; } = string.Empty;
}

public class AddressAutocompleteResult
{
    public long AddressId { get; set; }
    public string FullAddress { get; set; } = string.Empty;
    public string? StreetName { get; set; }
    public string? Suburb { get; set; }
    public string? City { get; set; }
    public double X { get; set; }
    public double Y { get; set; }
}
