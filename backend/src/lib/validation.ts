import { badRequest } from './response';

/** Parses a JSON request body, tolerating an empty body as `{}`. */
export async function parseJsonBody(request: Request): Promise<Record<string, unknown>> {
  const text = await request.text();
  if (!text || text.trim().length === 0) return {};
  try {
    const parsed = JSON.parse(text);
    if (typeof parsed !== 'object' || parsed === null || Array.isArray(parsed)) {
      throw badRequest('Request body must be a JSON object.');
    }
    return parsed as Record<string, unknown>;
  } catch (err) {
    if (err instanceof Error && err.name === 'SyntaxError') {
      throw badRequest('Request body must be valid JSON.');
    }
    throw err;
  }
}

export function requireString(body: Record<string, unknown>, field: string, opts?: { maxLength?: number }): string {
  const value = body[field];
  if (typeof value !== 'string' || value.trim().length === 0) {
    throw badRequest(`Field "${field}" is required and must be a non-empty string.`);
  }
  if (opts?.maxLength && value.length > opts.maxLength) {
    throw badRequest(`Field "${field}" must be at most ${opts.maxLength} characters.`);
  }
  return value;
}

export function optionalString(body: Record<string, unknown>, field: string): string | undefined {
  const value = body[field];
  if (value === undefined || value === null) return undefined;
  if (typeof value !== 'string') throw badRequest(`Field "${field}" must be a string.`);
  return value;
}

export function requireInt(body: Record<string, unknown>, field: string, opts?: { min?: number; max?: number }): number {
  const value = body[field];
  if (typeof value !== 'number' || !Number.isInteger(value)) {
    throw badRequest(`Field "${field}" is required and must be an integer.`);
  }
  if (opts?.min !== undefined && value < opts.min) {
    throw badRequest(`Field "${field}" must be >= ${opts.min}.`);
  }
  if (opts?.max !== undefined && value > opts.max) {
    throw badRequest(`Field "${field}" must be <= ${opts.max}.`);
  }
  return value;
}

export function requireOneOf<T extends string>(body: Record<string, unknown>, field: string, allowed: readonly T[]): T {
  const value = body[field];
  if (typeof value !== 'string' || !allowed.includes(value as T)) {
    throw badRequest(`Field "${field}" must be one of: ${allowed.join(', ')}.`);
  }
  return value as T;
}

export function requireArray(body: Record<string, unknown>, field: string): unknown[] {
  const value = body[field];
  if (!Array.isArray(value)) {
    throw badRequest(`Field "${field}" must be an array.`);
  }
  return value;
}
