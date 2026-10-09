import { AdminAnalyticsService } from '../src/admin/analytics/admin-analytics.service';
import { AnalyticsOrder, buildMenuAnalytics } from '../src/admin/analytics/menu-analytics';
import { createPrismaMock } from './support/mocks';

const order = (
  vendorId: string,
  restaurantName: string,
  restaurantShare: number,
  items: [string | null, string, number, number][],
): AnalyticsOrder => ({
  vendorId,
  restaurantName,
  restaurantShare,
  items: items.map(([menuItemId, name, price, quantity]) => ({ menuItemId, name, price, quantity })),
});

// Golden Crust: jollof ₦2,000 and chicken ₦1,000; payout is food minus 15% and a ₦200 fee.
const gc = (items: [string | null, string, number, number][]) => {
  const food = items.reduce((s, [, , p, q]) => s + p * q, 0);
  return order('v-gc', 'Golden Crust', Math.round(food * 0.85) - 20_000, items);
};
const sg = (items: [string | null, string, number, number][]) => {
  const food = items.reduce((s, [, , p, q]) => s + p * q, 0);
  return order('v-sg', 'Spice Garden', Math.round(food * 0.85) - 20_000, items);
};

describe('buildMenuAnalytics — money', () => {
  it("splits each order's payout across its dishes by price × quantity", () => {
    // Food ₦5,000 (jollof 2 × ₦2,000 = ₦4,000; chicken ₦1,000); payout ₦4,050.
    const result = buildMenuAnalytics({
      current: [gc([['m-jollof', 'Jollof', 200_000, 2], ['m-chicken', 'Chicken', 100_000, 1]])],
      previous: [],
      menuItems: [],
      periodDays: 30,
    });

    const [jollof, chicken] = result.dishes;
    expect(jollof).toMatchObject({ name: 'Jollof', salesKobo: 400_000, earnedKobo: 324_000, quantity: 2, orders: 1, shareOfRestaurantPct: 80 });
    expect(chicken).toMatchObject({ name: 'Chicken', salesKobo: 100_000, earnedKobo: 81_000, shareOfRestaurantPct: 20 });
    expect(jollof.earnedKobo + chicken.earnedKobo).toBe(405_000);
    expect(result.restaurants[0]).toMatchObject({ name: 'Golden Crust', salesKobo: 500_000, earnedKobo: 405_000, orders: 1, itemsSold: 3 });
    expect(result.totals).toEqual({ salesKobo: 500_000, earnedKobo: 405_000, orders: 1, itemsSold: 3, restaurants: 1 });
  });

  it('ranks dishes across restaurants by what they earned the restaurant, not by sales or count', () => {
    const result = buildMenuAnalytics({
      current: [
        gc([['m-jollof', 'Jollof', 200_000, 1]]), // earns ₦1,500
        sg([['m-suya', 'Suya', 100_000, 5]]), // earns ₦4,050
        sg([['m-chips', 'Chips', 50_000, 1]]), // earns ₦225
      ],
      previous: [],
      menuItems: [],
      periodDays: 30,
    });
    expect(result.dishes.map((d) => `${d.name} @ ${d.restaurantName}`)).toEqual([
      'Suya @ Spice Garden',
      'Jollof @ Golden Crust',
      'Chips @ Spice Garden',
    ]);
    expect(result.restaurants.map((r) => r.name)).toEqual(['Spice Garden', 'Golden Crust']);
  });

  it("uses a dish's current menu name, and keeps deleted dishes (no menu id) by restaurant + name", () => {
    const result = buildMenuAnalytics({
      current: [gc([['m-jollof', 'Jollof Rice (old name)', 200_000, 1], [null, 'Puff Puff', 50_000, 1]]), gc([[null, 'puff puff ', 50_000, 2]])],
      previous: [],
      menuItems: [{ id: 'm-jollof', vendorId: 'v-gc', name: 'Smoky Jollof', isAvailable: true }],
      periodDays: 7,
    });
    expect(result.dishes.find((d) => d.menuItemId === 'm-jollof')?.name).toBe('Smoky Jollof');
    expect(result.dishes.filter((d) => /puff/i.test(d.name))).toHaveLength(1);
    expect(result.dishes.find((d) => /puff/i.test(d.name))).toMatchObject({ quantity: 3, orders: 2 });
  });

  it('compares sales with the previous period', () => {
    const result = buildMenuAnalytics({
      current: [gc([['m-jollof', 'Jollof', 200_000, 3]])],
      previous: [gc([['m-jollof', 'Jollof', 200_000, 2]])],
      menuItems: [],
      periodDays: 30,
    });
    expect(result.dishes[0]).toMatchObject({ previousSalesKobo: 400_000, previousQuantity: 2, changePct: 50 });
  });
});

