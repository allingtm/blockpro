# BlockPro – Bubble Backend API & Data Model Specification

**Version:** 2.1  
**Date:** 16 April 2026  
**Prepared by:** Marc Allington, Solve with Software Ltd  
**Purpose:** Definitive reference for developers building the BlockPro Flutter app against the Bubble.io backend

---

## 1. Changes from v1

### Endpoint Renaming

All workflow endpoints now use the `app_` prefix:

| v1 Endpoint | v2 Endpoint |
|-------------|-------------|
| `/wf/login` | `/wf/app_login` |
| `/wf/fetchbuildings` | `/wf/app_fetchbuildings` |
| `/wf/upload-image` | `/wf/app_upload-image` |
| `/wf/completed-inspection` | `/wf/app_completed-inspection` |
| `/wf/fetchchecklist` | `/wf/app_fetch_checklist_single` |

### Removed Endpoints

| Endpoint | Reason |
|----------|--------|
| `/wf/fetchbuilding` | Single building fetch removed — no direct replacement |
| `/wf/fetchassets` | Replaced by `/wf/app_fetch_all_assets` |
| `/wf/fetchassets-old` | Deprecated endpoint removed |
| `/wf/fetchquestions` | Removed — checklists now fetched separately via `/wf/app_fetch_checklist_single` |

### New Endpoints

| Endpoint | Method | Auth | Purpose |
|----------|--------|------|---------|
| `/wf/app_fetch_all_assets` | GET | Bearer | Fetch all assets for a block |
| `/wf/app_fetch_asset_single` | GET | Bearer | Fetch a single asset by ID |
| `/wf/app_upload-image-direct` | POST | Bearer | Alternative image upload via `_wf_request_data` |
| `/wf/app_createphoto_Adam` | POST | None | Create photo record from a URL |
| `/wf/app_upload-image_Adam` | POST | None | Upload base64 image with asset link |

### Parameter Changes

- **`app_upload-image`** now accepts `Image` (string) in the request body instead of `_wf_request_data`.
- **`app_fetch_checklist_single`** uses `asset_id` (unchanged from v1 `fetchchecklist`).

---

## 2. Overview

BlockPro is a building inspection app. The Flutter mobile client communicates with a Bubble.io backend via Bubble's Workflow API. This document covers every API endpoint, the complete data model, authentication flow, and error handling.

---

## 3. Base URL

**Development (version-test):**
```
https://flutterflowtest.bubbleapps.io/version-test/api/1.1/wf/
```

**Live:**
```
https://flutterflowtest.bubbleapps.io/api/1.1/wf/
```

The base URL should be configurable via environment variable (`BUBBLE_API_BASE_URL`).

---

## 4. Authentication

### 4.1 Mechanism

| Property | Value |
|----------|-------|
| Type | Bearer Token (JWT) |
| Obtained via | `POST /wf/app_login` |
| Sent as | `Authorization: Bearer <token>` header |
| Persistence | In-memory + `SharedPreferences` |
| Expiration | Server returns `expires` (seconds from now) |

### 4.2 Token Lifecycle

1. User logs in via `/wf/app_login` → receives `token` and `expires`
2. Client stores token and computes expiry as `DateTime.now() + Duration(seconds: expires)`
3. On every authenticated request, client sends `Authorization: Bearer <token>`
4. On app startup, client loads persisted token and checks expiry. If expired, clears auth state and redirects to login

### 4.3 Swagger Security Note

The Bubble Swagger spec defines `api_token` as a query parameter. In practice, the Flutter app uses Bearer token auth in headers. Both may work — **use Bearer headers as the standard approach**.

### 4.4 Public Endpoints

The following endpoints require **no authentication**:

- `POST /wf/app_login`
- `POST /wf/app_createphoto_Adam`
- `POST /wf/app_upload-image_Adam`

---

## 5. API Endpoints

### 5.1 POST /wf/app_login

Authenticate a user with email and password.

| Property | Value |
|----------|-------|
| Method | POST |
| Auth | None (public endpoint) |
| Content-Type | application/json |

**Request Body:**
```json
{
  "email": "string (required)",
  "password": "string (required)"
}
```

