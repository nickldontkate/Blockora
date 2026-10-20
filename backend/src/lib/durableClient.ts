import type { Env, ResourceType } from '../types';

const SINGLETON_ROOM_NAME = 'singleton';

function getRoomStub(env: Env): DurableObjectStub {
  const id = env.WORLD_PROJECT.idFromName(SINGLETON_ROOM_NAME);
  return env.WORLD_PROJECT.get(id);
}

export async function getWorldProjectState(env: Env): Promise<unknown> {
  const stub = getRoomStub(env);
  const res = await stub.fetch('https://world-project.internal/state');
  return res.json();
}

export interface ContributeResult {
  status: number;
  body: unknown;
}

export async function contributeToWorldProject(
  env: Env,
  playerId: string,
  resourceType: ResourceType,
  amount: number,
  idempotencyKey: string
): Promise<ContributeResult> {
  const stub = getRoomStub(env);
  const res = await stub.fetch('https://world-project.internal/contribute', {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ playerId, resourceType, amount, idempotencyKey }),
  });
  const body = await res.json();
  return { status: res.status, body };
}
