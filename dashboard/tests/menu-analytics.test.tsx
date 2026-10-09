import { render, screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { afterEach, describe, expect, it, vi } from "vitest";
import { MenuAnalyticsBoard } from "@/components/admin/menu-analytics-board";
import type { MenuAnalytics } from "@/lib/api/admin-client";

// recharts needs real layout; the chart itself isn't what's under test.
vi.mock("recharts", async (orig) => {
  const actual = await orig<typeof import("recharts")>();
  return { ...actual, ResponsiveContainer: ({ children }: { children: React.ReactNode }) => <div>{children}</div> };
});

const data: MenuAnalytics = {
  from: "2026-09-09T00:00:00.000Z",
  to: "2026-10-09T00:00:00.000Z",
  previousFrom: "2026-08-10T00:00:00.000Z",
  vendorId: null,
  restaurantOptions: [
    { id: "v-gc", name: "Golden Crust" },
    { id: "v-sg", name: "Spice Garden" },
  ],
  totals: { salesKobo: 900_000, earnedKobo: 725_000, orders: 4, itemsSold: 9, restaurants: 2 },
  dishes: [
    { key: "m-suya", menuItemId: "m-suya", name: "Suya", vendorId: "v-sg", restaurantName: "Spice Garden", salesKobo: 500_000, earnedKobo: 405_000, quantity: 5, orders: 2, shareOfRestaurantPct: 100, previousSalesKobo: 200_000, previousQuantity: 2, changePct: 150 },
    { key: "m-jollof", menuItemId: "m-jollof", name: "Jollof", vendorId: "v-gc", restaurantName: "Golden Crust", salesKobo: 400_000, earnedKobo: 320_000, quantity: 4, orders: 2, shareOfRestaurantPct: 100, previousSalesKobo: 0, previousQuantity: 0, changePct: null },
  ],
  restaurants: [
    { vendorId: "v-sg", name: "Spice Garden", salesKobo: 500_000, earnedKobo: 405_000, orders: 2, itemsSold: 5, topDish: { name: "Suya", earnedKobo: 405_000, sharePct: 100 }, unorderedDishes: ["Chips"] },
    { vendorId: "v-gc", name: "Golden Crust", salesKobo: 400_000, earnedKobo: 320_000, orders: 2, itemsSold: 4, topDish: { name: "Jollof", earnedKobo: 320_000, sharePct: 100 }, unorderedDishes: [] },
  ],
  insights: [
    { kind: "top_dish", tone: "positive", title: "Suya is the biggest earner", detail: "Suya at Spice Garden earned the restaurant ₦4,050.00 from 5 sold — 56% of what all restaurants earned." },
    { kind: "reliance", tone: "warning", title: "Spice Garden relies on one dish", detail: "Suya brings in 100% of Spice Garden's earnings." },
  ],
};

afterEach(() => vi.restoreAllMocks());

describe("Menu analytics", () => {
  it("shows totals, insights, dishes ranked with their restaurant, and restaurants — money in ₦ format", () => {
    render(<MenuAnalyticsBoard initialData={data} />);

    expect(screen.getByText("₦7,250.00")).toBeInTheDocument();
    expect(screen.getByText("₦9,000.00")).toBeInTheDocument();

    const insights = within(screen.getByRole("region", { name: "Insights" })).getAllByRole("listitem");
    expect(insights.map((i) => i.textContent)).toEqual([
      expect.stringContaining("Suya is the biggest earner"),
      expect.stringContaining("Spice Garden relies on one dish"),
    ]);

    const dishes = within(screen.getByRole("region", { name: "Top dishes" }));
    const rows = dishes.getAllByRole("row").slice(1);
    expect(rows[0]).toHaveTextContent(/1\s*Suya\s*Spice Garden\s*5\s*₦5,000\.00\s*₦4,050\.00\s*100%\s*▲ 150%/);
    expect(rows[1]).toHaveTextContent(/2\s*Jollof\s*Golden Crust.*New/);

    const restaurants = within(screen.getByRole("region", { name: "Restaurants" }));
    expect(restaurants.getAllByRole("row")[1]).toHaveTextContent(/Spice Garden\s*2\s*₦5,000\.00\s*₦4,050\.00\s*Suya \(100% of earnings\)\s*1/);
  });

  it("filters to one restaurant and asks the backend for it", async () => {
    const user = userEvent.setup();
    const fetchMock = vi.fn(() =>
      Promise.resolve(new Response(JSON.stringify({ ...data, vendorId: "v-gc", dishes: [data.dishes[1]] }), { status: 200, headers: { "content-type": "application/json" } })),
    );
    vi.stubGlobal("fetch", fetchMock);
    render(<MenuAnalyticsBoard initialData={data} />);

    await user.selectOptions(screen.getByLabelText("Restaurant"), "v-gc");

    await waitFor(() => expect(fetchMock).toHaveBeenCalledWith("/api/proxy/admin/analytics/menu?vendorId=v-gc", expect.anything()));
    await waitFor(() => expect(screen.queryByRole("region", { name: "Restaurants" })).toBeNull());
    expect(within(screen.getByRole("region", { name: "Top dishes" })).queryByText("Suya")).toBeNull();
  });

  it("with no orders, the insight says so and the tables show their empty state", () => {
    render(
      <MenuAnalyticsBoard
        initialData={{
          ...data,
          totals: { salesKobo: 0, earnedKobo: 0, orders: 0, itemsSold: 0, restaurants: 0 },
          dishes: [],
          restaurants: [],
          insights: [{ kind: "no_data", tone: "info", title: "No delivered orders in this period", detail: "Insights appear once restaurants have delivered orders in the selected dates." }],
        }}
      />,
    );
    expect(screen.getByText("No delivered orders in this period")).toBeInTheDocument();
    expect(screen.getByText("No dishes sold in this period")).toBeInTheDocument();
  });
});
