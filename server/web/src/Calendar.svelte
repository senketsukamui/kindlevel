<script>
  import Icon from './Icon.svelte';
  import { calendarWeeks, monthShift, formatDate, weekRuns, minutes } from './reading.js';
  let { month = $bindable(), books, activity, days, today, onday, onbook } = $props();
  let weeks = $derived(calendarWeeks(month));
  const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
</script>

<div class="calendar-toolbar">
  <div>
    <h2>{formatDate(`${month}-01`, { month: 'long', year: 'numeric' })}</h2>
  </div>
  <div class="month-controls">
    <button
      class="icon-button"
      aria-label="Previous month"
      onclick={() => (month = monthShift(month, -1))}><Icon name="left" size={17} /></button
    ><button class="quiet-button" onclick={() => (month = today.slice(0, 7))}>Today</button><button
      class="icon-button"
      aria-label="Next month"
      onclick={() => (month = monthShift(month, 1))}><Icon name="right" size={17} /></button
    >
  </div>
</div>
<div class="calendar-weekdays">
  {#each weekdays as day}<span>{day}</span>{/each}
</div>
<div class="book-calendar">
  {#each weeks as week}
    {@const runs = weekRuns(week, activity, books)}
    {@const lanes = Math.max(2, ...runs.map((run) => run.lane + 1))}
    <div class="calendar-week" style:min-height="{52 + lanes * 22}px">
      {#each week as date}
        {@const record = days.get(date)}
        <div
          class="calendar-day"
          class:outside={!date.startsWith(month)}
          class:is-today={date === today}
          class:future={date > today}
        >
          <button
            class="calendar-day-button"
            disabled={date > today}
            onclick={() => onday(date)}
            aria-label="{formatDate(date)}: {minutes(record?.seconds ?? 0)} minutes read"
          >
            <span class="day-number">{Number(date.slice(-2))}</span>
          </button>
          <span class="day-activity"
            ><span class="day-bars"
              >{#each activity.filter((item) => item.date === date) as item}<i
                  style:height="{Math.min(12, Math.max(2, item.seconds / 300))}px"
                  class="tone-{books.find((book) => book.id === item.book_id)?.color ?? 'olive'}"
                ></i>{/each}</span
            >{#if record?.seconds}<span
                >{minutes(record.seconds)}<span class="minute-label"> min</span></span
              >{/if}</span
          >
        </div>
      {/each}
      <div class="calendar-runs">
        {#each runs as run}
          <button
            class="book-run tone-{run.book.color}"
            style:grid-column="{run.start + 1} / {run.end + 2}"
            style:grid-row={run.lane + 1}
            onclick={() => onbook(run.book)}
            title={run.book.title}>{run.book.title}</button
          >
        {/each}
      </div>
    </div>
  {/each}
</div>
<div class="calendar-legend">
  <span><i></i> Reading time</span><span
    >Select a date for its journal · Ribbons open book details</span
  >
</div>
