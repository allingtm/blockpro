# BlockPro — When to Check for Data Updates

A best-practice strategy for deciding **when** the app should ask the backend
"has anything changed?" and refresh its local cache — taking the mobile app
lifecycle, connectivity, battery/data, and BlockPro's offline-first architecture
into account.

> Companion to [`data-sync-api-report.md`](data-sync-api-report.md), which
> describes *how* data is fetched and stored. This document covers *when* to
> trigger those fetches.

---

## TL;DR — the recommendation

The client's instinct is right; it just needs two refinements to be robust:

1. **Separate the *trigger* from the *throttle*.** Many events can request a
   refresh, but a single shared **freshness gate** decides whether the request
   actually hits the network. "If the app hasn't been minimised for an hour" is
   not a trigger — it's the throttle, and it belongs on *every* trigger.
2. **Scope each check to what the user is looking at.** "Clicking into a block"
   should refresh *that block*, not re-sync the whole estate. A full sync is a
   background, throttled, foreground event — not something the user waits on.

**The proposed triggers, kept and refined:**

| Client's idea | Verdict | Refinement |
|---------------|---------|------------|
| On login | ✅ Keep | First login already does a full initial sync; subsequent logins should do a throttled background refresh. |
| On app resume | ✅ Keep | But **debounce** it — `resumed` fires for trivial reasons (dismissing a dialog, the app switcher). Only refresh if it's been "a while". |
| On clicking into a block | ✅ Keep | Make it a **scoped** refresh of that block's assets, throttled per-block. |
| If not minimised for 1 hour | ✅ Keep, reframed | This is the **freshness window** (the throttle), plus an optional **foreground heartbeat** for long sessions. |

Everything below expands these into a concrete, testable policy.

---

## 1. Principles (why the cache changes the rules)

BlockPro is **offline-first**: the SQLite cache is the single source of truth the
UI renders from, and the network only *refreshes that cache in the background*
(see the companion report). That changes what an "update check" is for:

- **Freshness is a background concern, never a blocker.** Screens already render
  instantly from cache. An update check runs *behind* the visible UI and quietly
  swaps in new rows via the reactive Drift streams. The user should never see a
  spinner gating content because of a freshness check.
- **This is "stale-while-revalidate".** Show cached data immediately → check for
  updates in the background → reconcile when the response lands. The app already
  does exactly this on screen mount; the goal here is to make *when* it revalidates
  deliberate instead of "every time."
- **Cheapest correct check wins.** Prefer a small "what changed?" probe over
  re-downloading everything. BlockPro already does this for checklists
  (incremental via `checklistLastModified`); assets and buildings currently do
  not (they always full-refetch). See §6.
- **Writes are already handled separately.** Completed inspections flush through
  the durable **outbox drainer**, which has its own triggers (launch, resume,
  network-regained). This document is about the **read/refresh** path. Keep the
  two paths conceptually separate but note they share the same lifecycle hooks.

---

## 2. The mobile app lifecycle (what actually fires)

Flutter surfaces lifecycle transitions through
`WidgetsBindingObserver.didChangeAppLifecycleState`. The app already observes this
in [`main.dart`](../lib/main.dart#L82) (currently only to drain the outbox).

| State | Meaning | Use for freshness? |
|-------|---------|--------------------|
| `resumed` | Visible & receiving input (foreground) | **Yes** — primary "came back" signal, but debounce (see below). |
| `inactive` | Transitioning / not receiving input (call, app switcher, system dialog, iOS slide-over) | No — too noisy; fires constantly. |
| `hidden` | All views hidden; emitted just before `paused` (Flutter 3.13+, cross-platform) | **Yes** — clean "going to background" signal: record the timestamp here. |
| `paused` | Backgrounded, not rendering | Use as the background marker if you also support older behaviour. |
| `detached` | Engine alive but no view; app shutting down | No. |

### The `resumed` trap

`resumed` is **not** a reliable "user opened the app after a long time" signal. It
also fires when the user:

- dismisses a permission prompt, share sheet, or system dialog,
- returns from the app switcher without actually leaving,
- pulls down and dismisses the notification shade / control centre,
- (iOS) finishes a slide-over interaction.

Naively syncing on every `resumed` causes a **sync storm** — many redundant calls
in quick succession. The fix is the freshness gate (§3): on resume, only refresh
if enough time has elapsed since the last successful check.

**Implementation note:** record a `backgroundedAt` timestamp when entering
`hidden`/`paused`, and on `resumed` compute `now - backgroundedAt`. A real return
from background (e.g. > 60s away) is meaningfully different from a 2-second dialog
dismissal, and you can branch on it.

---

## 3. The freshness gate (the "one hour" idea, done right)

Route **every** refresh trigger through one shared gate. A trigger *requests* a
refresh; the gate decides whether it actually runs.

Two distinct time concepts — don't conflate them:

- **Minimum interval (throttle / debounce):** "Don't refresh the same scope more
  than once per *N* minutes." Prevents storms from chatty triggers (resume,
  re-entering a screen). This is what stops the `resumed` trap.
