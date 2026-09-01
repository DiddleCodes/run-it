import { WebhooksProcessor } from '../src/webhooks/webhooks.processor';

function makeProcessor() {
  const webhooks = { applyPaystackEvent: jest.fn() };
  const alerts = { send: jest.fn() };
  const processor = new WebhooksProcessor(webhooks as any, alerts as any);
  return { processor, webhooks, alerts };
}

const job = (overrides: Partial<{ attemptsMade: number; attempts: number; data: unknown }> = {}) => ({
  id: 'job-1',
  data: overrides.data ?? { event: 'charge.success', data: { reference: 'ref1' } },
  attemptsMade: overrides.attemptsMade ?? 1,
  opts: { attempts: overrides.attempts ?? 5 },
});

describe('WebhooksProcessor.process', () => {
  it('delegates to WebhooksService.applyPaystackEvent', async () => {
    const { processor, webhooks } = makeProcessor();
    const jobData = { event: 'charge.success', data: { reference: 'ref1' } };

    await processor.process(job({ data: jobData }) as any);

    expect(webhooks.applyPaystackEvent).toHaveBeenCalledWith(jobData);
  });

  it('rethrows a processing failure so BullMQ retries the job, rather than swallowing it', async () => {
    const { processor, webhooks } = makeProcessor();
    webhooks.applyPaystackEvent.mockRejectedValue(new Error('db unreachable'));

    await expect(processor.process(job() as any)).rejects.toThrow('db unreachable');
  });
});

describe('WebhooksProcessor.onFailed', () => {
  it('does not alert while retries remain', async () => {
    const { processor, alerts } = makeProcessor();

    await processor.onFailed(job({ attemptsMade: 2, attempts: 5 }) as any, new Error('temporary'));

    expect(alerts.send).not.toHaveBeenCalled();
  });

  it('alerts once retries are exhausted', async () => {
    const { processor, alerts } = makeProcessor();

    await processor.onFailed(job({ attemptsMade: 5, attempts: 5 }) as any, new Error('permanent'));

    expect(alerts.send).toHaveBeenCalledWith(
      expect.stringContaining('permanently failed'),
      expect.objectContaining({ jobId: 'job-1', error: 'permanent' }),
    );
  });

  it('does nothing if the job reference is missing', async () => {
    const { processor, alerts } = makeProcessor();

    await processor.onFailed(undefined, new Error('n/a'));

    expect(alerts.send).not.toHaveBeenCalled();
  });
});
