import { render, screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { afterEach, describe, expect, it, vi } from "vitest";
import { EarningsBoard } from "@/components/vendor/earnings-board";
import type { Earnings } from "@/lib/api/vendor-client";

const earnings: Earnings = {
  from: "2026-09-07T00:00:00.000Z",
  to: "2026-10-07T00:00:00.000Z",
  summary: {
    settledKobo: 170_825,
    settledCount: 2,
    pendingKobo: 48_000,
    pendingCount: 1,
    failedKobo: 99_950,
    failedCount: 1,
  },
  items: [
    {
      orderId: "o-1",
      pickupCode: "5319",
      deliveredAt: "2026-10-07T17:46:00.000Z",
      foodSubtotalKobo: 80_000,
      commissionKobo: 32_000,
      payoutKobo: 48_000,
      payoutStatus: "pending",
    },
    {
      orderId: "o-2",
      pickupCode: "4410",
      deliveredAt: "2026-10-06T09:00:00.000Z",
      foodSubtotalKobo: 154_825,
      commissionKobo: 32_000,
      payoutKobo: 122_825,
      payoutStatus: "settled",
    },
    {
      orderId: "o-3",
      pickupCode: "7702",
      deliveredAt: "2026-10-05T09:00:00.000Z",
      foodSubtotalKobo: 131_950,
      commissionKobo: 32_000,
      payoutKobo: 99_950,
      payoutStatus: "failed",
    },
  ],
};

afterEach(() => vi.unstubAllGlobals());

describe("Restaurant earnings", () => {
  it("shows settled, pending and failed totals in the shared money format", () => {
    render(<EarningsBoard initialData={earnings} />);
    expect(screen.getByText("₦1,708.25")).toBeInTheDocument();
    expect(screen.getByText("Settled (2 orders, this range)")).toBeInTheDocument();
    expect(screen.getAllByText("₦480.00").length).toBeGreaterThan(0);
    expect(screen.getByText("Pending (1 delivered, not yet paid out)")).toBeInTheDocument();
    expect(screen.getAllByText("₦999.50").length).toBeGreaterThan(0);
  });

  it("lists each order by pickup code with food, commission and payout right-aligned, and its status", () => {
    render(<EarningsBoard initialData={earnings} />);
    const row = within(screen.getByText("Order 5319").closest("tr")!);
    expect(row.getByText("₦800.00")).toBeInTheDocument();
    expect(row.getByText("−₦320.00")).toBeInTheDocument();
    expect(row.getByText("₦480.00")).toBeInTheDocument();
    expect(row.getByText("Pending")).toBeInTheDocument();
    // Lagos time, whatever zone this runs in: 17:46 UTC is 18:46 in Lagos.
    expect(row.getByText("7 Oct, 18:46")).toBeInTheDocument();
    expect(row.getByText("₦480.00").closest("td")!.className).toContain("text-right");
    expect(row.getByText("₦480.00").closest("td")!.className).toContain("tabular-nums");
    expect(within(screen.getByText("Order 4410").closest("tr")!).getByText("Settled")).toBeInTheDocument();
  });

  it("flags a failed payout with a way to fix the payout account", () => {
    render(<EarningsBoard initialData={earnings} />);
    expect(screen.getByRole("alert").textContent).toContain("1 payout (₦999.50) couldn't be sent to your bank.");
    const failedRow = within(screen.getByText("Order 7702").closest("tr")!);
    expect(failedRow.getByText("Failed")).toBeInTheDocument();
    expect(failedRow.getByRole("link", { name: "Fix payout account" })).toHaveAttribute("href", "/restaurant/profile");
  });

  it("a new restaurant sees zeros and an honest empty state, no failure banner", () => {
    render(
      <EarningsBoard
        initialData={{
          ...earnings,
          summary: { settledKobo: 0, settledCount: 0, pendingKobo: 0, pendingCount: 0, failedKobo: 0, failedCount: 0 },
          items: [],
        }}
      />,
    );
    expect(screen.getByText("No earnings in this range")).toBeInTheDocument();
    expect(screen.getAllByText("₦0.00")).toHaveLength(3);
    expect(screen.queryByRole("alert")).not.toBeInTheDocument();
  });

  it("a custom range asks for those whole days in Lagos time", async () => {
    const user = userEvent.setup();
    const fetchMock = vi.fn(() =>
      Promise.resolve(new Response(JSON.stringify({ ...earnings, items: [] }), { status: 200, headers: { "content-type": "application/json" } })),
    );
    vi.stubGlobal("fetch", fetchMock);
    render(<EarningsBoard initialData={earnings} />);

    await user.type(screen.getByLabelText("From"), "2026-10-01");
    await user.type(screen.getByLabelText("To"), "2026-10-07");
    await user.click(screen.getByRole("button", { name: "Apply" }));

    await waitFor(() => expect(fetchMock).toHaveBeenCalled());
    const url = decodeURIComponent((fetchMock.mock.calls[0] as unknown as [string])[0]);
    expect(url).toContain("from=2026-09-30T23:00:00.000Z"); // 1 Oct 00:00 Lagos
    expect(url).toContain("to=2026-10-07T22:59:59.999Z"); // 7 Oct 23:59:59 Lagos
    expect(await screen.findByText("No earnings in this range")).toBeInTheDocument();
  });
});