**Success Response (200):**
```json
{
  "status": "success",
  "response": {
    "user_id": "string — Bubble unique ID for the user",
    "token": "string — JWT bearer token",
    "expires": 3600
  }
}
```

**Error Response (400/401):**
```json
{
  "status": "error",
  "message": "Human-readable error message"
}
```

**Notes:**
- Sanitise `email` and `password` before embedding in JSON (escape special characters)
- The `expires` field is a float (seconds until token expiry)

---

### 5.2 GET /wf/app_fetchbuildings

Fetch all buildings accessible to the authenticated user.

| Property | Value |
|----------|-------|
| Method | GET |
| Auth | Bearer Token (required) |
| Parameters | None |

**Success Response (200):**

The response body is a JSON string that must be parsed by the client. Parsed structure is an array of Building objects:

```json
[
  {
    "id": "1756484476534x490740256824968800",
    "name": "Building 1"
  }
]
```

**Building Object:**

| Field | Type | Description |
|-------|------|-------------|
| `id` | string | Bubble unique ID of the building |
| `name` | string | Building display name |

---

### 5.3 GET /wf/app_fetch_all_assets

Fetch all assets for a specific building/block. Replaces the v1 endpoint `fetchassets`.

| Property | Value |
|----------|-------|
| Method | GET |
| Auth | Bearer Token (required) |

**Query Parameters:**

| Param | Type | Required | Description |
|-------|------|----------|-------------|
| block_id | string | Yes | Bubble unique ID of the building/block |

**Success Response (200):**

The response body is a JSON string that must be parsed by the client. Parsed structure is an array of Asset objects:

```json
[
  {
    "taskname": "Fire door inspection",
    "assetnickname": "896",
    "assetId": "1771864899143x375085884294525250",
    "buildingId": "1756831363197x720244312004630400",
    "assetregisteritems": "",
    "tooltiptext": "",
    "tooltipurls": "",
    "lastcompleted": "2026-04-14T11:27:56.319Z",
    "duedate": "2026-04-14T11:27:56.319Z",
    "frequency": "7 Day(s)",
    "colour": "Red",
    "location": "",
    "floor": "",
    "yellowdate": "2026-04-14T11:27:56.319Z",
    "assetlastmodified": "2026-04-13T10:09:31.738Z",
    "checklistlastmodified": "2026-04-14T11:02:50.833Z"
  }
]
```

**Asset Object:**

| Field | Type | Nullable | Description |
|-------|------|----------|-------------|
| `taskname` | string | No | Name of the inspection task |
| `assetnickname` | string | No | Informal identifier (can be empty string) |
| `assetId` | string | No | Bubble unique ID of the asset |
| `buildingId` | string | No | Bubble unique ID of the parent building |
| `assetregisteritems` | string | No | Comma-separated JSON objects of register items, or empty string (see below) |
| `tooltiptext` | string | No | Help text for the inspector, or empty string |
| `tooltipurls` | string | No | Comma-separated JSON objects of tooltip URLs, or empty string (see below) |
| `lastcompleted` | string (ISO 8601) | Yes | Timestamp of last completed inspection |
| `duedate` | string (ISO 8601) | Yes | Due date for next inspection |
| `frequency` | string | No | Human-readable inspection frequency (e.g. `"7 Day(s)"`) |
| `colour` | string | No | Status colour: `"Red"`, `"Yellow"`, or `"Green"` |
| `location` | string | No | Location description (can be empty string) |
| `floor` | string | No | Floor location (can be empty string) |
| `yellowdate` | string (ISO 8601) | Yes | Warning threshold date |
| `assetlastmodified` | string (ISO 8601) | No | Last modification timestamp of the asset |
| `checklistlastmodified` | string (ISO 8601) | Yes | Last modification timestamp of the checklist (`null` if no checklist exists) |

**`assetregisteritems` — Nested Structure:**

When populated, this field contains comma-separated JSON objects (not a valid JSON array — must be wrapped in `[...]` before parsing):

```
{"registeritemref": "Wallbox1", "registeritemfloor": "1st", "registeritemlocation": "Landing"},{"registeritemref": "Wallbox2", "registeritemfloor": "1st", "registeritemlocation": "Landing"}
```

| Field | Type | Description |
|-------|------|-------------|
| `registeritemref` | string | Reference identifier for the register item |
| `registeritemfloor` | string | Floor where the item is located |
| `registeritemlocation` | string | Location description |

