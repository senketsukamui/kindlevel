<script>
  let { name = 'book', size = 24 } = $props();
  const icons = {
    book: 'book-open',
    shelf: 'book-open',
    calendar: 'calendar',
    badge: 'trophy',
    sun: 'sun',
    arrow: 'arrow-right',
    left: 'arrow-left',
    right: 'arrow-right',
    close: 'close',
    search: 'search',
    check: 'check',
    target: 'trophy',
    clock: 'clock',
    leaf: 'sun',
    device: 'cloud',
    settings: 'settings',
    user: 'user',
    chart: 'chart',
    home: 'home',
    refresh: 'refresh',
    lock: 'lock',
  };
</script>

<span
  class="pixel-icon"
  aria-hidden="true"
  style:width="{size}px"
  style:height="{size}px"
  style:--icon="url('/assets/ui/{icons[name] ?? 'book-open'}.svg')"
></span>
