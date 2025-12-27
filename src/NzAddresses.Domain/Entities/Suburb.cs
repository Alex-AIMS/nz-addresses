using NetTopologySuite.Geometries;

namespace NzAddresses.Domain.Entities;

public class Suburb
{
    public string SuburbId { get; set; } = string.Empty;
    public string DistrictId { get; set; } = string.Empty;
    public string Name { get; set; } = string.Empty;
    public string? NameAscii { get; set; }
    public string? MajorName { get; set; }
    public Polygon? Geom { get; set; }

    public District? District { get; set; }
}
