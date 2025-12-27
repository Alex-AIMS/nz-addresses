using NzAddresses.Domain.Dtos;

namespace NzAddresses.Core.Services;

public interface INzAddressService
{
    Task<IEnumerable<RegionDto>> GetRegionsAsync();
    Task<IEnumerable<DistrictDto>> GetDistrictsAsync(string regionId);
    Task<IEnumerable<SuburbDto>> GetSuburbsAsync(string districtId);
    Task<IEnumerable<StreetDto>> GetStreetsAsync(string suburbId);
    Task<AddressVerificationResult> VerifyAsync(string rawAddress);
    Task<AddressVerificationResult> GetAddressForCoordinatesAsync(double latitude, double longitude);
    Task<CoordinatesResult> GetCoordinatesForAddressAsync(string rawAddress);
}