**`tooltipurls` — Nested Structure:**

When populated, this field contains comma-separated JSON objects (not a valid JSON array — must be wrapped in `[...]` before parsing):

```
{"tooltipurl": "https://blockpro.co.uk/"},{"tooltipurl": "https://www.google.com/"}
```

| Field | Type | Description |
|-------|------|-------------|
| `tooltipurl` | string | URL to display as a tooltip link |

---

### 5.4 GET /wf/app_fetch_asset_single

Fetch a single asset by ID.

| Property | Value |
|----------|-------|
| Method | GET |
| Auth | Bearer Token (required) |

**Query Parameters:**

| Param | Type | Required | Description |
|-------|------|----------|-------------|
| asset_id | string | Yes | Bubble unique ID of the asset |

**Success Response (200):**

The response body is a JSON string that must be parsed by the client. Parsed structure is a single-element array containing the same Asset object as `app_fetch_all_assets` (see §5.3 for full field reference):

```json
[
  {
    "taskname": "Fire door inspection",
    "assetnickname": "896",
    "assetId": "1771864899143x375085884294525250",
    "buildingId": "1756831363197x720244312004630400",
    "assetregisteritems": "",
    "tooltiptext": "",
    "tooltipurls": "",
    "lastcompleted": "2026-04-14T11:27:56.319Z",
    "duedate": "2026-04-14T11:27:56.319Z",
    "frequency": "7 Day(s)",
    "colour": "Red",
    "location": "",
    "floor": "",
    "yellowdate": "2026-04-14T11:27:56.319Z",
    "assetlastmodified": "2026-04-13T10:09:31.738Z",
    "checklistlastmodified": "2026-04-14T11:02:50.833Z"
  }
]
```

---

### 5.5 GET /wf/app_fetch_checklist_single

Fetch the checklist for a specific asset.

| Property | Value |
|----------|-------|
| Method | GET |
| Auth | Bearer Token (required) |

**Query Parameters:**

| Param | Type | Required | Description |
|-------|------|----------|-------------|
| asset_id | string | Yes | Bubble unique ID of the asset |

**Success Response (200):**

The response body is a JSON string that must be parsed by the client. Parsed structure is an array containing a single Checklist object:

```json
[
  {
    "parentassetid": "1771864899143x375085884294525250",
    "chapters": [
      {
        "chaptername": "Fire door",
        "chapterorder": 1,
        "questions": [
          {
            "questiontext": "Does this door self-close fully into its frame?",
            "questiondesc": "",
            "answertype": "Yes|No",
            "photorequirement": "Always",
            "questionordernumber": 5,
            "questionid": "1771871963645x392498056957566000",
            "existingremedials": []
          }
        ]
      }
    ]
  }
]
```

**Checklist Object:**

| Field | Type | Description |
|-------|------|-------------|
| `parentassetid` | string | Bubble unique ID of the parent asset |
| `chapters` | array of Chapter | Ordered list of chapters in the checklist |

**Chapter Object:**

| Field | Type | Description |
|-------|------|-------------|
| `chaptername` | string | Display name of the chapter |
| `chapterorder` | number | Sort order (1-based) |
| `questions` | array of Question | Ordered list of questions within the chapter |

**Question Object:**

| Field | Type | Description |
|-------|------|-------------|
| `questiontext` | string | The question to display to the inspector |
| `questiondesc` | string | Optional additional description/guidance (can be empty string) |
| `answertype` | string | Pipe-delimited answer options (see known values below) |
| `photorequirement` | string | When a photo is required (see known values below) |
| `questionordernumber` | number | Sort order within the chapter |
| `questionid` | string | Bubble unique ID of the question |
| `existingremedials` | array of Remedial | Previously raised remedial items for this question (can be empty) |

**Remedial Object:**

| Field | Type | Description |
|-------|------|-------------|
| `remedialname` | string | Short name/title of the remedial action |
| `remedialdesc` | string | Detailed description of the issue |
| `remediallocation` | string | Location where the remedial is needed |
| `remedialduedate` | string (ISO 8601) | Due date for the remedial action |
| `remedialpriority` | string | Priority level: `"Low"`, `"High"` |

