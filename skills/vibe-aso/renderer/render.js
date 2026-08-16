import { chromium } from "playwright";
import { readFileSync, existsSync, mkdirSync, accessSync, constants } from "fs";
import { fileURLToPath } from "url";
import { basename, dirname, join, resolve } from "path";

const __dirname = dirname(fileURLToPath(import.meta.url));

const cfg = JSON.parse(readFileSync(join(__dirname, "config.json"), "utf8"));
const template = readFileSync(join(__dirname, "template.html"), "utf8");

// font family -> file. DM Sans + Noto Sans are the always-loaded base (cover
// Latin / Latin-ext / Cyrillic / Greek / Vietnamese). The rest load per-locale.
const FONTS = {
  "DM Sans": "DMSans.ttf",
  "Noto Sans": "NotoSans.ttf",
  "Noto Sans Hebrew": "NotoSansHebrew.ttf",
  "Noto Sans Arabic": "NotoSansArabic.ttf",
  "Noto Sans Devanagari": "NotoSansDevanagari.ttf",
  "Noto Sans Bengali": "NotoSansBengali.ttf",
  "Noto Sans Gujarati": "NotoSansGujarati.ttf",
  "Noto Sans Gurmukhi": "NotoSansGurmukhi.ttf",
  "Noto Sans Kannada": "NotoSansKannada.ttf",
  "Noto Sans Malayalam": "NotoSansMalayalam.ttf",
  "Noto Sans Oriya": "NotoSansOriya.ttf",
  "Noto Sans Tamil": "NotoSansTamil.ttf",
  "Noto Sans Telugu": "NotoSansTelugu.ttf",
  "Noto Sans Thai": "NotoSansThai.ttf",
  "Noto Sans JP": "NotoSansJP.ttf",
  "Noto Sans KR": "NotoSansKR.ttf",
  "Noto Sans SC": "NotoSansSC.ttf",
  "Noto Sans TC": "NotoSansTC.ttf",
};
// locale -> extra script font appended to the base stack (per-glyph fallback)
const LOCALE_FONT = {
  he: "Noto Sans Hebrew",
  "ar-SA": "Noto Sans Arabic", "ur-PK": "Noto Sans Arabic",
  hi: "Noto Sans Devanagari", "mr-IN": "Noto Sans Devanagari",
  "bn-BD": "Noto Sans Bengali",
  "gu-IN": "Noto Sans Gujarati",
  "pa-IN": "Noto Sans Gurmukhi",
  "kn-IN": "Noto Sans Kannada",
  "ml-IN": "Noto Sans Malayalam",
  "or-IN": "Noto Sans Oriya",
  "ta-IN": "Noto Sans Tamil",
  "te-IN": "Noto Sans Telugu",
  th: "Noto Sans Thai",
  ja: "Noto Sans JP",
  ko: "Noto Sans KR",
  "zh-Hans": "Noto Sans SC",
  "zh-Hant": "Noto Sans TC",
};

// Fonts and backgrounds are served to the page over a synthetic origin (see
// the route handler below) instead of being inlined as base64 data URLs.
// Inlining cost real time: NotoSansSC.ttf alone is 17 MB, so a zh-Hans page
// carried ~23 MB of base64 in its HTML, re-encoded and re-parsed for every
// screenshot. Measured on 4 images: 17.4 s / 900 MB inlined vs 2.3 s / 209 MB
// for a Latin locale with the same code path.
const ORIGIN = "http://vibe-aso.invalid";

const fontPath = (family) => join(__dirname, "fonts", FONTS[family]);

// Latin-script locales that must NOT lead with DM Sans. DM Sans has no
// Vietnamese subset — measured against its cmap, it is missing 12 of the 18
// distinctive Vietnamese letters (ữ ỡ ế ề ạ ọ ơ ư ớ ầ ệ ỉ). With DM Sans
// first, per-glyph fallback pulls only those letters from Noto Sans, so a
// single Vietnamese word renders in two typefaces ("Theo dõi từng calo" mixes
// mid-word). Every other Latin locale in the phase-2 set is fully covered.
const NO_DM_SANS = new Set(["vi"]);

