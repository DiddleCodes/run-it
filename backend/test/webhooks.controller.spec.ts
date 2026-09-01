import { UnauthorizedException } from '@nestjs/common';
import { WebhooksController } from '../src/webhooks/webhooks.controller';
import { createPaystackMock } from './support/mocks';

function makeController(queueAddDelayMs = 0) {
  const paystack = createPaystackMock();
  paystack.verifyWebhookSignature.mockReturnValue(true);
  const queue = {
    add: jest.fn(
      () => new Promise((resolve) => setTimeout(() => resolve({ id: 'job-1' }), queueAddDelayMs)),
    ),
  };
  const controller = new WebhooksController(paystack as any, queue as any);
  return { controller, paystack, queue };
}

const req = (body: unknown) => ({ rawBody: Buffer.from(JSON.stringify(body)), body }) as any;

describe('WebhooksController — fast-ack pattern', () => {
  it('rejects immediately when the Paystack signature is invalid, without touching the queue', async () => {
    const { controller, paystack, queue } = makeController();
    paystack.verifyWebhookSignature.mockReturnValue(false);

    await expect(controller.handlePaystack(req({ event: 'charge.success' }), 'bad-sig')).rejects.toThrow(
      UnauthorizedException,
    );
    expect(queue.add).not.toHaveBeenCalled();
  });

  it('enqueues the event and returns 200 immediately, independent of how slow processing would be', async () => {
    // The "slow/failing worker" scenario: even if the consumer side takes
    // seconds (or never returns), the controller's own responsibility ends
    // at handing the job to BullMQ — it never calls into
    // WebhooksService/WebhooksProcessor directly. Modelled here by a queue
    // whose `add()` still resolves quickly regardless of what a hypothetical
    // slow worker is doing concurrently (BullMQ producer/consumer are
    // decoupled via Redis; add() never waits on a consumer).
    const { controller, queue } = makeController(5);
    const body = { event: 'charge.success', data: { reference: 'ref1', amount: 5000 } };

    const start = Date.now();
    const result = await controller.handlePaystack(req(body), 'good-sig');
    const elapsedMs = Date.now() - start;

    expect(result).toEqual({ received: true, queued: true });
    expect(elapsedMs).toBeLessThan(200);
    expect(queue.add).toHaveBeenCalledWith(
      'paystack-event',
      body,
      expect.objectContaining({ attempts: 5 }),
    );
  });

  it('propagates a genuinely broken queue rather than pretending the event was accepted', async () => {
    const { controller, queue } = makeController();
    queue.add.mockRejectedValue(new Error('redis unreachable'));

    await expect(controller.handlePaystack(req({ event: 'charge.success' }), 'good-sig')).rejects.toThrow(
      'redis unreachable',
    );
  });
});
