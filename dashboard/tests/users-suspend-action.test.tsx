import { render, screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { afterEach, describe, expect, it, vi } from "vitest";
import { UsersBoard } from "@/components/admin/users-board";
import type { AdminUserSummary, AdminUsersResponse } from "@/lib/api/admin-client";

vi.mock("sonner", () => ({ toast: { success: vi.fn(), error: vi.fn(), message: vi.fn() } }));

// Real-shaped payload — matches GET /admin/users' actual return shape
// (AdminUsersService.list's explicit USER_SELECT, no password field).
const activeRestaurant: AdminUserSummary = {
  id: "user-1",
  email: "chef@runit.dev",
  phone: "+2348011112222",
  name: "Chef Amaka",
  accountType: "restaurant",
  suspendedAt: null,
  createdAt: "2026-08-01T00:00:00.000Z",
  campusId: null,
};

const initialData: AdminUsersResponse = { items: [activeRestaurant], total: 1, page: 1, limit: 20 };

function jsonResponse(body: unknown) {
  return new Response(JSON.stringify(body), { status: 200, headers: { "content-type": "application/json" } });
}

afterEach(() => {
  vi.restoreAllMocks();
});

describe("Users suspend/reinstate action", () => {
  it("suspending requires a reason and posts it, then only updates the row after the response resolves", async () => {
    const user = userEvent.setup();
    const fetchMock = vi.fn((url: string, opts?: RequestInit) => {
      if (url === "/api/proxy/campuses") return Promise.resolve(jsonResponse([]));
      if (opts?.method === "POST" && url === "/api/proxy/admin/users/user-1/suspend") {
        expect(JSON.parse(opts.body as string)).toEqual({ reason: "Repeated policy violations" });
        return Promise.resolve(jsonResponse({ ...activeRestaurant, suspendedAt: "2026-08-31T00:00:00.000Z" }));
      }
      const suspended: AdminUserSummary = { ...activeRestaurant, suspendedAt: "2026-08-31T00:00:00.000Z" };
      return Promise.resolve(jsonResponse({ items: [suspended], total: 1, page: 1, limit: 20 }));
    });
    vi.stubGlobal("fetch", fetchMock);

    render(<UsersBoard initialData={initialData} />);
    const row = () => within(document.querySelector("tbody tr")!);

    await user.click(row().getByRole("button", { name: "Suspend" }));

    const saveButton = screen.getByRole("button", { name: "Suspend user" });
    expect(saveButton).toBeDisabled();
    expect(screen.getByText(/listing will also be hidden/)).toBeInTheDocument();

    await user.type(screen.getByLabelText(/Reason/), "Repeated policy violations");
    expect(saveButton).toBeEnabled();

    await user.click(saveButton);
    await waitFor(() => expect(row().getByText("Suspended")).toBeInTheDocument());
    expect(row().getByRole("button", { name: "Reinstate" })).toBeInTheDocument();
  });

  it("reinstating requires confirmation and calls the reinstate endpoint", async () => {
    const user = userEvent.setup();
    const suspendedUser: AdminUserSummary = { ...activeRestaurant, suspendedAt: "2026-08-31T00:00:00.000Z" };
    const fetchMock = vi.fn((url: string, opts?: RequestInit) => {
      if (url === "/api/proxy/campuses") return Promise.resolve(jsonResponse([]));
      if (opts?.method === "POST" && url === "/api/proxy/admin/users/user-1/reinstate") {
        return Promise.resolve(jsonResponse({ ...suspendedUser, suspendedAt: null }));
      }
      return Promise.resolve(jsonResponse({ items: [{ ...suspendedUser, suspendedAt: null }], total: 1, page: 1, limit: 20 }));
    });
    vi.stubGlobal("fetch", fetchMock);

    render(<UsersBoard initialData={{ items: [suspendedUser], total: 1, page: 1, limit: 20 }} />);
    const row = () => within(document.querySelector("tbody tr")!);

    await user.click(row().getByRole("button", { name: "Reinstate" }));
    const dialog = within(screen.getByRole("alertdialog"));
    await user.click(dialog.getByRole("button", { name: "Reinstate" }));

    await waitFor(() => expect(row().getByText("Active")).toBeInTheDocument());
  });
});
