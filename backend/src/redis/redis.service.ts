import { Injectable, OnModuleDestroy } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import Redis from 'ioredis';

@Injectable()
export class RedisService extends Redis implements OnModuleDestroy {
  constructor(config: ConfigService) {
    super(config.get<string>('redisUrl') as string);
  }

  /**
   * Fast-path dedupe cache for webhook events, keyed by provider event +
   * reference. This is purely an optimisation to skip re-processing a
   * delivery we've already confirmed handling — it is only ever written
   * *after* the underlying database work has committed, so a crash between
   * "processed" and "cached" just falls through to the (idempotent) database
   * path again. The database's conditional update is what actually
   * guarantees "credited exactly once"; this cache only saves the round
   * trip on true repeat deliveries.
   */
  async wasAlreadyProcessed(key: string): Promise<boolean> {
    return (await this.exists(key)) === 1;
  }

  async markProcessed(key: string, ttlSeconds = 60 * 60 * 24): Promise<void> {
    await this.set(key, '1', 'EX', ttlSeconds);
  }

  async onModuleDestroy() {
    this.disconnect();
  }
}
