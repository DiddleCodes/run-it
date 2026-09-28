import { ServiceUnavailableException } from '@nestjs/common';
import { HealthController } from '../src/health/health.controller';

function controller({ db = true, redis = true } = {}) {
  const prisma = { $queryRaw: jest.fn(() => (db ? Promise.resolve([{ '?column?': 1 }]) : Promise.reject(new Error('down')))) };
  const redisClient = { ping: jest.fn(() => (redis ? Promise.resolve('PONG') : Promise.reject(new Error('down')))) };
  return new HealthController(prisma as any, redisClient as any);
}

describe('HealthController (Task 71)', () => {
  it('200s with both dependencies up', async () => {
    await expect(controller().get()).resolves.toEqual({ status: 'ok', database: 'up', redis: 'up' });
  });

  it('503s naming the database when Postgres is down', async () => {
    const error = await controller({ db: false }).get().catch((e) => e);
    expect(error).toBeInstanceOf(ServiceUnavailableException);
    expect(error.getResponse()).toEqual({ status: 'degraded', database: 'down', redis: 'up' });
  });

  it('503s naming Redis when Redis is down', async () => {
    const error = await controller({ redis: false }).get().catch((e) => e);
    expect(error.getResponse()).toEqual({ status: 'degraded', database: 'up', redis: 'down' });
  });
});
