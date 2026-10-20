import type { Env, ModuleType } from '../types';
import { RESOURCE_TYPES } from '../types';
import { notFound } from './response';
import { newId } from './auth';
import { nowSeconds } from './time';
import { MODULE_CATALOG, BASE_BUILDING_SUPPORT_CAPACITY } from '../game/moduleCatalog';
import { computeEffectiveModuleRates, type PlacedModuleLite } from '../game/balance';

const STARTER_COINS = 500;
const STARTER_ENERGY = 50;
const STARTER_MODULE_GRANTS: Array<{ moduleType: ModuleType; quantity: number }> = [
  { moduleType: 'SOLAR', quantity: 2 },
  { moduleType: 'STORAGE', quantity: 1 },
  { moduleType: 'FARM_FIELD', quantity: 1 },
];

interface PlayerRow {
  id: string;
  display_name: string;
  created_at: number;
  last_login_at: number;
  last_sync_at: number;
}

/**
 * Looks up a player by their external auth subject, creating the player,
 * their starter city (one district, one building with a CORE module) and
 * starter resources/inventory on first sign-in. All of the creation writes
 * are batched into a single atomic D1 call.
 */
export async function findOrCreatePlayer(
  env: Env,
  authProvider: 'apple' | 'guest',
  authSubject: string,
  displayName: string
): Promise<{ playerId: string; isNewPlayer: boolean }> {
  const existing = await env.DB.prepare(`SELECT id FROM players WHERE auth_subject = ?`)
    .bind(authSubject)
    .first<{ id: string }>();

  const now = nowSeconds();

  if (existing) {
    await env.DB.prepare(`UPDATE players SET last_login_at = ? WHERE id = ?`).bind(now, existing.id).run();
    return { playerId: existing.id, isNewPlayer: false };
  }

  const playerId = newId();
  const cityId = newId();
  const districtId = newId();
  const buildingId = newId();
  const coreModuleId = newId();

  const coreRate = computeEffectiveModuleRates([{ id: coreModuleId, moduleType: 'CORE', x: 0, y: 0 }]);

  const statements: D1PreparedStatement[] = [
    env.DB.prepare(
      `INSERT INTO players (id, auth_subject, auth_provider, display_name, created_at, last_login_at, last_sync_at)
       VALUES (?, ?, ?, ?, ?, ?, ?)`
    ).bind(playerId, authSubject, authProvider, displayName, now, now, now),

    env.DB.prepare(
      `INSERT INTO cities (id, player_id, name, level, founded_at, last_offline_sync_at) VALUES (?, ?, ?, 1, ?, ?)`
    ).bind(cityId, playerId, `${displayName}'s City`, now, now),

    env.DB.prepare(
      `INSERT INTO districts (id, city_id, kind, grid_x, grid_y, unlocked_at) VALUES (?, ?, 'residential', 0, 0, ?)`
    ).bind(districtId, cityId, now),

    env.DB.prepare(
      `INSERT INTO buildings (id, district_id, plot_x, plot_y, name, rotation, support_capacity, created_at, updated_at)
       VALUES (?, ?, 0, 0, 'City Hall', 0, ?, ?, ?)`
    ).bind(buildingId, districtId, BASE_BUILDING_SUPPORT_CAPACITY + MODULE_CATALOG.CORE.support, now, now),

    env.DB.prepare(
      `INSERT INTO building_modules (id, building_id, module_type, grid_x, grid_y, rotation, installed_at, effective_rates_json)
       VALUES (?, ?, 'CORE', 0, 0, 0, ?, ?)`
    ).bind(coreModuleId, buildingId, now, JSON.stringify(coreRate[0])),

    env.DB.prepare(
      `INSERT INTO player_resources (player_id, resource_type, amount, updated_at) VALUES (?, 'COINS', ?, ?)`
    ).bind(playerId, STARTER_COINS, now),

    env.DB.prepare(
      `INSERT INTO player_resources (player_id, resource_type, amount, updated_at) VALUES (?, 'ENERGY', ?, ?)`
    ).bind(playerId, STARTER_ENERGY, now),
  ];

  for (const resource of RESOURCE_TYPES) {
    if (resource === 'COINS' || resource === 'ENERGY') continue;
    statements.push(
      env.DB.prepare(
        `INSERT INTO player_resources (player_id, resource_type, amount, updated_at) VALUES (?, ?, 0, ?)`
      ).bind(playerId, resource, now)
    );
  }

  for (const grant of STARTER_MODULE_GRANTS) {
    statements.push(
      env.DB.prepare(
        `INSERT INTO module_inventory (player_id, module_type, quantity, updated_at) VALUES (?, ?, ?, ?)`
      ).bind(playerId, grant.moduleType, grant.quantity, now)
    );
  }

  await env.DB.batch(statements);

  return { playerId, isNewPlayer: true };
}

export interface LoadedModule {
  id: string;
  moduleType: ModuleType;
  gridX: number;
  gridY: number;
  rotation: number;
  installedAt: number;
}

export interface LoadedBuilding {
  id: string;
  plotX: number;
  plotY: number;
  name: string;
  rotation: number;
  supportCapacity: number;
  modules: LoadedModule[];
}

export interface LoadedDistrict {
  id: string;
  kind: string;
  gridX: number;
  gridY: number;
  unlockedAt: number;
  buildings: LoadedBuilding[];
}

