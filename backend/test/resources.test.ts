import { describe, expect, it } from 'vitest';
import { assertSufficientResources, validateResourceMap } from '../src/lib/resources';
import { ApiError } from '../src/types';
import type { ResourceType } from '../src/types';

const emptyLedger = { COINS: 0, FOOD: 0, ENERGY: 0, GOODS: 0, DATA: 0, BLOCKS: 0 } as Record<ResourceType, number>;

describe('assertSufficientResources', () => {
  it('passes when the player has enough of every required resource', () => {
    const current = { ...emptyLedger, COINS: 100, GOODS: 50 };
    expect(() => assertSufficientResources(current, { COINS: 100, GOODS: 40 })).not.toThrow();
  });

  it('throws a 409 CONFLICT when a resource is short', () => {
    const current = { ...emptyLedger, COINS: 10 };
    try {
      assertSufficientResources(current, { COINS: 100 });
      throw new Error('expected assertSufficientResources to throw');
    } catch (err) {
      expect(err).toBeInstanceOf(ApiError);
      expect((err as ApiError).status).toBe(409);
    }
  });

  it('ignores non-positive requirements', () => {
    const current = { ...emptyLedger };
    expect(() => assertSufficientResources(current, { COINS: 0, GOODS: -5 })).not.toThrow();
  });
});

describe('validateResourceMap', () => {
  it('accepts a well-formed integer resource map', () => {
    expect(validateResourceMap({ COINS: 10, DATA: 5 })).toEqual({ COINS: 10, DATA: 5 });
  });

  it('rejects unknown resource types', () => {
    expect(() => validateResourceMap({ GEMS: 10 })).toThrow(ApiError);
  });

  it('rejects non-integer amounts', () => {
    expect(() => validateResourceMap({ COINS: 1.5 })).toThrow(ApiError);
  });

  it('rejects non-object input', () => {
    expect(() => validateResourceMap('nope')).toThrow(ApiError);
    expect(() => validateResourceMap(null)).toThrow(ApiError);
    expect(() => validateResourceMap([1, 2])).toThrow(ApiError);
  });
});
