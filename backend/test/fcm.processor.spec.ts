import { FcmProcessor } from '../src/notifications/fcm.processor';
import { createPrismaMock } from './support/mocks';

function makeProcessor() {
  const fcm = { send: jest.fn() };
  const prisma = createPrismaMock();
  const alerts = { send: jest.fn() };
  const processor = new FcmProcessor(fcm as any, prisma as any, alerts as any);
  return { processor, fcm, prisma, alerts };
}

const job = (data: { userId: string; payload: { title: string; body: string } }) => ({
  id: 'job-1',
  data,
  attemptsMade: 1,
  opts: { attempts: 3 },
});

describe('FcmProcessor.process', () => {
  it('sends to every device token registered for the recipient', async () => {
    const { processor, fcm, prisma } = makeProcessor();
    prisma.deviceToken.findMany.mockResolvedValue([{ token: 'token-a' }, { token: 'token-b' }]);

    await processor.process(job({ userId: 'user-1', payload: { title: 'Hi', body: 'There' } }) as any);

    expect(fcm.send).toHaveBeenCalledWith('token-a', { title: 'Hi', body: 'There' });
    expect(fcm.send).toHaveBeenCalledWith('token-b', { title: 'Hi', body: 'There' });
  });

  it('does nothing (no error) when the recipient has no registered device tokens', async () => {
    const { processor, prisma } = makeProcessor();
    prisma.deviceToken.findMany.mockResolvedValue([]);

    await expect(processor.process(job({ userId: 'user-1', payload: { title: 'Hi', body: 'There' } }) as any)).resolves.toBeUndefined();
  });

  it('prunes a dead token instead of failing the job', async () => {
    const { processor, fcm, prisma } = makeProcessor();
    prisma.deviceToken.findMany.mockResolvedValue([{ token: 'dead-token' }]);
    const err = new Error('not registered') as Error & { code: string };
    err.code = 'messaging/registration-token-not-registered';
    fcm.send.mockRejectedValue(err);

    await expect(processor.process(job({ userId: 'user-1', payload: { title: 'Hi', body: 'There' } }) as any)).resolves.toBeUndefined();
    expect(prisma.deviceToken.delete).toHaveBeenCalledWith({ where: { token: 'dead-token' } });
  });

  it('rethrows a non-dead-token failure so BullMQ retries the job', async () => {
    const { processor, fcm, prisma } = makeProcessor();
    prisma.deviceToken.findMany.mockResolvedValue([{ token: 'token-a' }]);
    fcm.send.mockRejectedValue(new Error('network timeout'));

    await expect(processor.process(job({ userId: 'user-1', payload: { title: 'Hi', body: 'There' } }) as any)).rejects.toThrow(
      'network timeout',
    );
  });
});

describe('FcmProcessor.onFailed', () => {
  it('alerts once retries are exhausted', async () => {
    const { processor, alerts } = makeProcessor();

    await processor.onFailed(
      { ...job({ userId: 'user-1', payload: { title: 'Hi', body: 'There' } }), attemptsMade: 3 } as any,
      new Error('permanent failure'),
    );

    expect(alerts.send).toHaveBeenCalled();
  });

  it('does not alert while retries remain', async () => {
    const { processor, alerts } = makeProcessor();

    await processor.onFailed(job({ userId: 'user-1', payload: { title: 'Hi', body: 'There' } }) as any, new Error('temporary'));

    expect(alerts.send).not.toHaveBeenCalled();
  });
});
