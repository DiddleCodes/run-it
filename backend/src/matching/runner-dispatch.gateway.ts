import { Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { JwtService } from '@nestjs/jwt';
import { OnGatewayConnection, OnGatewayDisconnect, WebSocketGateway, WebSocketServer } from '@nestjs/websockets';
import { Server, Socket } from 'socket.io';
import { JwtPayload } from '../auth/jwt-payload.interface';

export interface NewJobBroadcast {
  orderId: string;
  vendorId: string;
  campusId: string | null;
}

// Task 26: real per-campus rooms — replaces the single shared
// `runners:online` pool Task 21a's report anticipated swapping out ("a
// one-line swap", confirmed true: this constant plus the two call sites
// below were the whole change). A runner with no assigned campus yet joins
// no room at all (see handleConnection) rather than some fallback shared
// room, so they simply receive nothing until an admin assigns one —
// consistent with MatchingService.listAvailable's same null-campus ->
// empty default.
const campusRoom = (campusId: string): string => `runners:campus:${campusId}`;

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

      if (payload.campusId) {
        await client.join(campusRoom(payload.campusId));
      } else {
        this.logger.warn(`Runner ${payload.sub} connected to dispatch with no assigned campus — will receive no broadcasts`);
      }
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
    if (!job.campusId) {
      this.logger.warn(`broadcastNewJob for order ${job.orderId} skipped — vendor has no assigned campus`);
      return;
    }
    this.server.to(campusRoom(job.campusId)).emit('new_job_available', job);
  }
}
