import { formatKobo } from '../src/common/display/money';

describe('formatKobo (backend copy)', () => {
  it('matches the app and dashboard format', () => {
    expect(formatKobo(144500)).toBe('₦1,445.00');
    expect(formatKobo(144450)).toBe('₦1,444.50');
    expect(formatKobo(14450000)).toBe('₦144,500.00');
    expect(formatKobo(5)).toBe('₦0.05');
    expect(formatKobo(-144450)).toBe('-₦1,444.50');
  });
});