describe('buildMenuAnalytics — insights', () => {
  const kinds = (r: ReturnType<typeof buildMenuAnalytics>) => r.insights.map((i) => i.kind);

  it('with no delivered orders, says so and nothing else', () => {
    const result = buildMenuAnalytics({ current: [], previous: [], menuItems: [], periodDays: 30 });
    expect(result.insights).toEqual([expect.objectContaining({ kind: 'no_data', tone: 'info' })]);
    expect(result.dishes).toEqual([]);
  });

  it('names the top dish (with its restaurant and share) and the top restaurant', () => {
    const result = buildMenuAnalytics({
      current: [sg([['m-suya', 'Suya', 100_000, 5]]), gc([['m-jollof', 'Jollof', 200_000, 1]])],
      previous: [],
      menuItems: [],
      periodDays: 30,
    });
    expect(result.insights[0]).toMatchObject({ kind: 'top_dish', tone: 'positive', title: 'Suya is the biggest earner' });
    expect(result.insights[0].detail).toBe(
      'Suya at Spice Garden earned the restaurant ₦4,050.00 from 5 sold — 73% of what all restaurants earned.',
    );
    expect(result.insights[1]).toMatchObject({ kind: 'top_restaurant', title: 'Spice Garden earned the most' });
  });

  it('flags a restaurant that relies on one dish for half its earnings (with enough orders)', () => {
    const orders = [1, 2, 3, 4, 5].map(() => gc([['m-jollof', 'Jollof', 200_000, 1], ['m-water', 'Water', 20_000, 1]]));
    const result = buildMenuAnalytics({ current: orders, previous: [], menuItems: [], periodDays: 30 });
    const reliance = result.insights.find((i) => i.kind === 'reliance');
    expect(reliance).toMatchObject({ tone: 'warning', title: 'Golden Crust relies on one dish' });
    expect(reliance?.detail).toMatch(/^Jollof brings in 91% of Golden Crust's earnings/);

    const fewOrders = buildMenuAnalytics({ current: orders.slice(0, 4), previous: [], menuItems: [], periodDays: 30 });
    expect(kinds(fewOrders)).not.toContain('reliance');
  });

  it('spots rising, newly popular and falling dishes against the previous period', () => {
    const result = buildMenuAnalytics({
      current: [
        gc([['m-jollof', 'Jollof', 200_000, 6]]), // was 2 → rising
        gc([['m-wings', 'Wings', 150_000, 5]]), // new, 5 sold → new hit
        gc([['m-rice', 'Fried Rice', 180_000, 1]]), // was 4 → falling
      ],
      previous: [gc([['m-jollof', 'Jollof', 200_000, 2]]), gc([['m-rice', 'Fried Rice', 180_000, 4]]), gc([['m-beans', 'Beans', 80_000, 3]])],
      menuItems: [],
      periodDays: 7,
    });
    const rising = result.insights.find((i) => i.kind === 'rising');
    expect(rising?.detail).toBe('Jollof at Golden Crust: sales up 200% on the previous 7 days (₦4,000.00 → ₦12,000.00).');
    expect(result.insights.find((i) => i.kind === 'new_hit')?.detail).toBe(
      'Wings at Golden Crust sold 5 after none in the previous 7 days.',
    );
    const falling = result.insights.filter((i) => i.kind === 'falling').map((i) => i.title);
    expect(falling).toEqual(['Fried Rice is slowing down', 'Beans is slowing down']);
    expect(result.insights.find((i) => i.title === 'Beans is slowing down')?.detail).toMatch(/down 100%.*→ ₦0\.00\)/);
  });

  it("lists a busy restaurant's available dishes that nobody ordered — not unavailable ones", () => {
    const orders = [1, 2, 3].map(() => gc([['m-jollof', 'Jollof', 200_000, 1]]));
    const result = buildMenuAnalytics({
      current: orders,
      previous: [],
      menuItems: [
        { id: 'm-jollof', vendorId: 'v-gc', name: 'Jollof', isAvailable: true },
        { id: 'm-yam', vendorId: 'v-gc', name: 'Yam Porridge', isAvailable: true },
        { id: 'm-ofada', vendorId: 'v-gc', name: 'Ofada', isAvailable: true },
        { id: 'm-off', vendorId: 'v-gc', name: 'Seasonal Soup', isAvailable: false },
      ],
      periodDays: 30,
    });
    expect(result.restaurants[0].unorderedDishes).toEqual(['Ofada', 'Yam Porridge']);
    expect(result.insights.find((i) => i.kind === 'unordered')).toMatchObject({
      title: "2 of Golden Crust's dishes weren't ordered",
    });
  });
});

describe('AdminAnalyticsService.menu', () => {
  it('only loads delivered, unrefunded orders — cancelled and refunded never count — and compares with the period before', async () => {
    const prisma = createPrismaMock();
    prisma.order.findMany = jest.fn().mockResolvedValue([]);
    prisma.menuItem.findMany = jest.fn().mockResolvedValue([]);
    prisma.vendor.findMany = jest.fn().mockResolvedValue([{ id: 'v-gc', businessName: 'Golden Crust' }]);
    const service = new AdminAnalyticsService(prisma as any);

    const result = await service.menu({ from: '2026-10-01T00:00:00.000Z', to: '2026-10-08T00:00:00.000Z', vendorId: 'v-gc' });

    const [[current], [previous]] = prisma.order.findMany.mock.calls;
    for (const call of [current, previous]) {
      expect(call.where).toMatchObject({ vendorId: 'v-gc', status: 'delivered', escrow: { status: { not: 'refunded' } } });
    }
    expect(current.where.deliveredAt).toEqual({ gte: new Date('2026-10-01T00:00:00.000Z'), lte: new Date('2026-10-08T00:00:00.000Z') });
    expect(previous.where.deliveredAt).toEqual({ gte: new Date('2026-09-24T00:00:00.000Z'), lt: new Date('2026-10-01T00:00:00.000Z') });
    expect(result.restaurantOptions).toEqual([{ id: 'v-gc', name: 'Golden Crust' }]);
    expect(result.insights[0].kind).toBe('no_data');
  });
});
