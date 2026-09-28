import { FeaturesController } from '../src/features/features.controller';
import { PricingController } from '../src/features/pricing.controller';
import configuration from '../src/config/configuration';
import { createConfigMock } from './support/mocks';

describe('FeaturesController (Task 67)', () => {
  it('reports Pay on Delivery as off when the flag is unset', () => {
    expect(new FeaturesController(createConfigMock({}) as any).get()).toEqual({ podEnabled: false });
  });

  it('reports Pay on Delivery as on when switched on', () => {
    const config = createConfigMock({ 'features.podEnabled': true });
    expect(new FeaturesController(config as any).get()).toEqual({ podEnabled: true });
  });
});

describe('configuration features.podEnabled (Task 67)', () => {
  const original = process.env.POD_ENABLED;
  afterEach(() => {
    if (original === undefined) delete process.env.POD_ENABLED;
    else process.env.POD_ENABLED = original;
  });

  it.each([
    [undefined, false],
    ['false', false],
    ['TRUE', false],
    ['1', false],
    ['true', true],
  ])('POD_ENABLED=%s → %s', (value, expected) => {
    if (value === undefined) delete process.env.POD_ENABLED;
    else process.env.POD_ENABLED = value;
    expect(configuration().features.podEnabled).toBe(expected);
  });
});

describe('PricingController (Task 70)', () => {
  it('serves the exact numbers hold() charges with', () => {
    const config = createConfigMock({ 'escrow.serviceFeeRate': 0.05, 'escrow.defaultDeliveryFeeKobo': 50_000 });
    expect(new PricingController(config as any).get()).toEqual({
      serviceFeeRate: 0.05,
      deliveryFeeKobo: 50_000,
      groupOrderSurchargeKobo: 15_000,
      standardMainMealCap: 2,
      groupMainMealCap: 4,
    });
  });
});