- **Maximum staleness (freshness window):** "If the cache is older than *T*, it's
  stale — refresh on the next opportunity." This is the client's "one hour."

Persist a **`lastSyncedAt` per scope** so the gate survives app restarts:

- The rows already carry a per-row `lastSyncedAt` (assets, buildings, etc.).
- Add a small set of **scope-level** markers in `SharedPreferences` (survives the
  DB wipe on manual refresh / schema upgrade):
  - `lastFullSyncAt` — last whole-estate refresh.
  - `lastBlockSyncAt:<blockId>` — last refresh of one block's assets.

Suggested windows (tune with the client against how often Bubble data actually
changes):

| Scope | Min interval (throttle) | Staleness window | Rationale |
|-------|------------------------|------------------|-----------|
| Full estate (buildings + assets) | 15 min | 1–4 hours | Heavy; rarely needs to be minute-fresh. The client's 1 hour fits here. |
| Single block's assets | 2–5 min | 30–60 min | Cheap, scoped, user is actively looking at it. |
| Single checklist | — | already incremental | Guarded by `checklistLastModified`; refetches only on real change. |

Gate logic (pseudocode):

```
bool shouldRefresh(scope) {
  final last = lastSyncedAt(scope);
  if (last == null) return true;                 // never synced
  if (now - last < minInterval(scope)) return false; // throttled
  return true;                                    // within reach, go
}
```

A **manual pull-to-refresh always bypasses the gate** — explicit user intent
overrides throttling (but still respect connectivity).

---

## 4. The trigger matrix (the core deliverable)

Each row is an *event*; the *action* is always "request a refresh for this scope,
subject to the gate (§3) and connectivity (§5)."

| # | Trigger | Scope | Gate applies? | Notes |
|---|---------|-------|---------------|-------|
| 1 | **Cold start / first login** | Full | No (forced) | Already handled: `needsInitialSyncProvider` → full background `syncAll` from the Blocks list (per-building loading bars) when the DB is empty. |
| 2 | **Subsequent login (token still valid)** | Full | Yes | Background refresh after auth; don't block the home screen on it. |
| 3 | **App resumed from background** | Full | Yes (+ debounce) | Only if `now - backgroundedAt` is non-trivial *and* the full-sync gate allows. This is where the freshness window earns its keep. |
| 4 | **Open the Blocks list (home)** | Full (throttled) | Yes | Refresh the estate in the background; the list keeps showing cache meanwhile. |
| 5 | **Click into a block** | That block's assets | Yes (per-block) | Scoped refresh — *not* a full sync. Today this fires on **every** screen mount; add the per-block throttle. |
| 6 | **Open an asset's checklist** | That checklist | Incremental | Already correct — skips the call when `checklistLastModified` is unchanged. |
| 7 | **Network regained (offline → online)** | Full (throttled) | Yes | Mirror the outbox's `hasNetworkProvider` listener: when connectivity returns, refresh reads too (not just flush writes). |
| 8 | **Pull-to-refresh (manual)** | Whatever screen | **No** (forced) | Explicit intent. Also the user's escape hatch when something looks stale. |
| 9 | **After submitting an inspection** | Affected asset/block | n/a | The completion response already writes back authoritative due/yellow dates; no separate read needed. |
| 10 | **Foreground heartbeat (optional)** | Full (throttled) | Yes | A periodic timer (e.g. every 30–60 min) so a phone left open all day on one screen still goes stale-then-fresh. Covers the "open but never minimised" case the client raised. |

Triggers 1, 4, 5, 6, 7, 8 mostly exist today; the work is to **route them through
the gate**, **scope #5 correctly**, and **add #2, #3, #10**.

---

## 5. Connectivity & resource awareness

- **Never check when offline.** Skip the call when `hasNetworkProvider` /
  `isOfflineProvider` reports no network — a failed fetch is silently swallowed
  today, so an offline check is wasted work and a wasted wake-up. The gate should
  short-circuit on no-network.
