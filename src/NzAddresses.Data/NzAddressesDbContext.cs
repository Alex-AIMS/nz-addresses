using Microsoft.EntityFrameworkCore;
using NzAddresses.Domain.Entities;

namespace NzAddresses.Data;

public class NzAddressesDbContext : DbContext
{
    public NzAddressesDbContext(DbContextOptions<NzAddressesDbContext> options)
        : base(options)
    {
    }

    public DbSet<Region> Regions => Set<Region>();
    public DbSet<District> Districts => Set<District>();
    public DbSet<Suburb> Suburbs => Set<Suburb>();
    public DbSet<Address> Addresses => Set<Address>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        base.OnModelCreating(modelBuilder);

        modelBuilder.HasDefaultSchema("nz_addresses");

        // Region entity configuration
        modelBuilder.Entity<Region>(entity =>
        {
            entity.ToTable("regions");
            entity.HasKey(e => e.RegionId);
            entity.Property(e => e.RegionId).HasColumnName("region_id").HasMaxLength(10);
            entity.Property(e => e.Name).HasColumnName("name").HasMaxLength(200).IsRequired();
            entity.Property(e => e.Geom).HasColumnName("geom").HasColumnType("geometry(Polygon,2193)");

            entity.HasMany(e => e.Districts)
                .WithOne(e => e.Region)
                .HasForeignKey(e => e.RegionId)
                .OnDelete(DeleteBehavior.Restrict);
        });

        // District entity configuration
        modelBuilder.Entity<District>(entity =>
        {
            entity.ToTable("districts");
            entity.HasKey(e => e.DistrictId);
            entity.Property(e => e.DistrictId).HasColumnName("district_id").HasMaxLength(10);
            entity.Property(e => e.RegionId).HasColumnName("region_id").HasMaxLength(10).IsRequired();
            entity.Property(e => e.Name).HasColumnName("name").HasMaxLength(200).IsRequired();
            entity.Property(e => e.Geom).HasColumnName("geom").HasColumnType("geometry(Polygon,2193)");

            entity.HasMany(e => e.Suburbs)
                .WithOne(e => e.District)
                .HasForeignKey(e => e.DistrictId)
                .OnDelete(DeleteBehavior.Restrict);
        });

        // Suburb entity configuration
        modelBuilder.Entity<Suburb>(entity =>
        {
            entity.ToTable("suburbs");
            entity.HasKey(e => e.SuburbId);
            entity.Property(e => e.SuburbId).HasColumnName("suburb_id").HasMaxLength(50);
            entity.Property(e => e.DistrictId).HasColumnName("district_id").HasMaxLength(10).IsRequired();
            entity.Property(e => e.Name).HasColumnName("name").HasMaxLength(200).IsRequired();
            entity.Property(e => e.NameAscii).HasColumnName("name_ascii").HasMaxLength(200);
            entity.Property(e => e.MajorName).HasColumnName("major_name").HasMaxLength(200);
            entity.Property(e => e.Geom).HasColumnName("geom").HasColumnType("geometry(Polygon,2193)");
        });

        // Address entity configuration
        modelBuilder.Entity<Address>(entity =>
        {
            entity.ToTable("addresses");
            entity.HasKey(e => e.AddressId);
            entity.Property(e => e.AddressId).HasColumnName("address_id");
            entity.Property(e => e.FullAddress).HasColumnName("full_address");
            entity.Property(e => e.FullAddressAscii).HasColumnName("full_address_ascii");
            entity.Property(e => e.FullRoadName).HasColumnName("full_road_name").HasMaxLength(200);
            entity.Property(e => e.FullRoadNameAscii).HasColumnName("full_road_name_ascii").HasMaxLength(200);
            entity.Property(e => e.AddressNumberPrefix).HasColumnName("address_number_prefix").HasMaxLength(10);
            entity.Property(e => e.AddressNumber).HasColumnName("address_number");
            entity.Property(e => e.AddressNumberSuffix).HasColumnName("address_number_suffix").HasMaxLength(10);
            entity.Property(e => e.SuburbLocality).HasColumnName("suburb_locality").HasMaxLength(200);
            entity.Property(e => e.SuburbLocalityAscii).HasColumnName("suburb_locality_ascii").HasMaxLength(200);
            entity.Property(e => e.TownCity).HasColumnName("town_city").HasMaxLength(200);
            entity.Property(e => e.TerritorialAuthority).HasColumnName("territorial_authority").HasMaxLength(200);
            entity.Property(e => e.XCoord).HasColumnName("x_coord");
            entity.Property(e => e.YCoord).HasColumnName("y_coord");
            entity.Property(e => e.Geom).HasColumnName("geom").HasColumnType("geometry(Point,2193)");
        });
    }
}
