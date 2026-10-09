import { PaymentCallbackController } from '../src/paystack/payment-callback.controller';

describe('GET /payments/callback', () => {
  it('shows a plain "go back to the app" page that confirms nothing about the payment', () => {
    const html = new PaymentCallbackController().callback();
    expect(html).toContain('Payment received');
    expect(html).toContain('go back to the Bridgit app');
    expect(html).toContain('once Paystack confirms');
    expect(html).not.toMatch(/<script/i);
  });
});
