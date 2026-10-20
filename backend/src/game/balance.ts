import type { ModuleType, ResourceMap, ResourceType } from '../types';
import { RESOURCE_TYPES } from '../types';
import { MODULE_CATALOG, SYNERGY_RULES } from './moduleCatalog';

export interface PlacedModuleLite {
  id: string;
  moduleType: ModuleType;
  x: number;
  y: number;
}

export interface EffectiveModuleRate {
  id: string;
  moduleType: ModuleType;
  producesPerHour: ResourceMap;
  consumesPerHour: ResourceMap;
  activeSynergies: string[];
}

export interface WorldEventModifier {
  resource: ResourceType;
  kind: 'production' | 'demand';
  percent: number; // e.g. 80 means +80%
}

function areAdjacent(a: PlacedModuleLite, b: PlacedModuleLite): boolean {
  return Math.abs(a.x - b.x) + Math.abs(a.y - b.y) === 1;
}

function scaleResourceMap(map: ResourceMap, multiplier: number): ResourceMap {
  const out: ResourceMap = {};
  for (const [resource, amount] of Object.entries(map) as [ResourceType, number][]) {
    out[resource] = amount * multiplier;
  }
  return out;
}

/**
 * Computes each module's production/consumption rates after applying
 * adjacency synergies (see SYNERGY_RULES) and active world-event
 * production modifiers. This is the single source of truth used by both
 * the "collect production" endpoint (elapsed-time delta since last sync)
 * and the offline-simulation path — they must never diverge, or players
 * would see different totals depending on whether the app was foregrounded
 * when a tick happened.
 */
export function computeEffectiveModuleRates(
  modules: PlacedModuleLite[],
  worldEventModifiers: WorldEventModifier[] = []
): EffectiveModuleRate[] {
  const productionModifiersByResource = new Map<ResourceType, number>();
  for (const modifier of worldEventModifiers) {
    if (modifier.kind !== 'production') continue;
    const current = productionModifiersByResource.get(modifier.resource) ?? 1;
    productionModifiersByResource.set(modifier.resource, current * (1 + modifier.percent / 100));
  }

  return modules.map((module) => {
    const base = MODULE_CATALOG[module.moduleType];
    let producesPerHour = { ...base.producesPerHour };
    let consumesPerHour = { ...base.consumesPerHour };
    const activeSynergies: string[] = [];

    for (const rule of SYNERGY_RULES) {
      if (rule.pair[0] !== module.moduleType) continue;
      const partnerType = rule.pair[1];
      const hasPartner = modules.some((other) => other.moduleType === partnerType && areAdjacent(module, other));
      if (!hasPartner) continue;
      producesPerHour = scaleResourceMap(producesPerHour, rule.productionMultiplier);
      consumesPerHour = scaleResourceMap(consumesPerHour, rule.consumptionMultiplier);
      activeSynergies.push(rule.code);
    }

    // World events modify the *effective* production the city achieves,
    // layered on top of synergies.
    for (const [resource, mult] of productionModifiersByResource) {
      if (producesPerHour[resource]) {
        producesPerHour[resource] = (producesPerHour[resource] ?? 0) * mult;
      }
    }

    return {
      id: module.id,
      moduleType: module.moduleType,
      producesPerHour,
      consumesPerHour,
      activeSynergies,
    };
  });
}

export interface StructuralCheckResult {
  totalWeight: number;
  totalSupportCapacity: number;
  isValid: boolean;
}

export function checkStructuralIntegrity(modules: PlacedModuleLite[], baseSupport: number): StructuralCheckResult {
  let totalWeight = 0;
  let totalSupportCapacity = baseSupport;
  for (const module of modules) {
    const def = MODULE_CATALOG[module.moduleType];
    totalWeight += def.weight;
    totalSupportCapacity += def.support;
  }
  return { totalWeight, totalSupportCapacity, isValid: totalWeight <= totalSupportCapacity };
}

export interface SimulationResult {
  secondsSimulated: number;
  resourceDeltas: ResourceMap;
  /** Per-resource amount that would have been produced with no constraints, for transparency in the API response. */
  unconstrainedPerHour: ResourceMap;
  /** True if any fuel resource (e.g. ENERGY) ran out at some point during the simulated window. */
  wasConstrained: boolean;
}

const TICK_SECONDS = 300; // 5-minute resolution keeps the loop small even at the 8h cap (96 ticks)

