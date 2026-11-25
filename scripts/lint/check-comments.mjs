import { execFileSync } from "node:child_process";
import { existsSync, lstatSync, readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

process.chdir(fileURLToPath(new URL("../..", import.meta.url)));
const allowed = /^(WARNING:|shellcheck )/;
const vendored = /^site\/public\/assets\/lenis\//;
const git = (...args) => execFileSync("git", args, { encoding: "utf8", maxBuffer: 1 << 28 });

function shellLexer() {
  const stack = [{ t: "code", depth: 0 }];
  let heredocs = [];
  return (line) => {
    if (heredocs.length) {
      if ((heredocs[0].strip ? line.replace(/^\t+/, "") : line) === heredocs[0].word) {
        heredocs.shift();
      }
      return [];
    }
    const pending = [];
    let prev = "";
    for (let i = 0; i < line.length; i++) {
      const c = line[i];
      const top = stack.at(-1);
      if (top.t === "sq") {
        if (c === "'") {
          stack.pop();
        }
      } else if (top.t === "ansi" || top.t === "dq") {
        if (c === "\\") {
          i++;
        } else if (top.t === "ansi" && c === "'") {
          stack.pop();
        } else if (top.t === "dq" && c === '"') {
          stack.pop();
        } else if (top.t === "dq" && line.startsWith("$(", i)) {
          const arith = line.startsWith("$((", i);
          stack.push({ t: "code", depth: 0, sub: true, arith });
          i += arith ? 2 : 1;
        } else if (top.t === "dq" && c === "`") {
          stack.push({ t: "code", depth: 0, end: "`" });
        }
      } else if (c === "\\") {
        i++;
        prev = "x";
        continue;
      } else if (top.t === "param") {
        if (c === "'") {
          stack.push({ t: "sq" });
        } else if (c === '"') {
          stack.push({ t: "dq" });
        } else if (c === "`") {
          stack.push({ t: "code", depth: 0, end: "`" });
        } else if (line.startsWith("$(", i)) {
          stack.push({ t: "code", depth: 0, sub: true });
          i++;
        } else if (c === "{") {
          top.depth++;
        } else if (c === "}" && top.depth-- === 0) {
          stack.pop();
        }
      } else if (top.end && c === top.end) {
        stack.pop();
      } else if (c === "'") {
        stack.push({ t: prev === "$" ? "ansi" : "sq" });
      } else if (c === '"') {
        stack.push({ t: "dq" });
      } else if (c === "`") {
        stack.push({ t: "code", depth: 0, end: "`" });
      } else if (c === "#" && (prev === "" || /[\s;&|()<>]/.test(prev))) {
        heredocs = pending;
        return [line.slice(i)];
      } else if (
        line.startsWith("$((", i) ||
        (line.startsWith("((", i) && (prev === "" || /[\s;&|]/.test(prev)))
      ) {
        const skip = line[i] === "$" ? 2 : 1;
        stack.push({ t: "code", depth: 0, sub: true, arith: true });
        i += skip;
      } else if (line.startsWith("$(", i)) {
        stack.push({ t: "code", depth: 0, sub: true });
        i++;
      } else if (line.startsWith("${", i)) {
        stack.push({ t: "param", depth: 0 });
        i++;
      } else if (c === "(") {
        top.depth++;
      } else if (c === ")") {
        if (top.depth > 0) {
          top.depth--;
        } else if (top.sub) {
          if (top.arith) {
            i++;
          }
          stack.pop();
        }
      } else if (line.startsWith("<<<", i)) {
        i += 2;
      } else if (!top.arith && line.startsWith("<<", i)) {
        const m = /^<<(-?)[ \t]*(?:(['"])(.*?)\2|\\?([^\s;&|()<>'"]+))/.exec(line.slice(i));
        if (m) {
          pending.push({ strip: m[1] === "-", word: m[3] ?? m[4] });
          i += m[0].length - 1;
          prev = "x";
          continue;
        }
      }
      prev = line[i];
    }
    heredocs = pending;
    return [];
  };
}

function yamlLexer() {
  let block = null;
  let quote = "";
  return (line) => {
    if (block?.plain) {
      const indent = line.match(/^ */)[0].length;
      if (line.trim() === "" || indent > block.indent) {
        const at = line.search(/(^|\s)#/);
        const code = at < 0 ? line : line.slice(0, at);
        const found = at < 0 ? [] : [line.slice(at).trim()];
        if (!block.inComment) {
          const shell = block.plain(` ${code.trim()}`);
          block.inComment = shell.length > 0;
          found.push(...shell);
        }
        return found;
      }
      block = null;
    }
    if (block) {
      const indent = line.match(/^ */)[0].length;
      if (line.trim() === "" || indent > block.indent) {
        if (!block.shell) {
          return [];
        }
        if (line.trim() !== "") {
          block.content ??= indent;
        }
        return block.shell(line.slice(block.content ?? 0));
      }
      block = null;
    }
    let at = -1;
    for (let i = 0; i < line.length; i++) {
      const c = line[i];
      if (quote === '"') {
        if (c === "\\") {
          i++;
        } else if (c === '"') {
          quote = "";
        }
      } else if (quote === "'") {
        if (c === "'" && line[i + 1] === "'") {
          i++;
        } else if (c === "'") {
          quote = "";
        }
      } else if (
        (c === '"' || c === "'") &&
        /(^\s*(-\s+)?|:\s+|[[{,]\s*)$/.test(line.slice(0, i))
      ) {
        quote = c;
      } else if (c === "#" && (i === 0 || /\s/.test(line[i - 1]))) {
        at = i;
        break;
      }
    }
    const found = [];
    if (at >= 0 && !isPin(line, at)) {
      found.push(line.slice(at));
    }
    const code = at < 0 ? line : line.slice(0, at);
    const m = /^(\s*(?:-\s+)?)([\w-]+):\s*[|>][-+0-9]*\s*$/.exec(code);
    if (m) {
      block = { indent: m[1].length, shell: m[2] === "run" ? shellLexer() : null };
    }
    const plain = /^(\s*(?:-\s+)?)run:(?:\s+([^\s"'|>].*))?\s*$/.exec(code);
    if (plain) {
      const shell = shellLexer();
      const comments = shell(plain[2] ?? "");
      found.push(...comments);
      block = { indent: plain[1].length, plain: shell, inComment: comments.length > 0 };
      quote = "";
    }
    const run = /^\s*(?:-\s+)?run:\s+(["'])(.*)\1\s*$/.exec(code);
    if (run) {
      const script =
        run[1] === '"'
          ? run[2].replaceAll(/\\(.)/g, (_, e) => (e === "n" ? "\n" : e))
          : run[2].replaceAll("''", "'");
      const lex = shellLexer();
      for (const part of script.split("\n")) {
        found.push(...lex(part));
      }
    }
    return found;
  };
}

function jsLexer() {
  const stack = [{ t: "code", depth: 0 }];
  let last = "";
  const regexCanStart = () =>
    last === "" ||
    /[(,=:[!&|?{};+\-*%<>~^]$/.test(last) ||
    /^(return|typeof|case|do|else|in|of|new|delete|void|throw|yield|await)$/.test(last);
  return (line) => {
    const found = [];
    let at = -1;
    for (let i = 0; i < line.length; i++) {
      const c = line[i];
      const top = stack.at(-1);
      if (top.t === "block") {
        if (line.startsWith("*/", i)) {
          stack.pop();
          i++;
        }
        continue;
      }
      if (top.t === "sq" || top.t === "dq") {
        if (c === "\\") {
          i++;
        } else if (c === (top.t === "sq" ? "'" : '"')) {
          stack.pop();
        }
        continue;
      }
      if (top.t === "tpl") {
        if (c === "\\") {
          i++;
        } else if (c === "`") {
          stack.pop();
        } else if (line.startsWith("${", i)) {
          stack.push({ t: "code", depth: 0, tpl: true });
          i++;
        }
        continue;
      }
      if (top.t === "regex") {
        if (c === "\\") {
          i++;
        } else if (c === "[") {
          top.inClass = true;
        } else if (c === "]") {
          top.inClass = false;
        } else if (c === "/" && !top.inClass) {
          stack.pop();
          last = "x";
        }
        continue;
      }
      if (/\s/.test(c)) {
        continue;
      }
      if (line.startsWith("//", i)) {
        found.push(line.slice(i));
        break;
      }
      if (line.startsWith("/*", i)) {
        if (at < 0) {
          at = i;
        }
        stack.push({ t: "block" });
        i++;
        continue;
      }
      if (c === "/" && regexCanStart()) {
        stack.push({ t: "regex" });
        continue;
      }
      if (c === "'") {
        stack.push({ t: "sq" });
      } else if (c === '"') {
        stack.push({ t: "dq" });
      } else if (c === "`") {
        stack.push({ t: "tpl" });
      } else if (c === "{") {
        top.depth++;
      } else if (c === "}" && top.tpl && top.depth === 0) {
        stack.pop();
      } else if (c === "}") {
        top.depth--;
      }
      if (/[\w$]/.test(c)) {
        const word = /^[\w$]+/.exec(line.slice(i))[0];
        last = word;
        i += word.length - 1;
      } else {
        last = c === "'" || c === '"' || c === "`" ? "x" : c;
      }
    }
    if (stack.at(-1).t === "regex") {
      stack.pop();
    }
    if (at >= 0) {
      found.push(line.slice(at));
    } else if (stack.at(-1).t === "block" && found.length === 0 && line.trim() !== "") {
      found.push(line.trim());
    }
    return found;
  };
}

const isPin = (line, at) =>
  /^\s*(?:-\s+)?uses:\s+\S+@[0-9a-f]{40}\s+$/.test(line.slice(0, at)) &&
  /^#\s*v\d/.test(line.slice(at));

const files = git("ls-files", "-z")
  .split("\0")
  .filter((file) => /\.(sh|ya?ml|m?js)$|^\.githooks\//.test(file) && !vendored.test(file))
  .filter((file) => existsSync(file) && !lstatSync(file).isSymbolicLink());
const hits = [];
for (const file of files) {
  const lex = /\.ya?ml$/.test(file) ? yamlLexer() : /\.m?js$/.test(file) ? jsLexer() : shellLexer();
  readFileSync(file, "utf8")
    .split("\n")
    .forEach((line, n) => {
      if (n === 0 && line.startsWith("#!")) {
        return;
      }
      if (lex(line).some((text) => !allowed.test(text.replace(/^(#+|\/\/+|\/\*+)\s*/, "")))) {
        hits.push(`${file}:${n + 1}: ${line}`);
      }
    });
}
if (hits.length) {
  console.log(hits.join("\n"));
  console.error(
    "check-comments: the lines above are comments. Delete each one, or start it with WARNING: when it warns about a tool or platform that this repo cannot change.",
  );
  process.exit(1);
}
