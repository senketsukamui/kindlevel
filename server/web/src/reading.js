export const dateKey = (date) => date.toISOString().slice(0, 10);
export const parseDate = (key) => new Date(`${key}T12:00:00Z`);
export function shiftDate(key, days) {
  const date = parseDate(key);
  date.setUTCDate(date.getUTCDate() + days);
  return dateKey(date);
}
export function formatDate(key, options = { month: 'long', day: 'numeric' }) {
  return parseDate(key).toLocaleDateString('en', { timeZone: 'UTC', ...options });
}
export function dailyActivity(activity) {
  const days = new Map();
  for (const item of activity) {
    const day = days.get(item.date) ?? { seconds: 0, pages: 0, books: new Set() };
    day.seconds += item.seconds;
    day.pages += item.pages;
    day.books.add(item.book_id);
    days.set(item.date, day);
  }
  return days;
}
export function streak(days, today) {
  let day = days.get(today)?.seconds > 0 ? today : shiftDate(today, -1);
  let count = 0;
  while ((days.get(day)?.seconds ?? 0) > 0) {
    count++;
    day = shiftDate(day, -1);
  }
  return count;
}
export function calendarWeeks(month) {
  const first = parseDate(`${month}-01`);
  const start = shiftDate(`${month}-01`, -(first.getUTCDay() + 6) % 7);
  const end = new Date(Date.UTC(first.getUTCFullYear(), first.getUTCMonth() + 1, 0, 12));
  const length = Math.ceil((((first.getUTCDay() + 6) % 7) + end.getUTCDate()) / 7) * 7;
  return Array.from({ length: length / 7 }, (_, week) =>
    Array.from({ length: 7 }, (_, day) => shiftDate(start, week * 7 + day)),
  );
}
export function monthShift(month, direction) {
  const date = parseDate(`${month}-01`);
  date.setUTCMonth(date.getUTCMonth() + direction);
  return dateKey(date).slice(0, 7);
}
export function weekRuns(week, activity, books) {
  const result = [];
  const occupied = [];
  for (const book of books) {
    const present = week.map((date) =>
      activity.some((item) => item.date === date && item.book_id === book.id && item.seconds > 0),
    );
    for (let start = 0; start < 7; start++) {
      if (!present[start]) continue;
      let end = start;
      while (end < 6 && present[end + 1]) end++;
      let lane = 0;
      while ((occupied[lane] ?? []).some((run) => start <= run.end && end >= run.start)) lane++;
      (occupied[lane] ??= []).push({ start, end });
      result.push({ book, start, end, lane });
      start = end;
    }
  }
  return result;
}
export function yearWeeks(year) {
  const first = `${year}-01-01`;
  const start = shiftDate(first, -(parseDate(first).getUTCDay() + 6) % 7);
  const last = `${year}-12-31`;
  const length = Math.ceil((Math.round((parseDate(last) - parseDate(start)) / 86400000) + 1) / 7);
  return Array.from({ length }, (_, week) =>
    Array.from({ length: 7 }, (_, day) => shiftDate(start, week * 7 + day)),
  );
}
export function minutes(seconds) {
  return Math.round(seconds / 60);
}
export function duration(seconds) {
  const value = minutes(seconds);
  return value < 60
    ? `${value} min`
    : `${Math.floor(value / 60)}h${value % 60 ? ` ${value % 60}m` : ''}`;
}
