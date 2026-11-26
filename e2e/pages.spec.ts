import type { Page } from "@playwright/test";
import { expect, test } from "./fixture.ts";

const featuresTop = async (page: Page) =>
  Math.abs(await page.locator("#features").evaluate((section) => section.getBoundingClientRect().top));

test("the Features link scrolls to Features, and the Privacy link opens the privacy page", { tag: ["@smoke", "@verify", "@pages"] }, async ({ page, isMobile }) => {
  await page.goto("/");
  if (isMobile) {
    await page.getByRole("button", { name: "Open menu" }).click();
  }
  await page.locator(isMobile ? "#menu" : ".nav-links").getByRole("link", { name: "Features" }).click();
  await expect.poll(() => featuresTop(page)).toBeLessThan(120);
  await page.waitForTimeout(1300);
  expect(await featuresTop(page)).toBeLessThan(120);
  await expect(page.getByRole("heading", { level: 2, name: "Fast at the few things it does" })).toBeInViewport();
  await page.getByRole("contentinfo").getByRole("link", { name: "Privacy" }).click();
  await expect(page).toHaveURL("/privacy");
  await expect(page).toHaveTitle("Privacy · Ciel");
  await expect(page.getByRole("heading", { level: 1, name: "Privacy" })).toBeVisible();
});

test.describe("a missing page", () => {
  test.use({ allowedConsole: [/status of 404/] });

  test("answers 404 with the Page not found page", { tag: ["@verify", "@pages"] }, async ({ page }) => {
    const response = await page.goto("/no-such-page");
    expect(response?.status()).toBe(404);
    await expect(page).toHaveTitle("Page not found · Ciel");
    await expect(page.getByRole("heading", { level: 1, name: "Ciel found nothing at this address" })).toBeVisible();
  });
});

test.describe("at phone width", () => {
  test.use({ viewport: { width: 390, height: 844 } });

  test("the menu button opens the menu and Escape closes it", { tag: ["@verify", "@pages"] }, async ({ page }) => {
    await page.goto("/");
    const burger = page.locator(".burger");
    await burger.click();
    await expect(page.locator("#menu")).toBeVisible();
    await expect(burger).toHaveAttribute("aria-expanded", "true");
    await page.keyboard.press("Escape");
    await expect(page.locator("#menu")).toBeHidden();
    await expect(burger).toHaveAttribute("aria-expanded", "false");
  });
});
