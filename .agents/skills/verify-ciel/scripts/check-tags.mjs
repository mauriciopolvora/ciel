import { spawnSync } from "node:child_process";
import { globSync } from "node:fs";
import { join, relative } from "node:path";
import { featureMap, grep, matches, repoRoot, select } from "./select.mjs";

const skill = relative(repoRoot, join(import.meta.dirname, ".."));
const tiers = new Set(["@smoke", "@verify"]);
const problems = [];

const routes = globSync(featureMap.routes, { cwd: repoRoot });
const covered = [...Object.values(featureMap.tags).flat(), ...featureMap.baseline];
for (const file of routes.filter((route) => !covered.some((pattern) => matches(route, pattern)))) {
  problems.push(`${file} is in no tag of ${skill}/features.json. Add it to the files of a tag, and tag a spec in e2e/ with that tag.`);
}

const list = (...flags) => {
  const run = spawnSync(join(repoRoot, "node_modules/.bin/playwright"), ["test", "--list", "--reporter=json", "--project=desktop", ...flags], {
    cwd: repoRoot,
    encoding: "utf8",
  });
  if (run.status !== 0) {
    process.stderr.write(`check-tags: playwright test --list failed. Run bun install first.\n${run.stderr}`);
    process.exit(1);
  }
  const specs = (suite) => [...(suite.specs ?? []), ...(suite.suites ?? []).flatMap(specs)];
  return specs(JSON.parse(run.stdout))
    .filter((spec) => spec.tests.some((test) => test.expectedStatus !== "skipped"))
    .map((spec) => ({ title: spec.title, tags: spec.tags.map((name) => `@${name}`) }));
};

const tests = list();
const used = new Set(tests.flatMap((test) => test.tags));
for (const name of Object.keys(featureMap.tags).filter((name) => !used.has(name))) {
  problems.push(`${name} in ${skill}/features.json tags no test that runs. Tag a test in e2e/ with it.`);
}
for (const name of [...used].filter((name) => !tiers.has(name) && !(name in featureMap.tags))) {
  problems.push(`${name} tags a test in e2e/ but is not in ${skill}/features.json. Add it with the files of its feature.`);
}
for (const test of tests.filter((test) => !test.tags.some((name) => name in featureMap.tags))) {
  problems.push(`"${test.title}" has no feature tag. Add one of ${Object.keys(featureMap.tags).join(", ")}.`);
}

const cases = [
  { files: ["Sources/Ciel/App/AppDelegate.swift", "docs/rules.md"], want: "smoke only" },
  { files: ["site/public/assets/site.js"], want: "@demo @pages" },
  { files: ["site/public/privacy.html"], want: "@pages" },
  { files: ["e2e/demo.spec.ts"], want: "all" },
  { files: ["site/cloudflare.config.ts"], want: "all" },
];
for (const { files, want } of cases) {
  const selection = select(files);
  const got = selection.all ? "all" : selection.tags.join(" ") || "smoke only";
  if (got !== want) problems.push(`select(${files.join(", ")}) gives ${got}, not ${want}. Fix ${skill}/scripts/select.mjs or features.json.`);
}

const titles = (found) => found.map((test) => test.title).toSorted((a, b) => a.localeCompare(b)).join("\n");
const demo = list("--grep", grep({ all: false, tags: ["@demo"] }));
const wantDemo = tests.filter((test) => test.tags.includes("@smoke") || (test.tags.includes("@verify") && test.tags.includes("@demo")));
if (titles(demo) !== titles(wantDemo)) {
  problems.push(`the grep for @demo runs:\n${titles(demo)}\nnot @smoke plus the @verify tests of @demo:\n${titles(wantDemo)}`);
}

if (problems.length > 0) {
  process.stderr.write(`check-tags:\n  ${problems.join("\n  ")}\n`);
  process.exit(1);
}
process.stdout.write(`check-tags: ok, ${routes.length} pages, ${tests.length} tests, ${Object.keys(featureMap.tags).length} feature tags\n`);
