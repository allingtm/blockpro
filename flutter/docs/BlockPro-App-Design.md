# BlockPro Flutter App — Design Document

**Version:** 1.0  
**Date:** 16 April 2026  
**Prepared by:** Marc Allington, Solve with Software Ltd

---

## 1. Purpose

BlockPro is an offline-first building inspection app. Users download their assigned buildings, assets, and checklists, then navigate the hierarchy to complete inspections — answering questions, attaching photos, and submitting results.

This document captures what has been built, what needs to change to align with the v2 API response structures (documented in `BlockPro-API-Spec-v2.md`), and what remains to be implemented.

---

## 2. Architecture Overview

```
┌─────────────────────────────────────────────────┐
│                   Screens (UI)                  │
│  Welcome → Login → InitialSync → Home           │
│  BuildingsList → BuildingDetail → AssetDetail    │
│  InspectionScreen                                │
└────────────────────┬────────────────────────────┘
                     │ Riverpod Providers
┌────────────────────┴────────────────────────────┐
│              State Management                    │
│  auth, buildings, assets, questions, checklist,  │
│  inspection, connectivity, initial_sync, theme   │
└────────────────────┬────────────────────────────┘
                     │
┌────────────────────┴────────────────────────────┐
│              Repositories                        │
│  AuthRepository, ApiRepository, SyncRepository   │
└────────┬───────────────────┬────────────────────┘
         │                   │
┌────────┴────────┐  ┌───────┴────────────────────┐
│  Bubble API     │  │  SQLite (Drift ORM)         │
│  (HTTP/JSON)    │  │  Buildings, Assets,          │
│                 │  │  Questions, Inspections,     │
│                 │  │  InspectionAnswers           │
└─────────────────┘  └────────────────────────────┘
```

**Key technologies:**
- **State management:** Riverpod 2.5
- **Routing:** GoRouter
- **Database:** Drift (SQLite ORM) with code generation
- **HTTP:** `http` package
- **Connectivity:** `connectivity_plus` + API reachability signals
- **Theming:** Flex Color Scheme (Material 3)

---

## 3. Offline-First Data Flow

### 3.1 Initial Sync (first login)

After authentication, the app downloads all data before showing the home screen:

```
Login → SyncRepository.syncAll() → Home
         ├── Phase 1: syncBuildings()
         ├── Phase 2: syncAssetsForBuilding() × N buildings
         └── Phase 3: syncChecklistForAsset() × N assets (max 5 concurrent)
```

Progress is displayed on `InitialSyncScreen` with step indicators.

### 3.2 Subsequent Access

Data is served from SQLite. Background syncs are triggered:
- **Buildings:** On `BuildingsList` mount (if DB is empty, sync first)
- **Assets:** On `BuildingDetailScreen` mount (always triggers sync)
- **Checklists:** On `AssetDetailScreen` / `InspectionScreen` watch (always triggers sync)

### 3.3 Offline Behaviour

- `ConnectivityService` combines hardware network status with API reachability
- `OfflineIndicator` widget shown in app bars when offline
- All list screens serve data from SQLite — the app is fully usable offline for reading
- Inspection submission requires connectivity (no offline queue yet)

---

## 4. Navigation Hierarchy

```
Buildings List
  └── Building Detail (assets list)
        └── Asset Detail
              └── Inspection Screen (checklist questions)
```

**Routes:**
| Path | Screen | Data Passed |
|------|--------|-------------|
| `/` | WelcomeScreen | — |
| `/login` | LoginScreen | — |
| `/initial-sync` | InitialSyncScreen | — |
| `/home` | HomeScreen (BuildingsList tab) | — |
| `/building/:id` | BuildingDetailScreen | building name |
| `/asset/:id` | AssetDetailScreen | Asset object |
| `/inspection/:id` | InspectionScreen | asset name |
| `/settings` | SettingsScreen | — |

---

## 5. Current Implementation Status

### 5.1 What Has Been Built

