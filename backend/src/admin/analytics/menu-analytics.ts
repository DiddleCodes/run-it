import { formatKobo } from '../../common/display/money';

/**
 * Which dishes make restaurants the most money — pure, so every rule here
 * is tested without a database.
 *
 * Only delivered orders whose payment wasn't refunded count (the same rule
 * as the restaurant Earnings page). "Earned" is what the restaurant actually
 * gets: each order's payout (food minus Bridgit's commission and fee)
 * split across its dishes in proportion to their price × quantity.
 */

export interface AnalyticsOrder {
  vendorId: string;
  restaurantName: string;
  /** The restaurant's payout on this order, in kobo. */
  restaurantShare: number;
  items: { menuItemId: string | null; name: string; price: number; quantity: number }[];
}

export interface AnalyticsMenuItem {
  id: string;
  vendorId: string;
  name: string;
  isAvailable: boolean;
}

export interface DishStats {
  key: string;
  menuItemId: string | null;
  name: string;
  vendorId: string;
  restaurantName: string;
  salesKobo: number;
  earnedKobo: number;
  quantity: number;
  orders: number;
  /** This dish's share of its restaurant's earnings, 0–100. */
  shareOfRestaurantPct: number;
  previousSalesKobo: number;
  previousQuantity: number;
  /** Change in sales against the previous period; null when it sold nothing then. */
  changePct: number | null;
}

export interface RestaurantStats {
  vendorId: string;
  name: string;
  salesKobo: number;
  earnedKobo: number;
  orders: number;
  itemsSold: number;
  topDish: { name: string; earnedKobo: number; sharePct: number } | null;
  /** Available menu items nobody ordered in the period. */
  unorderedDishes: string[];
}

export type InsightTone = 'positive' | 'warning' | 'info';

export interface Insight {
  kind: 'top_dish' | 'top_restaurant' | 'reliance' | 'rising' | 'new_hit' | 'falling' | 'unordered' | 'no_data';
  tone: InsightTone;
  title: string;
  detail: string;
}

export interface MenuAnalytics {
  totals: { salesKobo: number; earnedKobo: number; orders: number; itemsSold: number; restaurants: number };
  dishes: DishStats[];
  restaurants: RestaurantStats[];
  insights: Insight[];
}

const MAX_DISHES = 50;
const MAX_INSIGHTS = 8;
// Thresholds that keep insights to things worth acting on.
const RELIANCE_MIN_ORDERS = 5;
const RELIANCE_SHARE_PCT = 50;
const TREND_MIN_QUANTITY = 3;
const NEW_HIT_MIN_QUANTITY = 5;
const UNORDERED_MIN_ORDERS = 3;

const dishKey = (vendorId: string, item: { menuItemId: string | null; name: string }) =>
  item.menuItemId ?? `${vendorId}::${item.name.trim().toLowerCase()}`;

const pct = (part: number, whole: number) => (whole > 0 ? (part / whole) * 100 : 0);
const roundPct = (value: number) => Math.round(value);

interface Accumulator {
  key: string;
  menuItemId: string | null;
  name: string;
  vendorId: string;
  restaurantName: string;
  sales: number;
  earned: number;
  quantity: number;
  orderIds: Set<number>;
}

function accumulate(orders: AnalyticsOrder[], currentNames: Map<string, string>) {
  const dishes = new Map<string, Accumulator>();
  orders.forEach((order, orderIndex) => {
    const itemsTotal = order.items.reduce((sum, item) => sum + item.price * item.quantity, 0);
    for (const item of order.items) {
      const key = dishKey(order.vendorId, item);
      const sales = item.price * item.quantity;
      const dish =
        dishes.get(key) ??
        dishes
          .set(key, {
            key,
            menuItemId: item.menuItemId,
            // The dish's current name if it's still on the menu, else the name it was sold under.
            name: (item.menuItemId && currentNames.get(item.menuItemId)) || item.name,
            vendorId: order.vendorId,
            restaurantName: order.restaurantName,
            sales: 0,
            earned: 0,
            quantity: 0,
            orderIds: new Set(),
          })
          .get(key)!;
      dish.sales += sales;
      dish.earned += itemsTotal > 0 ? (order.restaurantShare * sales) / itemsTotal : 0;
      dish.quantity += item.quantity;
      dish.orderIds.add(orderIndex);
    }
  });
  return dishes;
}

