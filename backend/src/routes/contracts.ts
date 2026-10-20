import type { RequestContext, ResourceMap } from '../types';
import { json, badRequest, conflict } from '../lib/response';
import { parseJsonBody } from '../lib/validation';
import { resolveIdempotencyKey, runIdempotent, fetchStoredResponse } from '../lib/idempotency';
import { getPlayerResources, assertSufficientResources, buildResourceDeltaStatements } from '../lib/resources';
import { newId } from '../lib/auth';
import { nowSeconds } from '../lib/time';
import { loadCityForPlayer } from '../lib/cityLoader';

interface ContractRow {
  id: string;
  code: string;
  title: string;
  description: string;
  required_resources_json: string;
  reward_coins: number;
  reward_blocks: number;
  reward_module_pack_json: string;
  duration_seconds: number;
  min_city_level: number;
  available_from: number;
  available_until: number | null;
}

interface PlayerContractRow {
  id: string;
  contract_id: string;
  status: 'accepted' | 'completed' | 'failed' | 'expired';
  accepted_at: number;
  expires_at: number;
  completed_at: number | null;
}

function serializeContract(row: ContractRow) {
  return {
    id: row.id,
    code: row.code,
    title: row.title,
    description: row.description,
    requiredResources: JSON.parse(row.required_resources_json) as ResourceMap,
    reward: {
      coins: row.reward_coins,
      blocks: row.reward_blocks,
      modulePack: JSON.parse(row.reward_module_pack_json) as Array<{ moduleType: string; quantity: number }>,
    },
    durationSeconds: row.duration_seconds,
    minCityLevel: row.min_city_level,
  };
}

/**
 * GET /api/v1/contracts
 *
 * Returns three buckets: `available` (templates the player can still
 * accept), `active` (already-accepted, not yet expired/completed), and
 * `history` (terminal states, most recent first). Expiry is enforced
 * lazily here — any `accepted` row whose `expires_at` has passed is
 * flipped to `expired` before being returned, since nothing else sweeps it
 * on a timer in this Worker.
 */
export async function listContracts(ctx: RequestContext): Promise<Response> {
  const playerId = ctx.auth!.playerId;
  const now = nowSeconds();
  const city = await loadCityForPlayer(ctx.env, playerId);

  const { results: playerContractRows } = await ctx.env.DB.prepare(
    `SELECT id, contract_id, status, accepted_at, expires_at, completed_at
     FROM player_contracts WHERE player_id = ? ORDER BY accepted_at DESC`
  )
    .bind(playerId)
    .all<PlayerContractRow>();

  const expiredIds = (playerContractRows ?? []).filter((r) => r.status === 'accepted' && r.expires_at < now).map((r) => r.id);
  if (expiredIds.length > 0) {
    await ctx.env.DB.batch(
      expiredIds.map((id) => ctx.env.DB.prepare(`UPDATE player_contracts SET status = 'expired' WHERE id = ?`).bind(id))
    );
  }
  const expiredSet = new Set(expiredIds);

  const contractIds = [...new Set((playerContractRows ?? []).map((r) => r.contract_id))];
  const contractsById = new Map<string, ContractRow>();
  if (contractIds.length > 0) {
    const placeholders = contractIds.map(() => '?').join(',');
    const { results } = await ctx.env.DB.prepare(`SELECT * FROM contracts WHERE id IN (${placeholders})`)
      .bind(...contractIds)
      .all<ContractRow>();
    for (const row of results ?? []) contractsById.set(row.id, row);
  }

  const active: unknown[] = [];
  const history: unknown[] = [];
  const acceptedContractIds = new Set<string>();

  for (const pc of playerContractRows ?? []) {
    const contract = contractsById.get(pc.contract_id);
    if (!contract) continue;
    const effectiveStatus = expiredSet.has(pc.id) ? 'expired' : pc.status;
    const entry = {
      playerContractId: pc.id,
      status: effectiveStatus,
      acceptedAt: pc.accepted_at,
      expiresAt: pc.expires_at,
      completedAt: pc.completed_at,
      contract: serializeContract(contract),
    };
    if (effectiveStatus === 'accepted') {
      active.push(entry);
      acceptedContractIds.add(pc.contract_id);
    } else {
      history.push(entry);
    }
  }

  const { results: availableRows } = await ctx.env.DB.prepare(
    `SELECT * FROM contracts
     WHERE available_from <= ? AND (available_until IS NULL OR available_until >= ?) AND min_city_level <= ?
     ORDER BY available_from DESC`
  )
    .bind(now, now, city.level)
    .all<ContractRow>();

  const available = (availableRows ?? [])
    .filter((row) => !acceptedContractIds.has(row.id))
    .map(serializeContract);

  return json({ available, active, history: history.slice(0, 25) });
}

/**
 * POST /api/v1/contracts/:contractId/accept
 *
 * Starts the delivery window for a contract template. The
 * `idx_player_contracts_active_unique` partial unique index is the real
 * guard against double-accepting the same contract concurrently; this
 * handler's own SELECT check is just there to return a clean 409 instead
 * of a raw constraint-violation error in the common case.
 */
