import { render, screen } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";
import { PlatformMetricsBoard } from "@/components/admin/platform-metrics-board";
import type { PlatformMetrics } from "@/lib/api/admin-client";

// recharts relies on real layout measurement (ResponsiveContainer) which
// jsdom doesn't provide — replace it with a plain data dump, same
// discipline as tests/metrics-rendering.test.tsx.
vi.mock("recharts", () => ({
  ResponsiveContainer: ({ children }: { children: React.ReactNode }) => <div>{children}</div>,
  BarChart: ({ data }: { data: { category: string }[] }) => (
    <div data-testid="bar-chart">
      {data.map((d) => (
        <div key={d.category} data-testid="bar-chart-row">
          {d.category}
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

// Real-shaped payload — matches GET /admin/metrics' actual return
// (AdminPlatformMetricsService.metrics).
const metrics: PlatformMetrics = {
  from: "2026-08-01T00:00:00.000Z",
  to: "2026-08-30T00:00:00.000Z",
  gmv: 1_200_000,
  orderVolume: 24,
  activeVendors: 6,
  activeRunners: 3,
  platformRevenue: 180_000,
  takeRatePct: 15,
  categoryBreakdown: [
    { category: "Nigerian", gmv: 800_000 },
    { category: "Drinks", gmv: 400_000 },
  ],
};

describe("Platform metrics rendering", () => {
  it("shows the real StatCard numbers, not fabricated placeholders", () => {
    render(<PlatformMetricsBoard initialData={metrics} />);

    expect(screen.getByText("₦12,000.00")).toBeInTheDocument(); // GMV
    expect(screen.getByText("24")).toBeInTheDocument(); // order volume
    expect(screen.getByText("6")).toBeInTheDocument(); // active vendors
    expect(screen.getByText("3")).toBeInTheDocument(); // active runners
    expect(screen.getByText("₦1,800.00 (15.0%)")).toBeInTheDocument(); // platform revenue + take rate
  });

  it("renders the category breakdown chart with real categories", () => {
    render(<PlatformMetricsBoard initialData={metrics} />);

    const rows = screen.getAllByTestId("bar-chart-row").map((r) => r.textContent);
    expect(rows).toEqual(["Nigerian", "Drinks"]);
  });
});