export function buildMenuAnalytics(input: {
  current: AnalyticsOrder[];
  previous: AnalyticsOrder[];
  menuItems: AnalyticsMenuItem[];
  periodDays: number;
}): MenuAnalytics {
  const currentNames = new Map(input.menuItems.map((m) => [m.id, m.name]));
  const now = accumulate(input.current, currentNames);
  const before = accumulate(input.previous, currentNames);

  // Restaurants: exact payouts, not the sum of rounded per-dish shares.
  const restaurantTotals = new Map<string, { name: string; sales: number; earned: number; orders: number; itemsSold: number }>();
  for (const order of input.current) {
    const r = restaurantTotals.get(order.vendorId) ?? { name: order.restaurantName, sales: 0, earned: 0, orders: 0, itemsSold: 0 };
    r.earned += order.restaurantShare;
    r.orders += 1;
    for (const item of order.items) {
      r.sales += item.price * item.quantity;
      r.itemsSold += item.quantity;
    }
    restaurantTotals.set(order.vendorId, r);
  }

  const allDishes: DishStats[] = [...now.values()].map((d) => {
    const prev = before.get(d.key);
    const restaurantEarned = restaurantTotals.get(d.vendorId)?.earned ?? 0;
    return {
      key: d.key,
      menuItemId: d.menuItemId,
      name: d.name,
      vendorId: d.vendorId,
      restaurantName: d.restaurantName,
      salesKobo: d.sales,
      earnedKobo: Math.round(d.earned),
      quantity: d.quantity,
      orders: d.orderIds.size,
      shareOfRestaurantPct: roundPct(pct(d.earned, restaurantEarned)),
      previousSalesKobo: prev?.sales ?? 0,
      previousQuantity: prev?.quantity ?? 0,
      changePct: prev && prev.sales > 0 ? roundPct(pct(d.sales - prev.sales, prev.sales)) : null,
    };
  });
  allDishes.sort((a, b) => b.earnedKobo - a.earnedKobo || b.quantity - a.quantity || a.name.localeCompare(b.name));

  const soldMenuItemIds = new Set(allDishes.map((d) => d.menuItemId).filter(Boolean));
  const restaurants: RestaurantStats[] = [...restaurantTotals.entries()]
    .map(([vendorId, r]) => {
      const top = allDishes.find((d) => d.vendorId === vendorId);
      return {
        vendorId,
        name: r.name,
        salesKobo: r.sales,
        earnedKobo: r.earned,
        orders: r.orders,
        itemsSold: r.itemsSold,
        topDish: top ? { name: top.name, earnedKobo: top.earnedKobo, sharePct: top.shareOfRestaurantPct } : null,
        unorderedDishes: input.menuItems
          .filter((m) => m.vendorId === vendorId && m.isAvailable && !soldMenuItemIds.has(m.id))
          .map((m) => m.name)
          .sort((a, b) => a.localeCompare(b)),
      };
    })
    .sort((a, b) => b.earnedKobo - a.earnedKobo);

  const totals = {
    salesKobo: restaurants.reduce((s, r) => s + r.salesKobo, 0),
    earnedKobo: restaurants.reduce((s, r) => s + r.earnedKobo, 0),
    orders: input.current.length,
    itemsSold: restaurants.reduce((s, r) => s + r.itemsSold, 0),
    restaurants: restaurants.length,
  };

  return {
    totals,
    dishes: allDishes.slice(0, MAX_DISHES),
    restaurants,
    insights: buildInsights({ dishes: allDishes, before, restaurants, totals, periodDays: input.periodDays }),
  };
}

