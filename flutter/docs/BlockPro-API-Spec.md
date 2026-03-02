# BlockPro – Bubble Backend API & Data Model Specification

**Version:** 1.0  
**Date:** 23 February 2026  
**Prepared by:** Marc Allington, Solve with Software Ltd  
**Purpose:** Definitive reference for developers building the BlockPro Flutter app against the Bubble.io backend

---

## 1. Overview

BlockPro is a building inspection app. The Flutter mobile client communicates with a Bubble.io backend via Bubble's Workflow API. This document covers every API endpoint, the complete data model, authentication flow, and error handling.

---

## 2. Base URL

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

## 3. Authentication

### 3.1 Mechanism

| Property | Value |
|----------|-------|
| Type | Bearer Token (JWT) |
| Obtained via | `POST /wf/login` |
| Sent as | `Authorization: Bearer <token>` header |
| Persistence | In-memory + `SharedPreferences` |
| Expiration | Server returns `expires` (seconds from now) |

### 3.2 Token Lifecycle

1. User logs in via `/wf/login` → receives `token` and `expires`
2. Client stores token and computes expiry as `DateTime.now() + Duration(seconds: expires)`
3. On every authenticated request, client sends `Authorization: Bearer <token>`
4. On app startup, client loads persisted token and checks expiry. If expired, clears auth state and redirects to login

### 3.3 Swagger Security Note

The Bubble Swagger spec defines `api_token` as a query parameter. In practice, the Flutter app uses Bearer token auth in headers. Both may work — **use Bearer headers as the standard approach**.

---

## 4. API Endpoints

### 4.1 POST /wf/login

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
- The `expires` field is a number (seconds until token expiry)

---

### 4.2 GET /wf/fetchbuildings

Fetch all buildings accessible to the authenticated user.

| Property | Value |
|----------|-------|
| Method | GET |
| Auth | Bearer Token (required) |
| Parameters | None |

**Success Response (200):**
```
Type: string (JSON-encoded)
```

The response body is a JSON string that must be parsed by the client. Expected parsed structure is an array of Building objects (see Data Model §5.2).

---

### 4.3 GET /wf/fetchbuilding

Fetch a single building by ID.

| Property | Value |
|----------|-------|
| Method | GET |
| Auth | Bearer Token (required) |

**Query Parameters:**

| Param | Type | Required | Description |
|-------|------|----------|-------------|
| building_id | string | Yes | Bubble unique ID of the building |

**Success Response (200):**
```
Type: string (JSON-encoded)
```

---

### 4.4 GET /wf/fetchassets

Fetch assets belonging to a specific building/block.

| Property | Value |
|----------|-------|
| Method | GET |
| Auth | Bearer Token (required) |

**Query Parameters:**

| Param | Type | Required | Description |
|-------|------|----------|-------------|
| block_id | string | Yes | Bubble unique ID of the building/block |

**Success Response (200):**
```
Type: string (JSON-encoded)
```

---

### 4.5 GET /wf/fetchassets-old (Deprecated)

Legacy version of fetchassets. Returns a structured object rather than a raw string.

| Property | Value |
|----------|-------|
| Method | GET |
| Auth | Bearer Token (required) |

**Query Parameters:**

| Param | Type | Required | Description |
|-------|------|----------|-------------|
| block_id | string | Yes | Bubble unique ID of the building/block |

**Success Response (200):**
```json
{
  "status": "string",
  "response": {
    "assets": "string (JSON-encoded array)"
  }
}
```

**Note:** Prefer `/wf/fetchassets` for new development.

---

### 4.6 GET /wf/fetchquestions

Fetch question templates for a specific asset.

| Property | Value |
|----------|-------|
| Method | GET |
| Auth | Bearer Token (required) |

**Query Parameters:**

| Param | Type | Required | Description |
|-------|------|----------|-------------|
| asset_id | string | Yes | Bubble unique ID of the asset |

**Success Response (200):**
```
Type: string (JSON-encoded)
```

---

### 4.7 GET /wf/fetchchecklist

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
```json
{
  "status": "string",
  "response": {
    "checklist": "string (JSON-encoded)"
  }
}
```

---

### 4.8 POST /wf/upload-image

Upload an image (e.g. inspection photo).

| Property | Value |
|----------|-------|
| Method | POST |
| Auth | Bearer Token (required) |
| Content-Type | application/json |

