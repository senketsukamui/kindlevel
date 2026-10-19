<script>
  import Icon from './Icon.svelte';
  import { onMount } from 'svelte';
  let { devices = [], serverURL = '', sourceDevice = '', onrefresh, onselect } = $props();
  let code = $state('');
  let expires = $state(0);
  let error = $state('');
  let busy = $state(false);
  let confirmRevoke = $state('');
  let now = $state(Math.floor(Date.now() / 1000));
  let copyMessage = $state('');
  let serverAddress = $derived(serverURL || window.location.origin);
  let expired = $derived(expires > 0 && now >= expires);
  onMount(() => {
    const timer = setInterval(() => (now = Math.floor(Date.now() / 1000)), 1000);
    return () => clearInterval(timer);
  });
  async function copyAddress() {
    try {
      await navigator.clipboard.writeText(serverAddress);
      copyMessage = 'Server address copied.';
    } catch {
      copyMessage = 'Select and copy the address above.';
    }
  }
  function lastSeen(seconds) {
    return seconds ? new Date(seconds * 1000).toLocaleString() : 'Waiting for the first sync';
  }
  async function pairing() {
    busy = true;
    error = '';
    try {
      const response = await fetch('/api/v1/pairing', { method: 'POST' });
      const result = await response.json();
      if (!response.ok) throw new Error(result.error);
      code = result.code;
      expires = result.expires_at;
    } catch (e) {
      error = e.message;
    } finally {
      busy = false;
    }
  }
  async function revoke(id) {
    busy = true;
    error = '';
    try {
      const response = await fetch(`/api/v1/devices/${encodeURIComponent(id)}/revoke`, {
        method: 'POST',
      });
      const result = await response.json();
      if (!response.ok) throw new Error(result.error);
      confirmRevoke = '';
      await onrefresh();
    } catch (e) {
      error = e.message;
    } finally {
      busy = false;
    }
  }
</script>

<section class="pairing-panel">
  <div class="pair-instructions">
    <h2>1. Open Kindlevel on your Kindle</h2>
    <p>Settings → Web dashboard → Connect to server</p>
    <label class="server-address"
      ><span>2. Server address</span><input
        readonly
        value={serverAddress}
        aria-label="Server address"
      /></label
    >
    <button class="outline-button" onclick={copyAddress}>Copy server address</button>
    {#if copyMessage}<span class="copied-message" role="status">{copyMessage}</span>{/if}
    <div class="pair-code-box">
      <h2>3. Enter your pairing code</h2>
      {#if code}<strong class="pair-code">{code}</strong><span class="detail-footnote" role="status"
          >{expired
            ? 'Code expired. Generate a fresh code.'
            : `Expires at ${new Date(expires * 1000).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}`}</span
        >{/if}
      <button class="primary-button" disabled={busy} onclick={pairing}
        >{busy ? 'Generating code…' : code ? 'Generate a new code' : 'Pair a Kindle'}</button
      >
    </div>
    <p class="detail-footnote">
      Use an address your Kindle can reach. “localhost” points to the Kindle itself. For HTTP,
      confirm Allow HTTP on the device. Reading statistics arrive after the first sync.
    </p>
  </div>
  <aside class="pairing-aside">
    <h2>Your books stay with you.</h2>
    <p>Pair once, then bring your reading statistics and achievements here over Wi-Fi.</p>
  </aside>
</section>
{#if error}<p class="form-error" role="alert">{error}</p>{/if}
<div class="device-list">
  {#each devices as device}<section class="panel device-card">
      <span class="device-icon"><Icon name="device" size={22} /></span>
      <div>
        <h2>{device.name}</h2>
        <p>
          {device.revoked
            ? 'Access revoked · reading history retained'
            : `Last synced: ${lastSeen(device.last_sync)}`}
        </p>
      </div>
      <div class="device-card-actions">
        {#if device.last_sync}<button class="outline-button" onclick={() => onselect(device.id)}
            >{device.id === sourceDevice ? 'Viewing this Kindle' : 'View reading history'}</button
          >{/if}{#if !device.revoked}{#if confirmRevoke === device.id}<span
              >Revoke this Kindle’s access?</span
            ><button class="outline-button" disabled={busy} onclick={() => revoke(device.id)}
              >Confirm revoke</button
            ><button class="text-button" onclick={() => (confirmRevoke = '')}>Cancel</button
            >{:else}<button class="text-button" onclick={() => (confirmRevoke = device.id)}
              >Revoke access</button
            >{/if}{/if}
      </div>
    </section>{:else}<section class="panel no-devices">
      <Icon name="device" size={30} />
      <h2>A place for your Kindle.</h2>
      <p>Generate a code above to connect your first device.</p>
    </section>{/each}
</div>
