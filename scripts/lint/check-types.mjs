import { execFileSync, spawnSync } from "node:child_process";
import { existsSync, readFileSync } from "node:fs";
import { isAbsolute, relative } from "node:path";
import { fileURLToPath } from "node:url";

process.chdir(fileURLToPath(new URL("../..", import.meta.url)));

const baselineFile = "scripts/lint/type-baseline.txt";
const tsrs = "node_modules/.bin/tsrs";
const diagnostic = /^(.+?)\(\d+,\d+\): error TS\d+: /;

const fail = (message) => {
  console.error(`check-types: ${message}`);
  process.exit(1);
};

const parseBaseline = (name, text) => {
  const allowed = new Map();
  for (const [index, line] of text.split("\n").entries()) {
    if (line === "") {
      continue;
    }
    const row = /^([1-9]\d*) (\S.*)$/.exec(line);
    if (!row?.[1] || !row[2]) {
      fail(`${name}:${index + 1}: expected <count> <path>, with a count above 0.`);
    } else if (allowed.has(row[2])) {
      fail(`${name}:${index + 1}: ${row[2]} is listed again.`);
    } else {
      allowed.set(row[2], Number(row[1]));
    }
  }
  return allowed;
};

if (!existsSync(tsrs)) {
  fail("node_modules is missing. Run bun install, then run this again.");
}

const projects = JSON.parse(readFileSync("tsconfig.json", "utf8")).references.map(
  (reference) => reference.path,
);
const compile = (project, ...flags) => {
  const run = spawnSync(tsrs, ["-p", project, ...flags], { encoding: "utf8" });
  if (run.error) {
    fail(`cannot run ${tsrs}: ${run.error.message}`);
  }
  if (run.signal || run.stderr !== "") {
    fail(`${tsrs} -p ${project} ${flags.join(" ")} ended with ${run.signal ?? "output on stderr"}:\n${run.stdout}${run.stderr}`);
  }
  return run;
};

const covered = new Set();
for (const project of projects) {
  const run = compile(project, "--listFilesOnly");
  for (const line of run.stdout.split("\n")) {
    if (isAbsolute(line)) {
      covered.add(relative(process.cwd(), line));
    } else if (line !== "" && !diagnostic.test(line) && !line.startsWith("  ")) {
      fail(`${tsrs} -p ${project} --listFilesOnly printed a line that is not a file or a type error:\n${run.stdout}`);
    }
  }
}
const uncovered = execFileSync("git", ["ls-files", "-z"], { encoding: "utf8" })
  .split("\0")
  .filter((file) => /\.[cm]?[jt]sx?$/.test(file) && !file.startsWith("site/public/assets/lenis/"))
  .filter((file) => !covered.has(file));
if (uncovered.length > 0) {
  fail(`these files are in no project that tsconfig.json references. Add each one to the include list of a project:\n    ${uncovered.join("\n    ")}`);
}

const errors = new Map();
for (const project of projects) {
  const run = compile(project, "--pretty", "false");
  let found = 0;
  for (const line of run.stdout.split("\n")) {
    const file = diagnostic.exec(line)?.[1];
    if (file) {
      errors.set(file, [...(errors.get(file) ?? []), line]);
      found++;
    } else if (line !== "" && !(found > 0 && line.startsWith("  "))) {
      fail(`${project} printed a line that is not a type error in a file:\n${run.stdout}`);
    }
  }
  if ((run.status === 0) !== (found === 0)) {
    fail(`${tsrs} -p ${project} exited ${run.status} with ${found} type errors:\n${run.stdout}`);
  }
}

const allowed = parseBaseline(baselineFile, readFileSync(baselineFile, "utf8"));
const problems = [];
for (const [file, lines] of errors) {
  const limit = allowed.get(file) ?? 0;
  if (lines.length > limit) {
    problems.push(
      `${file} has ${lines.length} type errors, and ${baselineFile} allows ${limit}. Fix the new ones.\n    ${lines.join("\n    ")}`,
    );
  }
}
for (const [file, limit] of allowed) {
  const count = errors.get(file)?.length ?? 0;
  if (count < limit) {
    problems.push(
      `${file} has ${count} type errors, and ${baselineFile} still allows ${limit}. Lower its count to ${count}, or delete its line at 0.`,
    );
  }
}

let base = "";
try {
  base = execFileSync("git", ["merge-base", "HEAD", "origin/main"], {
    encoding: "utf8",
    stdio: ["ignore", "pipe", "ignore"],
  }).trim();
} catch {
  if (process.env.CI) {
    fail("cannot find the merge base with origin/main. Check out with fetch-depth: 0.");
  }
  console.error("check-types: no origin/main, so this run does not compare the baseline with main.");
}
const atBase =
  base && execFileSync("git", ["ls-tree", "--name-only", base, "--", baselineFile], { encoding: "utf8" }) !== ""
    ? execFileSync("git", ["show", `${base}:${baselineFile}`], { encoding: "utf8" })
    : null;
if (atBase !== null) {
  const before = parseBaseline(`${base}:${baselineFile}`, atBase);
  for (const [file, limit] of allowed) {
    if (limit > (before.get(file) ?? 0)) {
      problems.push(
        `${baselineFile} raises ${file} from ${before.get(file) ?? 0} to ${limit} type errors. The baseline only shrinks: fix the new errors instead.`,
      );
    }
  }
}

if (problems.length > 0) {
  fail(problems.join("\n"));
}
