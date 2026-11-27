import { execFileSync } from "node:child_process";
import { existsSync, readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

process.chdir(fileURLToPath(new URL("../..", import.meta.url)));
const week = 7 * 24 * 60 * 60;
const problems = [];

function gate(text) {
  let table = "";
  for (const line of text.split("\n").map((raw) => raw.trim())) {
    const header = /^\[([^\]]*)\]$/.exec(line);
    if (header) {
      table = header[1]?.trim() ?? "";
      continue;
    }
    const age = /^minimumReleaseAge\s*=\s*(\d+)\s*$/.exec(line);
    if (table === "install" && age) {
      return Number(age[1]);
    }
  }
  return undefined;
}

const folders = execFileSync("git", ["ls-files", "-z", "-co", "--exclude-standard", "--", "package.json", "**/package.json"], {
  encoding: "utf8",
})
  .split("\0")
  .filter((path) => path && existsSync(path))
  .map((path) => dirname(path));

for (const folder of new Set(folders)) {
  const config = join(folder, "bunfig.toml");
  if (!existsSync(config)) {
    problems.push(
      `${folder}/package.json has no ${config}. bun reads only the bunfig.toml next to the package.json, so add one with [install] minimumReleaseAge = ${week}.`,
    );
    continue;
  }
  const seconds = gate(readFileSync(config, "utf8"));
  if (seconds === undefined || seconds < week) {
    problems.push(
      `${config} must set minimumReleaseAge = ${week} (7 days, the Dependabot cooldown) or more under [install], as a number of seconds.`,
    );
  }
}

if (problems.length) {
  console.error(problems.map((problem) => `check-bunfig: ${problem}`).join("\n"));
  process.exit(1);
}
