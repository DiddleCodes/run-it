import { render, screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { afterEach, describe, expect, it, vi } from "vitest";
import { DisputesBoard } from "@/components/admin/disputes-board";
import type { AdminDisputeSummary } from "@/lib/api/admin-client";

vi.mock("sonner", () => ({ toast: { success: vi.fn(), error: vi.fn(), message: vi.fn() } }));

// Real-shaped payload — matches AdminDisputesService.list's actual include shape.
const openDispute: AdminDisputeSummary = {
  id: "dispute-1",
  orderId: "order-abc12345",
  status: "open",
  reason: "Delivery proof submitted — PIN verification unavailable",
  resolutionType: null,
  resolutionNote: null,
  resolvedBy: null,
  resolvedAt: null,
  openedAt: "2026-08-30T14:14:00.000Z",
  order: { id: "order-abc12345", status: "picked_up", totalAmount: 500000, deliveryLocationLabel: "Hall 4" },
};

function deferred<T>() {
  let resolve!: (value: T) => void;
  const promise = new Promise<T>((r) => {
    resolve = r;
  });
  return { promise, resolve };
}

function jsonResponse(body: unknown) {
  return new Response(JSON.stringify(body), { status: 200, headers: { "content-type": "application/json" } });
}

afterEach(() => {
  vi.restoreAllMocks();
});

describe("Disputes resolve action", () => {
  it("resolving as release posts {resolutionType: 'release'} and only updates the row after the response resolves", async () => {
    const user = userEvent.setup();
    const postDeferred = deferred<Response>();
    const refreshDeferred = deferred<Response>();

    const fetchMock = vi.fn((url: string, opts?: RequestInit) => {
      if (opts?.method === "POST" && url === "/api/proxy/admin/disputes/dispute-1/resolve") {
        expect(JSON.parse(opts.body as string)).toEqual({ resolutionType: "release", note: undefined });
        return postDeferred.promise;
      }
      return refreshDeferred.promise;
    });
    vi.stubGlobal("fetch", fetchMock);

    render(<DisputesBoard initialData={[openDispute]} />);
    // A plain DOM query (not RTL's getByRole/getByText) so this keeps working
    // while a dialog is open — dialogs mark the rest of the page aria-hidden,
    // which getByRole excludes by design, and getByText would otherwise match
    // the dialog's own title text (e.g. "Resolve order order-ab...") too.
    const row = () => within(document.querySelector("tbody tr")!);

    expect(row().getByText("Open")).toBeInTheDocument();

    await user.click(row().getByRole("button", { name: "Resolve" }));
    // "Release" is pre-selected by default.
    await user.click(screen.getByRole("button", { name: "Resolve dispute" }));
    const dialog = within(screen.getByRole("alertdialog"));
    await user.click(dialog.getByRole("button", { name: "Confirm" }));

    // No optimistic update: still "Open" while the POST is in flight.
    expect(row().getByText("Open")).toBeInTheDocument();

    postDeferred.resolve(jsonResponse({ ...openDispute, status: "resolved", resolutionType: "release" }));
    await waitFor(() => expect(fetchMock).toHaveBeenCalledTimes(2));
    expect(row().getByText("Open")).toBeInTheDocument();

    const resolvedDispute: AdminDisputeSummary = { ...openDispute, status: "resolved", resolutionType: "release" };
    refreshDeferred.resolve(jsonResponse([resolvedDispute]));

    // The default "Open" tab correctly filters the now-resolved dispute out —
    // switch to "All" to see it, same as a real admin would.
    await waitFor(() => expect(screen.getByText("No disputes here")).toBeInTheDocument());
    await user.click(screen.getByRole("button", { name: /All/ }));
    await waitFor(() => expect(row().getByText("Resolved")).toBeInTheDocument());
    expect(row().queryByText("Open")).not.toBeInTheDocument();
  });

  it("selecting refund and confirming sends {resolutionType: 'refund'}", async () => {
    const user = userEvent.setup();
    const fetchMock = vi.fn((url: string, opts?: RequestInit) => {
      if (opts?.method === "POST" && url === "/api/proxy/admin/disputes/dispute-1/resolve") {
        expect(JSON.parse(opts.body as string)).toEqual({ resolutionType: "refund", note: undefined });
        return Promise.resolve(jsonResponse({ ...openDispute, status: "resolved", resolutionType: "refund" }));
      }
      return Promise.resolve(jsonResponse([{ ...openDispute, status: "resolved", resolutionType: "refund" }]));
    });
    vi.stubGlobal("fetch", fetchMock);

    render(<DisputesBoard initialData={[openDispute]} />);
    // A plain DOM query (not RTL's getByRole/getByText) so this keeps working
    // while a dialog is open — dialogs mark the rest of the page aria-hidden,
    // which getByRole excludes by design, and getByText would otherwise match
    // the dialog's own title text (e.g. "Resolve order order-ab...") too.
    const row = () => within(document.querySelector("tbody tr")!);

    await user.click(row().getByRole("button", { name: "Resolve" }));
    await user.click(screen.getByRole("radio", { name: /Refund/ }));
    await user.click(screen.getByRole("button", { name: "Resolve dispute" }));
    const dialog = within(screen.getByRole("alertdialog"));
    await user.click(dialog.getByRole("button", { name: "Confirm" }));

    await waitFor(() => expect(screen.getByText("No disputes here")).toBeInTheDocument());
    await user.click(screen.getByRole("button", { name: /All/ }));
    await waitFor(() => expect(row().getByText("Resolved")).toBeInTheDocument());
  });
});
