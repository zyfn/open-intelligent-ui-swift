import assert from 'node:assert/strict';
import test from 'node:test';
import {
  chartArcPath, chartDomain, chartLinePath, chartSectorPath, positiveFractions, project,
} from '../src/library/components/chartGeometry';

test('stacked domains add positive and negative values independently', () => {
  const series = [{ name: 'A', values: [-3, 5] }, { name: 'B', values: [-2, 2] }];
  assert.deepEqual(chartDomain(series, 2, false), { low: -3, high: 5 });
  assert.deepEqual(chartDomain(series, 2, true), { low: -5, high: 7 });
  assert.deepEqual(chartDomain([{ name: 'zero', values: [0, 0] }], 2, false), { low: 0, high: 1 });
});

test('a finite mixed-sign domain stays finite near the number limit', () => {
  const domain = { low: -1e308, high: 1e308 };
  assert.equal(project(-1e308, domain, 0, 100), 0);
  assert.equal(project(0, domain, 0, 100), 50);
  assert.equal(project(1e308, domain, 0, 100), 100);
  assert.equal(project(0, domain, 100, 0), 50);
  assert.equal(chartDomain([{ name: 'A', values: [1e308] }, { name: 'B', values: [1e308] }], 1, true), undefined);
  assert.equal(chartDomain([{ name: 'short', values: [1] }], 2, false), undefined);
});

test('linear, midpoint step and natural cubic interpolation produce distinct paths', () => {
  const points = [{ x: 0, y: 0 }, { x: 3, y: 6 }, { x: 6, y: 0 }];
  assert.equal(chartLinePath(points, 'linear'), 'M0,0 L3,6 L6,0');
  assert.equal(chartLinePath(points, 'step'), 'M0,0 H1.5 V6 H3 H4.5 V0 H6');
  // Natural endpoint curvature is zero; this distinguishes it from a cardinal curve.
  assert.equal(chartLinePath(points, 'natural'), 'M0,0 C1,3 2,6 3,6 C4,6 5,3 6,0');
  assert.equal(chartLinePath([{ x: 1, y: 2 }], 'natural'), 'M1,2');
  assert.equal(chartLinePath([], 'natural'), '');
});

test('a complete circle and donut have explicit nondegenerate arc segments', () => {
  const center = { x: 100, y: 100 };
  const circle = chartArcPath(center, 80, -90, 270);
  const donut = chartSectorPath(center, 80, 40, -90, 270);
  assert.equal(circle.match(/ A/g)?.length, 2);
  assert.equal(donut.match(/ A/g)?.length, 4);
  assert.match(donut, / Z$/);
  assert.doesNotMatch(circle + donut, /NaN|Infinity/);
  assert.equal(chartSectorPath(center, 80, 40, 10, 10), '');
});

test('proportions normalize before summing large finite numbers', () => {
  assert.deepEqual(positiveFractions([1e308, 1e308]), [0.5, 0.5]);
  assert.deepEqual(positiveFractions([0, 0]), [0, 0]);
  assert.deepEqual(positiveFractions([1, 3]), [0.25, 0.75]);
});