function fontFamilies(locale) {
  // DM Sans first (Latin/brand), then the locale's script font (so it wins over
  // Noto Sans for shared scripts like Cyrillic), then Noto Sans as final safety net.
  const stack = NO_DM_SANS.has(locale) ? [] : ["DM Sans"];
  if (LOCALE_FONT[locale]) stack.push(LOCALE_FONT[locale]);
  stack.push("Noto Sans");
  return stack;
}

function fontAssets(locale) {
  const families = fontFamilies(locale);
  const faces = families
    .map(
      (f) =>
        `@font-face { font-family: "${f}"; src: url("${ORIGIN}/fonts/${FONTS[f]}") format("truetype"); font-weight: 100 900; }`
    )
    .join("\n  ");
  const stack = families.map((f) => `"${f}"`).join(", ");
  return { faces, stack };
}

// CLI: node render.js <project-dir> [device] [locale]
//   <project-dir> holds iphone_1..N.png / ipad_1..N.png, app.json, headings.json
const projectArg = process.argv[2];
const onlyDevice = process.argv[3];
const onlyLocale = process.argv[4];
if (!projectArg) {
  console.error("usage: node render.js <project-dir> [device] [locale]");
  process.exit(1);
}

const die = (msg) => {
  console.error(msg);
  process.exit(1);
};

const appDir = resolve(projectArg);
const readJson = (name) => {
  const p = join(appDir, name);
  if (!existsSync(p)) die(`missing ${name} in ${appDir} — see reference/screenshots.md`);
  try {
    return JSON.parse(readFileSync(p, "utf8"));
  } catch (e) {
    die(`${name} is not valid JSON: ${e.message}`);
  }
};

const headings = readJson("headings.json");
// per-app settings: { colors: { odd, even } }. odd = screenshots 1,3,5… / even = 2,4,6…
const appCfg = readJson("app.json");
if (!appCfg.colors?.odd || !appCfg.colors?.even)
  die(`app.json needs colors.odd and colors.even (e.g. {"colors":{"odd":"#FFF","even":"#1A1A1A"}})`);
const colorFor = (i) => (i % 2 === 1 ? appCfg.colors.odd : appCfg.colors.even);
// how many screenshots this device actually has (1,2,3,4…) — auto-detected
const shotCount = (device) => {
  let n = 0;
  while (existsSync(join(appDir, `${device}_${n + 1}.png`))) n++;
  return n;
};

const RTL_LANGS = ["ar", "he", "fa", "ur"];
const isRTL = (locale) => RTL_LANGS.some((l) => locale === l || locale.startsWith(l + "-"));
// keep alphanumeric product codes (e.g. "MP3-X", "B-12") from breaking at the hyphen
const protectCodes = (s) => s.replace(/([A-Za-z])-(?=\d)/g, "$1‑");
const escapeHtml = (s) =>
  protectCodes(s)
    .replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
    // honor an explicit line break in the heading ("a\nb") as a forced <br>
    .replace(/\n/g, "<br>");

function buildHtml({ device, bgUrl, text, color, dir, faces, stack }) {
  const d = cfg.devices[device];
  return template
    .replaceAll("__FONTFACES__", faces)
    .replaceAll("__FONTSTACK__", stack)
    .replaceAll("__BG_URL__", bgUrl)
    .replaceAll("__W__", d.width)
    .replaceAll("__H__", d.height)
    .replaceAll("__TOP__", d.topMarginPx)
    .replaceAll("__BAND__", d.bandHeightPx)
    .replaceAll("__PAD__", d.sidePaddingPx)
    .replaceAll("__WEIGHT__", cfg.font.weight)
    .replaceAll("__FONT__", d.sizePx)
    .replaceAll("__LH__", cfg.font.lineHeight)
    .replaceAll("__COLOR__", color)
    .replaceAll("__DIR__", dir)
    .replaceAll("__TEXT__", escapeHtml(text));
}