export async function acceptContract(ctx: RequestContext): Promise<Response> {
  const playerId = ctx.auth!.playerId;
  const contractId = ctx.params.contractId!;
  const body = await parseJsonBody(ctx.request);
  const idempotencyKey = resolveIdempotencyKey(ctx.request, body);
  const now = nowSeconds();

  // See the note on submitContract below: this must run before any check
  // that depends on state this same request may have already changed.
  const cached = await fetchStoredResponse<unknown>(ctx.env, playerId, idempotencyKey);
  if (cached !== undefined) return json(cached);

  const contract = await ctx.env.DB.prepare(`SELECT * FROM contracts WHERE id = ?`).bind(contractId).first<ContractRow>();
  if (!contract) throw badRequest('Unknown contract.');
  if (contract.available_from > now || (contract.available_until !== null && contract.available_until < now)) {
    throw conflict('This contract is not currently available.');
  }

  const city = await loadCityForPlayer(ctx.env, playerId);
  if (city.level < contract.min_city_level) {
    throw conflict('City level too low for this contract.', { required: contract.min_city_level, current: city.level });
  }

  const existingActive = await ctx.env.DB.prepare(
    `SELECT id FROM player_contracts WHERE player_id = ? AND contract_id = ? AND status = 'accepted'`
  )
    .bind(playerId, contractId)
    .first<{ id: string }>();
  if (existingActive) throw conflict('You already have this contract in progress.');

  const response = await runIdempotent(ctx.env, playerId, idempotencyKey, 'contract_accept', async () => {
    const playerContractId = newId();
    const expiresAt = now + contract.duration_seconds;

    const statements = [
      ctx.env.DB.prepare(
        `INSERT INTO player_contracts (id, player_id, contract_id, status, accepted_at, expires_at)
         VALUES (?, ?, ?, 'accepted', ?, ?)`
      ).bind(playerContractId, playerId, contractId, now, expiresAt),
    ];

    return {
      statements,
      resourceDeltas: {},
      response: { playerContractId, status: 'accepted', acceptedAt: now, expiresAt, contract: serializeContract(contract) },
    };
  });

  return json(response, 201);
}

/**
 * POST /api/v1/contracts/:playerContractId/submit
 *
 * Delivers the full required resource bundle for an accepted contract in
 * one shot and completes it. The server re-checks (a) the player_contract
 * actually belongs to the caller and is still `accepted`, (b) it hasn't
 * expired, and (c) the player *currently* holds every required resource —
 * all against fresh state — before deducting anything or paying out the
 * reward. Reward module-pack items are credited to `module_inventory`,
 * not placed automatically.
 */
export async function submitContract(ctx: RequestContext): Promise<Response> {
  const playerId = ctx.auth!.playerId;
  const playerContractId = ctx.params.playerContractId!;
  const body = await parseJsonBody(ctx.request);
  const idempotencyKey = resolveIdempotencyKey(ctx.request, body);
  const now = nowSeconds();

  // Replay check first: once this exact request has succeeded, the
  // player_contract's status is already 'completed', which would otherwise
  // make the check below ("is it still accepted?") incorrectly reject a
  // harmless retry.
  const cached = await fetchStoredResponse<unknown>(ctx.env, playerId, idempotencyKey);
  if (cached !== undefined) return json(cached);

  const pc = await ctx.env.DB.prepare(
    `SELECT id, contract_id, status, expires_at FROM player_contracts WHERE id = ? AND player_id = ?`
  )
    .bind(playerContractId, playerId)
    .first<{ id: string; contract_id: string; status: string; expires_at: number }>();
  if (!pc) throw badRequest('Unknown contract instance.');

  if (pc.status !== 'accepted') throw conflict(`Contract is already ${pc.status}.`);
  if (pc.expires_at < now) {
    await ctx.env.DB.prepare(`UPDATE player_contracts SET status = 'expired' WHERE id = ?`).bind(pc.id).run();
    throw conflict('This contract has expired.');
  }

  const contract = await ctx.env.DB.prepare(`SELECT * FROM contracts WHERE id = ?`).bind(pc.contract_id).first<ContractRow>();
  if (!contract) throw badRequest('Unknown contract.');

  const required = JSON.parse(contract.required_resources_json) as ResourceMap;
  const currentResources = await getPlayerResources(ctx.env, playerId);
  assertSufficientResources(currentResources, required);

  const modulePack = JSON.parse(contract.reward_module_pack_json) as Array<{ moduleType: string; quantity: number }>;
  const spendDeltas: ResourceMap = {};
  for (const [resource, amount] of Object.entries(required)) spendDeltas[resource as keyof ResourceMap] = -(amount ?? 0);
  const rewardDeltas: ResourceMap = { COINS: contract.reward_coins, BLOCKS: contract.reward_blocks };
  const netDeltas: ResourceMap = { ...spendDeltas };
  for (const [resource, amount] of Object.entries(rewardDeltas)) {
    netDeltas[resource as keyof ResourceMap] = (netDeltas[resource as keyof ResourceMap] ?? 0) + (amount ?? 0);
  }

  const response = await runIdempotent(ctx.env, playerId, idempotencyKey, 'contract_complete', async () => {
    const statements = [
      ctx.env.DB.prepare(
        `UPDATE player_contracts SET status = 'completed', completed_at = ?, delivered_resources_json = ? WHERE id = ?`
      ).bind(now, JSON.stringify(required), pc.id),
      ...buildResourceDeltaStatements(ctx.env, playerId, netDeltas),
      ...modulePack.map((entry) =>
        ctx.env.DB.prepare(
          `INSERT INTO module_inventory (player_id, module_type, quantity, updated_at)
           VALUES (?, ?, ?, ?)
           ON CONFLICT(player_id, module_type) DO UPDATE SET quantity = quantity + excluded.quantity, updated_at = excluded.updated_at`
        ).bind(playerId, entry.moduleType, entry.quantity, now)
      ),
    ];

    return {
      statements,
      resourceDeltas: netDeltas,
      response: {
        playerContractId: pc.id,
        status: 'completed',
        completedAt: now,
        rewardGranted: { coins: contract.reward_coins, blocks: contract.reward_blocks, modulePack },
        resourcesSpent: required,
      },
    };
  });

  return json(response);
}
