import assert from 'node:assert/strict';
import { test } from 'node:test';
import { mapBounds, mapPlaces, toWGS84 } from '../src/library/components/mapData';

const point = (title: string, lat: number, lng: number) => ({ type: 'element', typeName: 'MapPoint', props: { title, lat, lng } });

test('map identity survives reordering, duplicates collapse and invalid/partial coordinates remain inert', () => {
  const a = point('西湖', 30.242637, 120.134544), b = point('德寿宫', 30.2412, 120.16862);
  const first = mapPlaces([a, b, a, point('invalid', 91, 0), point('bad', Number.NaN, 0), { ...b, partial: true }]);
  assert.equal(first.length, 2);
  const reversed = mapPlaces([b, a]);
  assert.equal(first[0].id, reversed[1].id);
  assert.deepEqual(mapPlaces([a], 'unknown'), []);
  assert.equal(mapPlaces(Array.from({ length: 600 }, (_, index) => point(`Place ${index}`, 30, 100 + index / 1000))).length, 600);
});

test('declared CRS changes only mainland GCJ02 coordinates and uses stable WGS84 values', () => {
  assert.deepEqual(toWGS84(30, 120, 'wgs84'), [120, 30]);
  assert.deepEqual(toWGS84(51.5074, -0.1278, 'gcj02'), [-0.1278, 51.5074]);
  const [lng, lat] = toWGS84(30.242637, 120.134544, 'gcj02');
  assert.ok(lng < 120.134544 && lng > 120.12);
  assert.ok(lat > 30.242637 && lat < 30.25);
  assert.deepEqual(toWGS84(30.242637, 120.134544, 'gcj02'), [lng, lat]);
});

test('map bounds fit the short date-line interval and handle empty/single/polar data', () => {
  assert.equal(mapBounds([]), undefined);
  const crossing = mapBounds(mapPlaces([point('east', 10, 179.5), point('west', 11, -179.5)]))!;
  assert.equal(crossing[2] - crossing[0], 1);
  assert.deepEqual(crossing.slice(1, 2), [10]);
  const single = mapBounds(mapPlaces([point('one', 20, -20)]))!;
  assert.deepEqual(single, [-20, 20, -20, 20]);
  const pole = mapBounds(mapPlaces([point('north', 90, 0)]))!;
  assert.ok(pole[1] <= 85.0511 && pole[3] <= 85.0511);
});
