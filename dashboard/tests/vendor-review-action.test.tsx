import { render, screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { afterEach, describe, expect, it, vi } from "vitest";
import { VendorReviewBoard } from "@/components/admin/vendor-review-board";
import type { AdminVendorDetail, AdminVendorsResponse, AdminVendorSummary } from "@/lib/api/admin-client";

vi.mock("sonner", () => ({ toast: { success: vi.fn(), error: vi.fn(), message: vi.fn() } }));

// Real-shaped payload — matches GET /admin/vendors' actual return shape
// (AdminVendorReviewService.list: vendor row + { name, email, phone }).
const pendingVendor: AdminVendorSummary = {
  id: "vendor-1",
  userId: "user-1",
  businessName: "Suya Spot",
  category: "Nigerian",
  description: "Grilled meat and sides",
  logoUrl: null,
  status: "pending",
  rejectionReason: null,
  createdAt: "2026-08-30T14:14:00.000Z",
  commissionRateOverride: null,
  user: { name: "Adaeze Okoro", email: "adaeze@runit.dev", phone: "+2348012345678" },
};

const pendingVendorDetail: AdminVendorDetail = {
  ...pendingVendor,
  user: { ...pendingVendor.user, createdAt: "2026-08-01T00:00:00.000Z" },
  payoutAccount: null,
};

const initialData: AdminVendorsResponse = { items: [pendingVendor], total: 1, page: 1, limit: 20 };

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

describe("Vendor review action", () => {
  it("approving a pending vendor calls POST /admin/vendors/:id/approve and only updates the row after the response resolves", async () => {
    const user = userEvent.setup();
    const postDeferred = deferred<Response>();
    const refreshDeferred = deferred<Response>();

    const fetchMock = vi.fn((url: string, opts?: RequestInit) => {
      if (opts?.method === "POST" && url === "/api/proxy/admin/vendors/vendor-1/approve") {
        return postDeferred.promise;
      }
      return refreshDeferred.promise;
    });
    vi.stubGlobal("fetch", fetchMock);

    render(<VendorReviewBoard initialData={initialData} />);
    const row = () => within(screen.getByText("Suya Spot").closest("tr")!);

    expect(row().getByText("Pending")).toBeInTheDocument();

    await user.click(row().getByRole("button", { name: "Approve" }));
    const dialog = within(screen.getByRole("alertdialog"));
    await user.click(dialog.getByRole("button", { name: "Approve" }));

    // No optimistic update: still "Pending" while the POST is in flight.
    expect(row().getByText("Pending")).toBeInTheDocument();

    postDeferred.resolve(jsonResponse({ ...pendingVendor, status: "active" }));
    await waitFor(() => expect(fetchMock).toHaveBeenCalledTimes(2));
    expect(row().getByText("Pending")).toBeInTheDocument();

    const approvedVendor: AdminVendorSummary = { ...pendingVendor, status: "active" };
    refreshDeferred.resolve(jsonResponse({ items: [approvedVendor], total: 1, page: 1, limit: 20 }));

    // StatusBadge renders the real VendorStatus value "active" as "Active".
    await waitFor(() => expect(row().getByText("Active")).toBeInTheDocument());
    expect(row().queryByText("Pending")).not.toBeInTheDocument();
  });

  it("rejecting requires a reason and sends it in the request body", async () => {
    const user = userEvent.setup();
    const fetchMock = vi.fn((url: string, opts?: RequestInit) => {
      if (opts?.method === "POST" && url === "/api/proxy/admin/vendors/vendor-1/reject") {
        expect(JSON.parse(opts.body as string)).toEqual({ reason: "Missing business registration" });
        return Promise.resolve(jsonResponse({ ...pendingVendor, status: "rejected" }));
      }
      return Promise.resolve(jsonResponse({ items: [{ ...pendingVendor, status: "rejected" }], total: 1, page: 1, limit: 20 }));
    });
    vi.stubGlobal("fetch", fetchMock);

    render(<VendorReviewBoard initialData={initialData} />);
    const row = () => within(screen.getByText("Suya Spot").closest("tr")!);

    await user.click(row().getByRole("button", { name: "Reject" }));

    const rejectButton = screen.getByRole("button", { name: "Reject vendor" });
    expect(rejectButton).toBeDisabled();

    await user.type(screen.getByLabelText(/Reason/), "Missing business registration");
    expect(rejectButton).toBeEnabled();

    await user.click(rejectButton);
    // Scoped to the row: the filter tab also renders the text "Rejected".
    await waitFor(() => expect(row().getByText("Rejected")).toBeInTheDocument());
  });

  it("opening the drawer fetches and shows payout account details", async () => {
    const user = userEvent.setup();
    const fetchMock = vi.fn((url: string) => {
      if (url === "/api/proxy/admin/vendors/vendor-1") {
        return Promise.resolve(
          jsonResponse({
            ...pendingVendorDetail,
            payoutAccount: { bankCode: "058", accountNumber: "0123456789", accountName: "Suya Spot Ltd" },
          }),
        );
      }
      return Promise.resolve(jsonResponse(initialData));
    });
    vi.stubGlobal("fetch", fetchMock);

    render(<VendorReviewBoard initialData={initialData} />);
    await user.click(screen.getByText("Suya Spot"));

    await waitFor(() => expect(screen.getByText("Suya Spot Ltd")).toBeInTheDocument());
    expect(screen.getByText(/6789/)).toBeInTheDocument();
  });
});
