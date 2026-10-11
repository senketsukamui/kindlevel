<script>
  let { name = 'book', size = 20 } = $props();
  const paths = {
    book: 'M3 4h6c2 0 3 1 3 2 0-1 1-2 3-2h6v15h-6c-2 0-3 1-3 2 0-1-1-2-3-2H3z M12 6v15',
    shelf: 'M4 3v17M8 5v15M12 3v17M16 6l4 13M2 21h20',
    calendar: 'M3 5h18v16H3z M3 10h18 M7 3v4 M17 3v4 M7 14h1 M12 14h1 M17 14h1 M7 18h1 M12 18h1',
    badge: 'M12 3l7 4v9l-7 5-7-5V7z M9 12l2 2 4-4',
    sun: 'M12 2v2M12 20v2M2 12h2M20 12h2M5 5l2 2M17 17l2 2M5 19l2-2M17 7l2-2 M16 12a4 4 0 1 1-8 0 4 4 0 0 1 8 0',
    arrow: 'M5 12h14M14 7l5 5-5 5',
    left: 'M15 5l-7 7 7 7',
    right: 'M9 5l7 7-7 7',
    close: 'M6 6l12 12M6 18L18 6',
    search: 'M15 15l6 6 M17 10a7 7 0 1 1-14 0 7 7 0 0 1 14 0',
    check: 'M5 12l4 4L19 6',
    target: 'M20 12a8 8 0 1 1-16 0 8 8 0 0 1 16 0 M16 12a4 4 0 1 1-8 0 4 4 0 0 1 8 0 M12 12h.01',
    clock: 'M21 12a9 9 0 1 1-18 0 9 9 0 0 1 18 0 M12 7v5l3 2',
    leaf: 'M5 19c-2-8 2-13 14-14 0 12-5 16-14 14z M5 19L15 9',
    device: 'M6 3h12v18H6z M10 18h4',
  };
</script>

<svg
  width={size}
  height={size}
  viewBox="0 0 24 24"
  fill="none"
  stroke="currentColor"
  stroke-width="1.5"
  stroke-linecap="round"
  stroke-linejoin="round"
  aria-hidden="true"><path d={paths[name] || paths.book} /></svg
>
