import type { Env, ResourceMap, ResourceType } from '../types';
import { RESOURCE_TYPES } from '../types';
import { nowSeconds, uuid } from '../lib/time';

/**
 * WorldProjectRoom — single Durable Object instance coordinating the one
 * shared cooperative "World Project" that every player in BLOCKORA
 * contributes to.
 *
 * Why a Durable Object: many players can submit a contribution at the same
 * moment. A Durable Object guarantees a single JavaScript execution
 * context per instance (no two `fetch` calls run concurrently on the same
 * object), so incrementing `progress[resource] += amount` in memory is
 * naturally atomic — no read-modify-write race is possible the way it
 * would be with two concurrent D1 `UPDATE ... SET amount = amount + ?`
 * statements against a table with no row-level serialization guarantee
 * under high write concurrency.
 *
 * The room is addressed with a single, fixed name (see
 * `backend/src/routes/worldProject.ts`, `idFromName('singleton')`) since
 * there is exactly one active world project at a time.
 *
 * Durability model:
 *   - `state.storage` (the DO's own transactional KV storage) is the
 *     source of truth for in-flight progress and idempotency markers. It
 *     survives DO eviction/restart.
 *   - D1 (`world_projects`, `world_contributions`) is a queryable mirror
 *     used by the rest of the API (e.g. showing a contribution history) and
 *     as a durable audit trail. It's updated synchronously within the same
 *     request so it never drifts far from DO state, but the DO does not
 *     depend on D1 being reachable to stay internally consistent.
 */

interface StoredProject {
  id: string;
  code: string;
  title: string;
  description: string;
  goal: ResourceMap;
  progress: ResourceMap;
  status: 'active' | 'completed' | 'archived';
  reward: Record<string, unknown>;
  startedAt: number;
  completedAt: number | null;
}

interface ContributeRequestBody {
  playerId: string;
  resourceType: ResourceType;
  amount: number;
  idempotencyKey: string;
}

function jsonResponse(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), { status, headers: { 'content-type': 'application/json' } });
}

export class WorldProjectRoom {
  private state: DurableObjectState;
  private env: Env;
  private project: StoredProject | null = null;
  private loaded = false;

  constructor(state: DurableObjectState, env: Env) {
    this.state = state;
    this.env = env;
  }

  private async ensureLoaded(): Promise<void> {
    if (this.loaded) return;
    await this.state.blockConcurrencyWhile(async () => {
      const stored = await this.state.storage.get<StoredProject>('project');
      if (stored) {
        this.project = stored;
        this.loaded = true;
        return;
      }

      const row = await this.env.DB.prepare(
        `SELECT id, code, title, description, goal_resources_json, progress_json, status, reward_json, started_at, completed_at
         FROM world_projects WHERE status = 'active' ORDER BY started_at DESC LIMIT 1`
      ).first<{
        id: string;
        code: string;
        title: string;
        description: string;
        goal_resources_json: string;
        progress_json: string;
        status: 'active' | 'completed' | 'archived';
        reward_json: string;
        started_at: number;
        completed_at: number | null;
      }>();

      if (row) {
        this.project = {
          id: row.id,
          code: row.code,
          title: row.title,
          description: row.description,
          goal: JSON.parse(row.goal_resources_json),
          progress: JSON.parse(row.progress_json),
          status: row.status,
          reward: JSON.parse(row.reward_json),
          startedAt: row.started_at,
          completedAt: row.completed_at,
        };
        await this.state.storage.put('project', this.project);
      }
      this.loaded = true;
    });
  }

  private buildStateResponse() {
    if (!this.project) return { project: null };
    const percentByResource: Record<string, number> = {};
    for (const [resource, goalAmount] of Object.entries(this.project.goal)) {
      const current = this.project.progress[resource as ResourceType] ?? 0;
      percentByResource[resource] = goalAmount ? Math.min(1, current / goalAmount) : 1;
    }
    return {
      project: {
        id: this.project.id,
        code: this.project.code,
        title: this.project.title,
        description: this.project.description,
        goal: this.project.goal,
        progress: this.project.progress,
        percentByResource,
        status: this.project.status,
        startedAt: this.project.startedAt,
        completedAt: this.project.completedAt,
      },
    };
  }

  private isGoalMet(): boolean {
    if (!this.project) return false;
    return Object.entries(this.project.goal).every(
      ([resource, goalAmount]) => (this.project!.progress[resource as ResourceType] ?? 0) >= (goalAmount ?? 0)
    );
  }

