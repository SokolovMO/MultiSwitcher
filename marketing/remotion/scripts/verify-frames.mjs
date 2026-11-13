import path from "node:path";
import fs from "node:fs/promises";
import { bundle } from "@remotion/bundler";
import {
  openBrowser,
  selectComposition,
  renderStill,
} from "@remotion/renderer";
const root = path.resolve(import.meta.dirname, "..");
const browserExecutable = process.env.REMOTION_BROWSER_EXECUTABLE;
const serveUrl = await bundle({
  entryPoint: path.join(root, "src/index.ts"),
  outDir: path.join(root, "work/bundle"),
});
const browser = await openBrowser("chrome", { browserExecutable });
try {
  const composition = await selectComposition({
    serveUrl,
    id: "multiswitcher",
    puppeteerInstance: browser,
  });
  await fs.mkdir(path.join(root, "work/frames"), { recursive: true });
  for (const frame of [42, 86, 100, 168, 245, 375, 450, 530]) {
    await renderStill({
      serveUrl,
      composition,
      puppeteerInstance: browser,
      frame,
      output: path.join(root, `work/frames/frame-${frame}.png`),
    });
    console.log(`frame ${frame} rendered`);
  }
} finally {
  await browser.close({ silent: true });
}
