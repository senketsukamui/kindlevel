import { mkdir, copyFile, readdir } from 'node:fs/promises';
const source = new URL('../../../kindlevel.koplugin/assets/achievements/', import.meta.url);
const target = new URL('../public/assets/badges/', import.meta.url);
await mkdir(target, { recursive: true });
for (const file of await readdir(source))
  if (file.endsWith('.svg')) await copyFile(new URL(file, source), new URL(file, target));
const shared = new URL('../../../kindlevel.koplugin/assets/', import.meta.url);
const publicAssets = new URL('../public/assets/', import.meta.url);
await mkdir(new URL('ui/', publicAssets), { recursive: true });
for (const file of await readdir(new URL('ui/', shared)))
  if (file.endsWith('.svg'))
    await copyFile(new URL(`ui/${file}`, shared), new URL(`ui/${file}`, publicAssets));
const licenses = new URL('../../../kindlevel.koplugin/licenses/', import.meta.url);
await mkdir(new URL('licenses/', publicAssets), { recursive: true });
for (const name of ['IBM-Plex-Sans-OFL.txt', 'IBM-Plex-Mono-OFL.txt', 'Pixelarticons-MIT.txt'])
  await copyFile(new URL(name, licenses), new URL(`licenses/${name}`, publicAssets));
