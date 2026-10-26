"use strict";

const reduceMotion = matchMedia("(prefers-reduced-motion: reduce)").matches;
const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

/* Smooth scroll: wheel and anchor jumps glide to a stop instead of stepping */

const lenis = reduceMotion
  ? null
  : new Lenis({ duration: 1.2, easing: (t) => Math.min(1, 1.001 - 2 ** (-10 * t)), autoRaf: true, anchors: true });

/* Scroll reveal */

const revealer = new IntersectionObserver(
  (entries) => {
    for (const entry of entries) {
      if (!entry.isIntersecting) continue;
      entry.target.classList.add("in");
      revealer.unobserve(entry.target);
    }
  },
  { rootMargin: "0px 0px -10% 0px" },
);
document.querySelectorAll(".reveal").forEach((el) => revealer.observe(el));

/* Navigation */

const burger = document.querySelector(".burger");
const menu = document.getElementById("menu");

function setMenu(open) {
  burger.setAttribute("aria-expanded", String(open));
  burger.setAttribute("aria-label", open ? "Close menu" : "Open menu");
  document.body.style.overflow = open ? "hidden" : "";
  if (open) lenis?.stop();
  else lenis?.start();
  if (open) {
    menu.hidden = false;
    requestAnimationFrame(() => requestAnimationFrame(() => menu.classList.add("open")));
  } else {
    menu.classList.remove("open");
    setTimeout(() => {
      if (burger.getAttribute("aria-expanded") === "false") menu.hidden = true;
    }, reduceMotion ? 0 : 700);
  }
}

burger.addEventListener("click", () => setMenu(burger.getAttribute("aria-expanded") !== "true"));
menu.addEventListener("click", (event) => {
  if (event.target.closest("a")) setMenu(false);
});
addEventListener("keydown", (event) => {
  if (event.key === "Escape" && burger.getAttribute("aria-expanded") === "true") {
    setMenu(false);
    burger.focus();
  }
});

const navLinks = [...document.querySelectorAll(".nav-links a")];
const sectionSpy = new IntersectionObserver(
  (entries) => {
    for (const entry of entries) {
      if (!entry.isIntersecting) continue;
      for (const link of navLinks) {
        if (link.hash === "#" + entry.target.id) link.setAttribute("aria-current", "location");
        else link.removeAttribute("aria-current");
      }
    }
  },
  { rootMargin: "-45% 0px -50% 0px" },
);
document.querySelectorAll("main section").forEach((section) => sectionSpy.observe(section));

/* Tagline: words light up one at a time in reading order as the block scrolls past */

const tagline = document.querySelector("[data-words]");
if (tagline) {
  const words = tagline.textContent.trim().split(/\s+/);
  tagline.setAttribute("aria-label", tagline.textContent.trim());
  tagline.innerHTML = words.map((word) => `<span class="w" aria-hidden="true">${word}</span>`).join(" ");
  const spans = [...tagline.children];
  let queued = false;
  const update = () => {
    queued = false;
    const box = tagline.getBoundingClientRect();
    const start = innerHeight * 0.85;
    const end = innerHeight * 0.35;
    const progress = (start - box.top) / (start - end + box.height);
    const lit = Math.round(Math.min(1, Math.max(0, progress)) * spans.length);
    spans.forEach((span, index) => span.classList.toggle("on", index < lit));
  };
  const onScroll = () => {
    if (queued) return;
    queued = true;
    requestAnimationFrame(update);
  };
  if (reduceMotion) spans.forEach((span) => span.classList.add("on"));
  else {
    new IntersectionObserver(([entry]) => {
      if (entry.isIntersecting) addEventListener("scroll", onScroll, { passive: true });
      else removeEventListener("scroll", onScroll);
      onScroll();
    }).observe(tagline);
  }
}

/* Window commands, with the same geometry as WindowAction.swift */

const WINDOW_COMMANDS = [
  ["Left Half", [0, 0, 0.5, 1]],
  ["Right Half", [0.5, 0, 0.5, 1]],
  ["Top Half", [0, 0, 1, 0.5]],
  ["Bottom Half", [0, 0.5, 1, 0.5]],
  ["Top Left Quarter", [0, 0, 0.5, 0.5]],
  ["Top Right Quarter", [0.5, 0, 0.5, 0.5]],
  ["Bottom Left Quarter", [0, 0.5, 0.5, 0.5]],
  ["Bottom Right Quarter", [0.5, 0.5, 0.5, 0.5]],
  ["First Three Fourths", [0, 0, 0.75, 1]],
  ["Center Three Fourths", [0.125, 0, 0.75, 1]],
  ["Last Three Fourths", [0.25, 0, 0.75, 1]],
  ["Maximize", [0, 0, 1, 1], "full fill expand"],
  ["Almost Maximize", [0.05, 0.05, 0.9, 0.9], "large expand padding"],
  ["Center", "center"],
  ["Restore Previous Size", "restore", "undo reset previous"],
  ["Minimize", "minimize", "minimise hide dock"],
  ["Move to Next Display", "display", "monitor screen"],
  ["Move to Previous Display", "display", "monitor screen"],
].map(([title, action, keywords = "snap tile resize move"]) => ({
  kind: "window",
  title,
  action,
  keywords: keywords + " window",
}));