**Known Option Values:**

| Field | Known Values |
|-------|-------------|
| `answertype` | `"Yes\|No"`, `"Yes\|No\|N/A"`, `"Satisfactory\|Unsatisfactory"`, `"Satisfactory\|Unsatisfactory\|N/A"` |
| `photorequirement` | `"Always"`, `"Only when unsatisfactory"` |
| `remedialpriority` | `"Low"`, `"High"` |

---

### 5.6 POST /wf/app_upload-image

Upload an image (e.g. inspection photo).

| Property | Value |
|----------|-------|
| Method | POST |
| Auth | Bearer Token (required) |
| Content-Type | application/json |

**Request Body:**
```json
{
  "Image": "string (required) — image data (likely base64-encoded)"
}
```

**Success Response (200):**
```json
{
  "status": "string",
  "response": {
    "success": "string",
    "image_url": "string — URL of the uploaded image on Bubble's CDN",
    "image_id": "string — Bubble unique ID of the Photo record"
  }
}
```

---

### 5.7 POST /wf/app_upload-image-direct

Alternative image upload using Bubble's generic workflow data mechanism.

| Property | Value |
|----------|-------|
| Method | POST |
| Auth | Bearer Token (required) |
| Content-Type | application/json |

**Request Body:**
```json
{
  "_wf_request_data": "required — Bubble workflow request data"
}
```

**Success Response (200):**
```json
{
  "status": "string",
  "response": {
    "success": "string",
    "image_url": "string — URL of the uploaded image on Bubble's CDN",
    "image_id": "string — Bubble unique ID of the Photo record"
  }
}
```

---

### 5.8 POST /wf/app_createphoto_Adam

Create a photo record from an existing image URL.

| Property | Value |
|----------|-------|
| Method | POST |
| Auth | None (public endpoint) |
| Content-Type | application/json |

**Request Body:**
```json
{
  "image_url": "string (required) — URL of the image",
  "asset_id": "string (required) — Bubble unique ID of the asset"
}
```

**Success Response (200):**
```json
{
  "status": "string",
  "response": {}
}
```

---

### 5.9 POST /wf/app_upload-image_Adam

Upload a base64-encoded image and link it to an asset.

| Property | Value |
|----------|-------|
| Method | POST |
| Auth | None (public endpoint) |
| Content-Type | application/json |

**Request Body:**
```json
{
  "base64": "string (required) — base64-encoded image data",
  "asset_id": "string (required) — Bubble unique ID of the asset"
}
```

**Success Response (200):**
```json
{
  "status": "string",
  "response": {
    "success": "string",
    "image_url": "string — URL of the uploaded image on Bubble's CDN",
    "image_id": "string — Bubble unique ID of the Photo record"
  }
}
```

**Note:** Per the live Bubble swagger, this endpoint returns the same `success` / `image_url` / `image_id` response shape as `app_upload-image`.

---

### 5.10 POST /wf/app_completed-inspection

Mark an inspection as completed.

| Property | Value |
|----------|-------|
| Method | POST |
| Auth | Bearer Token (required) |
| Content-Type | application/json |

**Request Body (as sent by the app):**

All keys are `snake_case`.

```json
{
  "asset_id": "1776160199545x786906369052976900",
  "completion_date": "2026-06-15T10:30:00.000Z",
  "answers": [
    { "question": "Is the door undamaged?", "answer": "Satisfactory" },
    {
      "question": "Does the closer work?",
      "answer": "Unsatisfactory",
      "question_id": "1771871963645x392498056957566000",
      "chapter_id": "1776160199545x786906369052976900_1",
      "photo_ids": ["1781541587644x497486149803634050", "..."],
      "remedial": {
        "remedial_name": "Replace door closer",
        "remedial_location": "1st floor landing",
        "remedial_desc": "Closer leaking oil, door not latching",
        "remedial_priority": "High",
        "register_items": [
          {
            "register_item_ref": "Wallbox1",
            "register_item_floor": "1st",
            "register_item_location": "Landing"
          }
        ]
      }
    }
  ],
  "inspection_photo_ids": ["<header image id>", "..."],
  "register_items": [
    {
      "register_item_ref": "Wallbox1",
      "register_item_floor": "1st",
      "register_item_location": "Landing"
    }
  ]
}
```