| Layer | Component | Status |
|-------|-----------|--------|
| **Auth** | Login flow, token persistence, auto-expiry | Done |
| **Database** | Buildings, Assets, Questions, CompletedInspections, InspectionAnswers tables | Done |
| **Sync** | Full sync pipeline (buildings → assets → checklists) with progress | Done |
| **UI — Buildings** | Paginated list, pull-to-refresh, empty state | Done |
| **UI — Assets** | Paginated list per building, overdue indicators | Done |
| **UI — Asset Detail** | Asset info card, "Start Inspection" button with question count | Done |
| **UI — Inspection** | Question list, segmented answer buttons, photo capture/upload, submit | Done |
| **Connectivity** | Offline detection, offline indicator, API reachability tracking | Done |
| **Theming** | Light/dark/system mode, Material 3 design tokens | Done |
| **Routing** | GoRouter with auth guards, redirect to sync screen | Done |

### 5.2 What Uses v1 API Endpoints (Needs Migration)

The sync layer currently calls **v1 endpoint names** and parses using **guessed field names**:

| Current Code | v1 Endpoint | v2 Endpoint |
|-------------|-------------|-------------|
| `sync_repository.dart:85` | `fetchbuildings` | `app_fetchbuildings` |
| `sync_repository.dart:108` | `fetchassets` | `app_fetch_all_assets` |
| `sync_repository.dart:137` | `fetchquestions` | **Removed in v2** |
| `sync_repository.dart:166` | `fetchchecklist` | `app_fetch_checklist_single` |
| `inspection_provider.dart:163` | `upload-image` | `app_upload-image` |
| `inspection_provider.dart:197` | `completed-inspection` | `app_completed-inspection` |

### 5.3 Data Model Gaps (Current vs v2 API)

The v2 API returns significantly richer data than the current models capture.

**Building model** — minimal gap:
| Current Field | API Field | Status |
|---------------|-----------|--------|
| `id` | `id` | Mapped |
| `name` | `name` | Mapped |
| `assetCount` | *(not in v2 response)* | Derived client-side — OK |

**Asset model** — major gap. Current model has 5 fields; v2 API returns 16:
| v2 API Field | Current Model | Status |
|--------------|---------------|--------|
| `assetId` | `id` | Mapped |
| `taskname` | `name` (mapped from `assetName`) | **Needs remapping** — field is `taskname` not `assetName` |
| `assetnickname` | *(missing)* | **Not captured** |
| `buildingId` | *(from sync context)* | Available but not stored on model |
| `assetregisteritems` | *(missing)* | **Not captured** |
| `tooltiptext` | *(missing)* | **Not captured** |
| `tooltipurls` | *(missing)* | **Not captured** |
| `lastcompleted` | *(missing)* | **Not captured** |
| `duedate` | `nextInspection` | **Needs remapping** — field is `duedate` not `date_of_next_inspection` |
| `frequency` | `intervalDays` | **Needs remapping** — field is string `"7 Day(s)"` not integer |
| `colour` | *(missing)* | **Not captured** — used for status (Red/Yellow/Green) |
| `location` | *(missing)* | **Not captured** |
| `floor` | *(missing)* | **Not captured** |
| `yellowdate` | *(missing)* | **Not captured** |
| `assetlastmodified` | *(missing)* | **Not captured** — needed for incremental sync |
| `checklistlastmodified` | *(missing)* | **Not captured** — needed for incremental sync |
| `lastcompleted` | `previousInspection` | **Needs remapping** — field is `lastcompleted` |

**Question model** — moderate gap. The v2 checklist response is hierarchical (chapters → questions) but the current model flattens everything:
| v2 API Field | Current Model | Status |
|--------------|---------------|--------|
| `questionid` | `id` (mapped from `question_id`) | **Needs remapping** |
| `questiontext` | `questionText` (mapped from `question_text`) | **Needs remapping** |
| `questiondesc` | *(missing)* | **Not captured** |
| `answertype` | `answerOption` (parsed from `answer_option`) | **Needs remapping** — format is `"Yes\|No"` not `"Yes/no"` |
| `photorequirement` | `photoRequirement` (parsed from `photo_requirement`) | **Needs remapping** — value is `"Only when unsatisfactory"` not `"Only when no/unsatisfactory"` |
| `questionordernumber` | *(missing)* | **Not captured** — needed for sort order |
| `existingremedials` | *(missing)* | **Not captured** |