const APPS = [
  ["Safari", "compass"],
  ["Calculator", "calculator"],
  ["Terminal", "terminal-window"],
  ["Notes", "note-pencil"],
  ["Music", "music-notes"],
  ["Calendar", "calendar-blank"],
  ["Mail", "envelope-simple"],
  ["System Settings", "gear-six"],
  ["Finder", "folder-simple"],
  ["Visual Studio Code", "code"],
  ["Messages", "chat-circle"],
  ["Photo Booth", "camera"],
].map(([title, icon]) => ({ kind: "app", title, icon, keywords: "" }));

function shapeSVG(action) {
  const inner = (x, y, w, h) =>
    `<rect x="${3 + x * 22}" y="${3 + y * 14}" width="${w * 22}" height="${h * 14}" rx="1.5"/>`;
  let body;
  if (Array.isArray(action)) body = inner(...action);
  else if (action === "center") body = inner(0.25, 0.22, 0.5, 0.56);
  else if (action === "restore")
    body = `<rect x="7" y="6" width="14" height="9" rx="1.5" fill="none" stroke="currentColor" stroke-width="1.5" stroke-dasharray="2 2"/>`;
  else if (action === "minimize") body = `<rect x="9" y="13" width="10" height="2" rx="1"/>`;
  else
    body = `<rect x="4" y="5" width="9" height="10" rx="1.5" opacity="0.4"/><rect x="15" y="5" width="9" height="10" rx="1.5"/>`;
  return `<svg viewBox="0 0 28 20" aria-hidden="true"><rect x="1" y="1" width="26" height="18" rx="3" fill="none" stroke="currentColor" stroke-width="1.5" opacity="0.6"/>${body}</svg>`;
}

const shapes = document.querySelector("[data-shapes]");
if (shapes) {
  shapes.innerHTML = WINDOW_COMMANDS.map((command) => `<span title="${command.title}">${shapeSVG(command.action)}</span>`).join("");
  const tiles = [...shapes.children];
  let index = 0;
  let timer = 0;
  const step = () => {
    tiles.forEach((tile, i) => tile.classList.toggle("on", i === index));
    index = (index + 1) % tiles.length;
  };
  if (reduceMotion) tiles[0].classList.add("on");
  else {
    new IntersectionObserver(([entry]) => {
      clearInterval(timer);
      if (entry.isIntersecting) timer = setInterval(step, 900);
    }).observe(shapes);
  }
}

/* Search: prefixes, abbreviations, typing errors, accents, and words in any order */

const fold = (text) =>
  text.normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase().trim();

function editDistance(a, b) {
  const rows = Array.from({ length: a.length + 1 }, (_, i) => [i]);
  for (let j = 1; j <= b.length; j++) rows[0][j] = j;
  for (let i = 1; i <= a.length; i++) {
    for (let j = 1; j <= b.length; j++) {
      const cost = a[i - 1] === b[j - 1] ? 0 : 1;
      rows[i][j] = Math.min(rows[i - 1][j] + 1, rows[i][j - 1] + 1, rows[i - 1][j - 1] + cost);
      if (i > 1 && j > 1 && a[i - 1] === b[j - 2] && a[i - 2] === b[j - 1])
        rows[i][j] = Math.min(rows[i][j], rows[i - 2][j - 2] + 1);
    }
  }
  return rows[a.length][b.length];
}

function score(entry, query) {
  const title = fold(entry.title);
  const words = title.split(" ");
  const terms = query.split(/\s+/);
  if (title === query) return 1000;
  if (title.startsWith(query)) return 900;
  if (terms.every((term) => words.some((word) => word.startsWith(term)))) return 800;
  if (query.length > 1 && words.map((word) => word[0]).join("").startsWith(query)) return 760;
  let typos = 0;
  const close = terms.every((term) => {
    if (term.length < 3) return words.some((word) => word.startsWith(term));
    const best = Math.min(
      ...words.flatMap((word) => [
        editDistance(term, word.slice(0, term.length)),
        editDistance(term, word.slice(0, term.length + 1)),
        editDistance(term, word),
      ]),
    );
    typos += best;
    return best <= (term.length >= 6 ? 2 : 1);
  });
  if (close) return 600 - typos * 20;
  const keywords = fold(entry.keywords).split(" ");
  if (terms.every((term) => [...words, ...keywords].some((word) => word.startsWith(term)))) return 300;
  return 0;
}

