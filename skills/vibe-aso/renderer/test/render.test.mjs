// Tests for render.js. Run: npm test  (from renderer/)
//
// These drive the real CLI rather than importing internals, because render.js
// is a script: the behaviour worth protecting is what it does to a project
// directory and what it exits with, not its private helpers.
//
// render.js imports playwright at its first line, so `npm install` is needed
// for ANY of this to run — without it every test skips. The render cases
// additionally need the browser and the fonts (`npx playwright install
// chromium` and `./fetch_fonts.sh`) and skip themselves independently.

import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { mkdtempSync, mkdirSync, writeFileSync, readFileSync, existsSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { deflateSync } from "node:zlib";

const HERE = dirname(fileURLToPath(import.meta.url));
const RENDERER = join(HERE, "..");
const RENDER = join(RENDERER, "render.js");

const hasPlaywright = existsSync(join(RENDERER, "node_modules", "playwright"));

// The browser is a separate download from the package, so check the binary
// itself — otherwise the render tests run and fail between `npm install` and
// `npx playwright install chromium` instead of skipping.
let hasChromium = false;
if (hasPlaywright) {
  try {
    const { chromium } = await import("playwright");
    hasChromium = existsSync(chromium.executablePath());
  } catch {
    hasChromium = false;
  }
}

const hasFonts =
  existsSync(join(RENDERER, "fonts", "NotoSans.ttf")) &&
  existsSync(join(RENDERER, "fonts", "DMSans.ttf"));

const needSetup = "run: npm install && npx playwright install chromium && ./fetch_fonts.sh";
const skipAll = hasPlaywright ? false : `playwright not installed — ${needSetup}`;
const skipRender = !hasChromium
  ? `chromium not installed — ${needSetup}`
  : !hasFonts
    ? `fonts not fetched — ${needSetup}`
    : false;

// ── helpers ──────────────────────────────────────────────────────────────────

// Minimal valid PNG of a solid colour, so the fixtures need no image library.
function png(width, height, [r, g, b]) {
  const chunk = (type, data) => {
    const len = Buffer.alloc(4);
    len.writeUInt32BE(data.length);
    const body = Buffer.concat([Buffer.from(type, "ascii"), data]);
    const crcTable = png.crcTable ??= Array.from({ length: 256 }, (_, n) => {
      let c = n;
      for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
      return c >>> 0;
    });
    let crc = 0xffffffff;
    for (const byte of body) crc = crcTable[(crc ^ byte) & 0xff] ^ (crc >>> 8);
    const crcBuf = Buffer.alloc(4);
    crcBuf.writeUInt32BE((crc ^ 0xffffffff) >>> 0);
    return Buffer.concat([len, body, crcBuf]);
  };
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(width, 0);
  ihdr.writeUInt32BE(height, 4);
  ihdr[8] = 8; // bit depth
  ihdr[9] = 2; // colour type: truecolour
  const row = Buffer.concat([Buffer.from([0]), Buffer.concat(Array.from({ length: width }, () => Buffer.from([r, g, b])))]);
  const raw = Buffer.concat(Array.from({ length: height }, () => row));
  return Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    chunk("IHDR", ihdr),
    chunk("IDAT", deflateSync(raw)),
    chunk("IEND", Buffer.alloc(0)),
  ]);
}

// A project dir with `shots` iphone backgrounds at the size config.json expects.
function project(headings, { shots = 2, app = { colors: { odd: "#FFFFFF", even: "#1A1A1A" } } } = {}) {
  const dir = mkdtempSync(join(tmpdir(), "vibe-aso-test-"));
  const cfg = JSON.parse(readFileSync(join(RENDERER, "config.json"), "utf8"));
  const { width, height } = cfg.devices.iphone;
  for (let i = 1; i <= shots; i++) writeFileSync(join(dir, `iphone_${i}.png`), png(width, height, [20, 22, 28]));
  writeFileSync(join(dir, "headings.json"), JSON.stringify(headings));
  if (app !== null) writeFileSync(join(dir, "app.json"), JSON.stringify(app));
  return dir;
}

// Run the CLI; never throws, so a test can assert on a non-zero exit.
function render(dir, ...args) {
  try {
    const stdout = execFileSync("node", [RENDER, dir, ...args], { encoding: "utf8", stdio: "pipe" });
    return { code: 0, out: stdout, err: "" };
  } catch (e) {
    return { code: e.status ?? 1, out: e.stdout ?? "", err: e.stderr ?? "" };
  }
}

