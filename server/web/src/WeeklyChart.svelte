<script>
  import { formatDate, minutes } from './reading.js';
  let { dates, days, today, onday, metric = 'seconds' } = $props();
  let values = $derived(
    dates.map((date) =>
      date > today
        ? 0
        : metric === 'pages'
          ? (days.get(date)?.pages ?? 0)
          : minutes(days.get(date)?.seconds ?? 0),
    ),
  );
  let maximum = $derived(
    Math.max(
      metric === 'pages' ? 30 : 60,
      Math.ceil(Math.max(0, ...values) / (metric === 'pages' ? 30 : 60)) *
        (metric === 'pages' ? 30 : 60),
    ),
  );
</script>

<div
  class="weekly-chart"
  aria-label={metric === 'pages' ? 'Pages read each day' : 'Reading minutes each day'}
>
  <div class="chart-plot">
    {#each [3, 2, 1, 0] as tick}
      <div class="chart-rule" style:bottom="{(tick / 3) * 100}%">
        <span>{Math.round((maximum * tick) / 3)}{metric === 'seconds' ? 'm' : ''}</span>
      </div>
    {/each}
    <div class="chart-columns">
      {#each dates as date, i}
        <button
          class:today-column={date === today}
          disabled={date > today}
          class:future-column={date > today}
          onclick={() => onday(date)}
          aria-label="{formatDate(date)}: {values[i]} {metric === 'pages' ? 'pages' : 'minutes'}"
        >
          <span class="chart-bar" style:height="{(values[i] / maximum) * 100}%">
            {#if date <= today}<span class="chart-value">{values[i]}</span>{/if}
          </span>
          <span class="chart-date"
            >{formatDate(date, { weekday: 'short' }).slice(0, 1)}{Number(date.slice(-2))}</span
          >
        </button>
      {/each}
    </div>
  </div>
</div>
