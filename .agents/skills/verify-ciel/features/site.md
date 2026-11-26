# Site

The site in `site/` is a static Cloudflare Worker. Its home page has a launcher demo that answers typing, Tab, Return and Escape like the app, and four `Download for Mac` links to the latest release DMG. Playwright Test drives it on Linux, so this is the one feature an agent host can run itself.

## Sub-features

Each feature tag tags the tests in `e2e/` that prove it. [features.json](../features.json) maps each tag to the files of its feature.

- `@home` (`e2e/home.spec.ts`): `/` answers 200 with `X-Content-Type-Options: nosniff` and shows the heading.
- `@download` (`e2e/home.spec.ts`): every Download link goes to the latest release DMG. `bash site/check-downloads.sh` proves that link answers 200. It needs the network.
- `@demo` (`e2e/demo.spec.ts`): Left Half moves the demo window on Return, Tab cycles the category, Escape closes the launcher, and Return opens Calculator.
- `@pages` (`e2e/pages.spec.ts`): the Features and Privacy links, the 404 page, and the phone menu at 390 points.

## How to get to it (user POV)

- Open the site, use the demo, and click Download, Features or Privacy.

## Driving it with Playwright Test

| Tag | Runs in | Holds |
| --- | --- | --- |
| `@smoke` | the `verify` job of `checks.yml` on every PR and push | the home page, the Download links and the page links |
| `@verify` | the `verify` job, when the PR changes a file of its feature tag | one test for each flow |
| a feature tag | `--grep @demo` when you change that feature | every test of one feature |
| no tier tag | `nightly.yml` only | slow and rare paths |

- **Run.** `bun install && (cd site && bun install)`, then `node_modules/.bin/playwright test --grep @verify --project=desktop`, then `--grep @demo` with each tag that your change touches. The `webServer` of `playwright.config.ts` serves `site/` with `cf dev`. Set `PLAYWRIGHT_BASE_URL` to drive another server. `bun .agents/skills/verify-ciel/scripts/select.mjs origin/main` prints the grep that the `verify` job runs.
- **Coverage.** `scripts/check-tags.mjs` in this skill fails when a page in `site/public/` is in no tag, a tag tags no test, or a test has no feature tag. `check-fast.sh` runs it. Add the test and its tag in the PR that adds the page.
- **Nightly.** `nightly.yml` runs every test on `desktop` and `mobile` with one retry and a trace on the retry, and `bash site/prod-smoke.sh`, the signed-out GETs of prod that `bun run deploy` also runs. A red nightly opens or updates the issue "nightly is red". It is not a check on PRs.
- **Proof.** Paste each passed line (`✓ ... @verify`) in the PR body. A failure saves its screenshot and trace in `test-results/`.

## Gotchas

- Drive a local server, never the live site, so a proof shows the code under test. Prod gets only `site/prod-smoke.sh`.
- The demo is a copy in `site/public/assets/site.js`, not the app. A pass here proves nothing about the app.
- A test finds elements by role, label or text and waits on web-first assertions, never a fixed sleep. Each test fails on a console error or a 5xx through `e2e/fixture.ts`.
