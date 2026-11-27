import { execFileSync, spawnSync } from "node:child_process";
import { existsSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

process.chdir(fileURLToPath(new URL("../..", import.meta.url)));
const week = 7 * 24 * 60 * 60;
const problems = [];

function gate(config) {
  const result = spawnSync(
    "bun",
    ["--config=/dev/null", "-e", "process.stdout.write(JSON.stringify(Bun.TOML.parse(await Bun.file(process.argv.at(-1)).text())))", config],
    { encoding: "utf8" },
  );
  if (result.error) {
    console.error(`check-bunfig: bun did not run, so no bunfig.toml was read: ${result.error.message}`);
    process.exit(2);
  }
  if (result.status !== 0) {
    problems.push(`${config} is not TOML that bun reads: ${result.stderr.trim()}`);
    return null;
  }
  const seconds = JSON.parse(result.stdout)?.install?.minimumReleaseAge;
  return typeof seconds === "number" ? seconds : undefined;
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
  const seconds = gate(config);
  if (seconds !== null && (seconds === undefined || seconds < week)) {
    problems.push(
      `${config} must set minimumReleaseAge = ${week} (7 days, the Dependabot cooldown) or more under [install], as a number of seconds.`,
    );
  }
}

if (problems.length) {
  console.error(problems.map((problem) => `check-bunfig: ${problem}`).join("\n"));
  process.exit(1);
}
