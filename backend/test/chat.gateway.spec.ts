/**
 * Task 78: the order-chat socket, over real sockets — a real Nest app
 * serving ChatGateway on a random port, real socket.io clients, real JWTs.
 * Only Prisma is mocked (the order lookup), so this runs in plain `npm test`.
 */
import { INestApplication } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { JwtModule, JwtService } from '@nestjs/jwt';
import { Test } from '@nestjs/testing';
import { AddressInfo } from 'net';
import { io, Socket } from 'socket.io-client';
import { ChatGateway, JoinOrderAck } from '../src/chat/chat.gateway';
import { PrismaService } from '../src/prisma/prisma.service';

const SECRET = 'chat-gateway-test-secret';
const ORDER_ID = '6b0e3a8e-1111-4c3f-9a52-0d8c1f2e3a4b';
const STUDENT = 'student-1';
const RUNNER = 'runner-1';
const STRANGER = 'student-2';

describe('ChatGateway (real sockets)', () => {
  let app: INestApplication;
  let gateway: ChatGateway;
  let jwt: JwtService;
  let url: string;
  const sockets: Socket[] = [];
  const prisma = {
    order: {
      findUnique: jest.fn(async ({ where }: { where: { id: string } }) =>
        where.id === ORDER_ID ? { id: ORDER_ID, status: 'picked_up', studentUserId: STUDENT, runnerUserId: RUNNER } : null,
      ),
    },
  };

  beforeAll(async () => {
    const moduleRef = await Test.createTestingModule({
      imports: [JwtModule.register({ secret: SECRET })],
      providers: [
        ChatGateway,
        { provide: PrismaService, useValue: prisma },
        { provide: ConfigService, useValue: { get: (key: string) => (key === 'jwt.secret' ? SECRET : undefined) } },
      ],
    }).compile();
    app = moduleRef.createNestApplication();
    await app.listen(0);
    gateway = app.get(ChatGateway);
    jwt = app.get(JwtService);
    url = `http://127.0.0.1:${(app.getHttpServer().address() as AddressInfo).port}/order-chat`;
  });

  afterEach(async () => {
    while (sockets.length) sockets.pop()!.disconnect();
    // Let the server see those disconnects before the next test looks.
    await new Promise((r) => setTimeout(r, 100));
  });

  afterAll(async () => {
    await app.close();
  });

  function connect(token?: string): Promise<Socket> {
    const socket = io(url, { transports: ['websocket'], auth: token ? { token } : {}, forceNew: true });
    sockets.push(socket);
    return new Promise((resolve, reject) => {
      socket.once('connected', () => resolve(socket));
      socket.once('error', (err: { message: string }) => reject(new Error(err.message)));
      socket.once('connect_error', reject);
    });
  }

  const tokenFor = (userId: string) => jwt.sign({ sub: userId, role: 'user' });
  const join = (socket: Socket, orderId: string) =>
    socket.timeout(2000).emitWithAck('join_order', { orderId }) as Promise<JoinOrderAck>;

  it('rejects a connection with no token', async () => {
    await expect(connect()).rejects.toThrow('Authentication required');
  });

  it('rejects a connection with a token signed by anyone else', async () => {
    const forged = new JwtService({ secret: 'not-the-real-secret' }).sign({ sub: STUDENT, role: 'user' });
    await expect(connect(forged)).rejects.toThrow('Invalid or expired token');
  });

  it("lets the order's student and its assigned runner join the order's room", async () => {
    const student = await connect(tokenFor(STUDENT));
    const runner = await connect(tokenFor(RUNNER));
    await expect(join(student, ORDER_ID)).resolves.toEqual({ ok: true });
    await expect(join(runner, ORDER_ID)).resolves.toEqual({ ok: true });
  });

  it('refuses a third party — a signed-in user who is not on the order', async () => {
    const stranger = await connect(tokenFor(STRANGER));
    await expect(join(stranger, ORDER_ID)).resolves.toEqual({ ok: false, error: 'You are not part of this order’s chat' });
  });

  it('refuses an order that does not exist', async () => {
    const student = await connect(tokenFor(STUDENT));
    await expect(join(student, '00000000-0000-4000-8000-00000000dead')).resolves.toMatchObject({ ok: false });
  });

  it('delivers a message to both parties in the room, and never to a refused third party', async () => {
    const student = await connect(tokenFor(STUDENT));
    const runner = await connect(tokenFor(RUNNER));
    const stranger = await connect(tokenFor(STRANGER));
    await join(student, ORDER_ID);
    await join(runner, ORDER_ID);
    await join(stranger, ORDER_ID); // refused

    const strangerGot = jest.fn();
    stranger.on('message', strangerGot);
    stranger.on('message_notice', strangerGot);
    const studentGot = new Promise((resolve) => student.once('message', resolve));
    const runnerNotice = new Promise((resolve) => runner.once('message_notice', resolve));

    const message = { id: 'm1', orderId: ORDER_ID, senderUserId: RUNNER, body: 'At the gate', createdAt: new Date(), readAt: null };
    gateway.broadcastMessage(message, [STUDENT, RUNNER]);

    await expect(studentGot).resolves.toMatchObject({ id: 'm1', body: 'At the gate' });
    await expect(runnerNotice).resolves.toMatchObject({ id: 'm1' });
    await new Promise((r) => setTimeout(r, 150));
    expect(strangerGot).not.toHaveBeenCalled();
  });

  it('knows whether a user has the app open (a connected socket) — the push-or-not signal', async () => {
    expect(await gateway.isUserConnected(STUDENT)).toBe(false);
    const student = await connect(tokenFor(STUDENT));
    expect(await gateway.isUserConnected(STUDENT)).toBe(true);
    student.disconnect();
    await new Promise((r) => setTimeout(r, 150));
    expect(await gateway.isUserConnected(STUDENT)).toBe(false);
  });
});
