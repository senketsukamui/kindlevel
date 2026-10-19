<script>
  import Icon from './Icon.svelte';
  let { book, compact = false } = $props();
</script>

<div class:compact class="cover cover-{book.color ?? 'olive'}" aria-hidden="true">
  <span class="cover-imprint">KINDLEVEL EDITIONS</span>
  <span class="cover-title">{book.title}</span>
  <Icon name="book" size={32} />
  <span class="cover-author">{book.author}</span>
</div>
