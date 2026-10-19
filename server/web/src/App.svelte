<script>
  import { onMount } from 'svelte';
  import Icon from './Icon.svelte';
  import Auth from './Auth.svelte';
  import Devices from './Devices.svelte';
  import Cover from './Cover.svelte';
  import Calendar from './Calendar.svelte';
  import WeeklyChart from './WeeklyChart.svelte';
  import {
    dailyActivity,
    streak,
    duration,
    minutes,
    formatDate,
    shiftDate,
    yearWeeks,
    parseDate,
  } from './reading.js';

  let data = $state(null);
  let auth = $state(null);
  let selectedDevice = $state('');
  let error = $state('');
  let loading = $state(true);
  let page = $state('home');
  let activityView = $state('week');
  let weekOffset = $state(0);
  let query = $state('');
  let bookFilter = $state('all');
  let badgeFilter = $state('all');
  let month = $state('');
  let selectedBook = $state(null);
  let selectedDay = $state('');
  let selectedBadge = $state(null);
  let goalOpen = $state(false);
  let dailyGoal = $state(30);
  let yearlyGoal = $state(12);
  let saving = $state(false);
  let goalError = $state('');
  let message = $state('');
  let dialog = $state();
  const tabs = [
    { id: 'home', label: 'Reading home', short: 'Home', mobile: 'Home', icon: 'home' },
    { id: 'library', label: 'Your library', short: 'Library', mobile: 'Library', icon: 'book' },
    {
      id: 'activity',
      label: 'Reading activity',
      short: 'Activity',
      mobile: 'Activity',
      icon: 'chart',
    },
    {
      id: 'achievements',
      label: 'Achievements',
      short: 'Achievements',
      mobile: 'Badges',
      icon: 'badge',
    },
    { id: 'devices', label: 'Your Kindle', icon: 'device' },
  ];
  const titles = {
    devices: ['Your Kindle', 'A bridge between your reading spaces.'],
    home: ['Your reading, at a glance.', ''],
    library: ['Your library', 'Stories on your device, in one quiet place.'],
    activity: ['Time between the pages', 'Every small reading moment counts.'],
    achievements: ['Little milestones', 'A collection of the moments that made you a reader.'],
  };
  let days = $derived(dailyActivity(data?.activity ?? []));
  let today = $derived(days.get(data?.today) ?? { seconds: 0, pages: 0 });
  let currentBook = $derived(
    data?.books.find((book) => book.id === data?.current_book) ??
      data?.books.find((book) => book.status === 'reading') ??
      data?.books[0],
  );
  let currentStreak = $derived(data ? streak(days, data.today) : 0);
  let sourceDevice = $derived(data?.devices.find((device) => device.id === data.source_device));
  let year = $derived(Number(data?.today.slice(0, 4) ?? new Date().getFullYear()));
  let yearActivity = $derived(
    data?.activity.filter((item) => item.date.startsWith(String(year))) ?? [],
  );
  let totalSeconds = $derived(yearActivity.reduce((sum, item) => sum + item.seconds, 0));
  let totalPages = $derived(yearActivity.reduce((sum, item) => sum + item.pages, 0));
  let finished = $derived(
    data?.books.filter((book) => book.finished?.startsWith(String(year))).length ?? 0,
  );
  let earned = $derived(data?.achievements.filter((badge) => badge.unlocked).length ?? 0);
  let filteredBooks = $derived(
    data?.books.filter(
      (book) =>
        (bookFilter === 'all' || book.status === bookFilter) &&
        `${book.title} ${book.author} ${book.format}`.toLowerCase().includes(query.toLowerCase()),
    ) ?? [],
  );
  let filteredBadges = $derived(
    data?.achievements.filter(
      (badge) =>
        badgeFilter === 'all' || (badgeFilter === 'earned' ? badge.unlocked : !badge.unlocked),
    ) ?? [],
  );
  let latestBadge = $derived(
    data?.achievements
      .filter((item) => item.unlocked)
      .sort((a, b) => b.unlocked.localeCompare(a.unlocked))[0],
  );
  let featuredBadge = $derived(
    data?.achievements
      .filter((badge) => !badge.unlocked)
      .sort((a, b) => b.progress / Math.max(1, b.target) - a.progress / Math.max(1, a.target))[0] ??
      latestBadge,
  );
  let weekStart = $derived(
    data
      ? shiftDate(data.today, -((parseDate(data.today).getUTCDay() + 6) % 7) + weekOffset * 7)
      : '2026-01-01',
  );
  let weekDates = $derived(Array.from({ length: 7 }, (_, i) => shiftDate(weekStart, i)));
  let weekLabel = $derived(
    `${formatDate(weekStart, { day: 'numeric', month: 'short' })} – ${formatDate(weekDates[6], { day: 'numeric', month: 'short', year: 'numeric' })}`,
  );
  let weekSeconds = $derived(weekDates.reduce((n, d) => n + (days.get(d)?.seconds ?? 0), 0));
  let weekPages = $derived(weekDates.reduce((n, d) => n + (days.get(d)?.pages ?? 0), 0));
  let weekActive = $derived(
    weekDates.filter((d) => d <= data?.today && (days.get(d)?.seconds ?? 0) > 0).length,
  );
  let weekElapsed = $derived(weekDates.filter((d) => d <= data?.today).length);
  let yearMonths = $derived(
    Array.from({ length: 12 }, (_, i) => ({
      name: new Date(Date.UTC(year, i, 1)).toLocaleDateString('en', {
        month: 'short',
        timeZone: 'UTC',
      }),
      column:
        yearWeeks(year).findIndex((week) =>
          week.includes(`${year}-${String(i + 1).padStart(2, '0')}-01`),
        ) + 1,
    })),
  );
  function badgeSource(icon) {
    const match = {
      book: 'book-open',
      pages: 'book-open',
      calendar: 'calendar',
      clock: 'clock',
      moon: 'moon',
      sun: 'sun',
      spark: 'sun',
      stack: 'book-open',
    }[icon];
    return match ? `/assets/ui/${match}.svg` : `/assets/badges/${icon}.svg`;
  }
  let bookHistory = $derived(
    data?.activity.filter((item) => item.book_id === selectedBook?.id) ?? [],
  );
  let dayRecord = $derived(days.get(selectedDay));
  let modalOpen = $derived(Boolean(selectedBook || selectedDay || selectedBadge || goalOpen));

  async function load() {
    loading = true;
    error = '';
    try {
      const status = await fetch('/api/v1/auth/status');
      if (!status.ok) throw new Error('Could not connect to your reading server.');
      auth = await status.json();
      if (!auth.authenticated) {
        data = null;
        closeDialog();
        return;
      }
      const response = await fetch(
        `/api/v1/dashboard${selectedDevice ? `?device=${encodeURIComponent(selectedDevice)}` : ''}`,
      );
      if (response.status === 401) {
        auth.authenticated = false;
        data = null;
        return;
      }
      if (!response.ok) throw new Error('Your reading home could not load. Please try again.');
      data = await response.json();
      month ||= data.today.slice(0, 7);
    } catch (e) {
      error = e.message;
    } finally {
      loading = false;
    }
  }
  async function logout() {
    const response = await fetch('/api/v1/auth/logout', { method: 'POST' });
    if (!response.ok) {
      error = 'Could not sign out. Please try again.';
      return;
    }
    data = null;
    auth.authenticated = false;
    selectedDevice = '';
    closeDialog();
  }
  async function viewDevice(id) {
    selectedDevice = id;
    navigate('home');
    await load();
  }
  onMount(() => {
    load();
    const interval = setInterval(() => {
      if (auth?.authenticated && !modalOpen) load();
    }, 30000);
    return () => clearInterval(interval);
  });
  $effect(() => {
    if (modalOpen) dialog?.showModal();
    else dialog?.close();
  });
  function closeDialog() {
    selectedBook = null;
    selectedDay = '';
    selectedBadge = null;
    goalOpen = false;
  }
  function navigate(id) {
    closeDialog();
    page = id;
    if (id === 'home') weekOffset = 0;
    message = '';
    window.scrollTo({ top: 0, behavior: 'instant' });
  }
  function editGoals() {
    dailyGoal = data.goals.daily_minutes;
    yearlyGoal = data.goals.yearly_books;
    goalError = '';
    goalOpen = true;
  }
  async function saveGoals(event) {
    event.preventDefault();
    saving = true;
    goalError = '';
    try {
      const response = await fetch('/api/v1/goals', {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          daily_minutes: Number(dailyGoal),
          yearly_books: Number(yearlyGoal),
        }),
      });
      const result = await response.json();
      if (!response.ok) throw new Error(result.error ?? 'Could not save your goals.');
      data.goals = result;
      closeDialog();
      message = 'Your reading goals have been saved.';
    } catch (e) {
      goalError = e.message;
    } finally {
      saving = false;
    }
  }
  function level(date) {
    const value = minutes(days.get(date)?.seconds ?? 0);
    return value === 0 ? 0 : value < 20 ? 1 : value < 40 ? 2 : value < 60 ? 3 : 4;
  }
