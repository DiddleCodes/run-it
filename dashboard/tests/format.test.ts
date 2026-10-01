import { describe, expect, it } from "vitest";
import { formatKobo } from "@/lib/format";

describe("formatKobo — the dashboard's one money format", () => {
  it("whole naira get two decimals", () => {
    expect(formatKobo(90000)).toBe("₦900.00");
    expect(formatKobo(0)).toBe("₦0.00");
  });

  it("thousands are separated", () => {
    expect(formatKobo(144500)).toBe("₦1,445.00");
    expect(formatKobo(14450000)).toBe("₦144,500.00");
  });

  it("kobo that are not whole naira are kept", () => {
    expect(formatKobo(144450)).toBe("₦1,444.50");
    expect(formatKobo(144405)).toBe("₦1,444.05");
    expect(formatKobo(1)).toBe("₦0.01");
  });
});
