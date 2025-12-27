using NetTopologySuite.Geometries;

namespace NzAddresses.Domain.Entities;

public class Address
{
    public long AddressId { get; set; }
    public string? FullAddress { get; set; }
    public string? FullAddressAscii { get; set; }
    public string? FullRoadName { get; set; }
    public string? FullRoadNameAscii { get; set; }
    public string? AddressNumberPrefix { get; set; }
    public int? AddressNumber { get; set; }
    public string? AddressNumberSuffix { get; set; }
    public string? SuburbLocality { get; set; }
    public string? SuburbLocalityAscii { get; set; }
    public string? TownCity { get; set; }
    public string? TerritorialAuthority { get; set; }
    public double? XCoord { get; set; }
    public double? YCoord { get; set; }
    public Point? Geom { get; set; }
}
