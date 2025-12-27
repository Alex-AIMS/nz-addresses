using NetTopologySuite.Geometries;

namespace NzAddresses.Domain.Entities;

public class Region
{
    public string RegionId { get; set; } = string.Empty;
    public string Name { get; set; } = string.Empty;
    public Polygon? Geom { get; set; }

    public ICollection<District> Districts { get; set; } = new List<District>();
}
