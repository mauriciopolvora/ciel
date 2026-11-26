import { spawnSync } from "node:child_process";
import { existsSync, readFileSync } from "node:fs";
import { matchesGlob, resolve } from "node:path";
import { fileURLToPath } from "node:url";

export const repoRoot = fileURLToPath(new URL("../../../..", import.meta.url));

export const featureMap = JSON.parse(readFileSync(new URL("../features.json", import.meta.url), "utf8"));

export const matches = (file, pattern) =>
  existsSync(resolve(repoRoot, pattern)) ? file === pattern : matchesGlob(file, pattern);

export function select(files, map = featureMap) {
  const tags = new Set();
  for (const file of files) {
    const owners = Object.keys(map.tags).filter((tag) => map.tags[tag]?.some((pattern) => matches(file, pattern)));
    if (owners.length > 0) {
      for (const tag of owners) tags.add(tag);
    } else if (!map.smokeOnly.some((pattern) => matches(file, pattern))) {
      return { all: true, tags: [] };
    }
  }
  return { all: false, tags: [...tags].toSorted((a, b) => a.localeCompare(b)) };
}

const escape = (name) => name.replaceAll(/[.*+?^${}()|[\]\\]/g, String.raw`\$&`);

const tag = (name) => ` ${escape(name)}( |$)`;

export function grep(selection) {
  if (selection.all) return `${tag("@smoke")}|${tag("@verify")}`;
  if (selection.tags.length === 0) return tag("@smoke");
  return `${tag("@smoke")}|(?=.*${tag("@verify")})(?=.* (${selection.tags.map(escape).join("|")})( |$))`;
}

function changedFiles(base) {
  const diff = spawnSync("git", ["diff", "--name-only", "--no-renames", `${base}...HEAD`], { cwd: repoRoot, encoding: "utf8" });
  if (diff.status !== 0) throw new Error(`git diff ${base}...HEAD failed: ${diff.stderr.trim()}`);
  return diff.stdout.split("\n").filter(Boolean);
}

if (process.argv[1] === import.meta.filename) {
  const base = process.argv[2];
  const selection = base ? select(changedFiles(base)) : { all: true, tags: [] };
  process.stderr.write(
    selection.all
      ? "Selected every @smoke and @verify test.\n"
      : `Selected @smoke and the @verify tests of: ${selection.tags.join(", ") || "none"}.\n`,
  );
  process.stdout.write(grep(selection) + "\n");
}