const cleanup = (d) => rmSync(d, { recursive: true, force: true });

// ── validation: must fail before touching the browser ────────────────────────

describe("pre-flight validation", { skip: skipAll }, () => {
  test("locale absent from headings.json is named, not a TypeError", () => {
    const dir = project({ "en-US": ["a", "b"] });
    const { code, err } = render(dir, "iphone", "fr-FR");
    assert.equal(code, 1);
    assert.match(err, /fr-FR: not in headings\.json/);
    assert.doesNotMatch(err, /TypeError/);
    cleanup(dir);
  });

  test("too few headings for the screenshot count is refused, not blank-rendered", () => {
    const dir = project({ "en-US": ["only one"] }, { shots: 3 });
    const { code, err } = render(dir, "iphone", "en-US");
    assert.equal(code, 1);
    assert.match(err, /1 heading\(s\) but 3 iphone screenshot\(s\)/);
    assert.match(err, /missing iphone_2\.\.3/);
    assert.ok(!existsSync(join(dir, "out")), "must not write a partial out/ tree");
    cleanup(dir);
  });

  test("every problem is reported in one pass, not one per run", () => {
    const dir = project({ "en-US": ["a", ""], de: "not-an-array" });
    const { code, err } = render(dir);
    assert.equal(code, 1);
    assert.match(err, /de: headings must be an array/);
    assert.match(err, /en-US\[1\]: heading is empty/);
    cleanup(dir);
  });

  test("non-string heading is refused", () => {
    const dir = project({ "en-US": ["ok", 42] });
    const { code, err } = render(dir);
    assert.equal(code, 1);
    assert.match(err, /en-US\[1\]: heading must be a string, got number/);
    cleanup(dir);
  });

  test("valid JSON that is not an object is refused with the type named", () => {
    for (const [body, want] of [["null", /got null/], ["[1,2]", /got an array/]]) {
      const dir = project({ "en-US": ["a", "b"] });
      writeFileSync(join(dir, "headings.json"), body);
      const { code, err } = render(dir);
      assert.equal(code, 1);
      assert.match(err, /headings\.json must be a JSON object/);
      assert.match(err, want);
      cleanup(dir);
    }
  });

  test("malformed JSON names the file", () => {
    const dir = project({ "en-US": ["a", "b"] });
    writeFileSync(join(dir, "headings.json"), "{oops");
    const { code, err } = render(dir);
    assert.equal(code, 1);
    assert.match(err, /headings\.json is not valid JSON/);
    cleanup(dir);
  });

  test("missing app.json is named", () => {
    const dir = project({ "en-US": ["a", "b"] }, { app: null });
    const { code, err } = render(dir);
    assert.equal(code, 1);
    assert.match(err, /missing app\.json/);
    cleanup(dir);
  });

  test("app.json without both colors is refused", () => {
    const dir = project({ "en-US": ["a", "b"] }, { app: { colors: { odd: "#FFF" } } });
    const { code, err } = render(dir);
    assert.equal(code, 1);
    assert.match(err, /colors\.odd and colors\.even/);
    cleanup(dir);
  });

  // A truthy non-string passes a naive check and reaches the CSS as
  // "[object Object]", which Chromium drops — the heading renders in the
  // default black and the run still reports success.
  test("a color that is not a string is refused, not silently rendered black", () => {
    for (const odd of [{ hex: "#FFF" }, ["#FFF"], 255, true, "  "]) {
      const dir = project({ "en-US": ["a", "b"] }, { app: { colors: { odd, even: "#000" } } });
      const { code, err } = render(dir);
      assert.equal(code, 1, `colors.odd = ${JSON.stringify(odd)} must be refused`);
      assert.match(err, /non-empty strings/);
      cleanup(dir);
    }
  });

  test("unknown device lists the known ones instead of rendering nothing", () => {
    const dir = project({ "en-US": ["a", "b"] });
    const { code, err } = render(dir, "watch");
    assert.equal(code, 1);
    assert.match(err, /unknown device "watch"/);
    assert.match(err, /iphone/);
    cleanup(dir);
  });

  test("a project with no background PNGs fails instead of exiting 0", () => {
    const dir = mkdtempSync(join(tmpdir(), "vibe-aso-test-"));
    writeFileSync(join(dir, "headings.json"), JSON.stringify({ "en-US": ["a"] }));
    writeFileSync(join(dir, "app.json"), JSON.stringify({ colors: { odd: "#FFF", even: "#000" } }));
    const { code, err } = render(dir);
    assert.equal(code, 1);
    assert.match(err, /no background PNGs found/);
    cleanup(dir);
  });

  test("unreadable background PNG is caught before the browser starts", { skip: process.getuid?.() === 0 }, () => {
    const dir = project({ "en-US": ["a", "b"] });
    execFileSync("chmod", ["000", join(dir, "iphone_2.png")]);
    const { code, err } = render(dir);
    execFileSync("chmod", ["644", join(dir, "iphone_2.png")]);
    assert.equal(code, 1);
    assert.match(err, /iphone_2\.png is not readable/);
    cleanup(dir);
  });
});

