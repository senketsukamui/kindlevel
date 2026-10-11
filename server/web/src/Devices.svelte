<script>
  import Icon from './Icon.svelte';
  let { devices = [], serverURL = '', sourceDevice = '', onrefresh, onselect } = $props();
  let code = $state('');
  let expires = $state(0);
  let error = $state('');
  let busy = $state(false);
  let confirmRevoke = $state('');
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

<section class="panel pairing-panel">
  <span class="pairing-icon"><Icon name="device" size={32} /></span>
  <div>
    <span class="eyebrow">A LITTLE BRIDGE TO YOUR KINDLE</span>
    <h2>Bring your reading home.</h2>
    <p>Pair once, then sync your library, reading statistics and achievements over Wi-Fi.</p>
    <ol>
      <li>On Kindle, open <strong>Kindlevel → Settings → Web dashboard</strong>.</li>
      <li>
        Enter your server address{#if serverURL}: <strong>{serverURL}</strong>{/if}.
      </li>
      <li>Enter the pairing code below, then choose <strong>Sync now</strong>.</li>
    </ol>
    <p class="detail-footnote">
      Your Kindle needs a server address it can reach. “localhost” on Kindle points to the Kindle
      itself. Use your server’s HTTPS domain, or a trusted LAN address for local testing.
    </p>
  </div>
  <div class="pair-code-box">
    {#if code}<span class="eyebrow">ONE-TIME PAIRING CODE</span><strong class="pair-code"
        >{code}</strong
      ><span class="detail-footnote"
        >Expires at {new Date(expires * 1000).toLocaleTimeString([], {
          hour: '2-digit',
          minute: '2-digit',
        })}</span
      >{/if}<button class="primary-button" disabled={busy} onclick={pairing}
      >{code ? 'Generate a new code' : 'Pair a Kindle'}<Icon name="arrow" size={17} /></button
    >
  </div>
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
