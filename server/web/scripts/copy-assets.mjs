import { mkdir, copyFile, readdir } from 'node:fs/promises';
const source = new URL('../../../kindlevel.koplugin/assets/achievements/', import.meta.url);
const target = new URL('../public/assets/badges/', import.meta.url);
await mkdir(target, { recursive: true });
for (const file of await readdir(source))
  if (file.endsWith('.svg')) await copyFile(new URL(file, source), new URL(file, target));
