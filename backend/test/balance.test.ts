import { describe, expect, it } from 'vitest';
import {
  checkStructuralIntegrity,
  computeEffectiveModuleRates,
  simulateProduction,
  type PlacedModuleLite,
} from '../src/game/balance';
import { BASE_BUILDING_SUPPORT_CAPACITY } from '../src/game/moduleCatalog';

describe('checkStructuralIntegrity', () => {
  it('allows a light layout within the base capacity', () => {
    const modules: PlacedModuleLite[] = [
      { id: '1', moduleType: 'CORE', x: 0, y: 0 },
      { id: '2', moduleType: 'SOLAR', x: 1, y: 0 },
    ];
    const result = checkStructuralIntegrity(modules, BASE_BUILDING_SUPPORT_CAPACITY);
    expect(result.isValid).toBe(true);
  });

  it('rejects a layout that exceeds support capacity', () => {
    const modules: PlacedModuleLite[] = Array.from({ length: 10 }, (_, i) => ({
      id: `m${i}`,
      moduleType: 'FACTORY' as const,
      x: i,
      y: 0,
    }));
    const result = checkStructuralIntegrity(modules, BASE_BUILDING_SUPPORT_CAPACITY);
    expect(result.isValid).toBe(false);
    expect(result.totalWeight).toBeGreaterThan(result.totalSupportCapacity);
  });

  it('a CORE module raises the achievable capacity', () => {
    const withoutCore = checkStructuralIntegrity(
      [{ id: '1', moduleType: 'FACTORY', x: 0, y: 0 }],
      BASE_BUILDING_SUPPORT_CAPACITY
    );
    const withCore = checkStructuralIntegrity(
      [
        { id: '1', moduleType: 'FACTORY', x: 0, y: 0 },
        { id: '2', moduleType: 'CORE', x: 1, y: 0 },
      ],
      BASE_BUILDING_SUPPORT_CAPACITY
    );
    expect(withCore.totalSupportCapacity).toBeGreaterThan(withoutCore.totalSupportCapacity);
  });
});

describe('computeEffectiveModuleRates', () => {
  it('applies the Smart Irrigation synergy when Greenhouse is adjacent to a Water Tank', () => {
    const modules: PlacedModuleLite[] = [
      { id: 'gh', moduleType: 'GREENHOUSE', x: 0, y: 0 },
      { id: 'wt', moduleType: 'WATER_TANK', x: 1, y: 0 },
    ];
    const rates = computeEffectiveModuleRates(modules);
    const greenhouse = rates.find((r) => r.id === 'gh')!;
    expect(greenhouse.activeSynergies).toContain('SMART_IRRIGATION');
    // Base Greenhouse FOOD is 5/hr; +20% synergy => 6/hr.
    expect(greenhouse.producesPerHour.FOOD).toBeCloseTo(6);
  });

  it('does not apply a synergy when the partner module is not adjacent', () => {
    const modules: PlacedModuleLite[] = [
      { id: 'gh', moduleType: 'GREENHOUSE', x: 0, y: 0 },
      { id: 'wt', moduleType: 'WATER_TANK', x: 5, y: 5 },
    ];
    const rates = computeEffectiveModuleRates(modules);
    const greenhouse = rates.find((r) => r.id === 'gh')!;
    expect(greenhouse.activeSynergies).toHaveLength(0);
    expect(greenhouse.producesPerHour.FOOD).toBeCloseTo(5);
  });

  it('scales production by active world-event demand modifiers only for "production" kind', () => {
    const modules: PlacedModuleLite[] = [{ id: 'solar', moduleType: 'SOLAR', x: 0, y: 0 }];
    const rates = computeEffectiveModuleRates(modules, [{ resource: 'ENERGY', kind: 'production', percent: 50 }]);
    expect(rates[0]!.producesPerHour.ENERGY).toBeCloseTo(15); // 10 * 1.5
  });
});

describe('simulateProduction', () => {
  it('produces unconstrained resources fully across the elapsed window', () => {
    const rates = computeEffectiveModuleRates([{ id: 'solar', moduleType: 'SOLAR', x: 0, y: 0 }]);
    const result = simulateProduction(rates, { ENERGY: 0 }, 3600); // 1 hour
    expect(result.resourceDeltas.ENERGY).toBe(10);
    expect(result.wasConstrained).toBe(false);
  });

  it('constrains Factory GOODS output once Energy stock runs out', () => {
    // Factory alone: consumes 8 ENERGY/hr, produces 5 GOODS/hr, no Energy income.
    const rates = computeEffectiveModuleRates([{ id: 'factory', moduleType: 'FACTORY', x: 0, y: 0 }]);
    const result = simulateProduction(rates, { ENERGY: 4 }, 3600); // only 30 minutes worth of fuel
    expect(result.wasConstrained).toBe(true);
    // Only ~half the hour's worth of fuel was available => ~half the GOODS.
    expect(result.resourceDeltas.GOODS).toBeGreaterThan(0);
    expect(result.resourceDeltas.GOODS).toBeLessThan(5);
    // Energy stock should be fully drained, never negative.
    expect(result.resourceDeltas.ENERGY).toBe(-4);
  });

  it('lets a Solar module fuel a Factory in the same simulation', () => {
    const rates = computeEffectiveModuleRates([
      { id: 'solar', moduleType: 'SOLAR', x: 0, y: 0 },
      { id: 'factory', moduleType: 'FACTORY', x: 5, y: 5 },
    ]);
    // Solar produces 10 ENERGY/hr, Factory needs 8 ENERGY/hr -> fully sustainable.
    const result = simulateProduction(rates, { ENERGY: 0 }, 3600);
    expect(result.wasConstrained).toBe(false);
    expect(result.resourceDeltas.GOODS).toBeCloseTo(5);
    expect(result.resourceDeltas.ENERGY).toBeCloseTo(2); // 10 produced - 8 consumed
  });
});
