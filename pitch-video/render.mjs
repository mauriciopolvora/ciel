// Renders the Ciel pitch video from index.html, one frame at a time.
//
//   npm install
//   node render.mjs                  writes out/ciel-pitch-<seconds>s.mp4 and out/ciel-pitch-poster.png
//   node render.mjs stills 2.3 12.5  writes frames/stills/<seconds>.png, to check a moment without a full render
//
// index.html draws any moment from window.render(seconds), so frames render in any order and in parallel.
// Needs ffmpeg and a Chromium. Set CHROMIUM to its path, or run `npx playwright-core install chromium`.

import { spawn } from "node:child_process";
import { createReadStream, existsSync, readdirSync } from "node:fs";
import { mkdir } from "node:fs/promises";
import { createServer } from "node:http";
import { homedir } from "node:os";
import { extname, join, normalize } from "node:path";
import { fileURLToPath } from "node:url";
import { chromium } from "playwright-core";

const here = fileURLToPath(new URL(".", import.meta.url));
const root = join(here, "..");
const FPS = 60;
const WIDTH = 1280;
const HEIGHT = 720;
const SUPERSAMPLE = 3; // frames render at 3840x2160 and scale down to 1920x1080
const WORKERS = 4;

const TYPES = {
  ".html": "text/html; charset=utf-8",
  ".png": "image/png",
  ".svg": "image/svg+xml",
  ".webp": "image/webp",
  ".woff2": "font/woff2",
};

function serve() {
  const server = createServer((request, response) => {
    const path = normalize(join(root, decodeURIComponent(new URL(request.url, "http://localhost").pathname)));
    if (!path.startsWith(root) || !existsSync(path) || !TYPES[extname(path)]) {
      response.writeHead(404).end();
      return;
    }
    response.writeHead(200, { "Content-Type": TYPES[extname(path)] });
    createReadStream(path).pipe(response);
  });
  return new Promise((resolve) => server.listen(0, "127.0.0.1", () => resolve(server)));
}

function cachedChromium() {
  if (process.env.CHROMIUM) return process.env.CHROMIUM;
  const cache = join(homedir(), ".cache", "ms-playwright");
  if (!existsSync(cache)) return undefined;
  const builds = readdirSync(cache)
    .filter((name) => /^chromium-\d+$/.test(name))
    .sort((a, b) => Number(b.split("-")[1]) - Number(a.split("-")[1]));
  for (const build of builds) {
    for (const folder of readdirSync(join(cache, build))) {
      const binary = join(cache, build, folder, "chrome");
      if (existsSync(binary)) return binary;
    }
  }
  return undefined;
}

async function openPage(url, scale) {
  const browser = await chromium.launch({ executablePath: cachedChromium() });
  const page = await browser.newPage({ viewport: { width: WIDTH, height: HEIGHT }, deviceScaleFactor: scale });
  page.on("pageerror", (error) => {
    throw error;
  });
  await page.goto(url);
  if (!(await page.evaluate(() => window.ready))) throw new Error("Geist did not load");
  return { browser, page };
}

async function shoot(page, seconds, path) {
  await page.evaluate((t) => window.render(t), seconds);
  return page.screenshot({ path, type: "png" });
}

function ffmpeg(args) {
  const child = spawn("ffmpeg", ["-hide_banner", "-loglevel", "error", "-y", ...args], {
    stdio: ["pipe", "inherit", "inherit"],
  });
  const exit = new Promise((resolve, reject) => {
    child.on("exit", (code) => (code === 0 ? resolve() : reject(new Error(`ffmpeg exited with ${code}`))));
  });
  return { input: child.stdin, exit };
}

const server = await serve();
const url = `http://127.0.0.1:${server.address().port}/pitch-video/index.html`;

try {
  if (process.argv[2] === "stills") {
    const folder = join(here, "frames", "stills");
    await mkdir(folder, { recursive: true });
    const { browser, page } = await openPage(url, 1.5);
    for (const seconds of process.argv.slice(3).map(Number)) {
      await shoot(page, seconds, join(folder, `${seconds.toFixed(2)}.png`));
    }
    await browser.close();
  } else {
    await mkdir(join(here, "out"), { recursive: true });
    const scale = "scale=1920:1080:flags=lanczos";
    const first = await openPage(url, SUPERSAMPLE);
    const duration = await first.page.evaluate(() => window.DURATION);
    const posterAt = await first.page.evaluate(() => window.POSTER_AT);
    const total = Math.round(duration * FPS);

    const poster = join(here, "out", "ciel-pitch-poster.png");
    const still = ffmpeg(["-f", "image2pipe", "-c:v", "png", "-i", "-", "-vf", scale, "-frames:v", "1", poster]);
    still.input.end(await shoot(first.page, posterAt));
    await still.exit;

    // Frames render out of order and reach ffmpeg in order, straight from memory.
    const video = join(here, "out", `ciel-pitch-${duration}s.mp4`);
    const encoder = ffmpeg([
      "-f", "image2pipe", "-framerate", String(FPS), "-c:v", "png", "-i", "-",
      "-vf", `${scale}:out_color_matrix=bt709:out_range=tv,format=yuv420p`,
      "-c:v", "libx264", "-preset", "slow", "-crf", "15",
      "-colorspace", "bt709", "-color_primaries", "bt709", "-color_trc", "bt709",
      "-movflags", "+faststart", "-an", video,
    ]);
    const waiting = new Map();
    let next = 0;
    let written = 0;
    let turn = Promise.resolve();
    const flush = async () => {
      while (waiting.has(written)) {
        const frame = waiting.get(written);
        waiting.delete(written);
        if (!encoder.input.write(frame)) await new Promise((resolve) => encoder.input.once("drain", resolve));
        if (++written % 120 === 0) console.log(`${written} of ${total} frames`);
      }
    };
    const pages = [first, ...(await Promise.all(Array.from({ length: WORKERS - 1 }, () => openPage(url, SUPERSAMPLE))))];
    await Promise.all(
      pages.map(async ({ browser, page }) => {
        while (next < total) {
          const index = next++;
          while (index - written > WORKERS * 6) await new Promise((resolve) => setTimeout(resolve, 20));
          waiting.set(index, await shoot(page, index / FPS));
          turn = turn.then(flush);
          await turn;
        }
        await browser.close();
      }),
    );
    encoder.input.end();
    await encoder.exit;
    console.log(video);
    console.log(poster);
  }
} finally {
  server.close();
}
