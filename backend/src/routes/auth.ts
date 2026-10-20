import type { RequestContext } from '../types';
import { json } from '../lib/response';
import { parseJsonBody, requireOneOf, requireString, optionalString } from '../lib/validation';
import { findOrCreatePlayer } from '../lib/cityLoader';
import { createSession } from '../lib/auth';

/**
 * POST /api/v1/auth/bootstrap
 *
 * Single entry point for both first-run and returning-player sign-in. The
 * client always calls this at launch with its Sign in with Apple `sub`
 * (or a locally-generated guest device id) and gets back a bearer token to
 * use for every subsequent request. Idempotent by construction: a repeat
 * bootstrap for the same `authSubject` never re-grants starter resources
 * since the player row (and its one-time starter grants) is only created
 * the first time that auth subject is seen.
 */
export async function bootstrap(ctx: RequestContext): Promise<Response> {
  const body = await parseJsonBody(ctx.request);
  const authProvider = requireOneOf(body, 'authProvider', ['apple', 'guest'] as const);
  const authSubject = requireString(body, 'authSubject', { maxLength: 256 });
  const displayName = optionalString(body, 'displayName')?.slice(0, 40) ?? 'Mayor';

  const { playerId, isNewPlayer } = await findOrCreatePlayer(ctx.env, authProvider, authSubject, displayName);
  const userAgent = ctx.request.headers.get('user-agent');
  const { token, expiresAt } = await createSession(ctx.env, playerId, userAgent);

  return json({
    token,
    tokenType: 'Bearer',
    expiresAt,
    player: { id: playerId, isNewPlayer },
  });
}
