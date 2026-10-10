#!/usr/bin/env python3
"""Generate original sample books; no downloaded or third-party book content."""
from html import escape
from pathlib import Path
import zipfile

ROOT = Path(__file__).resolve().parents[1]
BOOKS = ROOT / "kindlevel.koplugin" / "books"

QUIET = [
    ("A place to begin", [
        "The room was quiet except for a kettle that had not quite decided to boil. On the table lay a notebook, a cup, and a book with a pale cover. Mira moved the notebook aside. There was nothing urgent written in it, and for once she chose to believe that.",
        "She opened the book in the middle, saw a sentence about a garden, and returned to the beginning. Outside, someone was carrying a ladder down the street. Its shadow crossed the window and disappeared. She read a page before the kettle called her back.",
        "When she returned with tea, the page was waiting exactly where she had left it. This small fact pleased her more than it should have. She did not need a plan for the whole afternoon. The next paragraph would do.",
    ]),
    ("The bookmark", [
        "Mira had used the same train ticket as a bookmark for nearly a year. The printed date had faded, but she could still remember the journey: rain on the glass, an empty seat opposite, a town whose station had no clock.",
        "She had missed her stop because of the last chapter. For a week she blamed the author. Later she decided that an extra twenty minutes on a train was a reasonable price for finding out how a story ended.",
        "Now the ticket lived between two pages about a place she had never visited. She wondered whether a bookmark collected something from every book it entered. If it did, this one knew more about the world than she did.",
    ]),
    ("A useful interruption", [
        "At noon a friend knocked on the door with a paper bag full of pears. Neither of them had expected a visit. They put the fruit in a bowl and spoke for a while about ordinary things: a repaired bicycle, a lost glove, a good loaf of bread.",
        "The book remained open on the table. Her friend asked what it was about, and Mira found that she could answer in three different ways. She chose the shortest. A person goes somewhere and comes back changed, she said.",
        "That sounds like most afternoons, her friend said. When the door closed, Mira sat down and reread the last paragraph. It meant something slightly different now.",
    ]),
    ("Another page", [
        "The afternoon grew longer without becoming busy. Light moved from the table to the floor. A small crease in the cover became visible, then vanished when she turned the book toward the window.",
        "She stopped at the end of a chapter. There was no particular achievement to announce. She had spent some time with a story, had noticed a few things, and could remember a sentence she wanted to keep.",
        "She put the train ticket between the pages. Tomorrow would have its own noise. Today, there had been enough room to read.",
    ]),
]

NOTES = [
    ("Try the reading screen", [
        "This is a small original book included with Kindlevel. It gives you something to open immediately, before choosing a folder for your own books. The library and carousel contain actual readable files.",
        "While reading, turn a few pages. Adjust the font size if you wish. KOReader handles the book text, layout, selection, and reading position. When you return to Kindlevel, the progress indicator reflects the position KOReader saved.",
        "To return, open KOReader's main menu and choose Kindlevel in the tools section. That action saves and closes the book through KOReader's normal navigation. Your next visit can continue from the same place.",
    ]),
    ("Make the library yours", [
        "On the home screen, tap Library to see the files in the selected folder. Tap a book to bring it into the reading carousel. The cover or the reading button opens it. Swipe left or right to move between books.",
        "To add your own books, copy readable files to a folder on your Kindle using USB. In Kindlevel, choose Settings, then Choose books folder. Navigate to your folder and long-press its name to select it. Nested folders are included.",
        "The application asks KOReader which files it can open. A book without an embedded cover receives a simple typographic cover. You can return to the sample library from Settings whenever you want.",
    ]),
    ("A few things to try", [
        "Try a long title, a book in a different language, and a PDF alongside an EPUB. Check that the text remains readable and that you can move through the library comfortably. This first version is intended to be tried on the device.",
        "You can leave Kindlevel with the cross in its top right corner. That takes you back to KOReader's normal file browser. Enabling Show home on file browser entry makes the custom home appear when that browser opens.",
        "Everything in this version is local. No account or server is needed. Your observations about spacing, cover sizes, navigation, and the reading transition will guide the next version.",
    ]),
]

