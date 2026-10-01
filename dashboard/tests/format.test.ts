import { describe, expect, it } from "vitest";
import { formatKobo, formatKoboCompact, orderReference } from "@/lib/format";

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

describe("orderReference", () => {
  it("is the last 8 characters, upper-cased — distinct per order", () => {
    expect(orderReference("order-1790832731040039")).toBe("#31040039");
    expect(orderReference("order-1790832731040040")).not.toBe(orderReference("order-1790832731040039"));
  });
});

describe("formatKoboCompact (chart axes)", () => {
  it("shortens large amounts", () => {
    expect(formatKoboCompact(25000000)).toBe("₦250K");
    expect(formatKoboCompact(0)).toBe("₦0");
  });
});