/**
 * Resource-constrained production simulation. Any resource that at least
 * one module *consumes* (currently just ENERGY) is treated as a "fuel"
 * whose available stock gates how much dependent modules can actually
 * produce each tick — this is what makes it correct for the classic case
 * of "a factory can't produce Goods offline if it ran out of Energy": if
 * Solar production can't keep the Energy stock ahead of Server/Factory/
 * Farm demand, those modules are scaled down (fairly, proportionally to
 * demand) or stopped for the remainder of the window, exactly as they
 * would be if the player were online and watching resources tick down.
 *
 * `startingFuelStock` should be the player's *current* balance for each
 * fuel resource, since production offline draws down the same stock the
 * player would spend while online.
 */
export function simulateProduction(
  moduleRates: EffectiveModuleRate[],
  startingFuelStock: Partial<Record<ResourceType, number>>,
  elapsedSeconds: number
): SimulationResult {
  const fuelResources = new Set<ResourceType>();
  for (const m of moduleRates) {
    for (const resource of Object.keys(m.consumesPerHour) as ResourceType[]) fuelResources.add(resource);
  }

  const fuelStock: Partial<Record<ResourceType, number>> = {};
  for (const resource of fuelResources) fuelStock[resource] = startingFuelStock[resource] ?? 0;

  const totals: ResourceMap = {};
  const unconstrainedPerHour: ResourceMap = {};
  let wasConstrained = false;

  for (const m of moduleRates) {
    for (const [resource, amount] of Object.entries(m.producesPerHour) as [ResourceType, number][]) {
      unconstrainedPerHour[resource] = (unconstrainedPerHour[resource] ?? 0) + amount;
    }
  }

  let remaining = elapsedSeconds;
  while (remaining > 0) {
    const tickSeconds = Math.min(TICK_SECONDS, remaining);
    const dtHours = tickSeconds / 3600;
    remaining -= tickSeconds;

    // 1. Fuel producers top up their stock first.
    for (const m of moduleRates) {
      for (const [resource, amount] of Object.entries(m.producesPerHour) as [ResourceType, number][]) {
        if (!fuelResources.has(resource)) continue;
        fuelStock[resource] = (fuelStock[resource] ?? 0) + amount * dtHours;
      }
    }

    // 2. Compute per-fuel demand this tick and the resulting fair-share scale factor.
    const demandByFuel: Partial<Record<ResourceType, number>> = {};
    for (const m of moduleRates) {
      for (const [resource, amount] of Object.entries(m.consumesPerHour) as [ResourceType, number][]) {
        demandByFuel[resource] = (demandByFuel[resource] ?? 0) + amount * dtHours;
      }
    }
    const scaleByFuel: Partial<Record<ResourceType, number>> = {};
    for (const resource of fuelResources) {
      const demand = demandByFuel[resource] ?? 0;
      const available = fuelStock[resource] ?? 0;
      if (demand <= 0) {
        scaleByFuel[resource] = 1;
      } else if (available >= demand) {
        scaleByFuel[resource] = 1;
      } else {
        scaleByFuel[resource] = available / demand;
        wasConstrained = true;
      }
    }

    // 3. Apply the scale factor (min across all fuels a module needs) to each
    //    module's non-fuel production for this tick, and draw down fuel stock.
    for (const m of moduleRates) {
      const neededFuels = Object.keys(m.consumesPerHour) as ResourceType[];
      const moduleScale = neededFuels.length === 0 ? 1 : Math.min(...neededFuels.map((f) => scaleByFuel[f] ?? 1));

      for (const [resource, amount] of Object.entries(m.producesPerHour) as [ResourceType, number][]) {
        if (fuelResources.has(resource)) continue; // fuel production already credited in step 1, unaffected by this module's own consumption
        totals[resource] = (totals[resource] ?? 0) + amount * dtHours * moduleScale;
      }
      for (const [resource, amount] of Object.entries(m.consumesPerHour) as [ResourceType, number][]) {
        fuelStock[resource] = Math.max(0, (fuelStock[resource] ?? 0) - amount * dtHours * moduleScale);
      }
    }
  }

  // Net fuel deltas: whatever accumulated above the player's starting stock.
  for (const resource of fuelResources) {
    const delta = (fuelStock[resource] ?? 0) - (startingFuelStock[resource] ?? 0);
    totals[resource] = (totals[resource] ?? 0) + delta;
  }

  // Round to whole units — resources are always integers at rest.
  const resourceDeltas: ResourceMap = {};
  for (const resource of RESOURCE_TYPES) {
    if (totals[resource] !== undefined) {
      resourceDeltas[resource] = Math.floor(totals[resource]!);
    }
  }

  return { secondsSimulated: elapsedSeconds, resourceDeltas, unconstrainedPerHour, wasConstrained };
}
