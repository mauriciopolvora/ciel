import { execFileSync } from "node:child_process";
import { existsSync, lstatSync, readFileSync, statSync } from "node:fs";
import { fileURLToPath } from "node:url";

process.chdir(fileURLToPath(new URL("../..", import.meta.url)));
const list = "scripts/lint/dotfolders.txt";
const owners = [
  { pattern: /^\.husky$/, owner: ".githooks holds the git hooks" },
  {
    pattern: /^\.(cursor|windsurf|codex|gemini|continue|roo|clinerules|kiro|amazonq)$/,
    owner: "AGENTS.md holds the agent rules and .agents/skills holds the skills",
  },
  { pattern: /^\.(vscode|idea|zed|fleet)$/, owner: "editor settings stay out of git" },
];
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
const folders = new Set(
  paths.flatMap((path) => {
    const parts = path.split("/");
    const link = present(path)?.isSymbolicLink() && linkedFolder(path);
    return parts
      .slice(0, link ? parts.length : -1)
      .flatMap((name, index) => (name.startsWith(".") ? [parts.slice(0, index + 1).join("/")] : []));
  }),
);

if (!existsSync(list)) {
  problems.push(
    `${list} is missing. Put the path of each folder whose name starts with a dot in it, one path on each line.`,
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
  for (const folder of folders) {
    const owner = owners.find(({ pattern }) => pattern.test(folder.split("/").at(-1) ?? ""));
    if (owner) {
      problems.push(`${folder}/ is not allowed: ${owner.owner}. Delete it.`);
    } else if (!allowed.includes(folder)) {
      problems.push(
        `${folder}/ is not on the dotfolder list in ${list}. Delete it, or add it to .gitignore when a tool writes it. Add it to ${list} only for a folder a tool must read from git.`,
      );
    }
  }
  for (const folder of allowed.filter((folder) => !folders.has(folder))) {
    problems.push(`${folder} is on the dotfolder list in ${list}, but no file is in it. Remove it from the list.`);
  }
}

if (problems.length) {
  console.error(problems.map((problem) => `check-dotfolders: ${problem}`).join("\n"));
  process.exit(1);
}
