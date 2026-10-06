import configuration from '../src/config/configuration';

describe('configuration — email sender name', () => {
  const original = process.env.BREVO_SENDER_NAME;
  afterEach(() => {
    if (original === undefined) delete process.env.BREVO_SENDER_NAME;
    else process.env.BREVO_SENDER_NAME = original;
  });

  it('defaults to Bridgit — the "From" name on every OTP and reset email', () => {
    delete process.env.BREVO_SENDER_NAME;
    expect(configuration().brevo.senderName).toBe('Bridgit');
  });

  it('can still be overridden per environment', () => {
    process.env.BREVO_SENDER_NAME = 'Bridgit Support';
    expect(configuration().brevo.senderName).toBe('Bridgit Support');
  });
});
