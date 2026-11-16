export type MapPlace = Readonly<{ id: string; title: string; lat: number; lng: number;
  image?: string; url?: string; description?: string }>;

// The same declared CRS conversion used by the existing OpenUI component.
export function toWGS84(lat: number, lng: number, crs: string): [number, number] {
  if (crs !== 'gcj02' || lng < 72.004 || lng > 137.8347 || lat < 0.8293 || lat > 55.8271) return [lng, lat];
  const project = (latitude: number, longitude: number): [number, number] => {
    const x = longitude - 105, y = latitude - 35, pi = Math.PI;
    let dLat = -100 + 2 * x + 3 * y + 0.2 * y * y + 0.1 * x * y + 0.2 * Math.sqrt(Math.abs(x));
    dLat += (20 * Math.sin(6 * x * pi) + 20 * Math.sin(2 * x * pi)) * 2 / 3
      + (20 * Math.sin(y * pi) + 40 * Math.sin(y * pi / 3)) * 2 / 3
      + (160 * Math.sin(y * pi / 12) + 320 * Math.sin(y * pi / 30)) * 2 / 3;
    let dLng = 300 + x + 2 * y + 0.1 * x * x + 0.1 * x * y + 0.1 * Math.sqrt(Math.abs(x));
    dLng += (20 * Math.sin(6 * x * pi) + 20 * Math.sin(2 * x * pi)) * 2 / 3
      + (20 * Math.sin(x * pi) + 40 * Math.sin(x * pi / 3)) * 2 / 3
      + (150 * Math.sin(x * pi / 12) + 300 * Math.sin(x * pi / 30)) * 2 / 3;
    const rad = latitude * pi / 180, axis = 6378245, e = 0.00669342162296594323;
    const magic = 1 - e * Math.sin(rad) ** 2;
    dLat = dLat * 180 / (axis * (1 - e) / (magic * Math.sqrt(magic)) * pi);
    dLng = dLng * 180 / (axis / Math.sqrt(magic) * Math.cos(rad) * pi);
    return [longitude + dLng, latitude + dLat];
  };
  let estimateLat = lat, estimateLng = lng;
  for (let iteration = 0; iteration < 10; iteration += 1) {
    const [projectedLng, projectedLat] = project(estimateLat, estimateLng);
    const deltaLat = projectedLat - lat, deltaLng = projectedLng - lng;
    estimateLat -= deltaLat; estimateLng -= deltaLng;
    if (Math.max(Math.abs(deltaLat), Math.abs(deltaLng)) < 1e-9) break;
  }
  return [estimateLng, estimateLat];
}

export function mapPlaces(value: unknown, crs = 'wgs84'): MapPlace[] {
  if (!Array.isArray(value) || !['wgs84', 'gcj02'].includes(crs)) return [];
  const seen = new Set<string>();
  return value.flatMap(item => {
    if (!item || item.type !== 'element' || item.typeName !== 'MapPoint' || item.partial) return [];
    const p = item.props;
    if (!p || typeof p.title !== 'string' || !p.title.trim() || typeof p.lat !== 'number' || typeof p.lng !== 'number'
      || !Number.isFinite(p.lat) || !Number.isFinite(p.lng) || Math.abs(p.lat) > 90 || Math.abs(p.lng) > 180) return [];
    const id = JSON.stringify([p.title, p.lat, p.lng]);
    if (seen.has(id)) return [];
    seen.add(id);
    const [lng, lat] = toWGS84(p.lat, p.lng, crs);
    return [{ id, title: p.title, lat, lng, image: typeof p.imageSrc === 'string' ? p.imageSrc : undefined,
      url: typeof p.url === 'string' ? p.url : undefined, description: typeof p.description === 'string' ? p.description : undefined }];
  });
}

/** Fit the short interval across the date line instead of almost the whole world. */
export function mapBounds(places: readonly MapPlace[]): [number, number, number, number] | undefined {
  if (!places.length) return;
  const longitudes = places.map(place => (place.lng + 360) % 360).sort((a, b) => a - b);
  let gap = -1, start = 0;
  for (let index = 0; index < longitudes.length; index += 1) {
    const next = longitudes[(index + 1) % longitudes.length] + (index === longitudes.length - 1 ? 360 : 0);
    if (next - longitudes[index] > gap) { gap = next - longitudes[index]; start = (index + 1) % longitudes.length; }
  }
  let west = longitudes[start], east = west + 360 - gap;
  if (west > 180) { west -= 360; east -= 360; }
  const clamp = (latitude: number) => Math.max(-85.0511, Math.min(85.0511, latitude));
  const south = clamp(Math.min(...places.map(place => place.lat)));
  const north = clamp(Math.max(...places.map(place => place.lat)));
  return [west, Math.min(south, north), east, Math.max(south, north)];
}
