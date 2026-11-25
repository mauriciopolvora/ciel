import { mkdirSync, rmSync, symlinkSync } from "node:fs";
import { createRequire } from "node:module";
import { fileURLToPath } from "node:url";

const base = process.argv[2]?.replace(/\/$/, "");
if (!base) {
  process.stderr.write("Usage: NODE_PATH=<dir with playwright-core> node site-verify.mjs <site url>\n");
  process.exit(64);
}
const { chromium } = createRequire(import.meta.url)("playwright-core");
const download = "https://github.com/mauriciopolvora/ciel/releases/latest/download/Ciel.dmg";
const root = fileURLToPath(new URL("../../../../.build/verify/site/", import.meta.url));
const id = new Date().toISOString().replaceAll(/[-:]/g, "").replace(/\..*/, "Z") + "-" + process.pid;
const evidence = root + id + "/";
mkdirSync(evidence, { recursive: true });
rmSync(root + "latest", { force: true });
symlinkSync(id, root + "latest");

const pass = (line) => process.stdout.write("PASS site: " + line + "\n");
const fail = (line) => {
  process.stdout.write("FAIL site: " + line + "\n");
  process.exit(1);
};
const expect = async (what, check) => {
  try {
    await check();
  } catch (error) {
    fail(what + " (" + String(error instanceof Error ? error.message : error).split("\n")[0] + ")");
  }
};

const browser = await chromium.launch();
const errors = [];
const open = async (viewport) => {
  const page = await browser.newPage({ viewport });
  page.on("pageerror", (error) => errors.push(page.url() + ": " + error.message));
  page.on("console", (message) => {
    const missingPage = message.location().url === base + "/no-such-page";
    if (message.type() === "error" && !missingPage) errors.push(page.url() + ": " + message.text());
  });
  return page;
};

try {
  const page = await open({ width: 1440, height: 900 });
  const home = await page.goto(base + "/");
  if (home.status() !== 200) fail("/ answers " + home.status());
  if (home.headers()["x-content-type-options"] !== "nosniff") fail("/ has no X-Content-Type-Options: nosniff");
  await expect("the home page shows its heading", () =>
    page.getByRole("heading", { level: 1, name: "Open apps, move windows" }).waitFor({ timeout: 5000 }),
  );
  await page.screenshot({ path: evidence + "site-home.png" });
  pass("/ answers 200 with nosniff and shows the heading");

  const hrefs = await page.locator("a").filter({ hasText: "Download for Mac" }).evaluateAll((links) => links.map((a) => a.href));
  if (hrefs.length !== 4 || hrefs.some((href) => href !== download)) fail("Download links are " + hrefs.join(", "));
  pass(hrefs.length + " Download links go to " + download);

  const input = page.locator("#demo-input");
  const results = page.locator("#demo-results .row-title");
  const field = await input.elementHandle();
  const demoWindow = await page.locator("[data-window]").elementHandle();
  const ready = () =>
    page.waitForFunction((box) => document.querySelector("[data-launcher]:not(.closed)") !== null && box.value === "", field);
  await input.click();
  await input.pressSequentially("left half");
  await expect('typing "left half" in the demo lists Left Half', () =>
    results.filter({ hasText: /^Left Half$/ }).first().waitFor({ timeout: 3000 }),
  );
  await input.press("Enter");
  await expect("Return on Left Half puts the demo window on the left half", () =>
    page.waitForFunction(
      (win) => {
        const style = win.style;
        return style.left === "0%" && style.top === "0%" && style.width === "50%" && style.height === "100%";
      },
      demoWindow,
      { timeout: 3000 },
    ),
  );
  await page.locator("#demo").screenshot({ path: evidence + "site-demo-left-half.png" });
  pass('the demo lists Left Half for "left half" and Return moves its window to the left half');

  await expect("the demo launcher opens again, empty", () => ready());
  await input.pressSequentially("safari");
  await input.press("Tab");
  const chip = page.locator("[data-category]");
  await expect("Tab switches the demo category to Apps and keeps Safari", async () => {
    await page.waitForFunction(() => document.querySelector("[data-category]")?.textContent?.startsWith("Apps"));
    await results.filter({ hasText: /^Safari$/ }).first().waitFor({ timeout: 3000 });
  });
  await input.press("Tab");
  await expect("a second Tab switches to Windows and lists no app", async () => {
    await page.waitForFunction(() => document.querySelector("[data-category]")?.textContent?.startsWith("Windows"));
    await page.locator("#demo-results").waitFor({ state: "hidden", timeout: 3000 });
  });
  pass("Tab cycles the demo category from All to Apps to Windows: " + (await chip.textContent()).trim());

  await input.press("Escape");
  await expect("Escape closes the demo launcher", () =>
    page.waitForFunction(() => document.querySelector("[data-launcher].closed") !== null, null, {
      timeout: 800,
    }),
  );
  await expect("the demo launcher opens again, empty", () => ready());
  await input.pressSequentially("calculator");
  await input.press("Enter");
  await expect("Return on Calculator opens it in the demo window", () =>
    page.waitForFunction(() => document.querySelector(".win-title [data-app-name]")?.textContent === "Calculator"),
  );
  pass("Escape closes the demo launcher, and Return on Calculator shows Calculator in the demo window");

  await page.locator('.nav-links a[href="#features"]').click();
  await expect("the Features link scrolls to the Features section", () =>
    page.waitForFunction(
      () => {
        const features = document.getElementById("features");
        return features !== null && Math.abs(features.getBoundingClientRect().top) < 120;
      },
      null,
      { timeout: 5000 },
    ),
  );
  pass("the Features link in the top bar scrolls to the Features section");

  await page.locator('a[href="/privacy"]').first().click();
  await expect("the Privacy link opens the privacy page", async () => {
    await page.waitForURL(base + "/privacy", { timeout: 5000 });
    if ((await page.title()) !== "Privacy · Ciel") throw new Error("title is " + (await page.title()));
  });
  await page.screenshot({ path: evidence + "site-privacy.png" });
  pass("the Privacy link opens /privacy, titled Privacy · Ciel");

  const missing = await page.goto(base + "/no-such-page");
  if (missing.status() !== 404) fail("/no-such-page answers " + missing.status());
  if ((await page.title()) !== "Page not found · Ciel") fail("/no-such-page shows " + (await page.title()));
  await page.screenshot({ path: evidence + "site-404.png" });
  pass("/no-such-page answers 404 with the Page not found page");

  const phone = await open({ width: 390, height: 844 });
  await phone.goto(base + "/");
  const burger = phone.locator(".burger");
  await burger.click();
  await expect("the phone menu opens", async () => {
    await phone.locator("#menu").waitFor({ state: "visible", timeout: 3000 });
    if ((await burger.getAttribute("aria-expanded")) !== "true") throw new Error("aria-expanded is not true");
  });
  await phone.screenshot({ path: evidence + "site-phone-menu.png" });
  await phone.keyboard.press("Escape");
  await expect("Escape closes the phone menu", async () => {
    await phone.locator("#menu").waitFor({ state: "hidden", timeout: 3000 });
    if ((await burger.getAttribute("aria-expanded")) !== "false") throw new Error("aria-expanded is not false");
  });
  pass("at 390 points the menu button opens the menu and Escape closes it");

  if (errors.length) fail("the browser logged errors: " + errors.join(" | "));
  pass("no page logged a script error, evidence in " + evidence);
} finally {
  await browser.close();
}