function buildInsights(args: {
  dishes: DishStats[];
  before: Map<string, Accumulator>;
  restaurants: RestaurantStats[];
  totals: MenuAnalytics['totals'];
  periodDays: number;
}): Insight[] {
  const { dishes, before, restaurants, totals, periodDays } = args;
  if (totals.orders === 0) {
    return [
      {
        kind: 'no_data',
        tone: 'info',
        title: 'No delivered orders in this period',
        detail: 'Insights appear once restaurants have delivered orders in the selected dates.',
      },
    ];
  }

  const insights: Insight[] = [];
  const period = `the previous ${periodDays} day${periodDays === 1 ? '' : 's'}`;

  const top = dishes[0];
  insights.push({
    kind: 'top_dish',
    tone: 'positive',
    title: `${top.name} is the biggest earner`,
    detail: `${top.name} at ${top.restaurantName} earned the restaurant ${formatKobo(top.earnedKobo)} from ${top.quantity} sold — ${roundPct(pct(top.earnedKobo, totals.earnedKobo))}% of what all restaurants earned.`,
  });

  if (restaurants.length >= 2) {
    const best = restaurants[0];
    insights.push({
      kind: 'top_restaurant',
      tone: 'positive',
      title: `${best.name} earned the most`,
      detail: `${formatKobo(best.earnedKobo)} across ${best.orders} order${best.orders === 1 ? '' : 's'} — ${roundPct(pct(best.earnedKobo, totals.earnedKobo))}% of all restaurant earnings.`,
    });
  }

  // Rising: up at least 50% on sales, with real volume now.
  const rising = dishes
    .filter((d) => d.changePct !== null && d.changePct >= 50 && d.quantity >= TREND_MIN_QUANTITY)
    .sort((a, b) => b.salesKobo - b.previousSalesKobo - (a.salesKobo - a.previousSalesKobo))
    .slice(0, 2);
  for (const d of rising) {
    insights.push({
      kind: 'rising',
      tone: 'positive',
      title: `${d.name} is selling faster`,
      detail: `${d.name} at ${d.restaurantName}: sales up ${d.changePct}% on ${period} (${formatKobo(d.previousSalesKobo)} → ${formatKobo(d.salesKobo)}).`,
    });
  }

  const newHit = dishes.find((d) => d.previousQuantity === 0 && d.quantity >= NEW_HIT_MIN_QUANTITY);
  if (newHit) {
    insights.push({
      kind: 'new_hit',
      tone: 'positive',
      title: `${newHit.name} took off`,
      detail: `${newHit.name} at ${newHit.restaurantName} sold ${newHit.quantity} after none in ${period}.`,
    });
  }

  for (const r of restaurants) {
    if (r.orders >= RELIANCE_MIN_ORDERS && r.topDish && r.topDish.sharePct >= RELIANCE_SHARE_PCT) {
      insights.push({
        kind: 'reliance',
        tone: 'warning',
        title: `${r.name} relies on one dish`,
        detail: `${r.topDish.name} brings in ${r.topDish.sharePct}% of ${r.name}'s earnings. A stock-out or price change there hits them hard.`,
      });
    }
  }

  // Falling: had real volume before, sales at most half of it now — including dishes that stopped selling.
  const currentByKey = new Map(dishes.map((d) => [d.key, d]));
  const falling = [...before.values()]
    .filter((p) => p.quantity >= TREND_MIN_QUANTITY)
    .map((p) => ({ prev: p, now: currentByKey.get(p.key) }))
    .filter(({ prev, now }) => (now?.salesKobo ?? 0) <= prev.sales / 2)
    .sort((a, b) => b.prev.sales - (b.now?.salesKobo ?? 0) - (a.prev.sales - (a.now?.salesKobo ?? 0)))
    .slice(0, 2);
  for (const { prev, now } of falling) {
    const nowSales = now?.salesKobo ?? 0;
    insights.push({
      kind: 'falling',
      tone: 'warning',
      title: `${prev.name} is slowing down`,
      detail: `${prev.name} at ${prev.restaurantName}: sales down ${roundPct(pct(prev.sales - nowSales, prev.sales))}% on ${period} (${formatKobo(prev.sales)} → ${formatKobo(nowSales)}).`,
    });
  }

  for (const r of restaurants) {
    if (r.orders >= UNORDERED_MIN_ORDERS && r.unorderedDishes.length > 0) {
      const shown = r.unorderedDishes.slice(0, 3).join(', ');
      const more = r.unorderedDishes.length > 3 ? ` and ${r.unorderedDishes.length - 3} more` : '';
      insights.push({
        kind: 'unordered',
        tone: 'info',
        title: `${r.unorderedDishes.length} of ${r.name}'s dishes weren't ordered`,
        detail: `Nobody ordered ${shown}${more} in this period, though ${r.name} had ${r.orders} orders. Worth a photo, a price check or a menu trim.`,
      });
    }
  }

  return insights.slice(0, MAX_INSIGHTS);
}
