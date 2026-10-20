import type { Env, ResourceMap, ResourceType } from '../types';
import { RESOURCE_TYPES } from '../types';
import { badRequest, conflict } from './response';
import { nowSeconds } from './time';

/** Reads a player's full resource ledger, defaulting missing rows to 0. */
export async function getPlayerResources(env: Env, playerId: string): Promise<Record<ResourceType, number>> {
  const { results } = await env.DB.prepare(
    `SELECT resource_type, amount FROM player_resources WHERE player_id = ?`
  )
    .bind(playerId)
    .all<{ resource_type: ResourceType; amount: number }>();

  const map = Object.fromEntries(RESOURCE_TYPES.map((r) => [r, 0])) as Record<ResourceType, number>;
  for (const row of results ?? []) {
    map[row.resource_type] = row.amount;
  }
  return map;
}

/**
 * Validates that a player currently has at least `cost` of every listed
 * resource. Throws 409 CONFLICT (not 400 — the request is well-formed, the
 * player's state just doesn't satisfy it) when insufficient. This must
 * always be called against a fresh read taken right before the mutation is
 * batched, never against a cached/client-supplied balance.
 */
export function assertSufficientResources(current: Record<ResourceType, number>, cost: ResourceMap): void {
  for (const [resource, amount] of Object.entries(cost) as [ResourceType, number][]) {
    if (amount <= 0) continue;
    if ((current[resource] ?? 0) < amount) {
      throw conflict(`Insufficient ${resource}.`, {
        resource,
        required: amount,
        available: current[resource] ?? 0,
      });
    }
  }
}

export function validateResourceMap(map: unknown): ResourceMap {
  if (typeof map !== 'object' || map === null || Array.isArray(map)) {
    throw badRequest('Expected a resource map object.');
  }
  const out: ResourceMap = {};
  for (const [key, value] of Object.entries(map as Record<string, unknown>)) {
    if (!RESOURCE_TYPES.includes(key as ResourceType)) {
      throw badRequest(`Unknown resource type: ${key}`);
    }
    if (typeof value !== 'number' || !Number.isFinite(value) || !Number.isInteger(value)) {
      throw badRequest(`Resource amount for ${key} must be an integer.`);
    }
    out[key as ResourceType] = value;
  }
  return out;
}

/**
 * Builds the D1 statements to apply a signed delta map to a player's
 * resources (positive = grant, negative = spend). Uses UPSERT with a
 * floor-at-zero clamp via SQLite's MAX() so a bug elsewhere can never drive
 * a balance negative at the storage layer, even if validation upstream is
 * ever skipped by mistake. Callers MUST have already validated sufficiency
 * for any negative deltas via `assertSufficientResources`.
 */
export function buildResourceDeltaStatements(
  env: Env,
  playerId: string,
  deltas: ResourceMap
): D1PreparedStatement[] {
  const now = nowSeconds();
  const statements: D1PreparedStatement[] = [];
  for (const [resource, amount] of Object.entries(deltas) as [ResourceType, number][]) {
    if (!amount) continue;
    // Numbered parameters let us reuse the same bound `amount` (?3) and
    // `now` (?4) in both the initial INSERT value and the ON CONFLICT
    // update, which is required here: a fresh row must clamp a negative
    // delta to 0 (MAX(0, ?3)), while an existing row must clamp the *sum*
    // of its current amount and the raw delta (MAX(0, amount + ?3)).
    // `excluded.amount` would be wrong for the latter since it only ever
    // holds the clamped insert value, not the raw delta.
    statements.push(
      env.DB.prepare(
        `INSERT INTO player_resources (player_id, resource_type, amount, updated_at)
         VALUES (?1, ?2, MAX(0, ?3), ?4)
         ON CONFLICT(player_id, resource_type)
         DO UPDATE SET amount = MAX(0, amount + ?3), updated_at = ?4`
      ).bind(playerId, resource, amount, now)
    );
  }
  return statements;
}