**Chapter structure** — completely missing:
| v2 API Field | Status |
|--------------|--------|
| `parentassetid` | Not modelled |
| `chaptername` | Not modelled |
| `chapterorder` | Not modelled |

---

## 6. Required Changes

### 6.1 Endpoint Migration

Update all endpoint strings in the codebase to v2 names:

**`sync_repository.dart`:**
- `'fetchbuildings'` → `'app_fetchbuildings'`
- `'fetchassets'` → `'app_fetch_all_assets'`
- Remove `syncQuestionsForAsset()` (v1 `fetchquestions` removed in v2)
- `'fetchchecklist'` → `'app_fetch_checklist_single'`

**`inspection_provider.dart`:**
- `'upload-image'` → `'app_upload-image'`
- `'completed-inspection'` → `'app_completed-inspection'`

### 6.2 Asset Model & Table Expansion

**New fields to add to `AssetsTable`:**

| Column | Drift Type | Nullable | Description |
|--------|-----------|----------|-------------|
| `taskname` | text | No | The inspection task name (replaces `name` as display) |
| `nickname` | text | Yes | Asset nickname (e.g. door number "896") |
| `assetRegisterItems` | text | Yes | Raw JSON string of register items |
| `tooltipText` | text | Yes | Help text |
| `tooltipUrls` | text | Yes | Raw JSON string of tooltip URLs |
| `lastCompleted` | dateTime | Yes | Last completed inspection timestamp |
| `dueDate` | dateTime | Yes | Due date (replaces `nextInspection`) |
| `frequency` | text | Yes | Human-readable frequency string |
| `colour` | text | Yes | Status colour: Red, Yellow, Green |
| `location` | text | Yes | Location description |
| `floor` | text | Yes | Floor location |
| `yellowDate` | dateTime | Yes | Warning threshold date |
| `assetLastModified` | dateTime | Yes | For incremental sync comparison |
| `checklistLastModified` | dateTime | Yes | For incremental sync comparison |

**Update `Asset.fromJson()`** to map from exact v2 field names (`taskname`, `assetnickname`, `assetId`, `duedate`, `lastcompleted`, `colour`, etc.).

**Database migration** from schema version 2 → 3 to add the new columns.

### 6.3 Question/Checklist Model Overhaul

The v2 API returns checklists as a **chapter → question hierarchy** with different field names and answer format.

**New `ChaptersTable`:**

| Column | Drift Type | Description |
|--------|-----------|-------------|
| `id` | text (PK) | Generated: `{assetId}_{chapterOrder}` |
| `assetId` | text (FK → assets) | Parent asset |
| `chapterName` | text | Chapter display name |
| `chapterOrder` | integer | Sort order |

**Update `QuestionsTable` — add columns:**

| Column | Drift Type | Description |
|--------|-----------|-------------|
| `chapterId` | text (FK → chapters) | Parent chapter |
| `questionDesc` | text (nullable) | Description/guidance text |
| `orderNumber` | integer | Sort order within chapter |
| `existingRemedials` | text (nullable) | Raw JSON string of remedial items |

**Update `AnswerOption.fromString()`** to parse pipe-delimited format:
- `"Yes|No"` → `yesNo`
- `"Yes|No|N/A"` → `yesNoNA`
- `"Satisfactory|Unsatisfactory"` → `satisfactoryUnsatisfactory`
- `"Satisfactory|Unsatisfactory|N/A"` → new enum value `satisfactoryUnsatisfactoryNA`

**Update `PhotoRequirement.fromString()`** to parse v2 values:
- `"Always"` → `always` (unchanged)
- `"Only when unsatisfactory"` → `onlyWhenNegative`

**Update `parseChecklistResponse()`** to extract the chapter/question hierarchy from the v2 structure instead of flattening.

### 6.4 Checklist UI — Chapter Grouping

The inspection screen currently renders a flat list of questions. With v2 data, questions should be grouped under chapter headings:

