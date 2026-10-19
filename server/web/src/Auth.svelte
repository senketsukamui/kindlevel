<script>
  import Icon from './Icon.svelte';
  let { initialized, onauthenticated } = $props();
  let username = $state('');
  let password = $state('');
  let code = $state('');
  let error = $state('');
  let busy = $state(false);
  async function submit(event) {
    event.preventDefault();
    busy = true;
    error = '';
    try {
      const response = await fetch(`/api/v1/auth/${initialized ? 'login' : 'setup'}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(initialized ? { username, password } : { code, username, password }),
      });
      const value = await response.json();
      if (!response.ok) throw new Error(value.error);
      password = '';
      code = '';
      await onauthenticated();
    } catch (e) {
      error = e.message;
    } finally {
      busy = false;
    }
  }
</script>

<main class="auth-page">
  <header class="auth-header">
    <a class="brand" href="#home"><Icon name="book" size={28} /><span>kindlevel</span></a>
  </header>
  <div class="auth-layout">
    <section class="auth-welcome">
      <h1>{initialized ? 'Welcome back.' : 'A reading space of your own.'}</h1>
      <p>
        {initialized
          ? 'Your reading corner is waiting.'
          : 'Books, little milestones, and a quiet place to see your reading life.'}
      </p>
      <span class="mono">A few pages. A little world of your own.</span>
    </section>
    <section class="auth-card">
      <h2>{initialized ? 'Sign in to Kindlevel' : 'Create your reading space'}</h2>
      <p>
        {initialized
          ? 'Your self-hosted reading space.'
          : 'Create the owner account for this Kindlevel server.'}
      </p>
      <form onsubmit={submit}>
        {#if !initialized}<label class="auth-field"
            >Server setup code<input
              type="password"
              autocomplete="off"
              required
              bind:value={code}
            /><small
              >Find it on your server:<code>docker compose exec kindlevel cat /data/setup-code</code
              ></small
            ></label
          >{/if}
        <label class="auth-field"
          >Username<input
            autocomplete="username"
            maxlength="64"
            required
            bind:value={username}
          /></label
        >
        <label class="auth-field"
          >Password<input
            type="password"
            autocomplete={initialized ? 'current-password' : 'new-password'}
            minlength={initialized ? 1 : 12}
            maxlength="256"
            required
            bind:value={password}
          />{#if !initialized}<small>At least 12 characters.</small>{/if}</label
        >
        {#if error}<p class="form-error" role="alert">{error}</p>{/if}
        <button class="primary-button" disabled={busy}
          >{busy
            ? 'Opening your reading space…'
            : initialized
              ? 'Sign in'
              : 'Create reading space'}</button
        >
      </form>
      <p class="auth-footnote">Self-hosted. Yours to keep.</p>
    </section>
  </div>
</main>