// ── rendering ────────────────────────────────────────────────────────────────

describe("rendering", { skip: skipAll || skipRender }, () => {
  test("writes one PNG per heading and exits 0", () => {
    const dir = project({ "en-US": ["First heading", "Second heading"] });
    const { code, out } = render(dir, "iphone");
    assert.equal(code, 0);
    assert.match(out, /rendered 2 screenshot\(s\)/);
    for (const i of [1, 2]) assert.ok(existsSync(join(dir, "out", "en-US", `iphone_${i}.png`)));
    cleanup(dir);
  });

  test("the fit log reports a size and line count per image", () => {
    const dir = project({ "en-US": ["Short", "A much longer heading that has to shrink to fit the band"] });
    const { out } = render(dir, "iphone");
    assert.match(out, /en-US\/iphone_1: \d+px · \d+ lines/);
    assert.match(out, /en-US\/iphone_2: \d+px · \d+ lines/);
    cleanup(dir);
  });

  // The Vietnamese font fix. DM Sans has no Vietnamese subset, so a stack led
  // by DM Sans renders only the accented letters from Noto Sans — two
  // typefaces inside one word. `vi` must therefore differ from a DM-Sans-led
  // locale on identical text, and `vi-VN` must match `vi` (subtag matching).
  test("vi drops DM Sans, and vi-VN is treated the same as vi", () => {
    const text = "Theo dõi từng calo";
    const dir = project({ "en-US": [text, text], vi: [text, text], "vi-VN": [text, text] });
    assert.equal(render(dir, "iphone").code, 0);
    const read = (loc) => readFileSync(join(dir, "out", loc, "iphone_1.png"));
    const vi = read("vi");
    assert.ok(!vi.equals(read("en-US")), "vi must not render with the DM-Sans-led stack");
    assert.ok(vi.equals(read("vi-VN")), "vi-VN must resolve to the same stack as vi");
    cleanup(dir);
  });

  test("a locale whose text needs no DM Sans substitute is unaffected", () => {
    const text = "Track every calorie";
    const dir = project({ "en-US": [text, text], "de-DE": [text, text] });
    assert.equal(render(dir, "iphone").code, 0);
    const a = readFileSync(join(dir, "out", "en-US", "iphone_1.png"));
    const b = readFileSync(join(dir, "out", "de-DE", "iphone_1.png"));
    assert.ok(a.equals(b), "same text, same Latin stack, so the images must match");
    cleanup(dir);
  });

  // A failure the pre-flight cannot predict: the output directory for one
  // locale is not writable, so its screenshots fail at write time. The other
  // locale must still render, and the run must not claim success.
  test("one failing locale does not stop the others, and the run exits 1", { skip: process.getuid?.() === 0 }, () => {
    const dir = project({ "en-US": ["one", "two"], "de-DE": ["eins", "zwei"] });
    const blocked = join(dir, "out", "en-US");
    mkdirSync(blocked, { recursive: true });
    execFileSync("chmod", ["500", blocked]);
    const { code, out, err } = render(dir, "iphone");
    execFileSync("chmod", ["755", blocked]);

    assert.equal(code, 1, "a run with failures must not exit 0");
    assert.match(out, /en-US\/iphone_1: FAILED/);
    assert.match(out, /de-DE\/iphone_1: \d+px/, "the healthy locale must still render");
    assert.match(out, /rendered 2 screenshot\(s\)/, "only de-DE's two images should be written");
    assert.match(err, /2 screenshot\(s\) FAILED/);
    assert.match(err, /do not upload this set/);
    assert.ok(existsSync(join(dir, "out", "de-DE", "iphone_1.png")));
    cleanup(dir);
  });
});
