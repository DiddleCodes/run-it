import axios from 'axios';
import { EmailService } from '../src/notifications/email.service';
import { createConfigMock } from './support/mocks';

jest.mock('axios');
const mockedAxios = axios as jest.Mocked<typeof axios>;

function makeService(configValues: Record<string, unknown> = {}) {
  const config = createConfigMock({
    'brevo.apiKey': 'test-api-key',
    'brevo.senderEmail': 'otp@runit.dev',
    'brevo.senderName': 'RUN-It',
    ...configValues,
  });
  return { service: new EmailService(config as any), config };
}

describe('EmailService.isConfigured', () => {
  it('is true when both an API key and sender email are set', () => {
    const { service } = makeService();
    expect(service.isConfigured).toBe(true);
  });

  it('is false when the API key is missing', () => {
    const { service } = makeService({ 'brevo.apiKey': undefined });
    expect(service.isConfigured).toBe(false);
  });

  it('is false when the sender email is missing', () => {
    const { service } = makeService({ 'brevo.senderEmail': undefined });
    expect(service.isConfigured).toBe(false);
  });
});

describe('EmailService.send', () => {
  beforeEach(() => jest.resetAllMocks());

  it('posts to Brevo\'s transactional email API and returns true on success', async () => {
    const { service } = makeService();
    mockedAxios.post.mockResolvedValue({ status: 201 });

    const result = await service.send({
      to: 'student@runit.dev',
      subject: 'Your code',
      html: '<p>123456</p>',
      text: '123456',
    });

    expect(result).toBe(true);
    expect(mockedAxios.post).toHaveBeenCalledWith(
      'https://api.brevo.com/v3/smtp/email',
      expect.objectContaining({
        sender: { name: 'RUN-It', email: 'otp@runit.dev' },
        to: [{ email: 'student@runit.dev' }],
        subject: 'Your code',
      }),
      expect.objectContaining({ headers: expect.objectContaining({ 'api-key': 'test-api-key' }) }),
    );
  });

  it('returns false and never throws when Brevo credentials are unconfigured', async () => {
    const { service } = makeService({ 'brevo.apiKey': undefined });

    const result = await service.send({ to: 'x@runit.dev', subject: 's', html: 'h', text: 't' });

    expect(result).toBe(false);
    expect(mockedAxios.post).not.toHaveBeenCalled();
  });

  it('returns false and never throws when the Brevo request itself fails', async () => {
    const { service } = makeService();
    mockedAxios.post.mockRejectedValue(new Error('network error'));

    const result = await service.send({ to: 'x@runit.dev', subject: 's', html: 'h', text: 't' });

    expect(result).toBe(false);
  });
});
