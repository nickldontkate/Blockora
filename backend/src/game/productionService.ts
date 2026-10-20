import type { Env, ResourceMap } from '../types';
import { loadCityForPlayer, flattenModulesByBuilding, type LoadedCity } from '../lib/cityLoader';
import { getPlayerResources } from '../lib/resources';
import { getActiveWorldEventModifiers } from '../lib/gameConfig';
import { nowSeconds, clampElapsed } from '../lib/time';
import { computeEffectiveModuleRates, simulateProduction, type EffectiveModuleRate } from './balance';

export interface ReconciliationResult {
  city: LoadedCity;
  now: number;
  /** Real wall-clock seconds since the last reconciliation, uncapped. */
  rawElapsedSeconds: number;
  /** Seconds actually simulated, after the offline-production cap. */
  simulatedSeconds: number;
  wasCapped: boolean;
  wasEnergyConstrained: boolean;
  resourceDeltas: ResourceMap;
  unconstrainedPerHour: ResourceMap;
}

/**
 * Shared production-reconciliation core used by both `POST /production/collect`
 * (routine foreground collection) and `POST /production/claim-offline`
 * (explicit "welcome back" claim after an absence). Both endpoints must
 * behave identically with respect to the elapsed-time source (server clock
 * vs. `cities.last_offline_sync_at`, never a client-supplied duration) and
 * the 8h simulation cap — the only difference between the two endpoints is
 * the response framing, not the underlying math.
 */
export async function reconcileProduction(env: Env, playerId: string): Promise<ReconciliationResult> {
  const city = await loadCityForPlayer(env, playerId);
  const now = nowSeconds();
  const rawElapsedSeconds = Math.max(0, now - city.lastOfflineSyncAt);
  const capSeconds = Number(env.OFFLINE_PRODUCTION_CAP_SECONDS) || 8 * 3600;
  const simulatedSeconds = clampElapsed(rawElapsedSeconds, capSeconds);

  const eventModifiers = await getActiveWorldEventModifiers(env);
  const modulesByBuilding = flattenModulesByBuilding(city);

  const allEffectiveRates: EffectiveModuleRate[] = [];
  for (const modules of modulesByBuilding.values()) {
    allEffectiveRates.push(...computeEffectiveModuleRates(modules, eventModifiers));
  }

  const currentResources = await getPlayerResources(env, playerId);

  const simulation = simulateProduction(allEffectiveRates, { ENERGY: currentResources.ENERGY }, simulatedSeconds);

  return {
    city,
    now,
    rawElapsedSeconds,
    simulatedSeconds,
    wasCapped: rawElapsedSeconds > capSeconds,
    wasEnergyConstrained: simulation.wasConstrained,
    resourceDeltas: simulation.resourceDeltas,
    unconstrainedPerHour: simulation.unconstrainedPerHour,
  };
}
