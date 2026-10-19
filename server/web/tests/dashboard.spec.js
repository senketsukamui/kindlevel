import { test, expect } from '@playwright/test';
import { readFile } from 'node:fs/promises';

test.beforeAll(async ({ request }) => {
  const status = await (await request.get('/api/v1/auth/status')).json();
  if (!status.initialized) {
    const code = await readFile(process.env.KINDLEVEL_BROWSER_DATA_DIR + '/setup-code', 'utf8');
    const response = await request.post('/api/v1/auth/setup', {
      data: { code, username: 'reader', password: 'test-password-only' },
    });
    expect(response.ok()).toBeTruthy();
  }
});
test.beforeEach(async ({ page }) => {
  const response = await page.request.post('/api/v1/auth/login', {
    data: { username: 'reader', password: 'test-password-only' },
  });
  expect(response.ok()).toBeTruthy();
});

test('desktop dashboard, persistent goals and actual navigation', async ({ page }) => {
  const errors = [];
  page.on('pageerror', (error) => errors.push(error.message));
  await page.setViewportSize({ width: 1440, height: 1100 });
  await page.goto('/');
  await expect(page.getByRole('heading', { name: 'Your reading, at a glance.' })).toBeVisible();
  await expect(page.getByText('Demo reading history')).toBeVisible();
  await expect(page.locator('.current-book')).toBeVisible();
  await page.screenshot({ path: '../../dist/previews/dashboard-home.png', fullPage: true });
  await page.getByRole('button', { name: 'Reading goals', exact: true }).click();
  const dialog = page.getByRole('dialog');
  await expect(dialog).toBeVisible();
  await dialog.getByLabel('Daily reading time').fill('45');
  await dialog.getByLabel('Books this year').fill('20');
  await dialog.getByRole('button', { name: 'Save goals' }).click();
  await expect(dialog).not.toBeVisible();
  await page.reload();
  await expect(page.locator('.today-value')).toContainText('/ 45');
  await page.getByRole('button', { name: 'Your library', exact: true }).click();
  await page.getByRole('textbox', { name: 'Search your library' }).fill('home');
  await expect(page.locator('.library-book')).toHaveCount(1);
  await page.locator('.library-book').click();
  await expect(dialog.getByRole('heading', { name: 'The Long Way Home' })).toBeVisible();
  await page.keyboard.press('Escape');
  await expect(dialog).not.toBeVisible();
  await page.getByRole('button', { name: 'Reading activity', exact: true }).click();
  await page.getByRole('button', { name: 'Year', exact: true }).click();
  await expect(page.locator('.heatmap')).toBeVisible();
  await page.getByRole('button', { name: 'Month', exact: true }).click();
  await page.getByRole('button', { name: 'Previous month', exact: true }).click();
  await page.getByRole('button', { name: 'Today', exact: true }).click();
  await page
    .locator('.calendar-day:not(.outside) .calendar-day-button:not(:disabled)')
    .first()
    .click();
  await expect(dialog).toBeVisible();
  await page.keyboard.press('Escape');
  await page.getByRole('button', { name: /^Achievements/ }).click();
  await page.getByRole('button', { name: 'Locked', exact: true }).click();
  await expect(page.locator('.achievement-card')).toHaveCount(6);
  await page.locator('.achievement-card').first().click();
  await expect(dialog).toBeVisible();
  await page.keyboard.press('Escape');
  await page.getByRole('button', { name: 'Reading home', exact: true }).click();
  await page.getByRole('button', { name: 'Reading goals', exact: true }).click();
  await dialog.getByLabel('Daily reading time').fill('30');
  await dialog.getByLabel('Books this year').fill('12');
  await dialog.getByRole('button', { name: 'Save goals' }).click();
  expect(errors).toEqual([]);
});

test('mobile layout stays inside the screen and goals remain usable', async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto('/');
  await expect(page.locator('.current-book')).toBeVisible();
  expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(390);
  await page.screenshot({ path: '../../dist/previews/dashboard-mobile.png', fullPage: true });
  await page.getByRole('button', { name: 'Reading goals', exact: true }).click();
  await expect(page.getByRole('dialog')).toBeVisible();
  await page.getByRole('button', { name: 'Close details' }).click();
  await page.getByRole('button', { name: 'Your library', exact: true }).click();
  await expect(page.locator('.library-book')).toHaveCount(6);
  expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(390);
});

