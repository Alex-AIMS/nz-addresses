using NetTopologySuite.Geometries;

namespace NzAddresses.Domain.Entities;

public class District
{
    public string DistrictId { get; set; } = string.Empty;
    public string RegionId { get; set; } = string.Empty;
    public string Name { get; set; } = string.Empty;
    public Polygon? Geom { get; set; }

    public Region? Region { get; set; }
    public ICollection<Suburb> Suburbs { get; set; } = new List<Suburb>();
}
