import test from 'node:test';
import assert from 'node:assert/strict';
import {
  calendarWeeks,
  monthShift,
  dailyActivity,
  streak,
  weekRuns,
  yearWeeks,
} from './reading.js';

test('calendar keeps Monday alignment across leap years and six-week months', () => {
  const february = calendarWeeks('2024-02');
  assert.equal(february[0][0], '2024-01-29');
  assert.equal(february.flat().filter((day) => day.startsWith('2024-02')).length, 29);
  const march = calendarWeeks('2026-03');
  assert.equal(march.length, 6);
  assert.equal(march[0][0], '2026-02-23');
  assert.equal(monthShift('2026-12', 1), '2027-01');
  assert.equal(monthShift('2026-01', -1), '2025-12');
  assert.equal(
    yearWeeks(2024)
      .flat()
      .filter((day) => day.startsWith('2024')).length,
    366,
  );
});

test('streak allows an unread today and ends at a gap', () => {
  const days = dailyActivity([
    { date: '2026-10-10', seconds: 60, pages: 2, book_id: 'a' },
    { date: '2026-10-11', seconds: 120, pages: 3, book_id: 'a' },
    { date: '2026-10-11', seconds: 60, pages: 1, book_id: 'b' },
  ]);
  assert.equal(days.get('2026-10-11').seconds, 180);
  assert.equal(days.get('2026-10-11').books.size, 2);
  assert.equal(streak(days, '2026-10-12'), 2);
  assert.equal(streak(days, '2026-10-13'), 0);
});

test('book timeline splits gaps and allocates separate lanes for overlaps', () => {
  const week = calendarWeeks('2026-10')[1];
  const books = [{ id: 'a' }, { id: 'b' }];
  const activity = [
    { date: week[0], book_id: 'a', seconds: 60 },
    { date: week[1], book_id: 'a', seconds: 60 },
    { date: week[3], book_id: 'a', seconds: 60 },
    { date: week[1], book_id: 'b', seconds: 60 },
  ];
  const runs = weekRuns(week, activity, books);
  assert.deepEqual(
    runs.map(({ start, end, lane }) => ({ start, end, lane })),
    [
      { start: 0, end: 1, lane: 0 },
      { start: 3, end: 3, lane: 0 },
      { start: 1, end: 1, lane: 1 },
    ],
  );
});
