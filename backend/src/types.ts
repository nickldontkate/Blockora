// Shared types for the BLOCKORA backend Worker.

export interface Env {
  DB: D1Database;
  CONFIG: KVNamespace;
  WORLD_PROJECT: DurableObjectNamespace;
  ENVIRONMENT: string;
  OFFLINE_PRODUCTION_CAP_SECONDS: string;
}

export type ResourceType = 'COINS' | 'FOOD' | 'ENERGY' | 'GOODS' | 'DATA' | 'BLOCKS';

export const RESOURCE_TYPES: ResourceType[] = ['COINS', 'FOOD', 'ENERGY', 'GOODS', 'DATA', 'BLOCKS'];

export type ResourceMap = Partial<Record<ResourceType, number>>;

export type ModuleType =
  | 'SOLAR'
  | 'SERVER'
  | 'COOLING'
  | 'STORAGE'
  | 'CORE'
  | 'FARM_FIELD'
  | 'GREENHOUSE'
  | 'WATER_TANK'
  | 'FACTORY';

export interface AuthContext {
  playerId: string;
  sessionId: string;
}

/** Request context threaded through route handlers. */
export interface RequestContext {
  env: Env;
  request: Request;
  url: URL;
  params: Record<string, string>;
  auth?: AuthContext;
  /** Client-supplied idempotency key, if any (also accepted via header). */
  idempotencyKey?: string;
}

export type RouteHandler = (ctx: RequestContext) => Promise<Response>;

export class ApiError extends Error {
  status: number;
  code: string;
  details?: unknown;

  constructor(status: number, code: string, message: string, details?: unknown) {
    super(message);
    this.status = status;
    this.code = code;
    this.details = details;
  }
}

export interface ModulePlacement {
  moduleType: ModuleType;
  x: number;
  y: number;
  rotation: 0 | 90 | 180 | 270;
}

export interface BlueprintLayout {
  width: number;
  height: number;
  modules: ModulePlacement[];
}
