import type { Env, ResourceType } from '../types';
import type { WorldEventModifier } from '../game/balance';
import { nowSeconds } from './time';

const ACTIVE_EVENTS_CACHE_KEY = 'active_world_event_modifiers_v1';
const CACHE_TTL_SECONDS = 60;

interface CachedModifiers {
  cachedAt: number;
  modifiers: WorldEventModifier[];
}

interface WorldEventRow {
  modifiers_json: string;
}

/**
 * Returns the flattened list of production/demand modifiers from every
 * currently-active world event. Backed by the `CONFIG` KV namespace as a
 * short-TTL read-through cache: world events change rarely (they're
 * time-boxed, not per-request), so it isn't worth hitting D1 on every
 * production/contract calculation. KV's eventual consistency is fine here
 * — being up to ~60s late to reflect a new event starting/ending is an
 * acceptable trade for cutting D1 read load dramatically.
 */
export async function getActiveWorldEventModifiers(env: Env): Promise<WorldEventModifier[]> {
  const cached = await env.CONFIG.get<CachedModifiers>(ACTIVE_EVENTS_CACHE_KEY, 'json');
  const now = nowSeconds();
  if (cached && now - cached.cachedAt < CACHE_TTL_SECONDS) {
    return cached.modifiers;
  }

  const { results } = await env.DB.prepare(
    `SELECT modifiers_json FROM world_events WHERE starts_at <= ? AND ends_at >= ?`
  )
    .bind(now, now)
    .all<WorldEventRow>();

  const modifiers: WorldEventModifier[] = [];
  for (const row of results ?? []) {
    try {
      const parsed = JSON.parse(row.modifiers_json) as WorldEventModifier[];
      modifiers.push(...parsed);
    } catch {
      // Malformed modifier JSON on a single event shouldn't take down every
      // production calculation in the city — skip it.
      continue;
    }
  }

  await env.CONFIG.put(ACTIVE_EVENTS_CACHE_KEY, JSON.stringify({ cachedAt: now, modifiers }), {
    expirationTtl: CACHE_TTL_SECONDS * 4,
  });

  return modifiers;
}

/** Demand-side modifiers (e.g. "Data demand +80%") scale contract rewards for that resource. */
export function demandMultiplierFor(resource: ResourceType, modifiers: WorldEventModifier[]): number {
  let mult = 1;
  for (const m of modifiers) {
    if (m.kind === 'demand' && m.resource === resource) {
      mult *= 1 + m.percent / 100;
    }
  }
  return mult;
}
