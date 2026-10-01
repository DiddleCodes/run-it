import 'reflect-metadata';
import { readdirSync, statSync } from 'fs';
import { join } from 'path';

/**
 * A circular import between two services (A imports B's file, B imports
 * A's) passes type-checking and every unit test — Nest only finds out at
 * startup, when one constructor parameter's type is `undefined` ("Nest
 * can't resolve dependencies of OrdersService (…, ?, …)"). This loads
 * every injectable class and fails on exactly that, with no database,
 * Redis or app bootstrap needed.
 */
const SRC = join(__dirname, '..', 'src');
const INJECTABLE_FILE = /\.(service|gateway|processor|guard|controller)\.ts$/;

function injectableFiles(dir: string): string[] {
  return readdirSync(dir).flatMap((entry) => {
    const path = join(dir, entry);
    if (statSync(path).isDirectory()) return injectableFiles(path);
    return INJECTABLE_FILE.test(entry) ? [path] : [];
  });
}

describe('dependency wiring', () => {
  it('no injectable class has an undefined constructor dependency (a circular import)', () => {
    const files = injectableFiles(SRC);
    expect(files.length).toBeGreaterThan(30);

    const broken: string[] = [];
    for (const file of files) {
      // eslint-disable-next-line @typescript-eslint/no-require-imports
      const exported = require(file) as Record<string, unknown>;
      for (const value of Object.values(exported)) {
        if (typeof value !== 'function') continue;
        const params: unknown[] | undefined = Reflect.getMetadata('design:paramtypes', value);
        if (!params) continue;
        // @Inject(TOKEN) parameters are resolved by token, not by type.
        const byToken = new Set(((Reflect.getMetadata('self:paramtypes', value) ?? []) as { index: number }[]).map((p) => p.index));
        params.forEach((param, index) => {
          if (param === undefined && !byToken.has(index)) broken.push(`${(value as { name: string }).name} [${index}]`);
        });
      }
    }
    expect(broken).toEqual([]);
  });
});
