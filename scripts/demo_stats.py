"""Deterministic preview history using KOReader's current statistics schema.

The page_stat view is adapted from KOReader's AGPL-3.0 statistics plugin.
This module only writes the disposable preview database supplied by its caller.
"""
import datetime as dt
from pathlib import Path
import sqlite3
import time

SCHEMA = """
CREATE TABLE book (
 id INTEGER PRIMARY KEY, title TEXT, authors TEXT, notes INTEGER, last_open INTEGER,
 highlights INTEGER, pages INTEGER, series TEXT, language TEXT, md5 TEXT,
 total_read_time INTEGER, total_read_pages INTEGER
);
CREATE TABLE page_stat_data (
 id_book INTEGER, page INTEGER NOT NULL DEFAULT 0, start_time INTEGER NOT NULL DEFAULT 0,
 duration INTEGER NOT NULL DEFAULT 0, total_pages INTEGER NOT NULL DEFAULT 0,
 UNIQUE(id_book,page,start_time), FOREIGN KEY(id_book) REFERENCES book(id)
);
CREATE INDEX page_stat_data_start_time ON page_stat_data(start_time);
CREATE TABLE numbers (number INTEGER PRIMARY KEY);
CREATE VIEW page_stat AS
 SELECT id_book, first_page + idx - 1 AS page, start_time,
        duration / (last_page - first_page + 1) AS duration
 FROM (
  SELECT id_book, page, total_pages, pages, start_time, duration,
         ((page - 1) * pages) / total_pages + 1 AS first_page,
         max(((page - 1) * pages) / total_pages + 1, (page * pages) / total_pages) AS last_page, idx
  FROM page_stat_data JOIN book ON book.id = id_book
  JOIN (SELECT number AS idx FROM numbers) AS n ON idx <= (last_page-first_page+1)
 );
PRAGMA user_version=20221111;
"""


def make_demo(path: Path):
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists():
        path.unlink()
    with sqlite3.connect(path) as conn:
        conn.executescript(SCHEMA)
        conn.executemany("INSERT INTO numbers VALUES (?)", ((i,) for i in range(1, 1001)))
        titles = ("A Quiet Beginning", "Notes on Reading", "The Long Way Home")
        for i, title in enumerate(titles, 1):
            conn.execute("INSERT INTO book VALUES (?,?,?,?,?,?,?,?,?,?,?,?)",
                         (i, title, "Kindlevel", i+1, 0, i*7, 180+i*30, None, "en", f"demo-{i}", 0, 0))
        today = dt.date.today()
        start = dt.date(today.year, 1, 1)
        count = (today-start).days
        for offset in range(count+1):
            day = start + dt.timedelta(days=offset)
            # Include longer breaks as well as short gaps, for the return views.
            if (offset % 11 in (3, 4) or 20 <= offset % 67 <= 24) and (today-day).days > 5:
                continue
            book = min(3, (day.day-1)//12+1)
            pages = 9 + offset*17 % 39
            for i in range(pages):
                session = 0 if i < pages//2 else 1
                local = dt.datetime.combine(day, dt.time(7, 30) if session == 0 else dt.time(20, 10))
                timestamp = int(time.mktime(local.timetuple())) + (i if session == 0 else i-pages//2)*100
                duration = 55 + (offset+i*7) % 55
                active_book = min(3, book+1) if session == 1 and day.day in (11, 12, 23, 24) else book
                total_pages = 180 + active_book*30
                # Advance through each monthly reading period; overlaps start the next book.
                start_page = ((day.day-1) % 12)*total_pages//12 if active_book == book else 0
                conn.execute("INSERT INTO page_stat_data VALUES (?,?,?,?,?)",
                             (active_book, min(total_pages, start_page+i+1), timestamp, duration, total_pages))
        conn.execute("""UPDATE book SET
            last_open=(SELECT max(start_time) FROM page_stat_data WHERE id_book=book.id),
            total_read_time=(SELECT sum(duration) FROM page_stat_data WHERE id_book=book.id),
            total_read_pages=(SELECT count(DISTINCT page) FROM page_stat_data WHERE id_book=book.id)""")
