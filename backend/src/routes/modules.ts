import type { RequestContext, ModuleType } from '../types';
import { json, badRequest, conflict, forbidden } from '../lib/response';
import { parseJsonBody, requireString, requireInt, requireOneOf } from '../lib/validation';
import { getOwnedBuilding } from '../lib/cityLoader';
import { getPlayerResources, assertSufficientResources, buildResourceDeltaStatements } from '../lib/resources';
import { runIdempotent, resolveIdempotencyKey, fetchStoredResponse } from '../lib/idempotency';
import { newId } from '../lib/auth';
import { nowSeconds } from '../lib/time';
import { checkStructuralIntegrity, computeEffectiveModuleRates } from '../game/balance';
import { MODULE_CATALOG, BASE_BUILDING_SUPPORT_CAPACITY } from '../game/moduleCatalog';

const MODULE_TYPES = Object.keys(MODULE_CATALOG) as ModuleType[];
const ROTATIONS = [0, 90, 180, 270] as const;

/**
 * POST /api/v1/modules/place
 *
 * Places a module the player already owns (in `module_inventory`) onto a
 * free grid cell of one of their buildings. The server — never the client —
 * is the one deciding whether this is legal:
 *   1. the player actually owns an unplaced unit of this module type
 *   2. the target cell is empty
 *   3. the resulting structural weight does not exceed the building's
 *      support capacity
 *   4. the player can afford the module's install cost
 * All four checks run against a fresh DB read taken in this request; none
 * of them trust anything the client asserts about its own state.
 */
export async function placeModule(ctx: RequestContext): Promise<Response> {
  const playerId = ctx.auth!.playerId;
  const body = await parseJsonBody(ctx.request);
  const buildingId = requireString(body, 'buildingId');
  const moduleType = requireOneOf(body, 'moduleType', MODULE_TYPES);
  const x = requireInt(body, 'x', { min: 0, max: 63 });
  const y = requireInt(body, 'y', { min: 0, max: 63 });
  const rotationRaw = body.rotation ?? 0;
  if (!ROTATIONS.includes(rotationRaw as (typeof ROTATIONS)[number])) {
    throw badRequest('rotation must be one of 0, 90, 180, 270.');
  }
  const rotation = rotationRaw as (typeof ROTATIONS)[number];
  const idempotencyKey = resolveIdempotencyKey(ctx.request, body);

  // Replay check MUST happen before any validation that reads current DB
  // state: if this exact request already succeeded, the cell it placed
  // into is now occupied and the inventory it decremented is now lower —
  // re-running those checks would wrongly reject a harmless retry instead
  // of replaying the original success response.
  const cached = await fetchStoredResponse<unknown>(ctx.env, playerId, idempotencyKey);
  if (cached !== undefined) return json(cached);

  const building = await getOwnedBuilding(ctx.env, playerId, buildingId);
  if (!building) throw badRequest('Unknown building.');

  if (building.modules.some((m) => m.gridX === x && m.gridY === y)) {
    throw conflict('That grid cell is already occupied.', { x, y });
  }

  const candidateModules = [...building.modules.map((m) => ({ id: m.id, moduleType: m.moduleType, x: m.gridX, y: m.gridY })), { id: 'candidate', moduleType, x, y }];
  const structural = checkStructuralIntegrity(candidateModules, BASE_BUILDING_SUPPORT_CAPACITY);
  if (!structural.isValid) {
    throw conflict('Placing this module would exceed the building\'s structural support.', {
      totalWeight: structural.totalWeight,
      supportCapacity: structural.totalSupportCapacity,
    });
  }

  const inventoryRow = await ctx.env.DB.prepare(
    `SELECT quantity FROM module_inventory WHERE player_id = ? AND module_type = ?`
  )
    .bind(playerId, moduleType)
    .first<{ quantity: number }>();

  if (!inventoryRow || inventoryRow.quantity < 1) {
    throw conflict(`You don't own any unplaced ${moduleType} modules.`, { moduleType });
  }

  const installCoinCost = MODULE_CATALOG[moduleType].installCoinCost;
  const currentResources = await getPlayerResources(ctx.env, playerId);
  assertSufficientResources(currentResources, { COINS: installCoinCost });

  const response = await runIdempotent(ctx.env, playerId, idempotencyKey, 'module_place', async () => {
    const now = nowSeconds();
    const moduleId = newId();
    const effectiveRate = computeEffectiveModuleRates([{ id: moduleId, moduleType, x, y }])[0]!;

    const statements = [
      ctx.env.DB.prepare(
        `INSERT INTO building_modules (id, building_id, module_type, grid_x, grid_y, rotation, installed_at, effective_rates_json)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?)`
      ).bind(moduleId, buildingId, moduleType, x, y, rotation, now, JSON.stringify(effectiveRate)),
      ctx.env.DB.prepare(
        `UPDATE module_inventory SET quantity = quantity - 1, updated_at = ? WHERE player_id = ? AND module_type = ? AND quantity >= 1`
      ).bind(now, playerId, moduleType),
      ctx.env.DB.prepare(`UPDATE buildings SET support_capacity = ?, updated_at = ? WHERE id = ?`).bind(
        structural.totalSupportCapacity,
        now,
        buildingId
      ),
      ...buildResourceDeltaStatements(ctx.env, playerId, { COINS: -installCoinCost }),
    ];

    return {
      statements,
      resourceDeltas: { COINS: -installCoinCost },
      response: {
        placedModule: { id: moduleId, moduleType, gridX: x, gridY: y, rotation, installedAt: now },
        structural: { totalWeight: structural.totalWeight, supportCapacity: structural.totalSupportCapacity },
        resources: { ...currentResources, COINS: currentResources.COINS - installCoinCost },
      },
    };
  });

  return json(response, 201);
}

