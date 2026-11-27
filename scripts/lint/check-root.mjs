import { execFileSync } from "node:child_process";
import { existsSync, lstatSync, readFileSync, statSync } from "node:fs";
import { fileURLToPath } from "node:url";

process.chdir(fileURLToPath(new URL("../..", import.meta.url)));
const list = "scripts/lint/root.txt";
const owners = [
  { pattern: /^(\.eslintrc.*|\.eslintignore|eslint\.config\..*)$/, owner: "oxlint lints" },
  {
    pattern: /^(jest\.config\..*|vitest\.(config|workspace)\..*|tests\/|test\/|__tests__\/)$/,
    owner: "the Swift tests go in Tests/, the SwiftPM test target folder, and the site tests go in e2e/",
  },
  {
    pattern:
      /^(\.lintstagedrc.*|lint-staged\.config\..*|lefthook\.ya?ml|\.simple-git-hooks.*|\.pre-commit-config\.yaml)$/,
    owner: ".githooks holds the git hooks",
  },
  { pattern: /^commitlint\.config\..*$/, owner: "scripts/lint/check-commits.sh checks the commits" },
  {
    pattern: /^((\.github\/|\.gitlab\/)?renovate\.json[c5]?|\.renovaterc(\.json[c5]?)?)$/,
    owner: ".github/dependabot.yml updates the dependencies",
  },
  { pattern: /^\.?knip(\.config)?\.[a-z]+$/, owner: "the knip key in package.json holds the knip config" },
  {
    pattern: /^(package-lock\.json|yarn\.lock|\.yarnrc.*|pnpm-lock\.yaml|pnpm-workspace\.yaml|bun\.lockb)$/,
    owner: "bun installs, with its lockfile in bun.lock",
  },
  {
    pattern: /^(\.cursorrules|\.windsurfrules|GEMINI\.md|CONVENTIONS\.md)$/,
    owner: "AGENTS.md holds the agent rules",
  },
];
const drawer = /^(utils?|helpers|common|shared|misc)$/;
const problems = [];

function present(path) {
  try {
    return lstatSync(path, { throwIfNoEntry: false });
  } catch (error) {
    if (error instanceof Error && "code" in error && (error.code === "ENOTDIR" || error.code === "ELOOP")) {
      return undefined;
    }
    throw error;
  }
}

function linkedFolder(path) {
  try {
    return statSync(path).isDirectory();
  } catch {
    return true;
  }
}

const paths = execFileSync("git", ["ls-files", "-z", "-co", "--exclude-standard"], {
  encoding: "utf8",
  maxBuffer: 1024 ** 3,
})
  .split("\0")
  .filter((path) => path && present(path));
const links = new Set(paths.filter((path) => present(path)?.isSymbolicLink() && linkedFolder(path)));
const folders = (path) => {
  const parts = path.split("/");
  return parts
    .slice(0, links.has(path) ? parts.length : -1)
    .map((_, index) => parts.slice(0, index + 1).join("/"));
};
const entries = new Set(
  paths
    .filter((path) => !(path.startsWith(".") && (path.includes("/") || links.has(path))))
    .map((path) => (path.includes("/") || links.has(path) ? `${path.split("/")[0]}/` : path)),
);
const drawers = new Set(paths.flatMap(folders).filter((folder) => drawer.test(folder.split("/").at(-1) ?? "")));

for (const folder of drawers) {
  problems.push(
    `${folder}/ is a folder named for a kind of file. Move each file into the feature folder that uses it, such as Sources/Ciel/<feature>/.`,
  );
}

for (const path of new Set([...entries, ...paths.filter((path) => /^\.(github|gitlab)\//.test(path))])) {
  const owner = owners.find(({ pattern }) => pattern.test(path));
  if (owner) {
    problems.push(`${path} is not allowed, because ${owner.owner}. Use that and delete ${path}.`);
  }
}

if (!existsSync(list)) {
  problems.push(
    `${list} is missing. Put each root file and each root folder (with a / at the end) in it, one on each line.`,
  );
} else {
  const allowed = readFileSync(list, "utf8")
    .split("\n")
    .flatMap((line, index) => {
      if (line !== line.trim()) {
        problems.push(`${list} line ${index + 1} has a space or a CR at its start or end. Remove it.`);
      }
      return line.trim() ? [line.trim()] : [];
    });
  for (const entry of entries) {
    if (!allowed.includes(entry) && !owners.some(({ pattern }) => pattern.test(entry))) {
      problems.push(
        `${entry} is not on the root list in ${list}. Move it into a folder that is on the list (app code in Sources/, scripts in scripts/, lint files in scripts/lint/, docs in docs/), or delete it. Add it to ${list} only for a file a tool reads at the root.`,
      );
    }
  }
  for (const entry of allowed.filter((entry) => !entries.has(entry))) {
    problems.push(`${entry} is on the root list in ${list}, but the root has no ${entry}. Remove it from the list.`);
  }
}

if (problems.length) {
  console.error(problems.map((problem) => `check-root: ${problem}`).join("\n"));
  process.exit(1);
}
