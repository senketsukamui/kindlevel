<script>
  import { onMount } from 'svelte';
  import Icon from './Icon.svelte';
  import Auth from './Auth.svelte';
  import Devices from './Devices.svelte';
  import Cover from './Cover.svelte';
  import Calendar from './Calendar.svelte';
  import {
    dailyActivity,
    streak,
    duration,
    minutes,
    formatDate,
    shiftDate,
    yearWeeks,
  } from './reading.js';

  let data = $state(null);
  let auth = $state(null);
  let selectedDevice = $state('');
  let error = $state('');
  let loading = $state(true);
  let page = $state('home');
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
    { id: 'home', label: 'Reading home', icon: 'book' },
    { id: 'library', label: 'Your library', icon: 'shelf' },
    { id: 'activity', label: 'Reading activity', icon: 'calendar' },
    { id: 'achievements', label: 'Achievements', icon: 'badge' },
    { id: 'devices', label: 'Your Kindle', icon: 'device' },
  ];
  const titles = {
    devices: [
      'Your reading life, connected.',
      'A little bridge between your Kindle and your reading home.',
    ],
    home: ['A little time, a few pages.', 'Make yourself at home. Your reading life is here.'],
    library: [
      'Good company, on every shelf.',
      'The books you’ve finished, found, and fallen into.',
    ],
    activity: ['Every page leaves a trace.', 'Small reading moments, gathered over time.'],
    achievements: [
      'Little milestones. Lasting habits.',
      'A collection of moments worth remembering.',
    ],
  };
  let days = $derived(dailyActivity(data?.activity ?? []));
  let today = $derived(days.get(data?.today) ?? { seconds: 0, pages: 0 });
  let currentBook = $derived(
    data?.books.find((book) => book.id === data?.current_book) ??
      data?.books.find((book) => book.status === 'reading') ??
      data?.books[0],
  );
  let currentStreak = $derived(data ? streak(days, data.today) : 0);
  let year = $derived(Number(data?.today.slice(0, 4) ?? new Date().getFullYear()));
  let yearActivity = $derived(
    data?.activity.filter((item) => item.date.startsWith(String(year))) ?? [],
  );
  let totalSeconds = $derived(yearActivity.reduce((sum, item) => sum + item.seconds, 0));
  let totalPages = $derived(yearActivity.reduce((sum, item) => sum + item.pages, 0));
  let finished = $derived(
    data?.books.filter((book) => book.finished?.startsWith(String(year))).length ?? 0,
  );
  let recent = $derived(
    Array.from({ length: 7 }, (_, i) => shiftDate(data?.today ?? '2026-01-01', i - 6)),
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
    page = id;
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

<svelte:head><title>Kindlevel · {tabs.find((tab) => tab.id === page)?.label}</title></svelte:head>

{#if auth && !auth.authenticated}
  <Auth initialized={auth.initialized} onauthenticated={load} />
{:else}
  <div class="app-shell">
    <aside class="sidebar">
      <a
        class="brand"
        href="#home"
        onclick={() => navigate('home')}
        aria-label="Kindlevel reading home"
        ><span class="brand-mark"><Icon name="book" size={22} /></span><span
          >kindlevel<span class="brand-subtitle">YOUR READING HOME</span></span
        ></a
      >
      <nav aria-label="Main navigation">
        {#each tabs as tab}<button
            class:active={page === tab.id}
            aria-current={page === tab.id ? 'page' : undefined}
            onclick={() => navigate(tab.id)}
            ><Icon name={tab.icon} size={19} /><span>{tab.label}</span
            >{#if tab.id === 'achievements' && data}<span class="nav-count">{earned}</span
              >{/if}</button
          >{/each}
      </nav>
      <div class="sidebar-note">
        <Icon name="leaf" size={24} />
        <p>A few pages at a time.<br />A little world of your own.</p>
      </div>
      <button class="device-note" onclick={() => navigate('devices')}>
        <span class="device-icon"><Icon name="device" size={19} /></span>
        <div>
          <strong
            >{data?.devices.find((device) => device.id === data.source_device)?.name ??
              'Connect your Kindle'}</strong
          ><span
            >{data?.source_device ? 'Reading history synced' : 'Pair once. Read anywhere.'}</span
          >
        </div>
      </button>
      <span class="sidebar-footer">Self-hosted. Yours to keep.</span>
    </aside>

    <main>
      <header class="topbar">
        <div class="breadcrumb">
          Your reading space <span>/</span>
          {tabs.find((tab) => tab.id === page)?.label}
        </div>
        <div class="topbar-actions">
          <span class="demo-pill"
            ><i></i>{data?.demo ? 'Demo reading history' : 'Kindle reading history'}</span
          ><button class="text-button" onclick={load} disabled={loading}>Refresh</button><button
            class="text-button"
            onclick={logout}>Sign out</button
          >
        </div>
      </header>
      {#if loading && !data}<div class="state-panel" role="status">
          <Icon name="book" size={35} />
          <h1>Opening your reading home…</h1>
        </div>
      {:else if error}<div class="state-panel" role="alert">
          <h1>A little pause.</h1>
          <p>{error}</p>
          <button class="primary-button" onclick={load}>Try again</button>
        </div>
      {:else if data}
        <div class="page-heading">
          <div>
            <span class="eyebrow"
              >{page === 'home'
                ? formatDate(data.today, { weekday: 'long', month: 'long', day: 'numeric' })
                : 'YOUR READING LIFE'}</span
            >
            <h1>{titles[page][0]}</h1>
            <p>{titles[page][1]}</p>
          </div>
          {#if page === 'home' || page === 'activity'}<button
              class="outline-button goal-action"
              onclick={editGoals}><Icon name="target" size={17} /> Reading goals</button
            >{/if}
        </div>
        {#if message}<div class="saved-message" role="status">
            <Icon name="check" size={17} />{message}<button
              aria-label="Dismiss message"
              onclick={() => (message = '')}><Icon name="close" size={16} /></button
            >
          </div>{/if}

        {#if page === 'devices'}
          <Devices
            devices={data.devices}
            serverURL={auth?.server_url ?? ''}
            sourceDevice={data.source_device ?? ''}
            onrefresh={load}
            onselect={viewDevice}
          />
        {:else if page === 'home'}
          <div class="home-top">
            {#if currentBook}<section class="current-book panel">
                <div class="current-book-cover"><Cover book={currentBook} /></div>
                <div class="current-book-info">
                  <span class="eyebrow">ON YOUR NIGHTSTAND</span>
                  <h2>{currentBook.title}</h2>
                  <p class="book-author">{currentBook.author}</p>
                  <p class="current-book-copy">
                    There’s a little more of this story waiting for you.
                  </p>
                  <div class="book-progress-label">
                    <span
                      >{currentBook.progress_known
                        ? `${currentBook.progress}% of the way`
                        : 'Reading on your Kindle'}</span
                    ><span
                      >{currentBook.progress_known
                        ? `${Math.round((currentBook.pages * currentBook.progress) / 100)} / ${currentBook.pages}`
                        : currentBook.pages
                          ? `${currentBook.pages} pages`
                          : ''}
                      pages</span
                    >
                  </div>
                  {#if currentBook.progress_known}<div class="progress-track">
                      <span style:width="{currentBook.progress}%"></span>
                    </div>{/if}
                  <button class="primary-button" onclick={() => (selectedBook = currentBook)}
                    >A closer look <Icon name="arrow" size={18} /></button
                  >
                </div>
              </section>{:else}<section class="panel empty-reading">
                <Icon name="book" size={32} />
                <h2>Your next chapter is waiting.</h2>
                <p>Open a book in KOReader, then choose Sync now in Kindlevel.</p>
                <button class="outline-button" onclick={() => navigate('devices')}
                  >Your Kindle</button
                >
              </section>{/if}
            <section class="today-card panel">
              <div class="card-heading">
                <span class="eyebrow">A LITTLE EVERY DAY</span><Icon name="sun" size={21} />
              </div>
              <div class="today-value">
                {minutes(today.seconds)}<span> / {data.goals.daily_minutes} min</span>
              </div>
              <p>
                {today.seconds >= data.goals.daily_minutes * 60
                  ? 'Your daily goal, quietly accomplished.'
                  : `${Math.max(0, data.goals.daily_minutes - minutes(today.seconds))} more minutes for a little reading moment.`}
              </p>
              <div class="progress-track">
                <span
                  style:width="{Math.min(
                    100,
                    (today.seconds / (data.goals.daily_minutes * 60)) * 100,
                  )}%"
                ></span>
              </div>
              <div class="today-bottom">
                <span><Icon name="leaf" size={18} />{currentStreak}-day reading streak</span><button
                  class="text-button"
                  onclick={editGoals}>Adjust goal</button
                >
              </div>
            </section>
          </div>
          <div class="metrics">
            <div>
              <span class="metric-icon"><Icon name="clock" size={21} /></span>
              <div>
                <span class="metric-label">Time between the pages</span><strong
                  >{duration(totalSeconds)}<small>this year</small></strong
                >
              </div>
            </div>
            <div>
              <span class="metric-icon"><Icon name="book" size={21} /></span>
              <div>
                <span class="metric-label">Pages turned</span><strong
                  >{totalPages.toLocaleString()}<small>this year</small></strong
                >
              </div>
            </div>
            <button onclick={editGoals}
              ><span class="metric-icon"><Icon name="shelf" size={21} /></span>
              <div>
                <span class="metric-label">Your {year} reading goal</span><strong
                  >{finished}<span class="metric-divider"> / {data.goals.yearly_books}</span><small
                    >books finished</small
                  ></strong
                >
              </div>
              <span
                class="mini-progress"
                style:background="conic-gradient(var(--olive) {Math.min(
                  100,
                  (finished / Math.max(1, data.goals.yearly_books)) * 100,
                )}%, var(--line) 0)"><span></span></span
              ></button
            >
          </div>
          <div class="home-bottom">
            <section class="panel calendar-panel">
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
            <div class="home-side">
              <section class="panel rhythm-card">
                <div class="section-heading">
                  <h2>Your daily rhythm</h2>
                  <Icon name="leaf" size={19} />
                </div>
                <p>Small moments add up.</p>
                <div class="rhythm-chart">
                  {#each recent as date}<button
                      class:today-column={date === data.today}
                      aria-label="{formatDate(date)}: {minutes(
                        days.get(date)?.seconds ?? 0,
                      )} minutes"
                      onclick={() => (selectedDay = date)}
                      ><span class="rhythm-value">{minutes(days.get(date)?.seconds ?? 0)}</span
                      ><span
                        class="rhythm-bar"
                        style:height="{Math.max(
                          4,
                          Math.min(104, (days.get(date)?.seconds ?? 0) / 45),
                        )}px"
                      ></span><span class="rhythm-day"
                        >{formatDate(date, { weekday: 'short' }).slice(0, 1)}</span
                      ></button
                    >{/each}
                </div>
                <div class="rhythm-total">
                  <strong
                    >{duration(
                      recent.reduce((sum, date) => sum + (days.get(date)?.seconds ?? 0), 0),
                    )}</strong
                  ><span>over the last seven days</span>
                </div>
              </section>
              <section class="panel recent-badge">
                <div class="section-heading">
                  <h2>A small milestone</h2>
                  <Icon name="badge" size={18} />
                </div>
                {#if latestBadge}<button
                    class="featured-badge"
                    onclick={() => (selectedBadge = latestBadge)}
                    ><div class="badge-frame">
                      <img src="/assets/badges/{latestBadge.icon}.svg" alt="" />
                    </div>
                    <strong>{latestBadge.title}</strong><span>{latestBadge.description}</span
                    ></button
                  >{:else}<p class="no-badges">
                    Your first milestone is still to come. Keep a little time for reading.
                  </p>{/if}<button
                  class="text-button badge-link"
                  onclick={() => navigate('achievements')}
                  >Explore your achievements <Icon name="arrow" size={16} /></button
                >
              </section>
            </div>
          </div>
        {:else if page === 'library'}
          <div class="library-toolbar">
            <div class="filter-tabs" aria-label="Filter books">
              {#each [['all', 'All books'], ['reading', 'Reading'], ['finished', 'Finished'], ['unread', 'Waiting']] as [id, label]}<button
                  class:active={bookFilter === id}
                  aria-pressed={bookFilter === id}
                  onclick={() => (bookFilter = id)}
                  >{label}<span
                    >{id === 'all'
                      ? data.books.length
                      : data.books.filter((book) => book.status === id).length}</span
                  ></button
                >{/each}
            </div>
            <label class="search-box"
              ><Icon name="search" size={18} /><input
                aria-label="Search your library"
                bind:value={query}
                placeholder="Find a book…"
              /></label
            >
          </div>
          <div class="library-grid">
            {#each filteredBooks as book}<button
                class="library-book"
                onclick={() => (selectedBook = book)}
                ><div class="library-cover"><Cover {book} /></div>
                <div class="library-book-meta">
                  <span class="format-label">{book.format}</span><span
                    class="book-status"
                    class:finished={book.status === 'finished'}
                    >{book.status === 'finished'
                      ? 'Finished'
                      : book.status === 'reading'
                        ? book.progress_known
                          ? `${book.progress}% read`
                          : 'Reading'
                        : 'Waiting for you'}</span
                  >
                </div>
                <h2>{book.title}</h2>
                <p>{book.author}</p>
                {#if book.status === 'reading' && book.progress_known}<div class="progress-track">
                    <span style:width="{book.progress}%"></span>
                  </div>{/if}</button
              >{/each}
          </div>
          {#if !filteredBooks.length}<div class="state-panel">
              <Icon name="search" size={28} />
              <h2>No books on this shelf.</h2>
              <p>Try another title or filter.</p>
              <button
                class="outline-button"
                onclick={() => {
                  query = '';
                  bookFilter = 'all';
                }}>Show all books</button
              >
            </div>{/if}
        {:else if page === 'activity'}
          <section class="panel year-panel">
            <div class="section-heading">
              <div>
                <span class="eyebrow">A YEAR IN LITTLE MOMENTS</span>
                <h2>Your {year} reading garden</h2>
              </div>
              <span class="activity-days"
                >{[...days.keys()].filter((date) => date.startsWith(String(year))).length} days with a
                book</span
              >
            </div>
            <div class="heatmap-scroll">
              <div class="heatmap">
                <div class="heatmap-day-labels">
                  <span>Mon</span><span>Wed</span><span>Fri</span>
                </div>
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
              <div class="heatmap-months">
                {#each ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'] as name}<span
                    >{name}</span
                  >{/each}
              </div>
            </div>
            <div class="heatmap-footer">
              <span>{currentStreak} days in your current streak</span><span
                >Less {#each [0, 1, 2, 3, 4] as value}<i class="heat-{value}"></i>{/each} More</span
              >
            </div>
          </section>
          <section class="panel activity-calendar">
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
        {:else if page === 'achievements'}
          <section class="achievement-summary">
            <span class="large-badge-mark"><Icon name="badge" size={30} /></span>
            <div>
              <strong>{earned}<span> / {data.achievements.length}</span></strong>
              <p>moments collected on your reading journey</p>
            </div>
            <div class="achievement-summary-progress">
              <div class="progress-track">
                <span style:width="{(earned / Math.max(1, data.achievements.length)) * 100}%"
                ></span>
              </div>
              <span>A little progress, one page at a time.</span>
            </div>
          </section>
          <div class="filter-tabs badge-filters" aria-label="Filter achievements">
            {#each [['all', 'All achievements'], ['earned', 'Collected'], ['locked', 'Still to discover']] as [id, label]}<button
                class:active={badgeFilter === id}
                aria-pressed={badgeFilter === id}
                onclick={() => (badgeFilter = id)}>{label}</button
              >{/each}
          </div>
          <div class="achievement-grid">
            {#each filteredBadges as badge}<button
                class="achievement-card panel"
                class:locked={!badge.unlocked}
                onclick={() => (selectedBadge = badge)}
                ><div class="badge-frame"><img src="/assets/badges/{badge.icon}.svg" alt="" /></div>
                <h2>{badge.title}</h2>
                <p>{badge.description}</p>
                {#if badge.unlocked}<span class="earned-label"
                    ><Icon name="check" size={14} /> Collected {formatDate(badge.unlocked, {
                      month: 'short',
                      day: 'numeric',
                    })}</span
                  >{:else}<div class="badge-card-progress">
                    <div class="progress-track">
                      <span style:width="{Math.min(100, (badge.progress / badge.target) * 100)}%"
                      ></span>
                    </div>
                    <span>{badge.progress} / {badge.target} {badge.unit}</span>
                  </div>{/if}</button
              >{/each}
          </div>
        {/if}
        <footer class="page-footer">
          <span><Icon name="leaf" size={14} /> Every little reading moment counts.</span><span
            >Kindlevel · {data.demo ? 'Demo workspace' : 'Your reading home'}</span
          >
        </footer>
      {/if}
    </main>
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
        <h2 id="dialog-title">Your reading goals</h2>
        <p>Make a little room for reading. You can change these anytime.</p>
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
            >{saving ? 'Saving…' : 'Save my goals'}<Icon name="check" size={17} /></button
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
        <div class="badge-frame"><img src="/assets/badges/{selectedBadge.icon}.svg" alt="" /></div>
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