- **`completion_date`** — when the inspector tapped Complete, ISO-8601 UTC
  (trailing `Z`), a sibling of `asset_id`.
- **Per-answer ids** — `question_id` / `chapter_id` are echoed from the checklist
  (§5.5). `question_id` is whatever `app_fetch_checklist_single` returned; the app
  is a pass-through, so an empty value here means the checklist workflow did not
  populate `questionid`. `chapter_id` is the synthesised `{asset_id}_{chapterorder}`.
- **`photo_ids`** (optional, per answer) — the per-question photo `image_id`s
  (from `app_upload-image_Adam`) as a JSON array, omitted when that answer had no
  photo. A question may carry more than one photo.
- **`inspection_photo_ids`** — inspection-level (header) photo ids, only included
  when present (replaces the old flat top-level `photo_ids`).
- **`register_items`** (top-level, optional) — asset register items the inspector
  tagged the whole inspection with; omitted when none.
- **`remedial` (optional, per answer)** — present only on answers where the
  inspector raised a remedial against the question (the app offers this when
  the answer is negative: `No` / `Unsatisfactory`, at most one per question).
  Keys: `remedial_name` (always present, non-empty), `remedial_priority`
  (`Low` | `High`, always present), `remedial_location` / `remedial_desc`
  (omitted when empty), `register_items` (omitted when empty — echoes the asset's
  register-item objects, §5.3, that the remedial relates to). A `remedial_due_date`
  is NOT sent — the server assigns it. The Bubble workflow must be extended to
  create an ExistingRemedial from each `remedial` object and attach it to the
  matching question; unknown/absent keys must not break older payloads.

**Success Response (200):**
```json
{
  "status": "success",
  "response": {
    "nextduedate": "2027-06-15T10:30:00.000Z",
    "yellowdate": "2027-06-25T10:30:00.000Z"
  }
}
```

- **`nextduedate`** — the recomputed next due date (`now + frequency`). The app
  writes this to the asset's `dueDate`.
- **`yellowdate`** — the amber/warning threshold date (`nextduedate ± r1 days`
  from the asset option set). The app writes this to the asset's `yellowDate`.
- **Returned only for yearly assets.** The backend's "Return data from API" step
  is gated by *Frequency is Year(s)*, so both keys are absent for day/week/month
  frequencies. When absent, the app falls back to recomputing `dueDate` locally
  from the `frequency` string and leaves `yellowDate` untouched until the next
  sync.
- **Computed from the server's current time**, not the submitted
  `completion_date` — for a completion queued offline and drained later, the
  due date is relative to the drain time, not when the inspector tapped Complete.

---

## 6. Data Model

All data types include the following built-in fields from Bubble: `Creator` (User), `Modified Date` (date), `Created Date` (date), `Slug` (text). These are omitted from individual type definitions below for brevity.

### 6.1 User

The core Bubble user type. Has privacy rules applied.

| Field | Type | Description |
|-------|------|-------------|
| Date of site tasks modification (for app purposes) | date | Custom timestamp for signalling data changes to the app |
| Linked user profiles | List of User profiles | Associated user profiles |
| List of buildings | List of Buildings | Buildings assigned to this user |
| List of favourite colours | List of Colours | User's preferred colours (option set) |
| Name | text | User's display name |
| Role | User role | User's role (default: Regular) |
| email | text | User's email address (built-in) |

### 6.2 Buildings

A building or block that contains assets to be inspected.

| Field | Type | Description |
|-------|------|-------------|
| List of assets | List of Assets | Assets contained within this building |
| Name | text | Building name/identifier |

### 6.3 Asset

An inspectable item within a building (e.g. a fire door, lift, boiler).

