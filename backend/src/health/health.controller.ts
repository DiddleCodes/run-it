import { Controller, Get, Req, ServiceUnavailableException } from '@nestjs/common';
import type { Request } from 'express';
import { PrismaService } from '../prisma/prisma.service';
import { RedisService } from '../redis/redis.service';

const CHECK_TIMEOUT_MS = 2_000;

async function check(probe: () => Promise<unknown>): Promise<'up' | 'down'> {
  try {
    await Promise.race([
      probe(),
      new Promise((_, reject) => setTimeout(() => reject(new Error('timeout')), CHECK_TIMEOUT_MS)),
    ]);
    return 'up';
  } catch {
    return 'down';
  }
}

// Task 71: public liveness + dependency check — what Railway's healthcheck
// (railway.json) and a human both hit. 200 only when Postgres and Redis
// both actually answer; 503 (with which one failed) otherwise, so a deploy
// with a broken DATABASE_URL/REDIS_URL never goes live as "healthy".
// Exposes nothing but up/down.
@Controller('health')
export class HealthController {
  constructor(
    private readonly prisma: PrismaService,
    private readonly redis: RedisService,
  ) {}

  @Get()
  async get() {
    const [database, redis] = await Promise.all([
      check(() => this.prisma.$queryRaw`SELECT 1`),
      check(() => this.redis.ping()),
    ]);
    const body = { status: database === 'up' && redis === 'up' ? 'ok' : 'degraded', database, redis };
    if (body.status !== 'ok') throw new ServiceUnavailableException(body);
    return body;
  }

  // The caller's own address as this server resolved it (trust proxy) —
  // compare with what the caller sees as its public IP to confirm rate
  // limits and the Paystack allowlist see real clients, not the proxy.
  // RUNBOOK.md → "Checking the resolved client IP".
  @Get('client-ip')
  clientIp(@Req() req: Request) {
    return { ip: req.ip };
  }
}
