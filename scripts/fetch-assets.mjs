// Downloads the bundled third-party assets: Red Hat Mono (OFL-1.1) and the Lucide icons the app uses (ISC).
// usage: node scripts/fetch-assets.mjs   (re-run after adding an icon name below)
import { mkdirSync, writeFileSync } from 'node:fs'

const LUCIDE = '1.51.0'
const ICONS = ['wrench', 'settings', 'save-off', 'wifi', 'audio-lines', 'keyboard', 'headphones', 'chevron-down', 'check', 'x',
  'loader', 'copy', 'arrow-right', 'arrow-left', 'arrow-up-right', 'star', 'git-fork', 'folder-open', 'scan-search', 'rotate-ccw',
  'sun-dim', 'sun', 'layout-grid', 'search', 'mic', 'moon', 'rewind', 'play', 'fast-forward', 'volume-x', 'volume-1', 'volume-2', 'sliders-horizontal']
const res = new URL('../Sources/MGF/Resources/', import.meta.url)
const get = async (url) => { const r = await fetch(url); if (!r.ok) throw new Error(`${r.status} ${url}`); return Buffer.from(await r.arrayBuffer()) }
const save = async (path, url) => { const out = new URL(path, res); mkdirSync(new URL('.', out), { recursive: true }); writeFileSync(out, await get(url)) }

await save('Fonts/RedHatMono.ttf', 'https://raw.githubusercontent.com/google/fonts/main/ofl/redhatmono/RedHatMono%5Bwght%5D.ttf')
await save('Fonts/OFL.txt', 'https://raw.githubusercontent.com/google/fonts/main/ofl/redhatmono/OFL.txt')
for (const name of ICONS) await save(`Icons/${name}.svg`, `https://unpkg.com/lucide-static@${LUCIDE}/icons/${name}.svg`)
await save('Icons/LICENSE', `https://unpkg.com/lucide-static@${LUCIDE}/LICENSE`)
console.log(`font + ${ICONS.length} icons saved`)