| Field | Type | Description |
|-------|------|-------------|
| Asset option set | Asset option | Asset configuration options (option set) |
| Asset register items | List of Asset register items | Register items linked to this asset |
| Assigned to (user) | User | User assigned to this asset |
| BlocknameCSV | text | Building/block name as CSV text |
| Checklist (master) | Checklist (master) | The master checklist for this asset |
| Date of modification (for app purposes) | date | Custom timestamp for signalling data changes to the app |
| Date of next inspection | date | When the next inspection is due |
| Date of previous inspection | date | When the last inspection occurred |
| Floor | text | Floor location of the asset |
| Interval (number of days) | number | Days between inspections |
| Linked building | Buildings | The building this asset belongs to |
| List of completed inspections | List of Completed inspections | Historical inspection records |
| Location | text | Location description of the asset |
| Name | text | Asset name/identifier |
| Nickname | text | Informal name for the asset |
| Tooltip text | text | Help text displayed in the app |
| Tooltip URLs | List of texts | URLs referenced by tooltip content |
| Yellow date | date | Date threshold for warning status |
| Zero padded name | text | Name with zero-padding for sort order |

### 6.4 Checklist (master)

The master checklist template linked to an asset. Contains chapters.

| Field | Type | Description |
|-------|------|-------------|
| Chapters | List of Checklist (chapters) | Ordered list of chapters in this checklist |
| Date of modification (for app purposes) | date | Custom timestamp for signalling data changes to the app |
| Linked asset | Asset | The asset this checklist belongs to |
| Name | text | Checklist name |

### 6.5 Checklist (chapters)

A chapter within a master checklist. Contains questions.

| Field | Type | Description |
|-------|------|-------------|
| Chapter name | text | Name of the chapter |
| Master checklist | Checklist (master) | The master checklist this chapter belongs to |
| Order number | number | Sort order of the chapter |
| Questions | List of Checklist (questions) | Questions within this chapter |

### 6.6 Checklist (questions)

A question within a checklist chapter.

| Field | Type | Description |
|-------|------|-------------|
| Answer option | Answer options | The type of answer expected (option set) |
| Description | text | Additional description/guidance for the question |
| Linked checklist chapter | Checklist (chapters) | The chapter this question belongs to |
| Photo requirement | Photo requirement | Whether a photo is required (option set) |
| Question text | text | The question to ask during inspection |

### 6.7 Completed Inspections

A record of a completed inspection.

| Field | Type | Description |
|-------|------|-------------|
| Date | date | When the inspection was carried out |
| List of question answers | List of Questions (answers) | All answers recorded during this inspection |

---

## 7. Data Model Relationships (Entity Map)

```
User
 ├── has many → User profiles
 ├── has many → Buildings
 ├── has → Role (User role option set)
 └── has many → Colours (option set)

Buildings
 └── has many → Assets

Asset
 ├── belongs to → Buildings (Linked building)
 ├── assigned to → User
 ├── has one → Checklist (master)
 ├── has one → Asset option (option set)
 ├── has many → Asset register items
 ├── has many → Completed inspections
 └── has many → Photos

Checklist (master)
 ├── belongs to → Asset (Linked asset)
 └── has many → Checklist (chapters)

Checklist (chapters)
 ├── belongs to → Checklist (master)
 └── has many → Checklist (questions)

Checklist (questions)
 ├── belongs to → Checklist (chapters)
 ├── has → Answer options (option set)
 └── has → Photo requirement (option set)

Completed inspections
 └── has many → Questions (answers)

Photo
 └── belongs to → Asset
```

---

## 8. Error Handling

All endpoints return consistent error shapes:

| HTTP Status | Description | Response Shape |
|-------------|-------------|---------------|
| 200 | Success | Varies per endpoint (see above) |
| 400 | Workflow failure / Bad request | `{ "status": "string", "message": "string" }` |
| 401 | Permission denied / Unauthorised | `{ "message": "string" }` |
| 404 | Not found | `{ "message": "string" }` |
| 405 | Wrong HTTP method | `{ "message": "string" }` |
| 429 | Rate limited | `{ "message": "string" }` |
| 500 | Internal server error | `{ "code": "string", "message": "string" }` |
| 503 | Service unavailable | `{ "message": "string" }` |

### Recommended Client-Side Error Messages

| Error Condition | User-Facing Message |
|----------------|---------------------|
| No network / SocketException | "Unable to connect. Please check your internet connection." |
| Request timeout | "The request timed out. Please try again." |
| 401 / Token expired | "Your session has expired. Please sign in again." |
| Login failure | "Failed to login. Please check your email and password." |
| 403 | "You do not have permission." |
| 404 | "Item not found." |
| 5xx | "A server error occurred. Please try again later." |

---

