import type { Page } from "@playwright/test";

import { expect, test } from "./fixture.ts";

test.beforeEach(async ({ page }) => {
  await page.goto("/");
  await page.locator("#demo-input").click();
});

const results = (page: Page) => page.locator("#demo-results .row-title");

test("Return on Left Half moves the demo window to the left half", { tag: ["@verify", "@demo"] }, async ({ page }) => {
  const input = page.locator("#demo-input");
  await input.pressSequentially("left half");
  await expect(results(page).filter({ hasText: /^Left Half$/ }).first()).toBeVisible();
  await input.press("Enter");
  const frame = page.locator("[data-window]");
  await expect
    .poll(() => frame.evaluate(({ style }: HTMLElement | SVGElement) => [style.left, style.top, style.width, style.height].join(" ")))
    .toBe("0% 0% 50% 100%");
});

test("Tab cycles the demo category from All to Apps to Windows", { tag: ["@verify", "@demo"] }, async ({ page }) => {
  const input = page.locator("#demo-input");
  const chip = page.locator("[data-category]");
  await input.pressSequentially("safari");
  await input.press("Tab");
  await expect(chip).toHaveText(/^Apps/);
  await expect(results(page).filter({ hasText: /^Safari$/ }).first()).toBeVisible();
  await input.press("Tab");
  await expect(chip).toHaveText(/^Windows/);
  await expect(page.locator("#demo-results")).toBeHidden();
});

test("Escape closes the demo launcher, and Return on Calculator opens it", { tag: ["@verify", "@demo"] }, async ({ page }) => {
  const input = page.locator("#demo-input");
  await input.press("Escape");
  await expect(page.locator("[data-launcher].closed")).toHaveCount(1, { timeout: 800 });
  await expect(page.locator("[data-launcher]:not(.closed)")).toHaveCount(1);
  await expect(input).toHaveValue("");
  await input.pressSequentially("calculator");
  await input.press("Enter");
  await expect(page.locator(".win-title [data-app-name]")).toHaveText("Calculator");
});
