import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { afterEach, describe, expect, it, vi } from "vitest";
import { ReconciliationBoard } from "@/components/admin/reconciliation-board";
import type { ReconciliationReport, ReconciliationRun } from "@/lib/api/admin-client";

vi.mock("sonner", () => ({ toast: { success: vi.fn(), error: vi.fn(), message: vi.fn() } }));

// Real-shaped payload — matches ReconciliationService.compareAgainstPaystack's
// actual return shape.
const report: ReconciliationReport = {
  from: "2026-08-01T00:00:00.000Z",
  to: "2026-08-30T00:00:00.000Z",
  summary: { matched: 10, missingLocally: 1, missingOnPaystack: 0, amountMismatch: 0, statusMismatch: 0 },
  mismatches: [
    {
      reference: "wallet_fund_ghost123",
      type: "wallet_topup",
      kind: "missing_locally",
      localAmount: null,
      paystackAmount: 5000,
      localStatus: null,
      paystackStatus: "success",
      resolved: false,
    },
  ],
};

const history: ReconciliationRun[] = [
  { id: "run-1", startedAt: "2026-08-30T02:00:00.000Z", finishedAt: "2026-08-30T02:00:05.000Z", walletChecked: 2, transferLegsChecked: 0, mismatchCount: 1, triggeredBy: null },
];

function jsonResponse(body: unknown) {
  return new Response(JSON.stringify(body), { status: 200, headers: { "content-type": "application/json" } });
}

afterEach(() => {
  vi.restoreAllMocks();
});

describe("Reconciliation error handling", () => {
  it("shows a real error state with retry when the initial Paystack-backed report failed to load, instead of crashing", async () => {
    const user = userEvent.setup();
    const fetchMock = vi.fn(() => Promise.resolve(jsonResponse(report)));
    vi.stubGlobal("fetch", fetchMock);

    render(<ReconciliationBoard initialData={null} initialHistory={history} />);

    expect(screen.getByText("Couldn't reach Paystack")).toBeInTheDocument();
    expect(screen.queryByText("Matched")).not.toBeInTheDocument();

    await user.click(screen.getByRole("button", { name: "Retry" }));

    await waitFor(() => expect(screen.getByText("Matched")).toBeInTheDocument());
  });
});

describe("Reconciliation resolve action", () => {
  it("shows the real summary counts and a mismatch row from real data", () => {
    render(<ReconciliationBoard initialData={report} initialHistory={history} />);

    expect(screen.getByText("wallet_fund_ghost123")).toBeInTheDocument();
    // "Missing locally" appears both as a summary card label and the row's
    // issue-kind text — both are real, so just confirm at least one shows.
    expect(screen.getAllByText("Missing locally").length).toBeGreaterThan(0);
    expect(screen.getByText("Scheduled sweep")).toBeInTheDocument();
  });

  it("marking resolved requires a note and posts it, then refreshes the report", async () => {
    const user = userEvent.setup();
    const fetchMock = vi.fn((url: string, opts?: RequestInit) => {
      if (opts?.method === "POST" && url === "/api/proxy/reconciliation/wallet_fund_ghost123/resolve") {
        expect(JSON.parse(opts.body as string)).toEqual({ note: "Confirmed manually with Paystack support" });
        return Promise.resolve(jsonResponse({ reference: "wallet_fund_ghost123" }));
      }
      const resolvedReport: ReconciliationReport = {
        ...report,
        mismatches: [{ ...report.mismatches[0], resolved: true }],
      };
      return Promise.resolve(jsonResponse(resolvedReport));
    });
    vi.stubGlobal("fetch", fetchMock);

    render(<ReconciliationBoard initialData={report} initialHistory={history} />);

    await user.click(screen.getByRole("button", { name: "Mark resolved" }));

    const saveButton = screen.getByRole("button", { name: "Mark resolved" }); // now the modal's footer button
    expect(saveButton).toBeDisabled();

    await user.type(screen.getByLabelText(/Note/), "Confirmed manually with Paystack support");
    await user.click(screen.getByRole("button", { name: "Mark resolved" }));

    await waitFor(() => expect(screen.getByText("Resolved")).toBeInTheDocument());
  });
});