test('login, pairing, real history, revocation and an empty Kindle', async ({ page }) => {
  const errors = [];
  page.on('pageerror', (error) => errors.push(error.message));
  await page.goto('/');
  await page.getByRole('button', { name: 'Your Kindle', exact: true }).click();
  await page.getByRole('button', { name: 'Pair a Kindle', exact: true }).click();
  const code = await page.locator('.pair-code').textContent();
  await page.screenshot({ path: '../../dist/previews/dashboard-pairing.png', fullPage: true });
  const pair = await page.request.post('/api/v1/devices/pair', {
    data: { code, name: 'Test Paperwhite' },
  });
  expect(pair.ok()).toBeTruthy();
  const credentials = await pair.json();
  const today = new Date().toISOString().slice(0, 10);
  const snapshot = {
    schema: 1,
    sequence: 1,
    captured_at: Math.floor(Date.now() / 1000),
    timezone_offset: 0,
    version: '0.6.0-dev',
    current_book: 'stats:1',
    goals: { daily_minutes: 20, yearly_books: 24 },
    books: [
      {
        id: 'stats:1',
        title: 'Connected test book',
        author: 'Test author',
        format: 'EPUB',
        status: 'reading',
        progress: 42,
        progress_known: true,
        pages: 100,
        color: 'olive',
        description: 'Synced from KOReader.',
      },
    ],
    activity: [
      { id: 'stats:1:' + today, book_id: 'stats:1', date: today, seconds: 1200, pages: 10 },
    ],
    achievements: [
      {
        id: 'first_pages',
        title: 'First Pages',
        description: 'Read for fifteen minutes.',
        icon: 'book',
        progress: 20,
        target: 15,
        unit: 'min',
        xp: 25,
        unlocked: today,
      },
    ],
  };
  const upload = await page.request.post('/api/v1/sync', {
    headers: { Authorization: 'Bearer ' + credentials.token },
    data: snapshot,
  });
  expect(upload.ok()).toBeTruthy();
  await page.getByRole('button', { name: 'Refresh', exact: true }).click();
  await expect(page.getByRole('heading', { name: 'Test Paperwhite', exact: true })).toBeVisible();
  await page.getByRole('button', { name: /View reading history|Viewing this Kindle/ }).click();
  await expect(page.getByText('Kindle reading history', { exact: true })).toBeVisible();
  await expect(page.locator('.current-book-info h2')).toHaveText('Connected test book');
  await page.screenshot({ path: '../../dist/previews/dashboard-connected.png', fullPage: true });
  await page.getByRole('button', { name: 'Your Kindle', exact: true }).click();
  await page.getByRole('button', { name: 'Revoke access', exact: true }).click();
  await page.getByRole('button', { name: 'Confirm revoke', exact: true }).click();
  await expect(page.getByText('Access revoked · reading history retained')).toBeVisible();
  expect(
    (
      await page.request.post('/api/v1/sync', {
        headers: { Authorization: 'Bearer ' + credentials.token },
        data: snapshot,
      })
    ).status(),
  ).toBe(401);
  await page.getByRole('button', { name: /Pair a Kindle|Generate a new code/ }).click();
  const nextCode = await page.locator('.pair-code').textContent();
  const next = await (
    await page.request.post('/api/v1/devices/pair', {
      data: { code: nextCode, name: 'Empty Kindle' },
    })
  ).json();
  const empty = { ...snapshot, books: [], activity: [], achievements: [], current_book: '' };
  expect(
    (
      await page.request.post('/api/v1/sync', {
        headers: { Authorization: 'Bearer ' + next.token },
        data: empty,
      })
    ).ok(),
  ).toBeTruthy();
  await page.getByRole('button', { name: 'Refresh', exact: true }).click();
  const card = page
    .locator('.device-card')
    .filter({ has: page.getByRole('heading', { name: 'Empty Kindle' }) });
  await card.getByRole('button', { name: 'View reading history' }).click();
  await expect(page.getByRole('heading', { name: 'Your next chapter starts here.' })).toBeVisible();
  await page.getByRole('button', { name: 'Sign out', exact: true }).click();
  await expect(page.getByRole('heading', { name: 'Welcome back.' })).toBeVisible();
  await page.getByLabel('Username', { exact: true }).fill('reader');
  await page.getByLabel('Password', { exact: true }).fill('test-password-only');
  await page.getByRole('button', { name: 'Sign in', exact: true }).click();
  await expect(page.getByRole('heading', { name: 'Your reading, at a glance.' })).toBeVisible();
  expect(errors).toEqual([]);
});