/* Interactive launcher */

const demo = document.getElementById("demo");
if (demo) initDemo(demo);

function initDemo(stage) {
  const launcher = stage.querySelector("[data-launcher]");
  const input = stage.querySelector("#demo-input");
  const list = stage.querySelector("#demo-results");
  const chip = stage.querySelector("[data-category]");
  const win = stage.querySelector("[data-window]");
  const hud = stage.querySelector("[data-hud]");
  const appNames = stage.querySelectorAll("[data-app-name]");
  const appIcon = stage.querySelector("[data-app-icon]");
  const categories = ["All", "Apps", "Windows"];
  const entries = [...APPS, ...WINDOW_COMMANDS];

  let category = 0;
  let results = [];
  let selected = 0;
  let frame = null;
  let previous = null;
  let hudTimer = 0;
  let autoplay = !reduceMotion;
  let reopenTimer = 0;

  const search = () => {
    const query = fold(input.value);
    if (!query) return [];
    const wanted = categories[category];
    return entries
      .filter((entry) => wanted === "All" || (wanted === "Apps") === (entry.kind === "app"))
      .map((entry) => ({ entry, score: score(entry, query) }))
      .filter((match) => match.score > 0)
      .sort((a, b) => b.score - a.score || a.entry.title.localeCompare(b.entry.title))
      .map((match) => match.entry);
  };

  const render = () => {
    results = search();
    selected = Math.min(selected, Math.max(0, results.length - 1));
    const hasQuery = fold(input.value) !== "";
    chip.hidden = !hasQuery;
    chip.firstChild.textContent = categories[category] + " ";
    list.hidden = results.length === 0;
    input.setAttribute("aria-expanded", String(results.length > 0));
    list.innerHTML = results
      .map((entry, index) => {
        const icon =
          entry.kind === "app"
            ? `<span class="tile"><svg aria-hidden="true"><use href="assets/icons.svg#${entry.icon}"/></svg></span>`
            : `<span class="tile shape">${shapeSVG(entry.action)}</span>`;
        const number = index < 9 ? `<span class="row-key num">⌘${index + 1}</span>` : "";
        return `<li class="row" role="option" id="demo-row-${index}" data-index="${index}" aria-selected="${index === selected}">${icon}<span class="row-title">${entry.title}</span><span class="row-key ret" aria-hidden="true">↵</span>${number}</li>`;
      })
      .join("");
    if (results.length) input.setAttribute("aria-activedescendant", `demo-row-${selected}`);
    else input.removeAttribute("aria-activedescendant");
  };

  const select = (index) => {
    if (!results.length) return;
    selected = (index + results.length) % results.length;
    list.querySelectorAll(".row").forEach((row, i) => row.setAttribute("aria-selected", String(i === selected)));
    input.setAttribute("aria-activedescendant", `demo-row-${selected}`);
    list.children[selected]?.scrollIntoView({ block: "nearest" });
  };

  const showHUD = (message) => {
    hud.textContent = message;
    hud.classList.add("show");
    clearTimeout(hudTimer);
    hudTimer = setTimeout(() => hud.classList.remove("show"), 2400);
  };

  const place = (rect) => {
    const [x, y, w, h] = rect;
    Object.assign(win.style, { left: `${x * 100}%`, top: `${y * 100}%`, width: `${w * 100}%`, height: `${h * 100}%` });
    frame = rect;
  };

  const currentFrame = () => {
    if (frame) return frame;
    const area = win.parentElement.getBoundingClientRect();
    const box = win.getBoundingClientRect();
    return [
      (box.left - area.left) / area.width,
      (box.top - area.top) / area.height,
      box.width / area.width,
      box.height / area.height,
    ];
  };

  const runWindow = ({ action }) => {
    if (action === "display") return showHUD("Connect another display to use this command.");
    if (action === "minimize") {
      win.classList.add("minimized");
      return;
    }
    const wasMinimized = win.classList.contains("minimized");
    win.classList.remove("minimized");
    if (wasMinimized && action === "restore") return;
    const now = currentFrame();
    if (action === "restore") {
      if (!previous) return showHUD("Move or resize this window first.");
      const target = previous;
      previous = now;
      return place(target);
    }
    const target = action === "center" ? [(1 - now[2]) / 2, (1 - now[3]) / 2, now[2], now[3]] : action;
    if (target.every((value, i) => Math.abs(value - now[i]) < 0.001)) return;
    previous = now;
    place(target);
  };

  const runApp = ({ title, icon }) => {
    win.classList.remove("minimized", "pop");
    void win.offsetWidth;
    win.classList.add("pop");
    appNames.forEach((name) => (name.textContent = title));
    appIcon.setAttribute("href", `assets/icons.svg#${icon}`);
  };

  const close = (refocus) => {
    launcher.classList.add("closed");
    clearTimeout(reopenTimer);
    reopenTimer = setTimeout(() => {
      input.value = "";
      category = 0;
      selected = 0;
      render();
      launcher.classList.remove("closed");
      if (refocus) input.focus({ preventScroll: true });
    }, 900);
  };

  const run = (index, refocus) => {
    const entry = results[index];
    if (!entry) return;
    if (entry.kind === "app") runApp(entry);
    else runWindow(entry);
    close(refocus);
  };

  const cycleCategory = (direction) => {
    category = (category + direction + categories.length) % categories.length;
    selected = 0;
    render();
  };

  const takeOver = () => {
    if (!autoplay) return;
    autoplay = false;
    input.value = "";
    selected = 0;
    render();
  };

  input.addEventListener("input", () => {
    selected = 0;
    render();
  });

  input.addEventListener("keydown", (event) => {
    launcher.classList.toggle("cmd", event.metaKey);
    if (event.key === "ArrowDown" || event.key === "ArrowUp") {
      event.preventDefault();
      select(selected + (event.key === "ArrowDown" ? 1 : -1));
    } else if (event.key === "Enter") {
      event.preventDefault();
      run(selected, true);
    } else if (event.key === "Tab") {
      event.preventDefault();
      cycleCategory(event.shiftKey ? -1 : 1);
    } else if (event.key === "Escape") {
      event.preventDefault();
      event.stopPropagation();
      close(true);
    } else if (event.metaKey && /^[1-9]$/.test(event.key)) {
      event.preventDefault();
      run(Number(event.key) - 1, true);
    }
  });

  input.addEventListener("keyup", (event) => launcher.classList.toggle("cmd", event.metaKey));
  input.addEventListener("blur", () => launcher.classList.remove("cmd"));

  list.addEventListener("mousemove", (event) => {
    const row = event.target.closest(".row");
    if (row && Number(row.dataset.index) !== selected) select(Number(row.dataset.index));
  });
  list.addEventListener("mousedown", (event) => event.preventDefault());
  list.addEventListener("click", (event) => {
    const row = event.target.closest(".row");
    if (row) run(Number(row.dataset.index), true);
  });

  chip.addEventListener("mousedown", (event) => event.preventDefault());
  chip.addEventListener("click", () => cycleCategory(1));
  launcher.querySelector(".launcher-top").addEventListener("click", () => input.focus());

  stage.addEventListener("pointerdown", takeOver);
  input.addEventListener("focus", takeOver);

  // Control Option Space opens the demo launcher, as it opens Ciel.
  addEventListener("keydown", (event) => {
    if (!(event.ctrlKey && event.altKey && event.code === "Space")) return;
    event.preventDefault();
    takeOver();
    clearTimeout(reopenTimer);
    launcher.classList.remove("closed");
    if (lenis) lenis.scrollTo(scrollY + stage.getBoundingClientRect().top - (innerHeight - stage.offsetHeight) / 2);
    else stage.scrollIntoView({ block: "center" });
    input.focus({ preventScroll: true });
  });

  render();
  if (autoplay) play();

  async function play() {
    let visible = false;
    new IntersectionObserver(([entry]) => (visible = entry.isIntersecting)).observe(stage);
    const wait = async (ms) => {
      await sleep(ms);
      while (autoplay && (!visible || document.hidden)) await sleep(250);
    };
    const script = ["safrai", "left", "vsc", "almost", "calclator", "top right", "music", "center th"];
    await wait(1600);
    for (let turn = 0; autoplay; turn = (turn + 1) % script.length) {
      for (const letter of script[turn]) {
        if (!autoplay) return;
        input.value += letter;
        selected = 0;
        render();
        await wait(90 + Math.random() * 70);
      }
      await wait(1100);
      if (!autoplay) return;
      list.children[selected]?.classList.add("pressed");
      await wait(140);
      if (!autoplay) return;
      run(selected, false);
      await wait(2200);
    }
  }
}
