import { defineConfig, devices } from "@playwright/test";

const preview = process.env["PLAYWRIGHT_BASE_URL"];
const port = process.env["CIEL_SITE_PORT"] ?? "4318";
const local = `http://localhost:${port}`;

const config = defineConfig({
  testDir: "e2e",
  forbidOnly: Boolean(process.env["CI"]),
  retries: process.env["CI"] ? 1 : 0,
  reporter: process.env["CI"] ? [["list"], ["html", { open: "never" }]] : "list",
  use: {
    baseURL: preview || local,
    trace: "on-first-retry",
    screenshot: "only-on-failure",
  },
  projects: [
    { name: "desktop", use: { ...devices["Desktop Chrome"] } },
    { name: "mobile", use: { ...devices["iPhone 15"] } },
  ],
});

if (!preview) {
  config.webServer = {
    command: `bun run --cwd site dev --port ${port}`,
    url: local,
    reuseExistingServer: !process.env["CI"],
    timeout: 120_000,
  };
}

export default config;
