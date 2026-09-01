import { render, screen } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";
import { MetricsBoard } from "@/components/vendor/metrics-board";
import type { Metrics } from "@/lib/api/vendor-client";

// recharts relies on real layout measurement (ResponsiveContainer) which
// jsdom doesn't provide — replace it with a plain data dump so the test
// exercises this component's own sorting/derivation logic, not recharts'
// internal SVG rendering (which isn't this codebase's code to test).
vi.mock("recharts", () => ({
  ResponsiveContainer: ({ children }: { children: React.ReactNode }) => <div>{children}</div>,
  BarChart: ({ data }: { data: { name: string }[] }) => (
    <div data-testid="bar-chart">
      {data.map((d) => (
        <div key={d.name} data-testid="bar-chart-row">
          {d.name}
        </div>
      ))}
    </div>
  ),
  Bar: () => null,
  XAxis: () => null,
  YAxis: () => null,
  CartesianGrid: () => null,
  Tooltip: () => null,
}));

// Real-shaped payload — matches GET /vendors/me/metrics' actual return
// (VendorsService.metrics): unsorted mostOrderedItems, integer kobo.
const metrics: Metrics = {
  from: "2026-08-01T00:00:00.000Z",
  to: "2026-08-30T00:00:00.000Z",
  totalOrders: 4,
  totalRevenue: 400000, // ₦4,000.00
  mostOrderedItems: [
    { menuItemId: "m1", name: "Item B", count: 5, revenue: 150000 },
    { menuItemId: "m2", name: "Item A", count: 10, revenue: 120000 },
    { menuItemId: "m3", name: "Item C", count: 2, revenue: 50000 },
  ],
};

describe("Metrics rendering", () => {
  it("StatCards show real totals, including the client-derived average order value", () => {
    render(<MetricsBoard initialData={metrics} />);

    expect(screen.getByText("₦4,000.00")).toBeInTheDocument(); // total revenue
    expect(screen.getByText("4")).toBeInTheDocument(); // total orders
    // avgOrderValue = 400000 / 4 = 100000 kobo = ₦1,000.00 — a plain
    // division of two real numbers, never a fabricated figure.
    expect(screen.getByText("₦1,000.00")).toBeInTheDocument();
  });

  it("ranks 'most ordered items' by count descending, not the array's original order", () => {
    render(<MetricsBoard initialData={metrics} />);

    const rows = screen.getAllByTestId("bar-chart-row").map((el) => el.textContent);
    expect(rows).toEqual(["Item A", "Item B", "Item C"]); // counts: 10, 5, 2
  });

  it("ranks the 'revenue per item' table by revenue descending", () => {
    render(<MetricsBoard initialData={metrics} />);

    const cells = screen.getAllByRole("row").slice(1); // skip header row
    const names = cells.map((row) => row.textContent);
    // revenues: B=150000, A=120000, C=50000
    expect(names[0]).toContain("Item B");
    expect(names[1]).toContain("Item A");
    expect(names[2]).toContain("Item C");
  });
});
