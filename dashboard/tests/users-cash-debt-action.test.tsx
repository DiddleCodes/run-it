import { render, screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { afterEach, describe, expect, it, vi } from "vitest";
import { UsersBoard } from "@/components/admin/users-board";
import type { AdminUserDetail, AdminUserSummary, AdminUsersResponse } from "@/lib/api/admin-client";

vi.mock("sonner", () => ({ toast: { success: vi.fn(), error: vi.fn(), message: vi.fn() } }));

// Task 47: a runner carrying a real, unsettled Pay on Delivery cash debt —
// matches GET /admin/users/:id's actual shape (AdminUsersService.getOne).
const runnerSummary: AdminUserSummary = {
  id: "runner-1",
  email: "runner@runit.dev",
  phone: "+2348033334444",
  name: "Tunde Runner",
  accountType: "runner",
  suspendedAt: null,
  createdAt: "2026-08-01T00:00:00.000Z",
  campusId: null,
};

const runnerDetail: AdminUserDetail = {
  ...runnerSummary,
  vendor: null,
  wallet: { balance: 220_000 },
  outstandingCashDebtKobo: 15_000,
};

const initialData: AdminUsersResponse = { items: [runnerSummary], total: 1, page: 1, limit: 20 };

function jsonResponse(body: unknown) {
  return new Response(JSON.stringify(body), { status: 200, headers: { "content-type": "application/json" } });
}

afterEach(() => {
  vi.restoreAllMocks();
});

describe("Runner cash-collection debt visibility and settlement", () => {
  it("shows a runner's real outstanding Pay on Delivery debt and settles it only after confirmation", async () => {
    const user = userEvent.setup();
    let settled = false;
    const fetchMock = vi.fn((url: string, opts?: RequestInit) => {
      if (url === "/api/proxy/campuses") return Promise.resolve(jsonResponse([]));
      if (url === "/api/proxy/admin/users/runner-1") {
        return Promise.resolve(jsonResponse(settled ? { ...runnerDetail, outstandingCashDebtKobo: 0 } : runnerDetail));
      }
      if (opts?.method === "POST" && url === "/api/proxy/admin/users/runner-1/settle-cash-debt") {
        settled = true;
        return Promise.resolve(jsonResponse({ runnerId: "runner-1", settledCount: 1, outstandingCashDebtKobo: 0 }));
      }
      return Promise.resolve(jsonResponse(initialData));
    });
    vi.stubGlobal("fetch", fetchMock);

    render(<UsersBoard initialData={initialData} />);
    const row = () => within(document.querySelector("tbody tr")!);

    await user.click(row().getByText("Tunde Runner"));
    await waitFor(() => expect(screen.getByText("Pay on Delivery cash owed")).toBeInTheDocument());
    expect(screen.getByText("₦150.00")).toBeInTheDocument();

    await user.click(screen.getByRole("button", { name: "Mark settled" }));
    const dialog = within(screen.getByRole("alertdialog"));
    expect(dialog.getByText(/confirmed, outside the app/)).toBeInTheDocument();
    await user.click(dialog.getByRole("button", { name: "Mark settled" }));

    await waitFor(() => expect(screen.queryByText("Pay on Delivery cash owed")).not.toBeInTheDocument());
    expect(fetchMock).toHaveBeenCalledWith(
      "/api/proxy/admin/users/runner-1/settle-cash-debt",
      expect.objectContaining({ method: "POST" }),
    );
  });

  it("never shows the cash-debt section for a runner with nothing outstanding", async () => {
    const user = userEvent.setup();
    const fetchMock = vi.fn((url: string) => {
      if (url === "/api/proxy/campuses") return Promise.resolve(jsonResponse([]));
      if (url === "/api/proxy/admin/users/runner-1") {
        return Promise.resolve(jsonResponse({ ...runnerDetail, outstandingCashDebtKobo: 0 }));
      }
      return Promise.resolve(jsonResponse(initialData));
    });
    vi.stubGlobal("fetch", fetchMock);

    render(<UsersBoard initialData={initialData} />);
    await user.click(within(document.querySelector("tbody tr")!).getByText("Tunde Runner"));

    await waitFor(() => expect(screen.getByText("Wallet balance")).toBeInTheDocument());
    expect(screen.queryByText("Pay on Delivery cash owed")).not.toBeInTheDocument();
  });
});