**Request Body:**
```json
{
  "_wf_request_data": "required — Bubble workflow request data (likely base64-encoded image or file reference)"
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

### 4.9 POST /wf/completed-inspection

Mark an inspection as completed.

| Property | Value |
|----------|-------|
| Method | POST |
| Auth | Bearer Token (required) |
| Content-Type | application/json |

**Request Body:**
```json
{
  "_wf_request_data": "required — Bubble workflow request data containing inspection answers and metadata"
}
```

**Success Response (200):**
```json
{
  "status": "string",
  "response": {}
}
```

**Note:** The exact structure of `_wf_request_data` for both `upload-image` and `completed-inspection` needs to be determined from the Bubble workflow configuration. These endpoints use Bubble's generic workflow data mechanism.

---

## 5. Data Model

All data types include the following built-in fields from Bubble: `Creator` (User), `Modified Date` (date), `Created Date` (date), `Slug` (text). These are omitted from individual type definitions below for brevity.

### 5.1 User

The core Bubble user type. Has privacy rules applied (not publicly visible).

| Field | Type | Description |
|-------|------|-------------|
| Linked user profiles | List of User Profile | Associated user profiles |
| List of buildings | List of Buildings | Buildings assigned to this user |
| Name | text | User's display name |
| email | text | User's email address (built-in) |

### 5.2 User Profile

Extended profile information. Publicly visible.

| Field | Type | Description |
|-------|------|-------------|
| Linked user | User | The Bubble user this profile belongs to |
| Name | text | Profile display name |

### 5.3 Buildings

A building or block that contains assets to be inspected. Publicly visible.

| Field | Type | Description |
|-------|------|-------------|
| List of assets | List of Assets | Assets contained within this building |
| Name | text | Building name/identifier |

### 5.4 Assets

An inspectable item within a building (e.g. a fire door, lift, boiler). Publicly visible.

| Field | Type | Description |
|-------|------|-------------|
| Assigned to (user profiles) | List of User Profiles | User profiles assigned to inspect this asset |
| Assigned to (user) | User | Primary user assigned to this asset |
| Date of next inspection | date | When the next inspection is due |
| Date of previous inspection | date | When the last inspection occurred |
| Interval (number of days) | number | Days between inspections |
| Linked building | Buildings | The building this asset belongs to |
| List of completed inspections | List of Completed Inspections | Historical inspection records |
| List of question templates | List of Questions (Template) | The checklist questions for this asset type |
| Name | text | Asset name/identifier |

### 5.5 Questions (Template)

A question template that defines what to inspect on an asset. Publicly visible.

| Field | Type | Description |
|-------|------|-------------|
| Linked asset | Assets | The asset this question belongs to |
| Question text | text | The question to ask during inspection |

### 5.6 Questions (Answers)

A recorded answer to a question during a completed inspection. Publicly visible.

| Field | Type | Description |
|-------|------|-------------|
| Answer text | text | The inspector's answer |
| Linked inspection | Completed Inspections | The inspection this answer belongs to |
| Question text | text | The question that was answered (denormalised from template) |

### 5.7 Completed Inspections

A record of a completed inspection. Publicly visible.

| Field | Type | Description |
|-------|------|-------------|
| Date | date | When the inspection was carried out |
| List of question answers | List of Questions (Answers) | All answers recorded during this inspection |

### 5.8 Photo

An image captured during an inspection. Has privacy rules applied.

| Field | Type | Description |
|-------|------|-------------|
| Base64File | text | Base64-encoded image data |
| Image | file | The actual image file stored in Bubble |
| ImageUrl | text | URL to the image |
| Linked asset | Assets | The asset this photo is associated with |

### 5.9 Device

Device information. Has privacy rules applied. Fields not captured in screenshots.

---

## 6. Data Model Relationships (Entity Map)

```
User
 ├── has many → User Profile
 └── has many → Buildings

Buildings
 └── has many → Assets

Assets
 ├── belongs to → Buildings (Linked building)
 ├── assigned to → User / User Profiles
 ├── has many → Questions (Template)
 ├── has many → Completed Inspections
 └── has many → Photos

Questions (Template)
 └── belongs to → Assets (Linked asset)

Completed Inspections
 └── has many → Questions (Answers)

Questions (Answers)
 └── belongs to → Completed Inspections (Linked inspection)

Photo
 └── belongs to → Assets (Linked asset)
```

---

## 7. Error Handling

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

## 8. Privacy & Visibility

| Data Type | Visibility |
|-----------|-----------|
| Assets | Publicly visible |
| Buildings | Publicly visible |
| Completed Inspections | Publicly visible |
| Device | Privacy rules applied |
| Photo | Privacy rules applied |
| Questions (Answers) | Publicly visible |
| Questions (Template) | Publicly visible |
| User | Privacy rules applied |
| User Profile | Publicly visible |

**Note:** "Privacy rules applied" means Bubble's server-side privacy rules restrict which records are returned based on the authenticated user. The Flutter app must always send a valid Bearer token to access these types.

---

## 9. Endpoint Summary

| # | Endpoint | Method | Auth | Purpose |
|---|----------|--------|------|---------|
| 1 | `/wf/login` | POST | None | Authenticate user, obtain JWT |
| 2 | `/wf/fetchbuildings` | GET | Bearer | Fetch all buildings |
| 3 | `/wf/fetchbuilding` | GET | Bearer | Fetch single building by ID |
| 4 | `/wf/fetchassets` | GET | Bearer | Fetch assets for a building |
| 5 | `/wf/fetchassets-old` | GET | Bearer | Legacy: fetch assets (deprecated) |
| 6 | `/wf/fetchquestions` | GET | Bearer | Fetch question templates for an asset |
| 7 | `/wf/fetchchecklist` | GET | Bearer | Fetch checklist for an asset |
| 8 | `/wf/upload-image` | POST | Bearer | Upload an inspection photo |
| 9 | `/wf/completed-inspection` | POST | Bearer | Submit a completed inspection |

---

## 10. Open Questions / Missing Information

The following items need clarification from the Bubble backend:

1. **`_wf_request_data` structure** — The exact JSON structure expected by `upload-image` and `completed-inspection` endpoints is not defined in the Swagger spec. This needs to be documented from the Bubble workflow editor.

2. **Device data type fields** — The fields for Device are behind privacy rules and were not captured.

4. **`/wf/appfetchprofile` endpoint** — Referenced in the original Flutter app spec but absent from the Swagger. Needs to be confirmed whether this endpoint exists in Bubble or was removed.

5. **Response parsing for string endpoints** — Several GET endpoints (`fetchbuildings`, `fetchbuilding`, `fetchassets`, `fetchquestions`) return `type: string` rather than structured JSON. The client must parse these strings into typed objects. The exact JSON structure within these strings should be documented.

6. **Image upload mechanism** — Whether `upload-image` expects base64 in the body, multipart form data, or a Bubble file reference URL needs confirmation.

7. **Inspection completion payload** — What data must be sent to `completed-inspection` (list of question answer IDs? inline answers? asset ID?) needs to be defined.
