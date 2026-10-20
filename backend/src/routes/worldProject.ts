import type { RequestContext, ResourceType } from '../types';
import { RESOURCE_TYPES } from '../types';
import { json, conflict } from '../lib/response';
import { parseJsonBody, requireInt, requireOneOf } from '../lib/validation';
import { resolveIdempotencyKey, runIdempotent, fetchStoredResponse } from '../lib/idempotency';
import { getPlayerResources, assertSufficientResources, buildResourceDeltaStatements } from '../lib/resources';
import { getWorldProjectState, contributeToWorldProject } from '../lib/durableClient';

/** GET /api/v1/world-project — current shared progress, served by the Durable Object. */
export async function getWorldProject(ctx: RequestContext): Promise<Response> {
  const state = await getWorldProjectState(ctx.env);
  return json(state as object);
}

/**
 * POST /api/v1/world-project/contribute
 *
 * Spends resources out of the player's own balance into the single shared
 * World Project. Two systems have to agree here — D1 (the player's wallet)
 * and the WorldProjectRoom Durable Object (the shared counter) — and D1
 * cannot span a transaction across both. The order chosen is deliberate:
 *
 *   1. Verify (fresh read) the player can actually afford the contribution.
 *   2. Call the Durable Object first. It is idempotent per
 *      (playerId, idempotencyKey), so a retried request never double-counts
 *      the shared progress.
 *   3. Only after the DO confirms the contribution landed, deduct the
 *      resources from the player's D1 balance (also idempotent, via the
 *      `transactions` ledger under the same key).
 *
 * This ordering means the failure mode of a crash between steps 2 and 3 is
 * "player got free credit toward the shared goal" rather than "player was
 * charged but the shared goal didn't move" — the former is a minor economy
 * leak, the latter is a much worse player-facing bug (money vanishes). If
 * step 3 fails, retrying the same request is safe: the DO returns its
 * cached result for step 2, and step 3 simply retries the D1 deduction.
 */
export async function contributeToProject(ctx: RequestContext): Promise<Response> {
  const playerId = ctx.auth!.playerId;
  const body = await parseJsonBody(ctx.request);
  const resourceType = requireOneOf(body, 'resourceType', RESOURCE_TYPES as readonly ResourceType[]);
  const amount = requireInt(body, 'amount', { min: 1 });
  const idempotencyKey = resolveIdempotencyKey(ctx.request, body);

  // Replay check first: a retried request must not re-check affordability
  // against a balance that this same request already deducted from on its
  // first (successful, but perhaps dropped-response) attempt.
  const cached = await fetchStoredResponse<unknown>(ctx.env, playerId, idempotencyKey);
  if (cached !== undefined) return json(cached);

  const currentResources = await getPlayerResources(ctx.env, playerId);
  assertSufficientResources(currentResources, { [resourceType]: amount });

  const doResult = await contributeToWorldProject(ctx.env, playerId, resourceType, amount, idempotencyKey);
  if (doResult.status >= 400) {
    const errBody = doResult.body as { error?: { code?: string; message?: string } };
    throw conflict(errBody.error?.message ?? 'World project contribution rejected.', errBody.error);
  }

  const response = await runIdempotent(ctx.env, playerId, idempotencyKey, 'world_contribution', async () => {
    const statements = buildResourceDeltaStatements(ctx.env, playerId, { [resourceType]: -amount });
    return {
      statements,
      resourceDeltas: { [resourceType]: -amount },
      response: {
        ...(doResult.body as object),
        resourcesSpent: { [resourceType]: amount },
      },
    };
  });

  return json(response);
}
