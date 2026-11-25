# Site

The site in `site/` is a static Cloudflare Worker. Its home page has a launcher demo that answers typing, Tab, Return and Escape like the app, and four `Download for Mac` links to the latest release DMG. The recipe finds them by their text, so a link with a wrong address fails. It runs on Linux, so this is the one recipe an agent host can run itself.

## Sub-features

- `site-home` answers 200 with `X-Content-Type-Options: nosniff` and shows the heading.
- `site-download` points every Download link at the latest release DMG, and that link answers 200.
- `site-demo` lists Left Half for `left half`, moves the demo window on Return, cycles the category with Tab, closes on Escape, and opens Calculator.
- `site-pages` opens Features, Privacy and the 404 page, and the phone menu at 390 points.

## How to get to it (user POV)

- Open the site, use the demo, and click Download, Features or Privacy.

## Driving it with site-verify.mjs

Preconditions:

- Node and a `playwright-core` with its Chromium. Point `NODE_PATH` at the `node_modules` that holds it.
- The site serves on a local port: `cd site && bun install --frozen-lockfile && bun run dev`. It prints the URL.

- **Run.** `NODE_PATH=<dir> node .agents/skills/verify-ciel/scripts/site-verify.mjs http://localhost:<port>`. Each step prints a `PASS site:` line. The first failure prints one `FAIL site:` line and exits 1.
- **Download.** `bash site/check-downloads.sh` asks GitHub for each release link and prints `200 <url>`. It needs the network.
- **Proof.** Screenshots go to `.build/verify/site/<run id>/`, and `.build/verify/site/latest` points at the newest run: `site-home.png`, `site-demo-left-half.png`, `site-privacy.png`, `site-404.png` and `site-phone-menu.png`.

## Gotchas

- Run it against a local server, never the live site, so a proof shows the code under test.
- The demo is a copy in `site/public/assets/site.js`, not the app. A pass here proves nothing about the app.
