import { execFileSync, spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";

process.chdir(fileURLToPath(new URL("../..", import.meta.url)));
const script = "git-auth.sh";
const banned = ["pull_request_target", "workflow_run", "workflow_call"];
const problems = [];

const files = execFileSync("git", ["ls-files", "-z", "--", "*.yml", "*.yaml"], { encoding: "utf8" })
  .split("\0")
  .filter(Boolean);

const result = spawnSync(
  "bun",
  [
    "--config=/dev/null",
    "-e",
    "const out = {}; for (const path of process.argv.slice(1)) out[path] = Bun.YAML.parse(await Bun.file(path).text()); process.stdout.write(JSON.stringify(out))",
    ...files,
  ],
  { encoding: "utf8" },
);
if (result.error || result.status !== 0) {
  console.error(`check-git-auth: bun did not parse the YAML files, so no workflow was read: ${result.error?.message ?? result.stderr.trim()}`);
  process.exit(2);
}
const parsed = JSON.parse(result.stdout);

const runsScript = (value) => JSON.stringify(value ?? null).includes(script);
const isObject = (value) => typeof value === "object" && value !== null && !Array.isArray(value);
const readOnly = (permissions) =>
  isObject(permissions) && Object.keys(permissions).length === 1 && permissions.contents === "read";

function events(on) {
  if (typeof on === "string") return [on];
  if (Array.isArray(on)) return on;
  if (isObject(on)) return Object.keys(on);
  return [];
}

for (const file of files) {
  const document = parsed[file];
  if (!runsScript(document)) continue;
  if (!file.startsWith(".github/workflows/") || !isObject(document) || !isObject(document.jobs)) {
    problems.push(`${file} names ${script}. Only a step of a workflow job may run it, so this lint can read its token.`);
    continue;
  }
  const everyJob = runsScript({ ...document, jobs: null });
  const jobs = Object.entries(document.jobs).filter(([, job]) => everyJob || runsScript(job));
  if (!jobs.length) continue;
  const on = events(document.on);
  for (const event of banned.filter((name) => on.includes(name))) {
    problems.push(`${file} runs ${script} and starts on ${event}, which can give a job a token from another context.`);
  }
  for (const [name, job] of jobs) {
    const permissions = isObject(job) && "permissions" in job ? job.permissions : document.permissions;
    if (!readOnly(permissions)) {
      problems.push(`${file}: job ${name} runs ${script} with permissions ${JSON.stringify(permissions ?? null)}. It needs exactly {"contents":"read"}.`);
    }
  }
}

if (problems.length) {
  console.error(problems.map((problem) => `check-git-auth: ${problem}`).join("\n"));
  console.error(`check-git-auth: ${script} puts the job token in the env of every later step, so it runs only in a job whose token can only read the repo.`);
  process.exit(1);
}
