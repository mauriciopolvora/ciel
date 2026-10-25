import { defineConfig } from "cf/config";

export default defineConfig({
  worker: {
    name: "ciel-site",
    compatibilityDate: "2026-10-19",
    assets: { htmlHandling: "auto-trailing-slash", notFoundHandling: "404-page" },
    domains: ["cielmac.app"],
    workersDev: false,
  },
});
