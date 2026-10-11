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
  <section class="auth-card panel">
    <span class="brand-mark"><Icon name="book" size={25} /></span>
    <span class="eyebrow">YOUR READING HOME</span>
    <h1>{initialized ? 'Welcome back.' : 'Make yourself at home.'}</h1>
    <p>
      {initialized
        ? 'Sign in to your own little reading space.'
        : 'Create the owner account for your Kindlevel server.'}
    </p>
    <form onsubmit={submit}>
      {#if !initialized}<label class="auth-field"
          >Setup code<input type="password" autocomplete="off" required bind:value={code} /><small
            >Find it on your server: <code>docker compose exec kindlevel cat /data/setup-code</code
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
          ? 'Opening your reading home…'
          : initialized
            ? 'Sign in'
            : 'Create my reading home'}<Icon name="arrow" size={17} /></button
      >
    </form>
    <p class="auth-footnote">Self-hosted. Yours to keep.</p>
  </section>
</main>
