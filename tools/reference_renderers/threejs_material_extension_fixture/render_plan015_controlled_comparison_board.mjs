import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

import puppeteer from 'puppeteer';

import { outputRoot } from './plan015_controlled_comparison_contract.mjs';

const systemChromePath =
  '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
const executablePath =
  process.env.PUPPETEER_EXECUTABLE_PATH ??
  (fs.existsSync(systemChromePath) ? systemChromePath : undefined);
const profilePath = fs.mkdtempSync(
  path.join(os.tmpdir(), 'plan015-controlled-board-'),
);
const rows = [
  ['directOnly', 'Direct only — analytic directional light'],
  ['iblOnly', 'IBL only — generated HDR environment'],
  ['combined', 'Combined — directional light + IBL'],
];

const imageData = Object.fromEntries(
  rows.flatMap(([pass]) =>
    ['ios_simulator', 'threejs'].map((renderer) => {
      const bytes = fs.readFileSync(
        path.join(outputRoot, renderer, `clearcoat_car_paint_${pass}.png`),
      );
      return [`${renderer}_${pass}`, `data:image/png;base64,${bytes.toString('base64')}`];
    }),
  ),
);

let browser;
try {
  browser = await puppeteer.launch({
    headless: true,
    executablePath,
    userDataDir: profilePath,
    args: ['--disable-background-networking', '--disable-gpu-sandbox'],
  });
  const page = await browser.newPage();
  await page.setViewport({ width: 1180, height: 1880, deviceScaleFactor: 1 });
  await page.setContent(boardHtml(imageData, rows), { waitUntil: 'load' });
  await page.screenshot({
    path: path.join(outputRoot, 'clearcoat_car_paint_comparison_board.png'),
  });
  console.log('Plan 015 controlled ClearCoatCarPaint comparison board OK');
} finally {
  if (browser != null) await browser.close();
  fs.rmSync(profilePath, { recursive: true, force: true });
}

function boardHtml(images, boardRows) {
  const rowHtml = boardRows
    .map(
      ([pass, label]) => `
        <section>
          <h2>${label}</h2>
          <div class="pair">
            ${cell(images[`ios_simulator_${pass}`], 'flutter_scene · iOS Simulator')}
            ${cell(images[`threejs_${pass}`], 'Three.js r167')}
          </div>
        </section>`,
    )
    .join('');
  return `<!doctype html>
    <meta charset="utf-8">
    <style>
      * { box-sizing: border-box; }
      body { margin: 0; padding: 34px 40px; background: #09090d; color: #f5f4f8;
        font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; }
      h1 { margin: 0 0 8px; font-size: 34px; }
      .subtitle { margin: 0 0 24px; color: #aaa6b4; font-size: 18px; }
      section { margin-top: 22px; }
      h2 { margin: 0 0 10px; font-size: 20px; color: #d9d6e0; }
      .pair { display: grid; grid-template-columns: 1fr 1fr; gap: 20px; }
      figure { margin: 0; border: 1px solid #2c2934; border-radius: 16px;
        overflow: hidden; background: #121118; }
      .crop { height: 470px; background-repeat: no-repeat; background-size: 760px auto;
        background-position: center 53%; }
      figcaption { padding: 13px 16px; font-size: 17px; font-weight: 650;
        border-top: 1px solid #2c2934; }
    </style>
    <h1>Plan 015 · Controlled clearcoat comparison</h1>
    <p class="subtitle">Same model, canonical camera, HDR bytes, directional light, exposure, PBR Neutral, and sRGB output.</p>
    ${rowHtml}`;
}

function cell(dataUrl, label) {
  return `<figure><div class="crop" style="background-image:url('${dataUrl}')"></div><figcaption>${label}</figcaption></figure>`;
}
