import { render, screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { afterEach, describe, expect, it, vi } from "vitest";
import { MenuBoard } from "@/components/vendor/menu-board";
import type { MenuItem } from "@/lib/api/vendor-client";

vi.mock("sonner", () => ({ toast: { success: vi.fn(), error: vi.fn(), message: vi.fn() } }));

const existingItem: MenuItem = {
  id: "item-1",
  vendorId: "vendor-1",
  name: "Jollof Rice Bowl",
  description: "Smoky party jollof",
  price: 300000, // ₦3,000.00
  photoUrl: null,
  category: "Mains",
  isAvailable: true,
  createdAt: "2026-08-01T00:00:00.000Z",
  updatedAt: "2026-08-01T00:00:00.000Z",
};

function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json" } });
}

afterEach(() => {
  vi.restoreAllMocks();
});

describe("Menu CRUD", () => {
  it("Add item converts a ₦ price input to kobo on submit", async () => {
    const user = userEvent.setup();
    const fetchMock = vi.fn((url: string, opts?: RequestInit) => {
      if (opts?.method === "POST" && url === "/api/proxy/vendors/me/menu-items") {
        const body = JSON.parse(opts.body as string);
        expect(body).toMatchObject({ name: "Suya Platter", price: 185550, category: "Mains" });
        return Promise.resolve(jsonResponse({ ...existingItem, id: "item-2", name: "Suya Platter", price: 185550 }));
      }
      if (!opts || opts.method === undefined || opts.method === "GET") {
        return Promise.resolve(jsonResponse({ vendor: {}, items: [existingItem] }));
      }
      throw new Error(`Unexpected fetch: ${opts?.method} ${url}`);
    });
    vi.stubGlobal("fetch", fetchMock);

    render(<MenuBoard vendorId="vendor-1" initialItems={[existingItem]} />);

    await user.click(screen.getByRole("button", { name: /Add item/i }));
    expect(screen.getByText("Add menu item")).toBeInTheDocument();

    await user.type(screen.getByPlaceholderText("e.g. Jollof Rice Bowl"), "Suya Platter");
    const priceInput = screen.getByLabelText("Price (₦)");
    await user.clear(priceInput);
    await user.type(priceInput, "1855.50");

    await user.click(screen.getByRole("button", { name: "Add item" }));

    await waitFor(() => expect(fetchMock).toHaveBeenCalledWith("/api/proxy/vendors/me/menu-items", expect.objectContaining({ method: "POST" })));
  });

  it("Edit prefills the existing item and PATCHes on save", async () => {
    const user = userEvent.setup();
    const fetchMock = vi.fn((url: string, opts?: RequestInit) => {
      if (opts?.method === "PATCH") {
        expect(url).toBe(`/api/proxy/vendors/me/menu-items/${existingItem.id}`);
        const body = JSON.parse(opts.body as string);
        expect(body.price).toBe(325000); // ₦3,250.00
        return Promise.resolve(jsonResponse({ ...existingItem, price: 325000 }));
      }
      return Promise.resolve(jsonResponse({ vendor: {}, items: [{ ...existingItem, price: 325000 }] }));
    });
    vi.stubGlobal("fetch", fetchMock);

    render(<MenuBoard vendorId="vendor-1" initialItems={[existingItem]} />);

    const card = screen.getByText("Jollof Rice Bowl").closest("div.flex.gap-3") as HTMLElement;
    await user.click(within(card).getAllByRole("button")[1]); // edit icon (before delete icon)

    expect(screen.getByText("Edit menu item")).toBeInTheDocument();
    expect(screen.getByDisplayValue("Jollof Rice Bowl")).toBeInTheDocument();
    expect(screen.getByDisplayValue("3000.00")).toBeInTheDocument();

    const priceInput = screen.getByLabelText("Price (₦)");
    await user.clear(priceInput);
    await user.type(priceInput, "3250.00");
    await user.click(screen.getByRole("button", { name: "Save changes" }));

    await waitFor(() => expect(fetchMock).toHaveBeenCalledWith(`/api/proxy/vendors/me/menu-items/${existingItem.id}`, expect.objectContaining({ method: "PATCH" })));
  });

  it("Delete requires confirming through ConfirmDialog before the DELETE call fires", async () => {
    const user = userEvent.setup();
    const fetchMock = vi.fn((url: string, opts?: RequestInit) => {
      if (opts?.method === "DELETE") {
        expect(url).toBe(`/api/proxy/vendors/me/menu-items/${existingItem.id}`);
        return Promise.resolve(jsonResponse({ deleted: true }));
      }
      return Promise.resolve(jsonResponse({ vendor: {}, items: [] }));
    });
    vi.stubGlobal("fetch", fetchMock);

    render(<MenuBoard vendorId="vendor-1" initialItems={[existingItem]} />);

    const card = screen.getByText("Jollof Rice Bowl").closest("div.flex.gap-3") as HTMLElement;
    await user.click(within(card).getAllByRole("button")[2]); // delete icon

    expect(screen.getByText("Remove item?")).toBeInTheDocument();
    expect(fetchMock).not.toHaveBeenCalledWith(expect.anything(), expect.objectContaining({ method: "DELETE" }));

    await user.click(screen.getByRole("button", { name: "Remove" }));

    await waitFor(() => expect(fetchMock).toHaveBeenCalledWith(`/api/proxy/vendors/me/menu-items/${existingItem.id}`, expect.objectContaining({ method: "DELETE" })));
  });
});