export interface LoadedCity {
  id: string;
  playerId: string;
  name: string;
  level: number;
  foundedAt: number;
  lastOfflineSyncAt: number;
  districts: LoadedDistrict[];
}

/** Loads the full district/building/module graph for a player's city. */
export async function loadCityForPlayer(env: Env, playerId: string): Promise<LoadedCity> {
  const cityRow = await env.DB.prepare(
    `SELECT id, player_id, name, level, founded_at, last_offline_sync_at FROM cities WHERE player_id = ?`
  )
    .bind(playerId)
    .first<{ id: string; player_id: string; name: string; level: number; founded_at: number; last_offline_sync_at: number }>();

  if (!cityRow) throw notFound('City');

  const { results: districtRows } = await env.DB.prepare(
    `SELECT id, kind, grid_x, grid_y, unlocked_at FROM districts WHERE city_id = ? ORDER BY unlocked_at ASC`
  )
    .bind(cityRow.id)
    .all<{ id: string; kind: string; grid_x: number; grid_y: number; unlocked_at: number }>();

  const districts: LoadedDistrict[] = [];
  for (const d of districtRows ?? []) {
    const { results: buildingRows } = await env.DB.prepare(
      `SELECT id, plot_x, plot_y, name, rotation, support_capacity FROM buildings WHERE district_id = ? ORDER BY created_at ASC`
    )
      .bind(d.id)
      .all<{ id: string; plot_x: number; plot_y: number; name: string; rotation: number; support_capacity: number }>();

    const buildings: LoadedBuilding[] = [];
    for (const b of buildingRows ?? []) {
      const { results: moduleRows } = await env.DB.prepare(
        `SELECT id, module_type, grid_x, grid_y, rotation, installed_at FROM building_modules WHERE building_id = ?`
      )
        .bind(b.id)
        .all<{ id: string; module_type: ModuleType; grid_x: number; grid_y: number; rotation: number; installed_at: number }>();

      buildings.push({
        id: b.id,
        plotX: b.plot_x,
        plotY: b.plot_y,
        name: b.name,
        rotation: b.rotation,
        supportCapacity: b.support_capacity,
        modules: (moduleRows ?? []).map((m) => ({
          id: m.id,
          moduleType: m.module_type,
          gridX: m.grid_x,
          gridY: m.grid_y,
          rotation: m.rotation,
          installedAt: m.installed_at,
        })),
      });
    }

    districts.push({
      id: d.id,
      kind: d.kind,
      gridX: d.grid_x,
      gridY: d.grid_y,
      unlockedAt: d.unlocked_at,
      buildings,
    });
  }

  return {
    id: cityRow.id,
    playerId: cityRow.player_id,
    name: cityRow.name,
    level: cityRow.level,
    foundedAt: cityRow.founded_at,
    lastOfflineSyncAt: cityRow.last_offline_sync_at,
    districts,
  };
}

export interface OwnedBuilding {
  id: string;
  districtId: string;
  plotX: number;
  plotY: number;
  supportCapacity: number;
  modules: LoadedModule[];
}

/**
 * Loads a building together with its placed modules, verifying it belongs
 * to a district/city owned by `playerId`. Returns `undefined` if the
 * building doesn't exist or isn't owned by this player (the caller should
 * treat both cases identically as 404 — never leak whether a building id
 * exists under a different player).
 */
export async function getOwnedBuilding(env: Env, playerId: string, buildingId: string): Promise<OwnedBuilding | undefined> {
  const row = await env.DB.prepare(
    `SELECT b.id, b.district_id, b.plot_x, b.plot_y, b.support_capacity
     FROM buildings b
     JOIN districts d ON d.id = b.district_id
     JOIN cities c ON c.id = d.city_id
     WHERE b.id = ? AND c.player_id = ?`
  )
    .bind(buildingId, playerId)
    .first<{ id: string; district_id: string; plot_x: number; plot_y: number; support_capacity: number }>();

  if (!row) return undefined;

  const { results: moduleRows } = await env.DB.prepare(
    `SELECT id, module_type, grid_x, grid_y, rotation, installed_at FROM building_modules WHERE building_id = ?`
  )
    .bind(buildingId)
    .all<{ id: string; module_type: ModuleType; grid_x: number; grid_y: number; rotation: number; installed_at: number }>();

  return {
    id: row.id,
    districtId: row.district_id,
    plotX: row.plot_x,
    plotY: row.plot_y,
    supportCapacity: row.support_capacity,
    modules: (moduleRows ?? []).map((m) => ({
      id: m.id,
      moduleType: m.module_type,
      gridX: m.grid_x,
      gridY: m.grid_y,
      rotation: m.rotation,
      installedAt: m.installed_at,
    })),
  };
}

/** Flattens every placed module in the city into the shape balance.ts expects,
 * tagged with which building it belongs to (synergies only apply within a
 * building's own module grid). */
export function flattenModulesByBuilding(city: LoadedCity): Map<string, PlacedModuleLite[]> {
  const map = new Map<string, PlacedModuleLite[]>();
  for (const district of city.districts) {
    for (const building of district.buildings) {
      map.set(
        building.id,
        building.modules.map((m) => ({ id: m.id, moduleType: m.moduleType, x: m.gridX, y: m.gridY }))
      );
    }
  }
  return map;
}
