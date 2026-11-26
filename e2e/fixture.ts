import { expect, test as base } from "@playwright/test";

export const download = "https://github.com/mauriciopolvora/ciel/releases/latest/download/Ciel.dmg";

// WARNING: the browser logs the 404 of a missing page as a console error, so a test that opens one sets allowedConsole.
export const test = base.extend<{ allowedConsole: Array<RegExp>; failures: Array<string> }>({
  allowedConsole: [[], { option: true }],
  failures: [
    async ({ page, allowedConsole }, use) => {
      const failures: Array<string> = [];
      page.on("pageerror", (error) => failures.push(`${page.url()}: ${error.message}`));
      page.on("console", (message) => {
        const text = message.text();
        if (message.type() === "error" && !allowedConsole.some((pattern) => pattern.test(text))) {
          failures.push(`${page.url()}: ${text}`);
        }
      });
      page.on("response", (response) => {
        if (response.status() >= 500) {
          failures.push(`${response.url()} answered ${response.status()}`);
        }
      });
      await use(failures);
      expect(failures, "the browser logged errors or got a 5xx response").toEqual([]);
    },
    { auto: true },
  ],
});

export { expect };