```
Chapter: "Fire door"
  Q1: Does this door self-close...?
  Q2: If this door is a cupboard...?
  Q3: Is the door, frame and glazing...?

Chapter: "Emergency lighting"
  Q4: Are all luminaires...?
  ...
```

**Changes needed:**
- `InspectionScreen` — group questions by chapter, render chapter headers
- `QuestionsDao` — add `watchChecklistWithChapters()` joining chapters + questions
- `InspectionNotifier` — maintain chapter-aware indexing

### 6.5 Asset Detail — Display New Fields

The asset detail screen should show the additional v2 fields:

- **Nickname** (e.g. "896") alongside the task name
- **Status colour** (Red/Yellow/Green indicator)
- **Location / Floor** information
- **Frequency** (e.g. "7 Day(s)")
- **Tooltip text** and **tooltip URLs** (help section)
- **Existing remedials** on the checklist questions (read-only display)
- **Asset register items** (expandable list)

### 6.6 API Parser Updates

**`parseBuildingsResponse()`** — no change needed (field names match).

**`parseAssetsResponse()`** — update `Asset.fromJson()` to use v2 field names.

**`parseChecklistResponse()`** — complete rewrite:
- The v2 response is a flat array, not wrapped in `{ status, response: { checklist } }`
- Each item has `parentassetid` and `chapters` array
- Must extract chapters and questions into separate model objects
- Remove the smart-quote and concatenated-object workarounds (v2 returns clean JSON)

**Remove `parseQuestionsResponse()`** — the v1 `fetchquestions` endpoint no longer exists.

---

## 7. What Remains To Be Built

### 7.1 High Priority (Core Functionality)

| # | Feature | Description | Files Affected |
|---|---------|-------------|----------------|
| 1 | **v2 API migration** | Rename all endpoints, update parsers and models to v2 field names | `sync_repository.dart`, `api_parsers.dart`, `asset.dart`, `question.dart`, `building.dart` |
| 2 | **Asset model expansion** | Add all 16 v2 fields to model, table, DAO, and sync | `assets_table.dart`, `assets_dao.dart`, `asset.dart`, `database.dart` (migration) |
| 3 | **Chapter model** | New table, DAO, and model for checklist chapters | New: `chapters_table.dart`, `chapters_dao.dart`, `chapter.dart` |
| 4 | **Question model update** | Add chapterId, questionDesc, orderNumber, existingRemedials | `questions_table.dart`, `questions_dao.dart`, `question.dart`, `database.dart` |
| 5 | **Checklist parser rewrite** | Parse v2 hierarchical response into chapters + questions | `api_parsers.dart` |
| 6 | **Inspection screen — chapter grouping** | Group questions under chapter headings | `inspection_screen.dart`, `inspection_provider.dart` |
| 7 | **Answer type parsing** | Parse pipe-delimited format (`"Yes\|No"`) and add `Satisfactory\|Unsatisfactory\|N/A` | `question.dart` |

### 7.2 Medium Priority (UX Improvements)

| # | Feature | Description |
|---|---------|-------------|
| 8 | **Asset detail enrichment** | Show nickname, colour status, location, floor, frequency, tooltips, register items |
| 9 | **Existing remedials display** | Show read-only remedial items on checklist questions |
| 10 | **Question descriptions** | Display `questiondesc` as helper text below questions |
| 11 | **Incremental sync** | Use `assetlastmodified` / `checklistlastmodified` to skip unchanged data |
| 12 | **Status colour on asset list** | Show Red/Yellow/Green status badge on `BuildingDetailScreen` asset cards |

### 7.3 Low Priority (Future Features)

| # | Feature | Description |
|---|---------|-------------|
| 13 | **Offline inspection queue** | Queue completed inspections locally when offline, submit when connectivity returns |
| 14 | **Inspection history** | View past completed inspections (table exists, no UI) |
| 15 | **Home screen tabs** | Explore, Activity, More tabs are placeholders |
| 16 | **Photo gallery** | View photos from past inspections |
| 17 | **Single asset refresh** | Use `app_fetch_asset_single` for targeted refresh after inspection submission |

---

## 8. Database Schema (Target State)

After all changes, the schema should be:

