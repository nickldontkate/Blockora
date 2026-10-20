import type { ModuleType, ResourceMap, ResourceType } from '../types';

/**
 * Server-side game-balance table for modules. This is the authoritative
 * source for production/consumption/structural numbers — the iOS client
 * may render its own copy for UI purposes, but every reward and structural
 * check is recomputed here, never trusted from the client.
 *
 * Numbers are intentionally simple/round; they are expected to evolve as
 * the game is tuned. A future iteration should move this into the `CONFIG`
 * KV namespace so balance can be tweaked without a redeploy — the shape
 * below is already what would be JSON-serialized into that KV entry (see
 * `backend/src/lib/gameConfig.ts`).
 */
export interface ModuleDefinition {
  moduleType: ModuleType;
  /** Structural weight this module adds to its building. */
  weight: number;
  /** Structural support this module contributes to its building's capacity. */
  support: number;
  /** Base resources produced per in-game hour at 100% (unconstrained) rate. */
  producesPerHour: ResourceMap;
  /** Resources consumed per in-game hour to sustain `producesPerHour`. */
  consumesPerHour: ResourceMap;
  /** One-time COINS cost charged when the module is physically installed. */
  installCoinCost: number;
}

export const MODULE_CATALOG: Record<ModuleType, ModuleDefinition> = {
  SOLAR: {
    moduleType: 'SOLAR',
    weight: 2,
    support: 0,
    producesPerHour: { ENERGY: 10 },
    consumesPerHour: {},
    installCoinCost: 50,
  },
  SERVER: {
    moduleType: 'SERVER',
    weight: 3,
    support: 0,
    producesPerHour: { DATA: 8 },
    consumesPerHour: { ENERGY: 6 },
    installCoinCost: 120,
  },
  COOLING: {
    moduleType: 'COOLING',
    weight: 1,
    support: 0,
    producesPerHour: {},
    consumesPerHour: { ENERGY: 1 },
    installCoinCost: 60,
  },
  STORAGE: {
    moduleType: 'STORAGE',
    weight: 1,
    support: 4,
    producesPerHour: {},
    consumesPerHour: {},
    installCoinCost: 40,
  },
  CORE: {
    moduleType: 'CORE',
    weight: 0,
    support: 10,
    producesPerHour: { COINS: 2 },
    consumesPerHour: {},
    installCoinCost: 0, // the core module ships with every new building
  },
  FARM_FIELD: {
    moduleType: 'FARM_FIELD',
    weight: 2,
    support: 0,
    producesPerHour: { FOOD: 6 },
    consumesPerHour: { ENERGY: 2 },
    installCoinCost: 45,
  },
  GREENHOUSE: {
    moduleType: 'GREENHOUSE',
    weight: 2,
    support: 0,
    producesPerHour: { FOOD: 5 },
    consumesPerHour: { ENERGY: 3 },
    installCoinCost: 70,
  },
  WATER_TANK: {
    moduleType: 'WATER_TANK',
    weight: 1,
    support: 1,
    producesPerHour: {},
    consumesPerHour: {},
    installCoinCost: 35,
  },
  FACTORY: {
    moduleType: 'FACTORY',
    weight: 3,
    support: 0,
    producesPerHour: { GOODS: 5 },
    consumesPerHour: { ENERGY: 8 },
    installCoinCost: 150,
  },
};

/** A plot alone (before any support module is placed) can hold this much weight. */
export const BASE_BUILDING_SUPPORT_CAPACITY = 6;

/** Resource types that gate other modules' production when depleted offline. */
export const CONSTRAINING_RESOURCES: ResourceType[] = ['ENERGY'];

export interface SynergyRule {
  code: string;
  title: string;
  /** Both module types must be present and 4-directionally adjacent. */
  pair: [ModuleType, ModuleType];
  /** Multiplier applied to the *first* module's production (e.g. 1.2 = +20%). */
  productionMultiplier: number;
  /** Multiplier applied to the first module's consumption (1.0 = no change). */
  consumptionMultiplier: number;
}

export const SYNERGY_RULES: SynergyRule[] = [
  {
    code: 'SMART_IRRIGATION',
    title: 'Smart Irrigation',
    pair: ['GREENHOUSE', 'WATER_TANK'],
    productionMultiplier: 1.2,
    consumptionMultiplier: 1.0,
  },
  {
    code: 'THERMAL_REGULATION',
    title: 'Thermal Regulation',
    pair: ['SOLAR', 'COOLING'],
    productionMultiplier: 1.15,
    consumptionMultiplier: 1.0,
  },
  {
    code: 'OVERCLOCK',
    title: 'Overclock',
    pair: ['SERVER', 'COOLING'],
    productionMultiplier: 1.25,
    consumptionMultiplier: 1.1,
  },
];