  private async persistToD1(contributionRow: {
    id: string;
    playerId: string;
    resourceType: ResourceType;
    amount: number;
    idempotencyKey: string;
    contributedAt: number;
  }): Promise<void> {
    if (!this.project) return;
    try {
      const statements: D1PreparedStatement[] = [
        this.env.DB.prepare(
          `INSERT INTO world_contributions (id, world_project_id, player_id, resource_type, amount, idempotency_key, contributed_at)
           VALUES (?, ?, ?, ?, ?, ?, ?)`
        ).bind(
          contributionRow.id,
          this.project.id,
          contributionRow.playerId,
          contributionRow.resourceType,
          contributionRow.amount,
          contributionRow.idempotencyKey,
          contributionRow.contributedAt
        ),
        this.env.DB.prepare(
          `UPDATE world_projects SET progress_json = ?, status = ?, completed_at = ? WHERE id = ?`
        ).bind(
          JSON.stringify(this.project.progress),
          this.project.status,
          this.project.completedAt,
          this.project.id
        ),
      ];
      await this.env.DB.batch(statements);
    } catch (err) {
      // D1 is a mirror here, not the source of truth for this room's
      // in-memory/DO-storage state. A transient D1 failure must not corrupt
      // or roll back an already-durably-recorded contribution — log and
      // move on; a periodic reconciliation job (not implemented here) could
      // re-sync progress_json from world_contributions if this ever drifts.
      console.error('WorldProjectRoom: failed to mirror contribution to D1', err);
    }
  }

  async fetch(request: Request): Promise<Response> {
    await this.ensureLoaded();
    const url = new URL(request.url);

    if (request.method === 'GET' && url.pathname === '/state') {
      return jsonResponse(this.buildStateResponse());
    }

    if (request.method === 'POST' && url.pathname === '/contribute') {
      if (!this.project) {
        return jsonResponse({ error: { code: 'NO_ACTIVE_PROJECT', message: 'No active world project.' } }, 409);
      }
      if (this.project.status !== 'active') {
        return jsonResponse({ error: { code: 'PROJECT_CLOSED', message: 'This world project is no longer accepting contributions.' } }, 409);
      }

      let body: ContributeRequestBody;
      try {
        body = await request.json();
      } catch {
        return jsonResponse({ error: { code: 'BAD_REQUEST', message: 'Invalid JSON body.' } }, 400);
      }

      if (!body.playerId || typeof body.playerId !== 'string') {
        return jsonResponse({ error: { code: 'BAD_REQUEST', message: 'playerId is required.' } }, 400);
      }
      if (!RESOURCE_TYPES.includes(body.resourceType)) {
        return jsonResponse({ error: { code: 'BAD_REQUEST', message: 'Invalid resourceType.' } }, 400);
      }
      if (!Number.isInteger(body.amount) || body.amount <= 0) {
        return jsonResponse({ error: { code: 'BAD_REQUEST', message: 'amount must be a positive integer.' } }, 400);
      }
      if (!body.idempotencyKey || typeof body.idempotencyKey !== 'string') {
        return jsonResponse({ error: { code: 'BAD_REQUEST', message: 'idempotencyKey is required.' } }, 400);
      }
      if (!this.project.goal[body.resourceType]) {
        return jsonResponse(
          { error: { code: 'RESOURCE_NOT_NEEDED', message: `This project does not need ${body.resourceType}.` } },
          400
        );
      }

      // Idempotency: this DO instance processes one request at a time, so
      // this check-then-set is race-free by construction (no await between
      // the get and the set below touches shared mutable state).
      const dedupeKey = `contrib:${body.playerId}:${body.idempotencyKey}`;
      const existing = await this.state.storage.get<{ response: unknown }>(dedupeKey);
      if (existing) {
        return jsonResponse(existing.response);
      }

      // Atomic increment — single-threaded JS execution per DO instance is
      // what makes this safe under concurrent contributions from many
      // players hitting the same world project simultaneously.
      const before = this.project.progress[body.resourceType] ?? 0;
      this.project.progress[body.resourceType] = before + body.amount;

      // We only reach here when status was 'active' (checked above), so
      // reaching the goal now always means "just completed".
      let justCompleted = false;
      if (this.isGoalMet()) {
        this.project.status = 'completed';
        this.project.completedAt = nowSeconds();
        justCompleted = true;
      }

      await this.state.storage.put('project', this.project);

      const contributedAt = nowSeconds();
      const contributionId = uuid();
      const responseBody = {
        accepted: true,
        contributionId,
        resourceType: body.resourceType,
        amount: body.amount,
        project: this.buildStateResponse().project,
        projectJustCompleted: justCompleted,
      };

      await this.state.storage.put(dedupeKey, { response: responseBody });

      await this.persistToD1({
        id: contributionId,
        playerId: body.playerId,
        resourceType: body.resourceType,
        amount: body.amount,
        idempotencyKey: body.idempotencyKey,
        contributedAt,
      });

      return jsonResponse(responseBody);
    }

    return jsonResponse({ error: { code: 'NOT_FOUND', message: 'No such internal route.' } }, 404);
  }
}
