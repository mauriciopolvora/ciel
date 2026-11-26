import { download, expect, test } from "./fixture.ts";

test("a visitor sees the home page with its heading", { tag: ["@smoke", "@verify", "@home"] }, async ({ page }) => {
  const response = await page.goto("/");
  expect(response?.status()).toBe(200);
  expect(response?.headers()["x-content-type-options"]).toBe("nosniff");
  await expect(page.getByRole("heading", { level: 1, name: "Open apps, move windows" })).toBeVisible();
});

test("every Download for Mac link goes to the latest release disk image", { tag: ["@smoke", "@verify", "@download"] }, async ({ page }) => {
  await page.goto("/");
  // WARNING: getByRole skips the hidden link of the closed phone menu, so match the text of every link.
  const links = page.locator("a").filter({ hasText: "Download for Mac" });
  await expect(links).toHaveCount(4);
  for (const link of await links.all()) {
    await expect(link).toHaveAttribute("href", download);
  }
});
