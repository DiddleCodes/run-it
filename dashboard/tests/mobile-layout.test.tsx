import { render, screen, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { afterEach, describe, expect, it, vi } from "vitest";
import { DataTable } from "@/components/shared/data-table";
import { AppShell } from "@/components/layout/app-shell";

vi.mock("next/navigation", () => ({ usePathname: () => "/admin/users", useRouter: () => ({ push: vi.fn(), refresh: vi.fn() }) }));

function phoneScreen(isPhone: boolean) {
  vi.stubGlobal("matchMedia", (query: string) => ({
    matches: isPhone && query.includes("max-width: 767px"),
    addEventListener: () => {},
    removeEventListener: () => {},
  }));
}

afterEach(() => vi.unstubAllGlobals());

const rows = [{ id: "1", rank: 1, name: "Suya", restaurant: "Spice Garden", earned: "₦4,050.00" }];
const columns = [
  { key: "rank", header: "#", phoneHidden: true },
  { key: "name", header: "Dish", phoneTitle: true },
  { key: "restaurant", header: "Restaurant" },
  { key: "earned", header: "Earned", align: "right" as const },
  { key: "action", header: "", render: () => <button>Suspend</button> },
];

describe("Phone layouts", () => {
  it("on a phone, table rows become cards: title column on top, label/value lines, actions at the bottom, hidden columns left out", () => {
    phoneScreen(true);
    render(<DataTable columns={columns} data={rows} />);

    expect(screen.queryByRole("table")).toBeNull();
    const card = screen.getByRole("listitem");
    expect(card.firstElementChild).toHaveTextContent("Suya");
    expect(within(card).getByText("Restaurant").nextSibling).toHaveTextContent("Spice Garden");
    expect(within(card).getByText("Earned").nextSibling).toHaveTextContent("₦4,050.00");
    expect(within(card).queryByText("#")).toBeNull();
    expect(within(card).getByRole("button", { name: "Suspend" })).toBeInTheDocument();
  });

  it("on a wider screen, it stays a table", () => {
    phoneScreen(false);
    render(<DataTable columns={columns} data={rows} />);
    expect(screen.getByRole("table")).toBeInTheDocument();
    expect(screen.getAllByRole("columnheader").map((h) => h.textContent)).toEqual(["#", "Dish", "Restaurant", "Earned", ""]);
  });

  it("the menu button opens the navigation and choosing a page or the backdrop closes it", async () => {
    const user = userEvent.setup();
    vi.stubGlobal("fetch", vi.fn(() => Promise.resolve(new Response("{}", { headers: { "content-type": "application/json" } }))));
    render(
      <AppShell role="admin" user={{ name: "Ada", email: "a@b.co", accountType: "admin" }}>
        <p>Page</p>
      </AppShell>,
    );

    await user.click(screen.getByRole("button", { name: "Open menu" }));
    const menu = screen.getByRole("dialog", { name: "Menu" });
    expect(within(menu).getByRole("link", { name: /Analytics/ })).toHaveAttribute("href", "/admin/analytics");

    await user.click(within(menu).getByRole("link", { name: /Users/ }));
    expect(screen.queryByRole("dialog", { name: "Menu" })).toBeNull();

    await user.click(screen.getByRole("button", { name: "Open menu" }));
    await user.keyboard("{Escape}");
    expect(screen.queryByRole("dialog", { name: "Menu" })).toBeNull();
  });
});
