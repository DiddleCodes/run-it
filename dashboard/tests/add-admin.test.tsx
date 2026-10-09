import { render, screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { afterEach, describe, expect, it, vi } from "vitest";
import { toast as sonner } from "sonner";
import { UsersBoard } from "@/components/admin/users-board";
import type { AdminUsersResponse } from "@/lib/api/admin-client";

vi.mock("sonner", () => ({ toast: { success: vi.fn(), error: vi.fn(), message: vi.fn() } }));

const initialData: AdminUsersResponse = { items: [], total: 0, page: 1, limit: 20 };
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json" } });

afterEach(() => vi.restoreAllMocks());

function mockBackend(createResponse: () => Response) {
  const calls: { url: string; body: unknown }[] = [];
  vi.stubGlobal(
    "fetch",
    vi.fn((url: string, opts?: RequestInit) => {
      if (opts?.method === "POST") {
        calls.push({ url, body: JSON.parse(opts.body as string) });
        return Promise.resolve(createResponse());
      }
      return Promise.resolve(json(url.includes("campuses") ? [] : initialData));
    }),
  );
  return calls;
}

describe("Add admin", () => {
  it("sends name and email only (no password), adds the admin to the list and confirms the invite", async () => {
    const user = userEvent.setup();
    const calls = mockBackend(() =>
      json({
        user: { id: "a2", email: "ops@bridgitcampus.com", name: "Ops", phone: null, accountType: "admin", suspendedAt: null, createdAt: "2026-10-09T10:00:00.000Z", campusId: null },
        inviteSent: true,
      }),
    );
    render(<UsersBoard initialData={initialData} />);

    await user.click(screen.getByRole("button", { name: "+ Add admin" }));
    const dialog = screen.getByRole("dialog");
    const submit = within(dialog).getByRole("button", { name: "Add admin" });
    expect(submit).toBeDisabled();
    expect(within(dialog).queryByLabelText(/password/i)).toBeNull();

    await user.type(within(dialog).getByLabelText("Name"), "Ops");
    await user.type(within(dialog).getByLabelText("Email"), "not-an-email");
    expect(submit).toBeDisabled();
    await user.clear(within(dialog).getByLabelText("Email"));
    await user.type(within(dialog).getByLabelText("Email"), "ops@bridgitcampus.com");
    await user.click(submit);

    await waitFor(() => expect(calls).toEqual([{ url: "/api/proxy/admin/users/admins", body: { name: "Ops", email: "ops@bridgitcampus.com" } }]));
    await waitFor(() => expect(screen.queryByRole("dialog")).toBeNull());
    expect(screen.getByText("ops@bridgitcampus.com")).toBeInTheDocument();
    expect(sonner.success).toHaveBeenCalledWith(expect.stringContaining("emailed them a link"), expect.anything());
  });

  it("shows the backend's reason when the email is already taken, and keeps the dialog open", async () => {
    const user = userEvent.setup();
    mockBackend(() => json({ message: "That email already belongs to a restaurant account. Use a different email for the admin." }, 409));
    render(<UsersBoard initialData={initialData} />);

    await user.click(screen.getByRole("button", { name: "+ Add admin" }));
    const dialog = screen.getByRole("dialog");
    await user.type(within(dialog).getByLabelText("Name"), "Chef");
    await user.type(within(dialog).getByLabelText("Email"), "chef@example.com");
    await user.click(within(dialog).getByRole("button", { name: "Add admin" }));

    expect(await within(dialog).findByRole("alert")).toHaveTextContent("already belongs to a restaurant account");
    expect(screen.getByRole("dialog")).toBeInTheDocument();
  });

  it("says so when the admin was added but the invite email didn't send", async () => {
    const user = userEvent.setup();
    mockBackend(() =>
      json({ user: { id: "a3", email: "x@bridgitcampus.com", name: "X", phone: null, accountType: "admin", suspendedAt: null, createdAt: "2026-10-09T10:00:00.000Z", campusId: null }, inviteSent: false }),
    );
    render(<UsersBoard initialData={initialData} />);
    await user.click(screen.getByRole("button", { name: "+ Add admin" }));
    const dialog = screen.getByRole("dialog");
    await user.type(within(dialog).getByLabelText("Name"), "X");
    await user.type(within(dialog).getByLabelText("Email"), "x@bridgitcampus.com");
    await user.click(within(dialog).getByRole("button", { name: "Add admin" }));
    await waitFor(() => expect(sonner.message).toHaveBeenCalledWith(expect.stringContaining("Forgot password?"), expect.anything()));
  });
});
