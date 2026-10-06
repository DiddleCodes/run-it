import { render, screen } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";
import { AuthShell } from "@/components/auth/auth-shell";

vi.mock("next/image", () => ({
  // eslint-disable-next-line @next/next/no-img-element
  default: ({ alt }: { alt: string }) => <img alt={alt} />,
}));

describe("Branding on the login screen", () => {
  it("says Bridgit, never the old name", () => {
    const { container } = render(
      <AuthShell>
        <form />
      </AuthShell>,
    );

    expect(screen.getByRole("heading", { level: 1 }).textContent).toBe("Bridgit");
    expect(screen.getByAltText("Bridgit")).toBeInTheDocument();
    expect(screen.getByText("Bridgit Campus Delivery · Internal Portal")).toBeInTheDocument();
    expect(container.textContent).not.toMatch(/run[- ]?it/i);
  });
});
