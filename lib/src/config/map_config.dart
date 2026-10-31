/// Inject this configuration when changing map providers. The attribution must
/// match the provider's terms. Public OSM tiles are for modest demo usage only.
class MapConfig {
  const MapConfig({
    this.tileUrl = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
    this.attribution = '© OpenStreetMap contributors',
    this.attributionUrl = 'https://www.openstreetmap.org/copyright',
    this.userAgentPackageName = 'ph.jeeplink.passenger.demo',
  });

  final String tileUrl;
  final String attribution;
  final String attributionUrl;
  final String userAgentPackageName;
}