</script>

<svelte:head
  ><title
    >Kindlevel · {page === 'settings'
      ? 'Your reading space'
      : tabs.find((tab) => tab.id === page)?.label}</title
  ></svelte:head
>

{#snippet goalStrip()}
  <div class="goal-strip">
    <button onclick={editGoals} aria-label="Reading goals" class="goal-metric today-value"
      ><Icon name="clock" size={28} /><span
        ><strong>{minutes(today.seconds)} / {data.goals.daily_minutes}</strong><small
          >minutes today</small
        ></span
      ></button
    >
    <div class="goal-metric">
      <Icon name="sun" size={28} /><span
        ><strong>{currentStreak}</strong><small>day streak</small></span
      >
    </div>
    <div class="mobile-daily-track progress-track">
      <span
        style:width="{Math.min(
          100,
          (today.seconds / Math.max(1, data.goals.daily_minutes * 60)) * 100,
        )}%"
      ></span>
    </div>
    <button onclick={editGoals} class="goal-metric"
      ><Icon name="book" size={28} /><span
        ><strong
          >{finished}{data.goals.yearly_books > 0 ? ` / ${data.goals.yearly_books}` : ''}</strong
        ><small>books this year</small></span
      ></button
    >
  </div>
{/snippet}

{#if auth && !auth.authenticated}
  <Auth initialized={auth.initialized} onauthenticated={load} />
{:else}
  <div class="app-shell">
    <header class="site-header">
      <a
        class="brand"
        href="#home"
        onclick={() => navigate('home')}
        aria-label="Kindlevel reading home"><Icon name="book" size={28} /><span>kindlevel</span></a
      >
      <nav class="desktop-nav" aria-label="Main navigation">
        {#each tabs.filter((tab) => tab.id !== 'devices') as tab}<button
            class:active={page === tab.id}
            aria-current={page === tab.id ? 'page' : undefined}
            aria-label={tab.label}
            onclick={() => navigate(tab.id)}>{tab.short}</button
          >{/each}
      </nav>
      <div class="header-tools">
        <button
          class="connection-status"
          aria-label="Your Kindle"
          onclick={() => navigate('devices')}
          ><Icon name="device" size={20} /><span
            >{data?.source_device
              ? sourceDevice?.revoked
                ? 'Kindle · Disconnected'
                : 'Kindle · Synced'
              : data?.demo
                ? 'Demo · Your Kindle'
                : 'Connect Kindle'}</span
          ></button
        >
        <button
          class="icon-button"
          class:active={page === 'settings'}
          aria-label="Your reading space settings"
          onclick={() => navigate('settings')}><Icon name="user" size={24} /></button
        >
      </div>
    </header>
    <main id="main-content" class:home-page={page === 'home'}>
      {#if loading && !data}<div class="state-panel" role="status">
          <Icon name="book" size={64} />
          <h1>Gathering your reading moments…</h1>
          <p>Loading history from your server.</p>
        </div>
      {:else if error}<div class="state-panel" role="alert">
          <Icon name="device" size={64} />
          <h1>A little pause.</h1>
          <p>{error}</p>
          <button class="primary-button" onclick={load}>Try again</button>
        </div>
      {:else if data}
        {#if message}<div class="saved-message" role="status">
            <Icon name="check" size={20} />{message}<button
              class="icon-button"
              aria-label="Dismiss message"
              onclick={() => (message = '')}><Icon name="close" size={16} /></button
            >
          </div>{/if}
        <div class="page-heading ledger-heading">
          <div>
            <h1>
              {#if page === 'home'}<span class="desktop-home-title">Your reading, at a glance.</span
                ><span class="mobile-home-title">A little reading,<br />a little world.</span
                >{:else}{page === 'settings' ? 'Your reading space' : titles[page][0]}{/if}
            </h1>
            <p>
              {page === 'home'
                ? formatDate(data.today, {
                    weekday: 'long',
                    day: 'numeric',
                    month: 'long',
                    year: 'numeric',
                  })
                : page === 'settings'
                  ? 'The small practical things.'
                  : titles[page][1]}
            </p>
          </div>
        </div>
        {#if page === 'home'}
          {@render goalStrip()}
          {#if currentBook}<section class="current-book">
              <div class="current-book-cover"><Cover book={currentBook} /></div>
              <div class="current-book-info">
                <span class="eyebrow">CURRENTLY READING</span>
                <h2>{currentBook.title}</h2>
                <p class="book-author">{currentBook.author}</p>
                <div class="book-progress-label">
                  <span
                    >{currentBook.progress_known
                      ? `${currentBook.progress}% read`
                      : 'Reading on your Kindle'}{currentBook.progress_known && currentBook.pages
                      ? ` · ${Math.round((currentBook.pages * currentBook.progress) / 100)} / ${currentBook.pages} pages`
                      : ''}</span
                  >
                </div>
                {#if currentBook.progress_known}<div class="progress-track">
                    <span style:width="{currentBook.progress}%"></span>
                  </div>{/if}
                <button class="primary-button" onclick={() => (selectedBook = currentBook)}
                  >View book details</button
                >
              </div>
            </section>{:else}<section class="state-panel empty-reading">
              <Icon name="book" size={64} />
              <h2>Your next chapter starts here.</h2>
              <p>
                {data.source_device
                  ? 'Open a book in KOReader. Your next sync brings its reading history here.'
                  : 'Connect your Kindle to bring in your books, reading days and achievements.'}
              </p>
              <button class="primary-button" onclick={() => navigate('devices')}
                >Connect your Kindle</button
              >
            </section>{/if}
          <section class="week-section">
            <div class="section-heading">
              <h2 class="eyebrow">READING THIS WEEK</h2>
              <span class="mono">{weekLabel}</span>
            </div>
            <WeeklyChart
              dates={weekDates}
              {days}
              today={data.today}
              onday={(date) => (selectedDay = date)}
            />
          </section>
          <section class="next-milestone">
            <span class="badge-frame"
              >{#if featuredBadge}<img src={badgeSource(featuredBadge.icon)} alt="" />{:else}<Icon
                  name="badge"
                  size={28}
                />{/if}</span
            >
            <div>
              <h2>{featuredBadge?.title ?? 'One chapter at a time'}</h2>
              <p>
                {featuredBadge?.description ??
                  'Your first milestone is still to come. Keep a little time for reading.'}
              </p>
            </div>
            <button class="text-button" onclick={() => navigate('achievements')}
              >All achievements</button
            >
          </section>
          <button class="outline-button mobile-activity-link" onclick={() => navigate('activity')}
            >Your reading activity</button
          >
        {:else if page === 'library'}
          <div class="library-toolbar">
            <label class="search-box"
              ><Icon name="search" size={20} /><input
                aria-label="Search your library"
                bind:value={query}
                placeholder="Title or author"
              /></label
            >
            <div class="filter-tabs" aria-label="Filter books">
              {#each [['all', 'All'], ['reading', 'Reading'], ['finished', 'Finished'], ['unread', 'Unread']] as [id, label]}<button
                  class:active={bookFilter === id}
                  aria-pressed={bookFilter === id}
                  onclick={() => (bookFilter = id)}>{label}</button
                >{/each}
            </div>
          </div>
          <p class="eyebrow list-count">
            {filteredBooks.length}
            {filteredBooks.length === 1 ? 'BOOK' : 'BOOKS'} · {data.demo
              ? 'DEMO METADATA'
              : 'DEVICE METADATA'}
          </p>
          <div class="library-grid">
            {#each filteredBooks as book}<button
                class="library-book"
                onclick={() => (selectedBook = book)}
                ><div class="library-cover"><Cover {book} compact /></div>
                <div class="library-book-info">
                  <h2>{book.title}</h2>
                  <p>{book.author} · {book.format}</p>
                  <span class="book-status mono"
                    >{book.status === 'finished'
                      ? 'Finished'
                      : book.status === 'reading'
                        ? book.progress_known
                          ? `${book.progress}% read`
                          : 'Reading'
                        : 'Not started'}</span
                  >
                </div>
                <span class="row-action">Details <Icon name="right" size={18} /></span></button
              >{/each}
          </div>
          {#if !filteredBooks.length}<div class="state-panel">
              <Icon name="search" size={64} />
              <h2>No books in this corner.</h2>
              <p>Try another title or clear your filters.</p>
              <button
                class="outline-button"
                onclick={() => {
                  query = '';
                  bookFilter = 'all';
                }}>Clear search and filters</button
              >
            </div>{/if}
          <p class="detail-footnote">
            Book files stay on your Kindle. This dashboard shows synced reading metadata.
          </p>
        {:else if page === 'activity'}
          <div class="filter-tabs activity-tabs" aria-label="Reading activity period">
            {#each [['week', 'Week'], ['month', 'Month'], ['year', 'Year']] as [id, label]}<button
                class:active={activityView === id}
                aria-pressed={activityView === id}
                onclick={() => (activityView = id)}>{label}</button
              >{/each}
          </div>
          {#if activityView === 'week'}
            <div class="goal-strip">
              <div class="goal-metric">
                <Icon name="clock" size={28} /><span
                  ><strong>{duration(weekSeconds)}</strong><small>this week</small></span
                >
              </div>
              <div class="goal-metric">
                <Icon name="calendar" size={28} /><span
                  ><strong>{weekActive} / {weekElapsed}</strong><small>reading days</small></span
                >
              </div>
              <div class="goal-metric">
                <Icon name="book" size={28} /><span
                  ><strong>{weekPages}</strong><small>pages read</small></span
                >
              </div>
            </div>
            <div class="period-controls">
              <button
                class="outline-button"
                aria-label="Previous week"
                onclick={() => (weekOffset -= 1)}><Icon name="left" size={20} />Previous</button
              >
              <h2>{weekLabel}</h2>
              <button
                class="outline-button"
                aria-label="Next week"
                disabled={weekOffset === 0}
                onclick={() => (weekOffset = Math.min(0, weekOffset + 1))}
                >Next<Icon name="right" size={20} /></button
              >
            </div>
            <WeeklyChart
              dates={weekDates}
              {days}
              today={data.today}
              onday={(date) => (selectedDay = date)}
            />
            <div class="activity-links">
              <button class="outline-button" onclick={() => (activityView = 'month')}
                >Open monthly calendar</button
              ><button class="text-button" onclick={editGoals}>Reading goals</button>
            </div>
          {:else if activityView === 'month'}
            <section class="activity-calendar">
              <Calendar
                bind:month
                books={data.books}
                activity={data.activity}
                {days}
                today={data.today}
                onday={(date) => (selectedDay = date)}
                onbook={(book) => (selectedBook = book)}
              />
            </section>
          {:else}
            <div class="goal-strip">
              <div class="goal-metric">
                <Icon name="clock" size={28} /><span
                  ><strong>{duration(totalSeconds)}</strong><small>reading time</small></span
                >
              </div>
              <div class="goal-metric">
                <Icon name="book" size={28} /><span
                  ><strong>{totalPages.toLocaleString()}</strong><small>pages read</small></span
                >
              </div>
              <button class="goal-metric" onclick={editGoals}
                ><Icon name="badge" size={28} /><span
                  ><strong
                    >{finished}{data.goals.yearly_books > 0
                      ? ` / ${data.goals.yearly_books}`
                      : ''}</strong
                  ><small>books finished</small></span
                ></button
              >
            </div>
            <section class="year-panel">
              <h2 class="visually-hidden">{year} reading days</h2>
              <div class="heatmap-scroll">
                <div class="heatmap-months" style:--weeks={yearWeeks(year).length}>
                  {#each yearMonths as item}<span style:grid-column={item.column}>{item.name}</span
                    >{/each}
                </div>
                <div class="heatmap">
                  {#each yearWeeks(year) as week}<div class="heatmap-week">
                      {#each week as date}<button
                          class="heatmap-cell heat-{level(date)}"
                          class:hidden-cell={!date.startsWith(String(year))}
                          class:future={date > data.today}
                          disabled={!date.startsWith(String(year)) || date > data.today}
                          title="{formatDate(date)} · {minutes(days.get(date)?.seconds ?? 0)} min"
                          aria-label="{formatDate(date)}: {minutes(
                            days.get(date)?.seconds ?? 0,
                          )} minutes"
                          onclick={() => (selectedDay = date)}
                        ></button>{/each}
                    </div>{/each}
                </div>
              </div>
              <div class="heatmap-footer">
                <span
                  >Less {#each [0, 1, 2, 3, 4] as value}<i class="heat-{value}"></i>{/each}More ·
                  Future days are blank</span
                >
              </div>
            </section>
            <section class="year-goal">
              <h2>Your {year} reading goal</h2>
              <p>
                {data.goals.yearly_books > 0
                  ? `${finished} of ${data.goals.yearly_books} books finished. There is room for another story.`
                  : `${finished} books finished this year. Your yearly goal is off.`}
              </p>
              {#if data.goals.yearly_books > 0}<div class="progress-track">
                  <span
                    style:width="{Math.min(
                      100,
                      (finished / Math.max(1, data.goals.yearly_books)) * 100,
                    )}%"
                  ></span>
                </div>{/if}
              <div class="activity-links">
                <button class="outline-button" onclick={editGoals}>Adjust goals</button><button
                  class="text-button"
                  onclick={() => {
                    bookFilter = 'finished';
                    navigate('library');
                  }}>View finished books</button
                >
              </div>
            </section>
          {/if}
        {:else if page === 'achievements'}
          <div class="achievement-summary">
            <strong>{earned} / {data.achievements.length}</strong><span>achievements earned</span
            ><span class="badge-frame"><Icon name="badge" size={28} /></span>
          </div>
          <div class="filter-tabs badge-filters" aria-label="Filter achievements">
            {#each [['all', 'All'], ['earned', 'Earned'], ['locked', 'Locked']] as [id, label]}<button
                class:active={badgeFilter === id}
                aria-pressed={badgeFilter === id}
                onclick={() => (badgeFilter = id)}>{label}</button
              >{/each}
          </div>
          <div class="achievement-grid">
            {#each filteredBadges as badge}<button
                class="achievement-card"
                class:locked={!badge.unlocked}
                onclick={() => (selectedBadge = badge)}
                ><span class="badge-frame"><img src={badgeSource(badge.icon)} alt="" /></span>
                <div class="achievement-copy">
                  <h2>{badge.title}</h2>
                  <p>{badge.description}</p>
                  {#if badge.unlocked}<span class="earned-label"
                      >Earned · {formatDate(badge.unlocked, {
                        month: 'short',
                        day: 'numeric',
                        year: 'numeric',
                      })}</span
                    >{:else}<span class="badge-progress-label"
                      >{badge.progress} / {badge.target} {badge.unit}</span
                    >
                    <div class="progress-track">
                      <span
                        style:width="{Math.min(
                          100,
                          (badge.progress / Math.max(1, badge.target)) * 100,
                        )}%"
                      ></span>
                    </div>{/if}
                </div>
                <Icon name="right" size={20} /></button
              >{/each}
          </div>
          {#if !filteredBadges.length}<div class="state-panel">
              <Icon name="badge" size={64} />
              <h2>
                {badgeFilter === 'earned'
                  ? 'Your first milestone is still to come.'
                  : 'A quiet moment in your collection.'}
              </h2>
              <p>Reading moments and achievements arrive with your next sync.</p>
            </div>{/if}
        {:else if page === 'devices'}
          <Devices
            devices={data.devices}
            serverURL={auth?.server_url ?? ''}
            sourceDevice={data.source_device ?? ''}
            onrefresh={load}
            onselect={viewDevice}
          />
        {:else if page === 'settings'}
          <section class="settings-list">
            <button onclick={editGoals}
              ><span
                ><strong>Reading goals</strong><small
                  >{data.goals.daily_minutes} minutes a day · {data.goals.yearly_books} books in {year}</small
                ></span
              ><Icon name="right" /></button
            ><button onclick={() => navigate('devices')}
              ><span
                ><strong>Connected devices</strong><small
                  >{data.devices.filter((device) => !device.revoked).length} paired devices</small
                ></span
              ><Icon name="right" /></button
            ><button onclick={load} disabled={loading}
              ><span
                ><strong>Refresh reading history</strong><small
                  >{loading
                    ? 'Gathering your reading moments…'
                    : 'Bring in the latest data from your server'}</small
                ></span
              ><Icon name="refresh" /></button
            ><button onclick={logout}
              ><span><strong>Account</strong><small>Sign out of your reading space</small></span
              ><span>Sign out</span></button
            >
          </section>
          <p class="detail-footnote">
            Kindlevel · Self-hosted. Your reading data is stored on your server. Book and highlight
            sync is planned.
          </p>
        {/if}
        <footer class="page-footer">
          <span
            >{data.demo ? 'Demo reading history' : 'Kindle reading history'} · Self-hosted. Yours to keep.</span
          ><button class="text-button" onclick={load} disabled={loading}
            >{loading ? 'Refreshing…' : 'Refresh'}</button
          >
        </footer>
      {/if}
    </main>
    <nav class="mobile-nav" aria-label="Mobile navigation">
      {#each tabs.filter((tab) => tab.id !== 'devices') as tab}<button
          class:active={page === tab.id}
          aria-label={tab.label}
          aria-current={page === tab.id ? 'page' : undefined}
          onclick={() => navigate(tab.id)}
          ><Icon name={tab.icon} size={24} /><span>{tab.mobile}</span></button
        >{/each}
    </nav>
  </div>
  <dialog
    bind:this={dialog}
    oncancel={closeDialog}
    onclose={closeDialog}
    aria-labelledby="dialog-title"
  >
    <button class="dialog-close icon-button" aria-label="Close details" onclick={closeDialog}
      ><Icon name="close" size={20} /></button
    >
    {#if goalOpen}
      <div class="dialog-content">
        <span class="eyebrow">A PACE THAT FEELS LIKE YOU</span>
        <h2 id="dialog-title">Your reading pace</h2>
        <p>Make a little room for reading. You can change these anytime.</p>
        <p class="goal-note">
          Dashboard goals are saved here. Set your Kindle goals in the plugin.
        </p>
        <form onsubmit={saveGoals}>
          <label class="goal-field"
            >Daily reading time<span
              ><input type="number" min="1" max="1440" required bind:value={dailyGoal} /> minutes a day</span
            ></label
          ><label class="goal-field"
            >Books this year<span
              ><input type="number" min="0" max="10000" required bind:value={yearlyGoal} /> books in {year}</span
            ></label
          >{#if goalError}<p class="form-error" role="alert">{goalError}</p>{/if}<button
            class="primary-button"
            type="submit"
            disabled={saving}
            >{saving ? 'Saving…' : 'Save goals'}<Icon name="check" size={17} /></button
          >
        </form>
      </div>
    {:else if selectedBook}
      <div class="dialog-book">
        <Cover book={selectedBook} compact /><span class="eyebrow"
          >{selectedBook.format} · {selectedBook.status === 'finished'
            ? 'FINISHED'
            : selectedBook.status === 'reading'
              ? 'CURRENTLY READING'
              : 'ON YOUR SHELF'}</span
        >
        <h2 id="dialog-title">{selectedBook.title}</h2>
        <p class="book-author">{selectedBook.author}</p>
        <p>{selectedBook.description}</p>
        <div class="book-progress-label">
          <span
            >{selectedBook.progress_known
              ? `${selectedBook.progress}% read`
              : 'Reading position not available'}</span
          ><span>{selectedBook.pages} pages</span>
        </div>
        <div class="progress-track"><span style:width="{selectedBook.progress}%"></span></div>
        <div class="book-detail-stats">
          <div>
            <strong>{duration(bookHistory.reduce((sum, item) => sum + item.seconds, 0))}</strong
            ><span>reading time</span>
          </div>
          <div>
            <strong>{new Set(bookHistory.map((item) => item.date)).size}</strong><span
              >reading days</span
            >
          </div>
        </div>
        {#if selectedBook.finished}<p class="detail-footnote">
            Finished {formatDate(selectedBook.finished)}.
          </p>{/if}
        <p class="detail-footnote">
          {data.demo ? 'Demo book metadata.' : 'Synced from KOReader.'} Book file delivery is coming later.
        </p>
      </div>
    {:else if selectedDay}
      <div class="dialog-content">
        <span class="eyebrow">YOUR READING JOURNAL</span>
        <h2 id="dialog-title">
          {formatDate(selectedDay, { weekday: 'long', month: 'long', day: 'numeric' })}
        </h2>
        {#if dayRecord}<p>
            {duration(dayRecord.seconds)} between the pages · {dayRecord.pages} pages read
          </p>
          <div class="journal-books">
            {#each data.books.filter( (book) => dayRecord.books.has(book.id) ) as book}{@const entries =
                data.activity.filter(
                  (item) => item.date === selectedDay && item.book_id === book.id,
                )}<button
                onclick={() => {
                  selectedDay = '';
                  selectedBook = book;
                }}
                ><div class="journal-cover"><Cover {book} compact /></div>
                <div>
                  <h3>{book.title}</h3>
                  <span
                    >{duration(entries.reduce((sum, item) => sum + item.seconds, 0))} · {entries.reduce(
                      (sum, item) => sum + item.pages,
                      0,
                    )} pages</span
                  >
                </div>
                <Icon name="right" size={18} /></button
              >{/each}
          </div>{:else}<div class="quiet-day">
            <Icon name="leaf" size={32} />
            <p>
              {selectedDay > data.today
                ? 'A reading moment still to come.'
                : 'A quiet day away from the pages.'}
            </p>
          </div>{/if}
      </div>
    {:else if selectedBadge}
      <div class="dialog-achievement">
        <div class="badge-frame"><img src={badgeSource(selectedBadge.icon)} alt="" /></div>
        <span class="eyebrow"
          >{selectedBadge.unlocked ? 'A MOMENT COLLECTED' : 'STILL TO DISCOVER'}</span
        >
        <h2 id="dialog-title">{selectedBadge.title}</h2>
        <p>{selectedBadge.description}</p>
        {#if selectedBadge.unlocked}<span class="earned-label"
            ><Icon name="check" size={16} /> Collected {formatDate(selectedBadge.unlocked)}</span
          >{:else}<div class="progress-track">
            <span
              style:width="{Math.min(100, (selectedBadge.progress / selectedBadge.target) * 100)}%"
            ></span>
          </div>
          <p class="detail-footnote">
            {selectedBadge.progress} / {selectedBadge.target}
            {selectedBadge.unit}
          </p>{/if}
        <p class="detail-footnote">{selectedBadge.xp} XP reserved for future progression.</p>
      </div>
    {/if}
  </dialog>
{/if}