```
BuildingsTable
  id          TEXT PK
  name        TEXT
  assetCount  INTEGER
  lastSyncedAt DATETIME?

AssetsTable
  id                    TEXT PK
  taskname              TEXT
  nickname              TEXT?
  buildingId            TEXT FK → buildings
  assetRegisterItems    TEXT?       -- raw JSON
  tooltipText           TEXT?
  tooltipUrls           TEXT?       -- raw JSON
  lastCompleted         DATETIME?
  dueDate               DATETIME?
  frequency             TEXT?
  colour                TEXT?
  location              TEXT?
  floor                 TEXT?
  yellowDate            DATETIME?
  assetLastModified     DATETIME?
  checklistLastModified DATETIME?
  lastSyncedAt          DATETIME?

ChaptersTable
  id            TEXT PK   -- "{assetId}_{chapterOrder}"
  assetId       TEXT FK → assets
  chapterName   TEXT
  chapterOrder  INTEGER

QuestionsTable
  id               TEXT PK
  questionText     TEXT
  questionDesc     TEXT?
  assetId          TEXT FK → assets
  chapterId        TEXT? FK → chapters
  source           TEXT          -- 'checklist'
  answerOption     TEXT?
  photoRequirement TEXT?
  orderNumber      INTEGER?
  existingRemedials TEXT?        -- raw JSON
  lastSyncedAt     DATETIME?

CompletedInspectionsTable
  id          TEXT PK
  assetId     TEXT FK → assets
  date        DATETIME
  lastSyncedAt DATETIME?

InspectionAnswersTable
  id             INTEGER PK autoincrement
  inspectionId   TEXT FK → completed_inspections
  questionText   TEXT
  answerText     TEXT
```

**Migration path:** Schema version 2 → 3

---

## 9. Sync Flow (Target State)

```
SyncRepository.syncAll()
  ├── Phase 1: GET /wf/app_fetchbuildings
  │     → parse → upsert BuildingsTable
  │
  ├── Phase 2: For each building:
  │     GET /wf/app_fetch_all_assets?block_id={id}
  │     → parse → upsert AssetsTable (all 16 fields)
  │
  └── Phase 3: For each asset (max 5 concurrent):
        GET /wf/app_fetch_checklist_single?asset_id={id}
        → parse chapters → upsert ChaptersTable
        → parse questions → upsert QuestionsTable
```

**Key change:** The `syncQuestionsForAsset()` call (v1 `fetchquestions`) is removed. All question data now comes from the checklist endpoint.

---

## 10. Inspection Submission Flow (Current)

```
User answers all questions
  → Validate: all answers provided, required photos attached
  → Upload each photo: POST /wf/app_upload-image (base64)
  → Submit inspection: POST /wf/app_completed-inspection
  → On success: pop back to asset detail
```

**Open question:** The exact payload structure for `app_completed-inspection` is not yet confirmed by the backend (see API Spec v2.1, Open Question #6).

---

## 11. File Reference

| File | Purpose |
|------|---------|
| `lib/core/config/api_config.dart` | Base URL configuration |
| `lib/core/router/app_router.dart` | GoRouter setup with auth guards |
| `lib/database/database.dart` | Drift database definition and migrations |
| `lib/database/tables/*.dart` | Table definitions |
| `lib/database/daos/*.dart` | Data access objects |
| `lib/models/asset.dart` | Asset model with `fromJson()` |
| `lib/models/building.dart` | Building model with `fromJson()` |
| `lib/models/question.dart` | Question model, AnswerOption and PhotoRequirement enums |
| `lib/providers/*.dart` | Riverpod state providers |
| `lib/repositories/api_repository.dart` | HTTP client with auth |
| `lib/repositories/auth_repository.dart` | Login, token management |
| `lib/repositories/sync_repository.dart` | API → SQLite sync orchestration |
| `lib/screens/*.dart` | UI screens |
| `lib/services/connectivity_service.dart` | Network status tracking |
| `lib/utils/api_parsers.dart` | Response parsing for each endpoint |
| `flutter/docs/BlockPro-API-Spec-v2.md` | API specification (v2.1) |