/**
 * POST /api/v1/modules/remove
 *
 * Removes a placed module and returns it to the player's inventory. The
 * building's CORE module anchors it and cannot be removed. No coin refund
 * is given for the original install cost (matches the client-side "you'll
 * need to re-buy the module pack" expectation — tune via
 * MODULE_CATALOG if that should change).
 */
export async function removeModule(ctx: RequestContext): Promise<Response> {
  const playerId = ctx.auth!.playerId;
  const body = await parseJsonBody(ctx.request);
  const buildingId = requireString(body, 'buildingId');
  const moduleId = requireString(body, 'moduleId');
  const idempotencyKey = resolveIdempotencyKey(ctx.request, body);

  const cached = await fetchStoredResponse<unknown>(ctx.env, playerId, idempotencyKey);
  if (cached !== undefined) return json(cached);

  const building = await getOwnedBuilding(ctx.env, playerId, buildingId);
  if (!building) throw badRequest('Unknown building.');

  const target = building.modules.find((m) => m.id === moduleId);
  if (!target) throw badRequest('Unknown module.');
  if (target.moduleType === 'CORE') {
    throw forbidden('The CORE module anchors this building and cannot be removed.');
  }

  const remainingModules = building.modules
    .filter((m) => m.id !== moduleId)
    .map((m) => ({ id: m.id, moduleType: m.moduleType, x: m.gridX, y: m.gridY }));
  const structural = checkStructuralIntegrity(remainingModules, BASE_BUILDING_SUPPORT_CAPACITY);

  const response = await runIdempotent(ctx.env, playerId, idempotencyKey, 'module_remove', async () => {
    const now = nowSeconds();
    const statements = [
      ctx.env.DB.prepare(`DELETE FROM building_modules WHERE id = ? AND building_id = ?`).bind(moduleId, buildingId),
      ctx.env.DB.prepare(
        `INSERT INTO module_inventory (player_id, module_type, quantity, updated_at)
         VALUES (?, ?, 1, ?)
         ON CONFLICT(player_id, module_type) DO UPDATE SET quantity = quantity + 1, updated_at = excluded.updated_at`
      ).bind(playerId, target.moduleType, now),
      ctx.env.DB.prepare(`UPDATE buildings SET support_capacity = ?, updated_at = ? WHERE id = ?`).bind(
        structural.totalSupportCapacity,
        now,
        buildingId
      ),
    ];

    return {
      statements,
      resourceDeltas: {},
      response: {
        removedModuleId: moduleId,
        returnedToInventory: target.moduleType,
        structural: { totalWeight: structural.totalWeight, supportCapacity: structural.totalSupportCapacity },
      },
    };
  });

  return json(response);
}
