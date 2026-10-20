import type { Env, AuthContext } from '../types';
import { unauthorized } from './response';
import { nowSeconds, uuid } from './time';

const SESSION_TTL_SECONDS = 60 * 60 * 24 * 30; // 30 days

/** SHA-256 hex digest of a string, using Web Crypto (available in Workers). */
export async function sha256Hex(input: string): Promise<string> {
  const data = new TextEncoder().encode(input);
  const digest = await crypto.subtle.digest('SHA-256', data);
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, '0')).join('');
}

export function generateBearerToken(): string {
  // 32 bytes of CSPRNG entropy, base64url-encoded.
  const bytes = crypto.getRandomValues(new Uint8Array(32));
  return btoa(String.fromCharCode(...bytes)).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

/**
 * Creates (or reuses) a session for a player and returns the raw bearer
 * token. Only the SHA-256 hash of the token is ever persisted, so a DB leak
 * doesn't hand out usable sessions.
 */
export async function createSession(
  env: Env,
  playerId: string,
  userAgent: string | null
): Promise<{ token: string; expiresAt: number }> {
  const token = generateBearerToken();
  const tokenHash = await sha256Hex(token);
  const now = nowSeconds();
  const expiresAt = now + SESSION_TTL_SECONDS;

  await env.DB.prepare(
    `INSERT INTO sessions (id, player_id, created_at, expires_at, user_agent) VALUES (?, ?, ?, ?, ?)`
  )
    .bind(tokenHash, playerId, now, expiresAt, userAgent)
    .run();

  return { token, expiresAt };
}

/** Resolves a bearer token from the Authorization header into an AuthContext. */
export async function authenticate(env: Env, request: Request): Promise<AuthContext> {
  const authHeader = request.headers.get('authorization') ?? request.headers.get('Authorization');
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    throw unauthorized('Missing bearer token.');
  }
  const token = authHeader.slice('Bearer '.length).trim();
  if (!token) throw unauthorized('Missing bearer token.');

  const tokenHash = await sha256Hex(token);
  const now = nowSeconds();

  const row = await env.DB.prepare(
    `SELECT id, player_id, expires_at, revoked_at FROM sessions WHERE id = ?`
  )
    .bind(tokenHash)
    .first<{ id: string; player_id: string; expires_at: number; revoked_at: number | null }>();

  if (!row) throw unauthorized('Invalid session.');
  if (row.revoked_at) throw unauthorized('Session revoked.');
  if (row.expires_at < now) throw unauthorized('Session expired.');

  return { playerId: row.player_id, sessionId: row.id };
}

export function newId(): string {
  return uuid();
}