// device classes come from config.json — add one there (e.g. "watch") and
// drop <device>_1..N.png files next to the others; no code change needed
if (onlyDevice && !cfg.devices[onlyDevice])
  die(`unknown device "${onlyDevice}" — config.json defines: ${Object.keys(cfg.devices).join(", ")}`);
const devices = (onlyDevice ? [onlyDevice] : Object.keys(cfg.devices)).filter((dev) =>
  existsSync(join(appDir, `${dev}_1.png`))
);
if (!devices.length)
  die(
    `no background PNGs found in ${appDir} — expected ${(onlyDevice ? [onlyDevice] : Object.keys(cfg.devices))
      .map((d) => `${d}_1.png`)
      .join(" or ")}`
  );

const locales = onlyLocale ? [onlyLocale] : Object.keys(headings);
if (!locales.length) die("headings.json has no locales");

// Per-device shot counts, resolved once — the render loop used to re-stat the
// project directory on every iteration of its own loop condition.
const shots = Object.fromEntries(devices.map((dev) => [dev, shotCount(dev)]));

// ── pre-flight ───────────────────────────────────────────────────────────────
// Catch a bad headings.json BEFORE launching the browser and writing half an
// output tree. A locale missing from the file used to throw a bare TypeError
// on the documented single-locale command; a locale with too few headings
// silently rendered a blank band, which is the worst outcome of the three
// because the screenshot looks fine until it is on the store.
const problems = [];
for (const locale of locales) {
  const texts = headings[locale];
  if (texts === undefined) {
    problems.push(`${locale}: not in headings.json (has: ${Object.keys(headings).join(", ")})`);
    continue;
  }
  if (!Array.isArray(texts)) {
    problems.push(`${locale}: headings must be an array of strings, got ${typeof texts}`);
    continue;
  }
  for (const device of devices) {
    if (texts.length < shots[device])
      problems.push(
        `${locale}: ${texts.length} heading(s) but ${shots[device]} ${device} screenshot(s) — ` +
          `missing ${device}_${texts.length + 1}..${shots[device]}`
      );
  }
  texts.forEach((t, i) => {
    if (typeof t !== "string") problems.push(`${locale}[${i}]: heading must be a string, got ${typeof t}`);
    else if (!t.trim()) problems.push(`${locale}[${i}]: heading is empty`);
  });
}
for (const device of devices)
  for (let i = 1; i <= shots[device]; i++) {
    const p = join(appDir, `${device}_${i}.png`);
    try {
      accessSync(p, constants.R_OK);
    } catch {
      problems.push(`${device}_${i}.png is not readable`);
    }
  }
const missingFonts = [...new Set(locales.flatMap(fontFamilies))].filter((f) => !existsSync(fontPath(f)));
if (missingFonts.length)
  problems.push(
    `missing font file(s): ${missingFonts.map((f) => FONTS[f]).join(", ")} — run ./fetch_fonts.sh once`
  );
if (problems.length) die("headings.json / setup problems:\n  - " + problems.join("\n  - "));

const browser = await chromium.launch();
let count = 0;
const failures = [];

// One page for the whole run instead of one per screenshot, and every asset
// served from disk through the route below rather than inlined in the HTML.
const page = await browser.newPage({ deviceScaleFactor: 1 });
let pendingHtml = "";
// Assets that failed to load for the image currently being rendered. A throw
// inside a route handler escapes the per-image try/catch below (Playwright
// dispatches it outside that stack) and takes the whole process down, so the
// handler records instead of throwing and the render step checks after goto.
let assetErrors = [];
await page.route(`${ORIGIN}/**`, async (route) => {
  const path = decodeURIComponent(new URL(route.request().url()).pathname);
  try {
    if (path === "/")
      return await route.fulfill({ contentType: "text/html; charset=utf-8", body: pendingHtml });
    if (path.startsWith("/fonts/"))
      return await route.fulfill({
        contentType: "font/ttf",
        body: readFileSync(join(__dirname, "fonts", basename(path))),
      });
    if (path.startsWith("/bg/"))
      return await route.fulfill({
        contentType: "image/png",
        body: readFileSync(join(appDir, basename(path))),
      });
    assetErrors.push(`unexpected request ${path}`);
  } catch (e) {
    // a missing or unreadable asset must fail this image loudly, never render
    // a screenshot that is silently missing its background or its font
    assetErrors.push(`${path}: ${e.message.split("\n")[0]}`);
  }
  await route.abort().catch(() => {});
});

