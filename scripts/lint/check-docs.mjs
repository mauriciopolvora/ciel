import { execFileSync } from "node:child_process";
import { existsSync, lstatSync, readdirSync, readFileSync, readlinkSync, statSync } from "node:fs";
import { fileURLToPath } from "node:url";

process.chdir(fileURLToPath(new URL("../..", import.meta.url)));

const cap = 4096;
const docLineCaps = {
  ".agents/skills/verify-ciel/SKILL.md": 85,
  ".agents/skills/verify-ciel/features/README.md": 40,
  ".agents/skills/verify-ciel/features/launcher-search.md": 35,
  ".agents/skills/verify-ciel/features/onboarding.md": 30,
  ".agents/skills/verify-ciel/features/open-app.md": 35,
  ".agents/skills/verify-ciel/features/settings.md": 35,
  ".agents/skills/verify-ciel/features/site.md": 40,
  ".agents/skills/verify-ciel/features/window-commands.md": 35,
  ".github/ISSUE_TEMPLATE.md": 15,
  "AGENTS.md": 45,
  "CONTRIBUTING.md": 30,
  "README.md": 125,
  "docs/artwork.md": 10,
  "docs/design-system.md": 105,
  "docs/releasing.md": 125,
  "docs/rules.md": 55,
};

const problems = [];
const git = (...args) => execFileSync("git", args, { encoding: "utf8", maxBuffer: 1 << 28 });
const link = (path) =>
  lstatSync(path, { throwIfNoEntry: false })?.isSymbolicLink() ? readlinkSync(path) : null;

if (!existsSync("AGENTS.md")) {
  problems.push("AGENTS.md is missing.");
} else if (statSync("AGENTS.md").size > cap) {
  problems.push(
    `AGENTS.md has ${statSync("AGENTS.md").size} bytes, over the ${cap} byte cap. Move each rule a machine can check into a lint rule, a test or a CI check, and cut the rest.`,
  );
}
if (link("CLAUDE.md") !== "AGENTS.md") {
  problems.push("CLAUDE.md must be a symlink to AGENTS.md: ln -sfn AGENTS.md CLAUDE.md");
}

const dirs = (path) => (existsSync(path) ? readdirSync(path) : []);
for (const name of dirs(".agents/skills")) {
  const want = `../../.agents/skills/${name}`;
  if (link(`.claude/skills/${name}`) !== want) {
    problems.push(
      `.claude/skills/${name} must be a symlink to ${want}: ln -sfn ${want} .claude/skills/${name}`,
    );
  }
}
for (const name of dirs(".claude/skills")) {
  if (!existsSync(`.agents/skills/${name}`)) {
    problems.push(
      `.claude/skills/${name} has no .agents/skills/${name}. Move the skill to .agents/skills/${name} and link it, or delete the link.`,
    );
  }
}

const docs = git("ls-files", "-z", "--", "*.md")
  .split("\0")
  .filter((path) => path && existsSync(path) && !lstatSync(path).isSymbolicLink());
for (const path of docs) {
  const lines = readFileSync(path, "utf8").split("\n");
  const count = lines.at(-1) === "" ? lines.length - 1 : lines.length;
  if (!(path in docLineCaps)) {
    problems.push(
      `${path} is not on the docs list in scripts/lint/check-docs.mjs. Put its facts in an existing doc, or add it to the list with a line cap.`,
    );
  } else if (count > docLineCaps[path]) {
    problems.push(
      `${path} has ${count} lines, over its cap of ${docLineCaps[path]} in scripts/lint/check-docs.mjs. Cut it, or move the part only some readers need behind a pointer.`,
    );
  }
}
for (const path of Object.keys(docLineCaps)) {
  if (!docs.includes(path)) {
    problems.push(
      `${path} is on the docs list in scripts/lint/check-docs.mjs, but git does not track it. Remove it from the list.`,
    );
  }
}

try {
  const lines = execFileSync("git", ["grep", "-nIF", "\u2014", "--", "."], { encoding: "utf8" });
  problems.push(
    `${lines}These lines have an em dash. Use a comma, a colon or parentheses instead.`,
  );
} catch (error) {
  if (!(error instanceof Error && "status" in error && error.status === 1)) {
    throw error;
  }
}

if (problems.length) {
  console.error(problems.map((problem) => `check-docs: ${problem}`).join("\n"));
  process.exit(1);
}
