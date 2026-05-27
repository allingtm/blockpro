# Bubble API Usage

This document describes how the BlockPro Flutter app communicates with the Bubble.io backend API.

---

## Overview

| Item | Detail |
|------|--------|
| **Base URL** | Configured via the `BUBBLE_API_BASE_URL` env var (`.env` file). Currently points to the Bubble workflow API: `.../api/1.1/wf/` |
| **HTTP client** | Dart `http` package |
| **Auth method** | Bearer token in the `Authorization` header |
| **Config file** | `lib/core/config/api_config.dart` |
| **HTTP helpers** | `lib/repositories/api_repository.dart` — provides `authenticatedGet`, `authenticatedGetRaw`, and `authenticatedPost` |

All authenticated requests include these headers:

```
Authorization: Bearer <token>
Content-Type: application/json
```

---

## Endpoints

### 1. `login` — User Authentication

| | |
|---|---|
| **Path** | `login` |
| **Method** | POST |
| **Auth required** | No |
| **Source file** | `lib/repositories/auth_repository.dart` |

**When it's called:** User taps the login button on the login screen.

**Request body:**

```json
{
  "email": "<email>",
  "password": "<password>"
}
```

**Response:**

```json
{
  "status": "success",
  "response": {
    "token": "<bearer-token>",
    "user_id": "<user-id>",
    "expires": 86400
  }
}
```

**What happens next:**
- The bearer token is stored in-memory and persisted to `SharedPreferences`.
- Token expiry is calculated from the `expires` field (seconds from now).
- On app restart, the stored token is restored and checked for expiration. If expired, the user is logged out automatically.

---

### 2. `fetchbuildings` — Download Buildings

| | |
|---|---|
| **Path** | `fetchbuildings` |
| **Method** | GET |
| **Auth required** | Yes |
| **Source file** | `lib/repositories/sync_repository.dart` |

**When it's called:** Phase 1 of the initial sync after login. Also called on retry.

**Query params:** None.

**Response:** JSON array of building objects.

```json
[
  {
    "id": "abc123",
    "name": "Block A",
    "List of assets": ["asset1", "asset2"]
  }
]
```

**Parsed fields:**

| JSON key | Model field | Notes |
|----------|-------------|-------|
| `id` or `_id` | `Building.id` | |
| `name` or `Name` | `Building.name` | Falls back to `"Unnamed"` |
| `List of assets` | `Building.assetCount` | Length of array |

**What happens next:** Buildings are upserted into the local SQLite `buildings` table via `buildingsDao.upsertBuildings()`.

**Response format notes:** The parser (`parseBuildingsResponse`) handles three response shapes defensively:
1. A direct JSON array (expected)
2. A map with a `response` key containing the array
3. A JSON string that needs a second decode

---

### 3. `fetchassets` — Download Assets for a Building

| | |
|---|---|
| **Path** | `fetchassets` |
| **Method** | GET |
| **Auth required** | Yes |
| **Source file** | `lib/repositories/sync_repository.dart` |

**When it's called:** Phase 2 of initial sync — one call per building, sequentially.

**Query params:**

| Param | Value |
|-------|-------|
| `block_id` | The building ID |

**Response:** JSON array of asset objects.

```json
[
  {
    "assetId": "xyz789",
    "assetName": "Fire Extinguisher #1",
    "date_of_next_inspection": "2026-06-15",
    "date_of_previous_inspection": "2025-12-15",
    "interval_number_of_days": 182
  }
]
```

**Parsed fields:**

| JSON key | Model field | Notes |
|----------|-------------|-------|
| `assetId` or `id` | `Asset.id` | |
| `assetName` or `name` | `Asset.name` | Falls back to `"Unnamed"` |
| `date_of_next_inspection` | `Asset.nextInspection` | Parsed as `DateTime` |
| `date_of_previous_inspection` | `Asset.previousInspection` | Parsed as `DateTime` |
| `interval_number_of_days` | `Asset.intervalDays` | Integer |

**What happens next:** Assets are upserted into the local SQLite `assets` table, linked to their building via `buildingId`.

---

### 4. `fetchquestions` — Download Question Templates

| | |
|---|---|
| **Path** | `fetchquestions` |
| **Method** | GET |
| **Auth required** | Yes |
| **Source file** | `lib/repositories/sync_repository.dart` |

**When it's called:** Not currently invoked during the initial sync flow. The method `syncQuestionsForAsset()` exists but is not called. Checklists (endpoint 5) are used instead.

**Query params:**

| Param | Value |
|-------|-------|
| `asset_id` | The asset ID |

**Response:** JSON array of question objects.

```json
[
  {
    "question_id": "q001",
    "question_text": "Is the pressure gauge in the green zone?",
    "answer_option": "Yes/no",
    "photo_requirement": "Always"
  }
]
```

**Parsed fields:** Same as checklist (see below). Stored with `source = 'template'` in the questions table.

---

### 5. `fetchchecklist` — Download Checklist for an Asset

| | |
|---|---|
| **Path** | `fetchchecklist` |
| **Method** | GET |
| **Auth required** | Yes |
| **Source file** | `lib/repositories/sync_repository.dart` |

**When it's called:**
1. **Initial sync (Phase 3)** — One call per asset, run in parallel with a max concurrency of 5.
2. **Background sync** — Triggered when the inspection screen or asset detail loads, via `checklistStreamProvider` and `checklistCountProvider` in `lib/providers/checklist_provider.dart`. These are fire-and-forget calls that refresh local data in the background.

**Query params:**

| Param | Value |
|-------|-------|
| `asset_id` | The asset ID |

**Response:** Nested envelope with a malformed checklist string.

