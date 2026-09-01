import { Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { JwtService } from '@nestjs/jwt';
import { OnGatewayConnection, OnGatewayDisconnect, WebSocketGateway, WebSocketServer } from '@nestjs/websockets';
import { Server, Socket } from 'socket.io';
import { JwtPayload } from '../auth/jwt-payload.interface';

export interface NewJobBroadcast {
  orderId: string;
  vendorId: string;
}

// Task 21a: a runner has no notion of campus server-side yet (nothing in
// this backend persists one — see Task 21's investigation report), and
// campus enforcement is explicitly out of scope for this task. Every
// connected, available runner joins this single pool for now, regardless
// of campus. Swapping this for real per-campus rooms (`campus:<id>`) later
// only touches this constant and handleConnection's room-join call — the
// broadcast/claim logic elsewhere doesn't know or care about room
// granularity.
const RUNNER_POOL_ROOM = 'runners:online';

/**
 * Task 21a: the live channel a runner's app connects to for new-job
 * broadcasts — NotificationsGateway's own doc comment already anticipated
 * this as a separate namespace/gateway rather than an extension of the
 * restaurant-only one, since that gateway's handleConnection hard-rejects
 * any non-vendor token. Same JWT-at-handshake auth shape, same
 * never-cross-namespace isolation, different connection guard (runner
 * accountType, not a Vendor row lookup) and a many-runner room instead of
 * a 1:1 vendor room.
 */
@WebSocketGateway({
  namespace: 'runner-dispatch',
  cors: { origin: (process.env.DASHBOARD_ORIGIN ?? 'http://localhost:3001').split(',') },
})
export class RunnerDispatchGateway implements OnGatewayConnection, OnGatewayDisconnect {
  private readonly logger = new Logger(RunnerDispatchGateway.name);

  @WebSocketServer()
  private server!: Server;

  constructor(
    private readonly jwt: JwtService,
    private readonly config: ConfigService,
  ) {}

  async handleConnection(client: Socket): Promise<void> {
    const token = (client.handshake.auth?.token as string | undefined) ?? (client.handshake.query?.token as string | undefined);

    if (!token) {
      client.emit('error', { message: 'Authentication required' });
      client.disconnect(true);
      return;
    }

    try {
      const payload = await this.jwt.verifyAsync<JwtPayload>(token, { secret: this.config.get<string>('jwt.secret') });

      if (payload.accountType !== 'runner') {
        client.emit('error', { message: 'This channel is for runner accounts only' });
        client.disconnect(true);
        return;
      }

      await client.join(RUNNER_POOL_ROOM);
      client.emit('connected', {});
      this.logger.log(`Runner ${payload.sub} connected to dispatch (socket ${client.id})`);
    } catch {
      client.emit('error', { message: 'Invalid or expired token' });
      client.disconnect(true);
    }
  }

  handleDisconnect(client: Socket): void {
    this.logger.debug(`Socket ${client.id} disconnected`);
  }

  broadcastNewJob(job: NewJobBroadcast): void {
    this.server.to(RUNNER_POOL_ROOM).emit('new_job_available', job);
  }
}