for (const locale of locales) {
  const texts = headings[locale];
  const dir = isRTL(locale) ? "rtl" : "ltr";
  const { faces, stack } = fontAssets(locale);
  for (const device of devices) {
    const d = cfg.devices[device];
    const outDir = join(appDir, "out", locale);
    mkdirSync(outDir, { recursive: true });
    for (let i = 1; i <= shots[device]; i++) {
     try {
      const color = colorFor(i);
      const text = texts[i - 1];
      assetErrors = [];
      await page.setViewportSize({ width: d.width, height: d.height });
      pendingHtml = buildHtml({
        device, bgUrl: `${ORIGIN}/bg/${device}_${i}.png`, text, color, dir, faces, stack,
      });
      // cache-busting query so each image is a fresh navigation on one page
      await page.goto(`${ORIGIN}/?n=${count}`, { waitUntil: "load" });
      if (assetErrors.length) throw new Error(assetErrors.join("; "));
      await page.evaluate(async () => {
        await document.fonts.ready;
        await Promise.all(
          Array.from(document.images).map((img) =>
            img.complete ? null : new Promise((r) => (img.onload = img.onerror = r))
          )
        );
      });
      // auto-fit: default 2 lines; stretch to 3 only when it buys a much bigger font.
      const fit = await page.evaluate(
        ({ base, min, lh, band, maxLines, maxLinesStretch, gain }) => {
          const h = document.getElementById("heading");
          // largest size <= base that fits `cap` lines within the band AND
          // does not overflow horizontally (long unbreakable words)
          const fitsWidth = () => h.scrollWidth <= h.clientWidth + 1;
          const best = (cap) => {
            for (let size = base; size >= min; size -= 2) {
              h.style.fontSize = size + "px";
              const lines = Math.round(h.scrollHeight / (size * lh));
              if (lines <= cap && h.scrollHeight <= band && fitsWidth()) return { size, lines };
            }
            h.style.fontSize = min + "px";
            return { size: min, lines: Math.round(h.scrollHeight / (min * lh)) };
          };
          const two = best(maxLines);
          let chosen = two;
          // only consider more lines if 2 lines forced a shrink below base
          if (two.size < base) {
            const more = best(maxLinesStretch);
            if (more.size >= two.size * gain) chosen = more;
          }
          h.style.fontSize = chosen.size + "px";
          return chosen;
        },
        {
          base: d.sizePx, min: cfg.font.minSizePx, lh: cfg.font.lineHeight, band: d.bandHeightPx,
          maxLines: cfg.font.maxLines, maxLinesStretch: cfg.font.maxLinesStretch, gain: cfg.font.stretchGain,
        }
      );
      await page.screenshot({
        path: join(outDir, `${device}_${i}.png`),
        clip: { x: 0, y: 0, width: d.width, height: d.height },
      });
      count++;
      const flag = fit.size < d.sizePx ? `  (shrunk from ${d.sizePx})` : "";
      // streamed, not buffered to the end — a run that dies partway used to
      // take every fit measurement it had already made down with it
      console.log(`  ${locale}/${device}_${i}: ${fit.size}px · ${fit.lines} lines${flag}`);
     } catch (e) {
      // one bad image must not cost the other 49 locales their render
      failures.push(`${locale}/${device}_${i}: ${e.message.split("\n")[0]}`);
      console.log(`  ${locale}/${device}_${i}: FAILED — ${e.message.split("\n")[0]}`);
     }
    }
  }
}

await browser.close();
console.log(`\nrendered ${count} screenshot(s) → ${join(appDir, "out")}`);

if (failures.length) {
  console.error(`\n${failures.length} screenshot(s) FAILED:`);
  for (const f of failures) console.error(`  - ${f}`);
  console.error("\nthe locales above are incomplete — do not upload this set");
  process.exit(1);
}
