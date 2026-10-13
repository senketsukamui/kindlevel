<script>
  let { book, compact = false } = $props();
</script>

<div class:compact class="cover cover-{book.color}" aria-hidden="true">
  <span class="cover-imprint">KINDLEVEL EDITIONS</span>
  <div class="cover-title">{book.title}</div>
  <div class="cover-ornament"><span></span><span></span><span></span></div>
  <span class="cover-author">{book.author}</span>
</div>
