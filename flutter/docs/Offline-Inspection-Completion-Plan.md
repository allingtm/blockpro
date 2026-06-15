# Implementation Plan: Complete Inspections Offline

> Goal: let a user **Complete** an inspection while offline. The completion is
> saved durably on-device and **auto-submits to the Bubble backend when
> connectivity returns**. Today, completing offline fails with an error and
> nothing is queued ([`inspection_provider.dart:284-290`](../lib/providers/inspection_provider.dart#L284-L290)).

> **Decisions locked in:** (1) logout while completions are pending → **warn +
> discard**; (2) **no Bubble/backend changes for now** — the client ships the
> conservative, zero-silent-duplicate behaviour (§5), with the `submission_id`
> dedup left as a deferred future drop-in (§7); (3) an asset with a queued
> completion **remains re-openable** — re-opening loads the queued answers/photos
> to review or amend, and re-completing **supersedes** the queued entry (§4
> Phase 3/5, §6).

## 1. Problem & the dominating constraint

`InspectionNotifier.submit()` uploads photos, POSTs `app_completed-inspection`,
then optimistically marks the asset completed. On a `SocketException` /
`ClientException` it just sets `submitError` — the completed inspection is **not
persisted anywhere**, so the user's work is stuck on-screen behind an error.

The hard constraint that shapes the whole design: **the local SQLite DB is a
disposable cache.**

- `onUpgrade` **drops every table** ([`database.dart:60-72`](../lib/database/database.dart#L60-L72)).
- `clearAllData()` deletes every row, called on **logout** ([`main.dart:32`](../lib/main.dart#L32))
  and on **every manual refresh** ([`refresh_sync_provider.dart:95/155/188`](../lib/providers/refresh_sync_provider.dart#L95)).

Therefore a queued completion **cannot** live in Drift — not in the draft
tables, and not in the unused `CompletedInspectionsTable` scaffolding. A manual
refresh between "save offline" and "back online" would silently wipe it.

Two facts make the rest tractable:
- **`DraftPhotoStore` already proves** the filesystem-under-`<appDocs>` pattern
  survives all wipe paths ([`draft_photo_store.dart`](../lib/utils/draft_photo_store.dart)) — only DB rows are lost, files persist.
- A reliable, debounced **"back online" edge** already exists via
  [`isOfflineProvider`](../lib/providers/connectivity_provider.dart) (hardware + API-reachability, `distinct().debounceTime(1s)`).

## 2. Chosen approach — file-backed durable outbox

Store each queued completion as a **self-contained JSON entry** in a manifest
file, plus a per-submission photo folder, both under `<appDocs>/outbox/` and
**never** registered in Drift. The queue's normal depth is 1, so a JSON manifest
is the smallest thing that is provably untouched by `clearAllData()` / migration.

This was selected over two alternatives:
- *Draft-as-outbox* (smallest diff) — **rejected**: its payload (answers +
  `questionId→questionText`) lives in Drift tables a refresh wipes, producing a
  half-empty submission (silent corruption).
- *Second Drift DB for the outbox* — survives wipes, but adds a whole second
  `@DriftDatabase`, generated code, and migration discipline for a queue of
  depth ~1. Too heavy.

We graft their best ideas in: the **single shared replay function** (from
draft-as-outbox) and **per-photo upload memoization + an explicit status state
machine** (from the second-DB design).

## 3. Data model (all outside Drift)

**Manifest** — `<appDocs>/outbox/outbox.json`, written atomically (`*.tmp` then
rename) so a kill mid-write can't corrupt it. Single source of truth.

```jsonc
// OutboxEntry
{
  "submissionId": "uuid-v4",        // client idempotency key; generated ONCE at
                                    // enqueue (Random.secure), reused on EVERY retry
  "uid": "<authRepo.uid>",          // owning user — prevents cross-user drain
  "assetId": "<id>",
  "frequency": "7 Day(s)",          // for nextDueDate() optimistic due-date
  "checklistLastModified": "<ISO>", // for checklist-drift detection
  "answers": [ { "question": "<questionText>", "answer": "<text>" } ],
                                    // EXACT shape submit() builds today; questionText
                                    // is FROZEN here, not resolved from the wipeable
                                    // questions table at drain time
  "photos": [ { "localPath": "outbox/<submissionId>/0.jpg", "uploadedImageId": null } ],
                                    // uploadedImageId filled as each upload succeeds →
                                    // retries skip already-uploaded photos
  "status": "pending",              // pending | sending | needsReview | failed
  "attemptCount": 0,
  "createdAt": 0,                   // epoch ms; FIFO drain order
  "lastAttemptAt": null,
  "lastError": null
}
```

**Photos** — `<appDocs>/outbox/<submissionId>/<n>.jpg`, copied from the
image_picker temp path at **enqueue** time via a new `CompletionPhotoStore`
(mirror of `DraftPhotoStore`, but keyed by `submissionId`, **not** `assetId` —
so reopening the same asset's draft can never overwrite a queued completion's
photos).

**Optimistic status** — `assetsDao.markCompleted()` still writes to the
disposable DB at enqueue so the card turns green instantly. Because that write
is wiped by refresh/logout, the asset-card "queued/completed" indicator is
**also derived from the durable outbox** (`pendingOutboxAssetsProvider`), so the
green/queued state survives a cache wipe until the drain confirms.

**Drift cleanup** — delete the dead, never-used `CompletedInspectionsTable`,
`InspectionAnswersTable`, `InspectionsDao` so nobody mistakes them for a safe
outbox. Bump `schemaVersion` 5→6 (the existing drop-all `onUpgrade` handles it).

## 4. Implementation phases

### Phase 0 — Remove the dead-scaffolding trap (~0.5d)
- Drop `CompletedInspectionsTable` / `InspectionAnswersTable` from the
  `@DriftDatabase` tables list and `InspectionsDao` from daos
  ([`database.dart:32-33,42`](../lib/database/database.dart#L32-L42)); remove the imports.
- Delete `completed_inspections_table.dart`, `inspection_answers_table.dart`,
  `inspections_dao.dart`.
- Bump `schemaVersion` 5→6; run `build_runner`.

### Phase 1 — Durable file-backed outbox store + model (~1d, trickiest correctness)
- **`lib/models/outbox_entry.dart`** — `OutboxEntry` + `OutboxPhoto` immutable
  classes (`toJson`/`fromJson`/`copyWith`), `OutboxStatus` enum, and a
  `_genSubmissionId()` (v4 UUID from `Random.secure` — **no new pub dependency**;
  `uuid` isn't in pubspec).
- **`lib/utils/completion_photo_store.dart`** — mirror of `DraftPhotoStore`
  rooted at `<appDocs>/outbox/<submissionId>/`: `persistPhoto`,
  `deleteSubmissionPhotos`, `deleteAllPhotos` (logout), `listSubmissionDirs`
  (orphan sweep).
- **`lib/utils/outbox_store.dart`** — manages `outbox.json`. `readAll`,
  `enqueue`, `update` (replace by `submissionId`), `remove`, `clearAll`. **All
  mutations go through one Completer-based async mutex** (`_withLock`) so a
  drain's per-photo `update()` can't race an `enqueue` and clobber the array.
  Atomic writes (tmp + rename). Tolerate missing/corrupt file → `[]`. **Startup
  integrity pass**: drop entries whose photos are missing; delete
  `<submissionId>/` folders with no manifest entry.

### Phase 2 — Providers + shared replay function (~1–1.5d)
- **`lib/providers/outbox_provider.dart`** — `outboxStoreProvider`,
  `completionPhotoStoreProvider`, `outboxEntriesProvider` (**non-autoDispose**
  `StateNotifier`, rehydrated from disk; file is source of truth, memory is a
  cache written **before** memory updates), plus derived `pendingCountProvider`,
  `pendingOutboxAssetsProvider` (drives the asset chip + survives cache wipe),
  `assetOutboxStatusProvider`, and `buildingsWithQueuedProvider` (mirrors
  [`buildingsWithDraftsProvider`](../lib/providers/drafts_provider.dart#L40)).
- **Extract `replayCompletion(...)`** from the body of `submit()`
  ([`inspection_provider.dart:216-283`](../lib/providers/inspection_provider.dart#L216-L283)) into one function used by **both** the live tap and the drain:
  upload only photos with `uploadedImageId == null` (persist each `image_id`
  **immediately**), then POST `app_completed-inspection` with the stored
  `submissionId`; on 200 run cleanup + `outbox.remove`.
- **`lib/services/outbox_drainer.dart`** — `drain()` with **single-flight**
  (`bool _draining` set **synchronously before any `await`**, + `_rerunRequested`
  for "came online mid-send"). See §5.
- **`lib/providers/outbox_drain_provider.dart`** — `outboxDrainerProvider` +
  `drainTriggerProvider` that `ref.listen(isOfflineProvider)` and drains on the
  **true→false edge**. Kept alive by a root widget.

### Phase 3 — Rewire `submit()` to enqueue-first + re-open/supersede (~1d)
- Rewrite `InspectionNotifier.submit()`: keep validation, then **always, before
  any network**: generate `submissionId`; copy every photo to durable storage
  via `CompletionPhotoStore`; build the answers payload + photo list; stamp
  `uid` + `checklistLastModified`; `enqueue` the `OutboxEntry(status: pending)`.
- Optimistic local update at enqueue: `markCompleted(...)`; delete the now-
  redundant draft + draft photos.
- Add `bool isQueued` to `InspectionState`; on completion set
  `isComplete = true, isQueued = <current isOffline>`; **fire-and-forget**
  `drainer.drain()` (don't await). Online → sends ~instantly; offline → leaves
  it pending.
- Inject the new stores/drainer/`isOffline` into the notifier provider
  ([`inspection_provider.dart:299-316`](../lib/providers/inspection_provider.dart#L299-L316)).
- **Re-open (decision 3):** when an asset already has a queued entry, the
  inspection screen loads answers/photos **from that outbox entry** (not the
  deleted draft). Add this resolution to the form load in
  [`inspection_screen.dart:61-91`](../lib/screens/inspection_screen.dart#L61-L91): prefer a queued entry → else draft → else empty. The
  screen header shows a "Queued — not yet submitted" banner so the user knows
  they're editing a completion that hasn't reached the server.
- **Supersede-on-recomplete:** if the user completes again while a **non-sending**
  entry exists for that asset (`pending` / `failed` / `needsReview`), `enqueue`
  replaces it — `remove()` the old entry + its photo folder, then enqueue a fresh
  entry with a **new `submissionId`** (the amended answers fully replace the old
  ones). One queued completion per asset. If the entry is actively
  `sending`, disable Complete with a "submission in progress" message rather than
  racing the drain. (Rare edge: if the superseded entry had secretly committed
  server-side on a lost ack, the new submissionId produces a second record — an
  accepted, low-probability cost of letting the user redo an unconfirmed
  completion.)

### Phase 4 — Triggers, lifecycle, logout & refresh guards (~0.5–1d)
- **Startup**: in `main.dart`, after `authRepo.initialize()`, run
  `recoverStale() + drain()` once (bails internally if offline).
- **App resume**: add a `WidgetsBindingObserver` (none exists today) — make
  `MainApp` stateful (or a small `RootLifecycle` wrapper); on
  `AppLifecycleState.resumed` call `drain()`. Watch `drainTriggerProvider` in a
  root widget so the connectivity-edge listener stays alive.
- **Logout = warn + discard (decision 1):** when `pendingCount > 0`, show a
  confirm dialog ("You have N completed inspection(s) that haven't been uploaded
  yet. Logging out will discard them. Continue?"). On confirm, make `onSignOut`
  **awaited** — change [`auth_repository.dart:204`](../lib/repositories/auth_repository.dart#L204) from fire-and-forget to
  `await onSignOut?.call()`; the callback purges `outboxStore.clearAll()` +
  `CompletionPhotoStore.deleteAllPhotos()` **before** `database.clearAllData()`.
  uid-stamping + the drainer's uid check are defence-in-depth against a kill
  mid-purge auto-submitting under the next user. (No silent loss — the warning is
  the contract.)
- **Manual refresh**: `clearAllData()` already leaves the file outbox intact, so
  queued completions survive with no change. Optionally `drain()` after a
  successful refresh, and re-assert optimistic `markCompleted` for still-queued
  assets so the card doesn't briefly flip back to overdue.

### Phase 5 — UI: messaging, chips, pending count, manual retry (~0.5–1d)
- `inspection_screen.dart` `ref.listen` ([L175-190](../lib/screens/inspection_screen.dart#L175-L190)): branch on `isQueued` —
  queued → snackbar *"Saved — it will be submitted automatically when you're
  back online"*; else the existing *"Inspection submitted successfully"*. Never
  say "submitted" for a queued entry.
- New **`lib/widgets/common/queued_chip.dart`** — `QueuedChip` (amber),
  `SubmittingChip` (blue), `FailedChip` (red, tappable "Retry"), `ReviewChip`
  (red, "Needs review") — visual siblings of [`DraftChip`](../lib/widgets/common/draft_chip.dart).
- `block_inspections_screen.dart` `_InspectionCard` ([L102](../lib/screens/block_inspections_screen.dart#L102)): render a status
  chip from `assetOutboxStatusProvider` next to the existing `DraftChip`; a
  queued asset stays **green** and shows the Queued chip.
- `blockpro_app_bar.dart`: add a global pending-uploads indicator (cloud-upload
  icon + `pendingCountProvider`) next to the existing `cloud_off`
  [`OfflineIndicator`](../lib/widgets/common/offline_indicator.dart).
- **Manual retry**: `FailedChip` tap → re-queue (failed→pending) + `drain()`;
  `ReviewChip` → confirm dialog *"This may have already been submitted — re-send
  anyway?"* before resetting to pending.

## 5. Idempotency & the drain (the correctness core)

Bubble has **no server idempotency key** — each POST creates a new record,
each upload creates a new image, and question records are created *async after*
the response. So idempotency is layered:

1. **Stable `submissionId`** generated once at enqueue and reused on every retry.
   For now it's **local-only** — it names the photo folder, drives supersede, and
   keys single-flight/dedup of local enqueues. It is *not* sent to Bubble yet
   (see the deferred note below); when §7 happens it becomes the server dedup key
   with a one-line change.
2. **Per-photo memoization** — persist each returned `image_id` the instant the
   upload returns; a retry uploads only photos where `uploadedImageId == null`.
   (Today's loop re-uploads *everything* on retry.)
3. **Single-flight serial drain** — `_draining` set synchronously before any
   `await`; FIFO, one completion fully finishes before the next.
4. **Status-gated retry** — persist `status: 'sending'` **before** the POST. On
   restart, an entry stuck in `'sending'` (outcome unknown) → `'needsReview'`,
   never blind-resent.
5. **Error classification** (conservative — **no backend dedup**, decision 2) —
   - `SocketException` / `ClientException` = **confirmed no-delivery** → revert
     to `pending`, stop the loop, retry on next trigger. (Safe to auto-retry —
     nothing committed server-side.)
   - non-200 `Exception('API error: <code>')` = **ambiguous** (the Bubble action
     may have run) → `'needsReview'`, *not* auto-resent.
   - transient non-network error past an attempt cap → `'failed'` (tappable
     Retry chip; never silent infinite retry).

**Residual risk (accepted for now):** an ack lost **after** the server committed
→ a resend would duplicate, so we conservatively route ambiguous outcomes to
`'needsReview'` for the user to decide rather than auto-resending. This trades a
rare manual re-confirm for zero silent duplicates. The client still **generates
and stores a `submissionId`** per entry (it drives photo-folder naming, supersede,
and single-flight) — so the §7 backend dedup remains a clean drop-in later that
would let `'needsReview'` relax to auto-resend, with **no app rearchitecture**.

> Sending `submission_id`/`index` in the request bodies is deferred with §7. Since
> we're not touching Bubble now, only add those fields once a quick check confirms
> the workflow ignores unknown fields (it normally does) — it's a one-line change
> when the backend work happens.

## 6. Edge cases handled

| Case | Handling |
|---|---|
| App killed between enqueue and first POST | Entry persists `pending` with durable photos; startup drain picks it up. No loss. |
| App killed after upload but before persisting its `image_id` | One duplicate image on retry (minimized by persisting `image_id` immediately after each upload). Fully closed only by the deferred §7 photo dedup. |
| App killed after 200 but before cleanup | Entry stays `'sending'` → startup `recoverStale()` → `'needsReview'` (no blind resend); user re-confirms. |
| Manual refresh while queued | File outbox untouched; card stays green/Queued via `pendingOutboxAssetsProvider`. |
| Schema bump while queued | Outbox file survives (not a Drift table); drain replays from file. |
| Lost ack after server committed | Ambiguous → `'needsReview'` (not auto-resent), so no silent duplicate. Closing this fully needs the deferred §7 backend dedup. |
| Logout with pending | Warn user (N pending), then on confirm `clearAll()` + `deleteAllPhotos()` **before** `clearAllData()`; uid checks block cross-user submit. |
| Connectivity flaps inside the 1s debounce | Covered by extra triggers (startup, resume, post-refresh, manual) + `_rerunRequested`. |
| Checklist changed server-side before drain | `questionText` frozen at enqueue; `checklistLastModified` stamped; newer server checklist → `'needsReview'` with a re-confirm path. |
| Concurrent manifest mutations | One async mutex + atomic tmp+rename → no torn file / lost array. |
| Poison entry / orphan photo folders | `'failed'`/`'needsReview'` chips + startup orphan sweep. |
| Reopen an asset that's already queued (decision 3) | Screen loads answers/photos **from the outbox entry** + shows a "Queued — not yet submitted" banner; re-completing a non-`sending` entry **supersedes** it (remove old + photos, enqueue fresh with new `submissionId`). Photos namespaced by `submissionId` so they never collide. |

## 7. Backend dedup change — DEFERRED (future, recommended)

> **Decision 2: not now.** No Bubble changes for this feature. The client ships
> the conservative behaviour in §5 (zero silent duplicates; ambiguous outcomes go
> to `'needsReview'`). This section documents the future drop-in for when there's
> appetite to close the last residual duplicate window.

The **only** way to fully eliminate the residual "ack lost after commit"
duplicate is a Bubble.io workflow change (no-code, in the Bubble editor):

1. **`app_completed-inspection`** — accept an optional `submission_id` and, at the
   start of the workflow, search for an existing Completed inspection with it:
   if found → return it (don't create a new record, don't re-schedule
   `app_create-completed-question`); else store `submission_id` on the new record
   and proceed as today. Return `submission_id` in the response.
2. **`app_upload-image_Adam`** — accept optional `submission_id` + per-photo
   `index`; dedupe images on `(asset_id, submission_id, index)`, returning the
   existing `image_id` on a duplicate.

Because the client already generates and stores `submissionId` per entry, adopting
this later is a **drop-in**: start sending the fields and relax §5's
`'needsReview'` recovery to auto-resend — **no app rearchitecture**. When that
day comes, document it alongside [`app_completed-inspection.md`](app_completed-inspection.md).

## 8. Resolved & remaining decisions

**Resolved:** logout = **warn + discard** (1); **no backend changes now** —
backend dedup deferred to §7 (2); queued assets are **re-openable** with
supersede-on-recomplete (3).

**Still open (don't block Phase 0–2; can settle during Phase 3–5):**
1. **Retry policy for `'failed'`** — fixed attempt cap + manual retry (current
   plan), or add timed exponential backoff for unattended retry?
2. **Checklist-drift depth** — is routing a stale-checklist entry to
   `'needsReview'` + manual re-confirm enough, or is a richer re-map flow for
   renamed/removed questions wanted?
3. **`'needsReview'` UX volume** — with no backend dedup, ambiguous outcomes
   (rare, but real on flaky networks) need a manual re-confirm. Confirm that's an
   acceptable field workflow, or whether to suppress the prompt and just retry
   (accepting rare duplicates) — the inverse tradeoff.

## 9. Testing

- **Unit** — OutboxStore round-trip; atomic write survives simulated kill;
  `_withLock` serializes concurrent enqueue+update; corrupt file → `[]`.
  OutboxEntry JSON round-trip + stable `submissionId`. CompletionPhotoStore
  keyed by `submissionId`. `replayCompletion` skips memoized photos + sends
  `submission_id`. Drainer single-flight; SocketException→pending+stop;
  non-200→needsReview; stale `sending`→needsReview; uid mismatch skipped.
- **Widget** — offline submit enqueues, shows the "will send when online"
  snackbar, pops, card green; online submit drains immediately.
- **Integration** (`AppDatabase.forTesting`) — enqueue, run `clearAllData()`
  (logout/refresh), assert outbox + photos survive and drain replays; simulate a
  schema bump with a non-empty outbox.
- **Manual device** — (1) complete fully offline → snackbar + green + chips;
  (2) re-enable network → auto-drains, no server dupe; (3) kill mid-offline,
  relaunch online → startup drain submits; (4) logout with pending → warning;
  (5) manual refresh while queued → survives.

## 10. Effort

~**4–6 focused days** for one engineer. No new pub dependency. The optional
backend dedup is separate Bubble work, off the app critical path.
