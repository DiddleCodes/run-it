import { FeaturesController } from '../src/features/features.controller';
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
