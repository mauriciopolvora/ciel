import cloudflare from "@cloudflare/oxlint-config";
import { defineConfig } from "oxlint";

export default defineConfig({
  extends: [cloudflare],
  env: cloudflare.env,
  ignorePatterns: [
    ...cloudflare.ignorePatterns,
    ".build/**",
    ".claude/**",
    "site/public/assets/lenis/**",
  ],
  options: { typeAware: true, reportUnusedDisableDirectives: "error" },
  rules: { curly: "off" },
  overrides: [
    { files: ["scripts/**"], rules: { "no-console": "off" } },
    { files: ["site/public/**"], env: { browser: true }, globals: { Lenis: "readonly" } },
    {
      files: [".agents/skills/*/scripts/*.js"],
      globals: { $: "readonly", Application: "readonly", ObjC: "readonly" },
      rules: { "no-unused-vars": ["error", { varsIgnorePattern: "^run$" }] },
    },
  ],
});
