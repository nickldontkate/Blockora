import type { RequestContext } from '../types';
import { json } from '../lib/response';
import { nowSeconds } from '../lib/time';

interface WorldEventRow {
  id: string;
  code: string;
  title: string;
  description: string;
  modifiers_json: string;
  starts_at: number;
  ends_at: number;
}

function serialize(row: WorldEventRow, now: number) {
  return {
    id: row.id,
    code: row.code,
    title: row.title,
    description: row.description,
    modifiers: JSON.parse(row.modifiers_json),
    startsAt: row.starts_at,
    endsAt: row.ends_at,
    status: row.starts_at <= now ? 'active' : 'upcoming',
  };
}

/**
 * GET /api/v1/world-events
 *
 * Returns currently-active and upcoming (not-yet-started) world events.
 * Ended events are omitted entirely — the client doesn't need a history
 * feed for these. This is a straight D1 read (no KV cache) since it's a
 * lightweight, infrequently-polled endpoint; the hot path that actually
 * needs event modifiers on every production calculation goes through the
 * KV-cached `getActiveWorldEventModifiers` in lib/gameConfig.ts instead.
 */
export async function listWorldEvents(ctx: RequestContext): Promise<Response> {
  const now = nowSeconds();
  const { results } = await ctx.env.DB.prepare(
    `SELECT id, code, title, description, modifiers_json, starts_at, ends_at
     FROM world_events WHERE ends_at >= ? ORDER BY starts_at ASC`
  )
    .bind(now)
    .all<WorldEventRow>();

  const events = (results ?? []).map((row) => serialize(row, now));
  return json({
    active: events.filter((e) => e.status === 'active'),
    upcoming: events.filter((e) => e.status === 'upcoming'),
  });
}