```json
{
  "status": "success",
  "response": {
    "checklist": "{\"question_id\":\"q1\",\"question_text\":\"...\",\"answer_option\":\"Yes/no\",\"photo_requirement\":\"Always\"},{\"question_id\":\"q2\",...}"
  }
}
```

**Parsed fields:**

| JSON key | Model field | Notes |
|----------|-------------|-------|
| `question_id` or `id` or `_id` | `Question.id` | |
| `question_text` or `questionText` or `Question text` | `Question.questionText` | |
| `answer_option` or `answerOption` or `Answer option` | `Question.answerOption` | Enum: `Yes/no`, `Satisfactory/unsatisfactory`, `Yes/no/n/a` |
| `photo_requirement` or `photoRequirement` or `Photo requirement` | `Question.photoRequirement` | Enum: `Always`, `Only when no/unsatisfactory` |

**What happens next:** Questions are upserted into the local SQLite `questions` table with `source = 'checklist'`.

**Response format notes:** The parser (`parseChecklistResponse`) handles several quirks:
- Unwraps the `{ response: { checklist: "..." } }` envelope
- Replaces smart/curly quotes (`\u201C`, `\u201D`, etc.) with straight quotes
- Wraps concatenated JSON objects `{...},{...}` in array brackets `[{...},{...}]`
- Handles double-encoded strings

---

### 6. `upload-image` — Upload Inspection Photo

| | |
|---|---|
| **Path** | `upload-image` |
| **Method** | POST |
| **Auth required** | Yes |
| **Source file** | `lib/providers/inspection_provider.dart` |

**When it's called:** During inspection submission — before the final inspection payload is sent. Each photo is uploaded individually.

**Request body:**

```json
{
  "base64": "<base64-encoded-image-bytes>",
  "asset_id": "<asset-id>",
  "filename": "photo_2026-03-01.jpg"
}
```

**Response:**

```json
{
  "response": {
    "image_id": "img_abc123"
  }
}
```

**What happens next:**
- The returned `image_id` is collected into a list.
- If upload fails, the error is logged but submission continues (photos are best-effort).
- All collected `image_id` values are included in the `completed-inspection` payload.

---

### 7. `completed-inspection` — Submit Completed Inspection

| | |
|---|---|
| **Path** | `completed-inspection` |
| **Method** | POST |
| **Auth required** | Yes |
| **Source file** | `lib/providers/inspection_provider.dart` |

**When it's called:** When the user taps "Submit" on the inspection screen, after all photos have been uploaded.

**Request body:**

```json
{
  "asset_id": "<asset-id>",
  "answers": [
    {
      "question_text": "Is the pressure gauge in the green zone?",
      "answer_text": "Yes"
    },
    {
      "question_text": "Is the safety pin intact?",
      "answer_text": "No"
    }
  ],
  "photo_ids": ["img_abc123", "img_def456"]
}
```

- `photo_ids` is only included when at least one photo was successfully uploaded.
- `answer_text` is the selected label (e.g., `"Yes"`, `"No"`, `"Satisfactory"`, `"N/A"`), or an empty string if no answer was selected.

**Validation (client-side, before submission):**
- Every question with answer options must have a selected answer.
- If a photo is required (based on `PhotoRequirement` rules and the selected answer), at least one photo must be attached.

---

## Data Sync Flow

### Initial Sync (after login)

Orchestrated by `SyncRepository.syncAll()`, driven by `InitialSyncNotifier`.

```
Login
  |
  v
Phase 1: fetchbuildings  ──>  upsert into buildings table
  |
  v
Phase 2: fetchassets      ──>  one call per building (sequential)
  |                             upsert into assets table
  v
Phase 3: fetchchecklist   ──>  one call per asset (parallel, max 5)
                                upsert into questions table
```

The initial sync screen (`lib/screens/initial_sync_screen.dart`) shows progress through each phase. A retry button is available if any phase fails.

### Background Sync (on-demand)

When the user navigates to an asset detail or inspection screen, `checklistStreamProvider` fires a background call to `fetchchecklist` for that asset. This refreshes the local data without blocking the UI.

### Data Storage

All synced data is stored locally in a SQLite database (via Drift ORM). The app reads from the local database for all UI display, using the API only to populate/refresh the local cache.

---

## Connectivity & Offline Handling

**Source file:** `lib/services/connectivity_service.dart`

- Combines hardware connectivity checks (`connectivity_plus` package) with API success/failure signals.
- `reportApiSuccess()` / `reportApiFailure()` are called after every API request by `ApiRepository`.
- Connectivity changes are debounced (1 second) to prevent UI flicker.
- The app tracks both network interface availability and API reachability.

---

## Key Files

| File | Purpose |
|------|---------|
| `lib/core/config/api_config.dart` | Base URL configuration from `.env` |
| `lib/repositories/api_repository.dart` | HTTP client with authenticated GET/POST helpers |
| `lib/repositories/auth_repository.dart` | Login, token storage, session management |
| `lib/repositories/sync_repository.dart` | Orchestrates all data sync (buildings, assets, checklists) |
| `lib/utils/api_parsers.dart` | Response parsing & normalization for all data endpoints |
| `lib/providers/inspection_provider.dart` | Photo upload & inspection submission |
| `lib/providers/initial_sync_provider.dart` | Initial sync UI state machine |
| `lib/providers/checklist_provider.dart` | Background checklist sync & streaming |
| `lib/services/connectivity_service.dart` | Online/offline detection |
| `lib/models/building.dart` | Building model & JSON parsing |
| `lib/models/asset.dart` | Asset model & JSON parsing |
| `lib/models/question.dart` | Question model, answer options & photo requirement enums |