LONG_WAY = """The Long Way Home
Kindlevel

1. The turn

At the bridge, Arun took the longer road. The short road passed the shops and the bus stop. The long road followed the river until it reached a row of trees. He had no reason to hurry, which felt like a reason to go that way.

The river carried a single yellow leaf past the bridge. He watched until he lost it among the reflections. A bicycle bell sounded behind him, and he stepped aside. The cyclist raised a hand without slowing.

2. The bench

There was a bench under the largest tree. Someone had repaired one of its boards with wood of a different color. Arun sat on the new board and opened the book he had been carrying all morning.

He read a page, then another. A dog arrived, inspected his shoes, and decided there were more interesting things elsewhere. Its owner apologized. Arun said it was all right, and meant it.

The character in the book was looking for a house. Arun looked up at the houses across the river, each with a different window open. One had a blue curtain moving in the wind.

3. The return

By the time he reached his street, the sky had changed. He could have taken the short road and arrived twenty minutes earlier. Instead he had a new page marked in his book and the memory of a blue curtain.

He put his keys on the table, made tea, and opened the book again. There was still enough light.

About this sample

This is an original plain-text sample, included to let you try a second document format. Kindlevel opens it through KOReader, just like the EPUB samples. Its cover sits beside the text file.
"""


def epub(title, chapters):
    identifier = "kindlevel-" + title.lower().replace(" ", "-")
    filename = BOOKS / (title + ".epub")
    cover = BOOKS / (title + ".cover.png")
    if not cover.exists():
        raise SystemExit("Generate sample cover PNGs with scripts/render_covers.lua in KOReader first.")
    body = "".join(f'<section><h1>{escape(heading)}</h1>' + "".join(f'<p>{escape(p)}</p>' for p in paras) + '</section>'
                   for heading, paras in chapters)
    with zipfile.ZipFile(filename, "w") as archive:
        archive.writestr("mimetype", "application/epub+zip", compress_type=zipfile.ZIP_STORED)
        archive.writestr("META-INF/container.xml", '<?xml version="1.0"?><container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container"><rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles></container>')
        archive.writestr("OEBPS/content.opf", f'''<?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="2.0" unique-identifier="book-id">
<metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:identifier id="book-id">{identifier}</dc:identifier><dc:title>{escape(title)}</dc:title><dc:creator>Kindlevel</dc:creator><dc:language>en</dc:language><meta name="cover" content="cover"/></metadata>
<manifest><item id="text" href="book.xhtml" media-type="application/xhtml+xml"/><item id="cover" href="cover.png" media-type="image/png"/><item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/></manifest>
<spine toc="ncx"><itemref idref="text"/></spine></package>''')
        archive.writestr("OEBPS/book.xhtml", f'<?xml version="1.0" encoding="UTF-8"?><html xmlns="http://www.w3.org/1999/xhtml"><head><title>{escape(title)}</title><style>body{{line-height:1.5}}section{{page-break-before:always}}h1{{font-size:1.6em}}p{{text-indent:1em}}</style></head><body>{body}</body></html>')
        archive.writestr("OEBPS/toc.ncx", f'<?xml version="1.0"?><ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1"><head><meta name="dtb:uid" content="{identifier}"/></head><docTitle><text>{escape(title)}</text></docTitle><navMap><navPoint id="start" playOrder="1"><navLabel><text>Start</text></navLabel><content src="book.xhtml"/></navPoint></navMap></ncx>')
        archive.write(cover, "OEBPS/cover.png")
    print(filename)


if __name__ == "__main__":
    BOOKS.mkdir(parents=True, exist_ok=True)
    epub("A Quiet Beginning", QUIET)
    epub("Notes on Reading", NOTES)
    (BOOKS / "The Long Way Home.txt").write_text(LONG_WAY)
