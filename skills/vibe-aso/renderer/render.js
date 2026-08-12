import { chromium } from "playwright";
import { readFileSync, existsSync, mkdirSync } from "fs";
import { fileURLToPath } from "url";
import { dirname, join, resolve } from "path";

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
const BASE_STACK = ["DM Sans", "Noto Sans"];
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

const fontCache = {};
const fontDataUrl = (family) => {
  const path = join(__dirname, "fonts", FONTS[family]);
  if (!existsSync(path)) {
    console.error(
      `missing font: fonts/${FONTS[family]} — run ./fetch_fonts.sh once to download the font set`
    );
    process.exit(1);
  }
  return (fontCache[family] ??=
    "data:font/ttf;base64," + readFileSync(path).toString("base64"));
};

function fontAssets(locale) {
  // DM Sans first (Latin/brand), then the locale's script font (so it wins over
  // Noto Sans for shared scripts like Cyrillic), then Noto Sans as final safety net.
  const families = LOCALE_FONT[locale]
    ? ["DM Sans", LOCALE_FONT[locale], "Noto Sans"]
    : [...BASE_STACK];
  const faces = families
    .map(
      (f) =>
        `@font-face { font-family: "${f}"; src: url("${fontDataUrl(f)}") format("truetype"); font-weight: 100 900; }`
    )
    .join("\n  ");
  const stack = families.map((f) => `"${f}"`).join(", ");
  return { faces, stack };
}

const bgCache = {};
const bgDataUrl = (p) =>
  (bgCache[p] ??= "data:image/png;base64," + readFileSync(p).toString("base64"));

// CLI: node render.js <project-dir> [device] [locale]
//   <project-dir> holds iphone_1..N.png / ipad_1..N.png, app.json, headings.json
const projectArg = process.argv[2];
const onlyDevice = process.argv[3];
const onlyLocale = process.argv[4];
if (!projectArg) {
  console.error("usage: node render.js <project-dir> [device] [locale]");
  process.exit(1);
}

const appDir = resolve(projectArg);
const headings = JSON.parse(readFileSync(join(appDir, "headings.json"), "utf8"));
// per-app settings: { colors: { odd, even } }. odd = screenshots 1,3,5… / even = 2,4,6…
const appCfg = JSON.parse(readFileSync(join(appDir, "app.json"), "utf8"));
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
const devices = (onlyDevice ? [onlyDevice] : Object.keys(cfg.devices)).filter((dev) =>
  existsSync(join(appDir, `${dev}_1.png`))
);
const locales = onlyLocale ? [onlyLocale] : Object.keys(headings);

const browser = await chromium.launch();
let count = 0;
const fitLog = [];

for (const locale of locales) {
  const texts = headings[locale];
  const dir = isRTL(locale) ? "rtl" : "ltr";
  const { faces, stack } = fontAssets(locale);
  for (const device of devices) {
    const d = cfg.devices[device];
    const outDir = join(appDir, "out", locale);
    mkdirSync(outDir, { recursive: true });
    for (let i = 1; i <= shotCount(device); i++) {
      const bgPath = join(appDir, `${device}_${i}.png`);
      const color = colorFor(i);
      const text = texts[i - 1] ?? "";
      const page = await browser.newPage({
        viewport: { width: d.width, height: d.height },
        deviceScaleFactor: 1,
      });
      await page.setContent(
        buildHtml({ device, bgUrl: bgDataUrl(bgPath), text, color, dir, faces, stack }),
        { waitUntil: "load" }
      );
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
      await page.close();
      count++;
      const flag = fit.size < d.sizePx ? `  (shrunk from ${d.sizePx})` : "";
      fitLog.push(`  ${locale}/${device}_${i}: ${fit.size}px · ${fit.lines} lines${flag}`);
    }
  }
}

await browser.close();
console.log(`rendered ${count} screenshots → ${join(appDir, "out")}\n`);
console.log(fitLog.join("\n"));
