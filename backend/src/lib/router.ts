import type { Env, RequestContext, RouteHandler } from '../types';
import { errorResponse, json } from './response';
import { authenticate } from './auth';

interface Route {
  method: string;
  pattern: string;
  segments: string[];
  handler: RouteHandler;
}

/** Minimal hand-rolled router — no external routing dependency needed for
 * the surface area of this API. Supports `:param` path segments only. */
export class Router {
  private routes: Route[] = [];

  private register(method: string, pattern: string, handler: RouteHandler): void {
    this.routes.push({ method, pattern, segments: pattern.split('/').filter(Boolean), handler });
  }

  get(pattern: string, handler: RouteHandler): void {
    this.register('GET', pattern, handler);
  }

  post(pattern: string, handler: RouteHandler): void {
    this.register('POST', pattern, handler);
  }

  delete(pattern: string, handler: RouteHandler): void {
    this.register('DELETE', pattern, handler);
  }

  private match(method: string, pathSegments: string[]): { handler: RouteHandler; params: Record<string, string> } | undefined {
    for (const route of this.routes) {
      if (route.method !== method) continue;
      if (route.segments.length !== pathSegments.length) continue;
      const params: Record<string, string> = {};
      let matched = true;
      for (let i = 0; i < route.segments.length; i++) {
        const routeSeg = route.segments[i]!;
        const pathSeg = pathSegments[i]!;
        if (routeSeg.startsWith(':')) {
          params[routeSeg.slice(1)] = decodeURIComponent(pathSeg);
        } else if (routeSeg !== pathSeg) {
          matched = false;
          break;
        }
      }
      if (matched) return { handler: route.handler, params };
    }
    return undefined;
  }

  async handle(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);
    const pathSegments = url.pathname.split('/').filter(Boolean);
    const found = this.match(request.method, pathSegments);

    if (!found) {
      return json({ error: { code: 'NOT_FOUND', message: 'No such route.', details: null } }, 404);
    }

    const ctx: RequestContext = { env, request, url, params: found.params };

    try {
      return await found.handler(ctx);
    } catch (err) {
      return errorResponse(err);
    }
  }
}

/** Wraps a handler so it requires a valid session before running. */
export function withAuth(handler: RouteHandler): RouteHandler {
  return async (ctx: RequestContext) => {
    ctx.auth = await authenticate(ctx.env, ctx.request);
    return handler(ctx);
  };
}
