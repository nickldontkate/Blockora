import type { RequestContext, ModuleType, BlueprintLayout } from '../types';
import { json, badRequest, notFound } from '../lib/response';
import { parseJsonBody, requireString, optionalString } from '../lib/validation';
import { newId } from '../lib/auth';
import { nowSeconds } from '../lib/time';
import { MODULE_CATALOG } from '../game/moduleCatalog';

const MODULE_TYPES = new Set(Object.keys(MODULE_CATALOG));
const ROTATIONS = new Set([0, 90, 180, 270]);
const MAX_BLUEPRINT_DIMENSION = 32;
const MAX_MODULES_PER_BLUEPRINT = 256;

interface BlueprintRow {
  id: string;
  name: string;
  building_kind: string;
  layout_json: string;
  created_at: number;
  updated_at: number;
}

function serialize(row: BlueprintRow) {
  return {
    id: row.id,
    name: row.name,
    buildingKind: row.building_kind,
    layout: JSON.parse(row.layout_json) as BlueprintLayout,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

/**
 * Validates the *shape* of a blueprint layout only (bounds, known module
 * types, no duplicate cells). This is deliberately NOT checking the
 * player's module inventory — per the product spec, a blueprint is just a
 * saved layout. Whether the player currently owns enough of each module to
 * actually build it is a client-side concern (checked against the client's
 * live inventory view when the player chooses to apply the blueprint), and
 * actual placement is still validated/enforced module-by-module by
 * POST /api/v1/modules/place regardless of whether it came from a blueprint
 * or was placed by hand.
 */
function validateLayout(input: unknown): BlueprintLayout {
  if (typeof input !== 'object' || input === null) throw badRequest('layout must be an object.');
  const layout = input as Record<string, unknown>;

  const width = layout.width;
  const height = layout.height;
  if (typeof width !== 'number' || !Number.isInteger(width) || width < 1 || width > MAX_BLUEPRINT_DIMENSION) {
    throw badRequest(`layout.width must be an integer between 1 and ${MAX_BLUEPRINT_DIMENSION}.`);
  }
  if (typeof height !== 'number' || !Number.isInteger(height) || height < 1 || height > MAX_BLUEPRINT_DIMENSION) {
    throw badRequest(`layout.height must be an integer between 1 and ${MAX_BLUEPRINT_DIMENSION}.`);
  }

  const modulesRaw = layout.modules;
  if (!Array.isArray(modulesRaw)) throw badRequest('layout.modules must be an array.');
  if (modulesRaw.length > MAX_MODULES_PER_BLUEPRINT) {
    throw badRequest(`layout.modules must contain at most ${MAX_MODULES_PER_BLUEPRINT} entries.`);
  }

  const seenCells = new Set<string>();
  const modules = modulesRaw.map((entry, index) => {
    if (typeof entry !== 'object' || entry === null) throw badRequest(`layout.modules[${index}] must be an object.`);
    const e = entry as Record<string, unknown>;
    if (typeof e.moduleType !== 'string' || !MODULE_TYPES.has(e.moduleType)) {
      throw badRequest(`layout.modules[${index}].moduleType is invalid.`);
    }
    if (typeof e.x !== 'number' || !Number.isInteger(e.x) || e.x < 0 || e.x >= width) {
      throw badRequest(`layout.modules[${index}].x is out of bounds.`);
    }
    if (typeof e.y !== 'number' || !Number.isInteger(e.y) || e.y < 0 || e.y >= height) {
      throw badRequest(`layout.modules[${index}].y is out of bounds.`);
    }
    const rotation = e.rotation ?? 0;
    if (typeof rotation !== 'number' || !ROTATIONS.has(rotation)) {
      throw badRequest(`layout.modules[${index}].rotation must be one of 0, 90, 180, 270.`);
    }
    const cellKey = `${e.x},${e.y}`;
    if (seenCells.has(cellKey)) throw badRequest(`layout.modules[${index}] duplicates an occupied cell.`);
    seenCells.add(cellKey);

    return { moduleType: e.moduleType as ModuleType, x: e.x, y: e.y, rotation: rotation as 0 | 90 | 180 | 270 };
  });

  return { width, height, modules };
}

/** GET /api/v1/blueprints — list the player's saved layouts. */
export async function listBlueprints(ctx: RequestContext): Promise<Response> {
  const playerId = ctx.auth!.playerId;
  const { results } = await ctx.env.DB.prepare(
    `SELECT id, name, building_kind, layout_json, created_at, updated_at
     FROM blueprints WHERE player_id = ? ORDER BY updated_at DESC`
  )
    .bind(playerId)
    .all<BlueprintRow>();

  return json({ blueprints: (results ?? []).map(serialize) });
}

/** GET /api/v1/blueprints/:id — load a single saved layout. */
export async function getBlueprint(ctx: RequestContext): Promise<Response> {
  const playerId = ctx.auth!.playerId;
  const id = ctx.params.id!;
  const row = await ctx.env.DB.prepare(
    `SELECT id, name, building_kind, layout_json, created_at, updated_at FROM blueprints WHERE id = ? AND player_id = ?`
  )
    .bind(id, playerId)
    .first<BlueprintRow>();
  if (!row) throw notFound('Blueprint');
  return json(serialize(row));
}

/** POST /api/v1/blueprints — save a new layout. */
export async function saveBlueprint(ctx: RequestContext): Promise<Response> {
  const playerId = ctx.auth!.playerId;
  const body = await parseJsonBody(ctx.request);
  const name = requireString(body, 'name', { maxLength: 60 });
  const buildingKind = optionalString(body, 'buildingKind') ?? 'generic';
  const layout = validateLayout(body.layout);

  const now = nowSeconds();
  const id = newId();
  await ctx.env.DB.prepare(
    `INSERT INTO blueprints (id, player_id, name, building_kind, layout_json, created_at, updated_at)
     VALUES (?, ?, ?, ?, ?, ?, ?)`
  )
    .bind(id, playerId, name, buildingKind, JSON.stringify(layout), now, now)
    .run();

  return json({ id, name, buildingKind, layout, createdAt: now, updatedAt: now }, 201);
}
