import type { RequestContext } from '../types';
import { json } from '../lib/response';
import { loadCityForPlayer, flattenModulesByBuilding } from '../lib/cityLoader';
import { getPlayerResources } from '../lib/resources';
import { getActiveWorldEventModifiers } from '../lib/gameConfig';
import { computeEffectiveModuleRates } from '../game/balance';
import { checkStructuralIntegrity } from '../game/balance';
import { BASE_BUILDING_SUPPORT_CAPACITY } from '../game/moduleCatalog';

/**
 * GET /api/v1/city
 *
 * Full city snapshot: resources, districts -> buildings -> modules, each
 * module annotated with its *current* effective production/consumption
 * (post-synergy, post-active-world-event) so the client can render
 * per-module rate labels without re-implementing the balance formulas.
 * This does NOT collect pending production — call
 * `POST /api/v1/production/collect` for that.
 */
export async function getCity(ctx: RequestContext): Promise<Response> {
  const playerId = ctx.auth!.playerId;
  const [city, resources, eventModifiers] = await Promise.all([
    loadCityForPlayer(ctx.env, playerId),
    getPlayerResources(ctx.env, playerId),
    getActiveWorldEventModifiers(ctx.env),
  ]);

  const modulesByBuilding = flattenModulesByBuilding(city);

  const districts = city.districts.map((district) => ({
    id: district.id,
    kind: district.kind,
    gridX: district.gridX,
    gridY: district.gridY,
    unlockedAt: district.unlockedAt,
    buildings: district.buildings.map((building) => {
      const placedModules = modulesByBuilding.get(building.id) ?? [];
      const effectiveRates = computeEffectiveModuleRates(placedModules, eventModifiers);
      const structural = checkStructuralIntegrity(placedModules, BASE_BUILDING_SUPPORT_CAPACITY);
      const ratesById = new Map(effectiveRates.map((r) => [r.id, r]));

      return {
        id: building.id,
        plotX: building.plotX,
        plotY: building.plotY,
        name: building.name,
        rotation: building.rotation,
        structural: {
          totalWeight: structural.totalWeight,
          supportCapacity: structural.totalSupportCapacity,
          isStable: structural.isValid,
        },
        modules: building.modules.map((m) => {
          const rate = ratesById.get(m.id);
          return {
            id: m.id,
            moduleType: m.moduleType,
            gridX: m.gridX,
            gridY: m.gridY,
            rotation: m.rotation,
            installedAt: m.installedAt,
            producesPerHour: rate?.producesPerHour ?? {},
            consumesPerHour: rate?.consumesPerHour ?? {},
            activeSynergies: rate?.activeSynergies ?? [],
          };
        }),
      };
    }),
  }));

  return json({
    city: {
      id: city.id,
      name: city.name,
      level: city.level,
      foundedAt: city.foundedAt,
      lastOfflineSyncAt: city.lastOfflineSyncAt,
    },
    resources,
    activeWorldEventModifiers: eventModifiers,
    districts,
  });
}