- **Refresh on reconnect.** Extend the existing offline→online listener (which
  today only drains the outbox, [`outbox_drain_provider.dart`](../lib/providers/outbox_drain_provider.dart#L46))
  to also request a throttled read-refresh.
- **Coalesce overlapping triggers.** Resume + network-regained can fire together.
  Use single-flight per scope (the outbox drainer already models this with its
  `_draining` flag) so two triggers don't launch two identical syncs.
- **Be light on battery & mobile data.** A full estate sync is several calls plus
  every changed checklist. The throttle is the main lever; optionally prefer
  Wi-Fi for the *full* sync and let scoped per-block refreshes run on cellular
  (they're small). Avoid background polling timers while the app is *backgrounded*
  (see §7).

---

## 6. Backend support: a cheap "what changed?" probe

The biggest efficiency win is **not** asking more often — it's asking *cheaper*.

Today, `app_fetchbuildings` and `app_fetch_all_assets` **always return full
payloads**; only checklists are incremental. So any "is the data out of date?"
check currently costs a full download to answer.

**Recommended:** add a lightweight endpoint that returns *only* change markers,
not data — e.g.:

```
GET app_changes_since?since=<timestamp>
→ { blocks_changed: ["id1", ...], assets_changed_per_block: {...}, server_time }
```

or, minimally, a per-block "assets last modified" max timestamp the app can
compare against its cached `assetLastModified` (which it already stores but does
**not** currently use to skip the call). Then the flow becomes:

```
cheap probe → nothing changed?  → done (one tiny call)
            → something changed? → refresh only the changed scopes
```

This makes frequent checks essentially free and lets you *tighten* the windows in
§3 without cost. Until such an endpoint exists, the throttle windows are doing the
work of keeping traffic sane.

---

## 7. Optional: background refresh (proactive, while minimised)

Everything above is **foreground/opportunistic** — the app refreshes when the user
is (or just became) present. That covers the client's cases and is the right
default.

If the client later wants data to be *already fresh* the instant the app opens,
the OS-level background schedulers are the tool:

- **iOS:** `BGAppRefreshTask` (BGTaskScheduler) — the OS grants short, batched
  windows on its own schedule; you cannot guarantee timing.
- **Android:** `WorkManager` periodic work (min 15-minute interval).
- Flutter packages such as `workmanager` wrap both.

Caveats: limited frequency, OS-controlled, extra battery, and more moving parts.
Treat this as a **phase-2 enhancement**, not part of the core policy — the
foreground triggers already deliver fresh data by the time the user does anything.

---

## 8. Edge cases & pitfalls

- **Sync storm on resume** — the `resumed` trap. Solved by the debounce + gate
  (§2, §3). This is the single most important refinement to the client's plan.
- **Re-entering a screen repeatedly** — today opening a block syncs *every* mount
  ([`assets_provider.dart`](../lib/providers/assets_provider.dart#L70)). With the
  per-block throttle, rapid back-and-forth navigation makes at most one call per
  window.
- **Token expiry mid-session** — a refresh that 401s should route to re-login, not
  silently no-op. (Currently fetch failures are swallowed; an auth failure
  deserves distinct handling.)
- **Manual full refresh wipes the DB first** — so it *must* bypass the gate and is
  inherently a forced full sync. Already the case; just don't let the gate
  interfere.
- **Clock skew** — freshness math uses the device clock. If the backend gains a
  `server_time` (§6), prefer server-relative comparisons for the change probe.
- **Don't gate writes.** The outbox flush must keep firing on launch/resume/
  reconnect regardless of the read-freshness gate — they're independent.

---

## 9. Summary

> **Many triggers, one gate, scoped checks, cheapest probe.**

1. Keep all four of the client's triggers — they map to real lifecycle moments.
2. Add a **shared freshness gate** (min-interval throttle + staleness window),
   persisted per scope; this *is* the "one hour" idea, applied uniformly.
3. **Debounce `resumed`** so trivial foreground returns don't cause sync storms.
4. **Scope** each check: clicking a block refreshes that block, not the estate.
5. Refresh on **reconnect**, never when **offline**, and **single-flight**
   overlapping triggers.
6. Push for a **lightweight "what changed?" endpoint** so checking often is cheap;
   until then, the throttle windows keep traffic reasonable.
7. Treat OS **background refresh** as an optional later enhancement.
