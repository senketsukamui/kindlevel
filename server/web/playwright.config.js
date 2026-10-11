import { defineConfig } from '@playwright/test';
import path from 'node:path';
import { mkdirSync, mkdtempSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
const root = fileURLToPath(new URL('../../', import.meta.url));
mkdirSync(path.join(root,'.cache'), {recursive:true});
const data = process.env.KINDLEVEL_BROWSER_DATA_DIR || mkdtempSync(path.join(root,'.cache/dashboard-browser-server-'));
process.env.KINDLEVEL_BROWSER_DATA_DIR = data;
export default defineConfig({
  testDir: './tests',
  workers: 1,
  use: { baseURL: 'http://127.0.0.1:8083', headless: true },
  webServer: {
    command: 'go run .',
    cwd: '..',
    url: 'http://127.0.0.1:8083/healthz',
    timeout: 60000,
    env: {
      KINDLEVEL_ADDR: '127.0.0.1:8083',
      KINDLEVEL_DATA_DIR: data,
      KINDLEVEL_PUBLIC_URL: '',
      GOMODCACHE: path.join(root, '.cache/go-mod'),
      GOCACHE: path.join(root, '.cache/go-build'),
    },
  },
  outputDir: '../../.cache/dashboard-browser',
});
