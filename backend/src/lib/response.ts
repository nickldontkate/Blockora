import { ApiError } from '../types';

const JSON_HEADERS = { 'content-type': 'application/json; charset=utf-8' };

export function json(data: unknown, status = 200, extraHeaders?: Record<string, string>): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...JSON_HEADERS, ...(extraHeaders ?? {}) },
  });
}

export function noContent(): Response {
  return new Response(null, { status: 204 });
}

export function errorResponse(err: unknown): Response {
  if (err instanceof ApiError) {
    return json(
      { error: { code: err.code, message: err.message, details: err.details ?? null } },
      err.status
    );
  }
  console.error('Unhandled error', err);
  return json(
    { error: { code: 'INTERNAL_ERROR', message: 'Something went wrong.', details: null } },
    500
  );
}

export function notFound(resource: string): ApiError {
  return new ApiError(404, 'NOT_FOUND', `${resource} not found.`);
}

export function badRequest(message: string, details?: unknown): ApiError {
  return new ApiError(400, 'BAD_REQUEST', message, details);
}

export function unauthorized(message = 'Authentication required.'): ApiError {
  return new ApiError(401, 'UNAUTHORIZED', message);
}

export function forbidden(message: string): ApiError {
  return new ApiError(403, 'FORBIDDEN', message);
}

export function conflict(message: string, details?: unknown): ApiError {
  return new ApiError(409, 'CONFLICT', message, details);
}