## 9. Privacy & Visibility

| Data Type | Visibility |
|-----------|-----------|
| Asset | Publicly visible |
| Asset register items | TBC |
| Buildings | Publicly visible |
| Checklist (master) | Publicly visible |
| Checklist (chapters) | Publicly visible |
| Checklist (questions) | Publicly visible |
| Completed inspections | Publicly visible |
| Photo | Privacy rules applied |
| Questions (answers) | Publicly visible |
| User | Privacy rules applied |
| User profiles | Publicly visible |

**Note:** "Privacy rules applied" means Bubble's server-side privacy rules restrict which records are returned based on the authenticated user. The Flutter app must always send a valid Bearer token to access these types.

---

## 10. Endpoint Summary

| # | Endpoint | Method | Auth | Purpose |
|---|----------|--------|------|---------|
| 1 | `/wf/app_login` | POST | None | Authenticate user, obtain JWT |
| 2 | `/wf/app_fetchbuildings` | GET | Bearer | Fetch all buildings |
| 3 | `/wf/app_fetch_all_assets` | GET | Bearer | Fetch all assets for a block |
| 4 | `/wf/app_fetch_asset_single` | GET | Bearer | Fetch a single asset |
| 5 | `/wf/app_fetch_checklist_single` | GET | Bearer | Fetch checklist for an asset |
| 6 | `/wf/app_upload-image` | POST | Bearer | Upload an image (Image param) |
| 7 | `/wf/app_upload-image-direct` | POST | Bearer | Upload an image (workflow data) |
| 8 | `/wf/app_createphoto_Adam` | POST | None | Create photo record from URL |
| 9 | `/wf/app_upload-image_Adam` | POST | None | Upload base64 image with asset link |
| 10 | `/wf/app_completed-inspection` | POST | Bearer | Submit a completed inspection |

---

## 11. Open Questions / Missing Information

The following items need clarification from the Bubble backend:

1. **`_wf_request_data` structure** — The exact JSON structure expected by `app_upload-image-direct` and `app_completed-inspection` endpoints is not defined in the Swagger spec. This needs to be documented from the Bubble workflow configuration.

2. ~~**Response parsing for string endpoints**~~ — **RESOLVED in v2.1.** The JSON structures for `app_fetchbuildings`, `app_fetch_all_assets`, `app_fetch_asset_single`, and `app_fetch_checklist_single` are now fully documented in §5.2–§5.5.

3. **`app_createphoto_Adam` / `app_upload-image_Adam` naming** — These endpoints appear to be development/testing endpoints (suffixed with `_Adam`). Confirm whether these are intended for production use or will be renamed.

4. **`app_createphoto_Adam` / `app_upload-image_Adam` security** — These endpoints require no authentication. Confirm whether this is intentional for production.

5. **Single building fetch removed** — The v1 endpoint `/wf/fetchbuilding` (fetch single building by ID) has no direct replacement. Confirm whether this functionality is still needed or if it should be handled client-side by filtering the `app_fetchbuildings` response.

6. ~~**Inspection completion payload**~~ — **PROPOSED in §5.10** (pending backend confirmation): `asset_id` + inline `answers` (question text + answer), optional per-answer `remedial` object for remedials raised by the inspector, optional `photo_ids`. The Bubble workflow must be extended to consume the `remedial` object.

7. ~~**Option set values**~~ — **PARTIALLY RESOLVED in v2.1.** The following values are now documented:
   - `answertype`: `"Yes|No"`, `"Yes|No|N/A"`, `"Satisfactory|Unsatisfactory"`, `"Satisfactory|Unsatisfactory|N/A"`
   - `photorequirement`: `"Always"`, `"Only when unsatisfactory"`
   - `colour` (asset status): `"Red"`, `"Yellow"`, `"Green"`
   - `remedialpriority`: `"Low"`, `"High"`
   - Still unknown: `Asset option`, `User role`, `Colours`

8. ~~**Asset register items**~~ — **RESOLVED in v2.1.** Fields documented in §5.3 under `assetregisteritems` nested structure: `registeritemref`, `registeritemfloor`, `registeritemlocation`.

9. **Questions (answers) fields** — This data type was in v1 but not re-confirmed in current screenshots. Needs verification of current fields.
