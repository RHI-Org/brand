// Build-time prerendering: injects server-rendered HTML into the SPA shell
// so crawlers, archivers, and script-blocked visitors see the real content.
// Runs after `vite build` (client) and `vite build --ssr` (dist-ssr).
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const MARKER = '<div id="root"></div>';
const ROUTES = ['/'];

const { render } = await import(
  pathToFileURL(resolve(root, 'dist-ssr/prerender-entry.js')).href
);

const template = readFileSync(resolve(root, 'dist/index.html'), 'utf8');
if (!template.includes(MARKER)) {
  console.error(`prerender: marker ${MARKER} not found in dist/index.html`);
  process.exit(1);
}

// framer-motion serializes entrance-animation `initial` states as inline
// styles (opacity:0 + translateY), which would visually hide the prerendered
// text for script-blocked visitors. Neutralize them in the static HTML only.
// This cannot affect the browser experience: main.tsx mounts with createRoot,
// which discards this server markup and re-renders from scratch, restoring
// the exact animation behavior.
function neutralizeEntranceStyles(html) {
  return html.replaceAll(
    /opacity:0;transform:translateY\([^)]*\)/g,
    'opacity:1',
  );
}

for (const route of ROUTES) {
  const html = neutralizeEntranceStyles(render(route));
  if (!html || html.length < 500) {
    console.error(
      `prerender: rendered HTML for "${route}" is suspiciously small (${html ? html.length : 0} chars)`,
    );
    process.exit(1);
  }
  const out = template.replace(MARKER, `<div id="root">${html}</div>`);
  const file =
    route === '/'
      ? resolve(root, 'dist/index.html')
      : resolve(root, 'dist', route.replace(/^\//, ''), 'index.html');
  mkdirSync(dirname(file), { recursive: true });
  writeFileSync(file, out);
  console.log(`prerender: wrote ${file} (${html.length} chars of rendered HTML)`);
}
