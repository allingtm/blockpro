# Backend Workflow: `app_completed-inspection`

## Overview

`app_completed-inspection` is a Bubble.io backend API workflow that records a
completed inspection. It creates a **Completed inspection** record, appends that
record to the inspected **Asset**'s list of completed inspections, then fans out
one scheduled call to `app_create-completed-question` per answer in the request,
so each submitted question/answer is persisted as its own record.

It is the server-side endpoint the Flutter app calls when a user finishes (and
submits) an inspection.

## Trigger — API Event (`app_completed-inspection is called`)

| Property | Value |
|---|---|
| **Endpoint name** | `app_completed-inspection` |
| **Expose as public API workflow** | On |
| **Authentication** | User & admin |
| **Ignore privacy rules** | Off |
| **Trigger method** | `POST` |
| **Parameter definition** | Detect request data |
| **Include headers in detected data** | Off |
| **Response type** | JSON Object |
| **Return 200 if condition not met** | Off |

> **Parameter definition** is set to **Detect request data**, so the request
> body shape is inferred from a sample request rather than declared manually.
> Among the detected fields is an `answers` list (each entry exposing an
> `answer` text), plus the asset being inspected.

## Step 1 — Create a new Completed inspections…

Creates a record in the **Completed inspections** data type.

| Property | Value |
|---|---|
| **Type** | Completed inspections |
| **Fields** | *No fields added* |
| **Disable action** | Off |

> No fields are populated on creation — the record is created "empty" and used
> as a handle that is linked to the asset (Step 2) and to each question record
> (Step 3). Any inspection-level metadata (date, inspector, asset) would need to
> be added here if required.

## Step 2 — Make changes to Asset…

Updates the inspected **Asset** to reference the inspection created in Step 1.

| Property | Value |
|---|---|
| **Thing to change** | `Search for Assets:first item` |
| **Field changed** | `List of completed inspections add Result of step 1 (Create a new Comp...)` |
| **Disable action** | Off |

Appends the newly created Completed inspection to the Asset's
`List of completed inspections` field.

> **Note:** the Asset is resolved via `Search for Assets:first item`. The visible
> config does not show the search constraint, but it should be constrained to the
> asset identified in the request — otherwise it will always grab the first asset
> in the database. **Confirm the search has a constraint** (see Observations).

## Step 3 — Schedule API Workflow `app_create-completed-question` on a list

Schedules one run of `app_create-completed-question` for **each** answer in the
request's `answers` list, persisting each answer as its own question record.

| Property | Value |
|---|---|
| **Type of things** | Request Data answer |
| **List to run on** | `Request Data's answers` |
| **API Workflow** | `app_create-completed-question` |
| **Scheduled date** | `Current date/time` |
| **Interval (seconds)** | `2` |
| **Ignore privacy rules** | Off |
| **Disable action** | Off |

**Parameters passed to each scheduled run:**

| Param | Value |
|---|---|
| **answer text** | `This Request Data answer's answer` |
| **completed inspection** | `Result of step 1 (Create a new Comp...)` |

Each scheduled run receives the individual answer's text and the same parent
Completed inspection record (from Step 1), so all question records link back to
the one inspection. The `2`-second interval staggers the scheduled runs.

---

## Summary of the flow

```
POST { ...inspection data, answers: [ { answer }, ... ] }
        │
        ▼
Step 1: Create Completed inspections record (empty)
        │
        ▼
Step 2: Make changes to Asset (Search for Assets:first item)
        → List of completed inspections add (Result of step 1)
        │
        ▼
Step 3: Schedule app_create-completed-question on the list "Request Data's answers"
        for each answer → { answer text = this answer's answer,
                            completed inspection = Result of step 1 }
        (Current date/time, 2s interval between runs)
```

## Client payload contract

The Flutter app (`InspectionProvider.submit`) POSTs:

```json
{
  "asset_id": "<asset id>",
  "answers": [ { "answer": "<answer text>" }, ... ],
  "photo_ids": [ "<image id>", ... ]   // only when photos were uploaded
}
```

> **Important:** each `answers` item must use the sub-field name **`answer`** —
> Step 3 reads `This Request Data answer's answer`. The app originally sent
> `answer_text` (with `question_text`), which Bubble's *Detect request data* had
> not inferred as `answer`, so every Questions (answers) record was created with
> a blank answer. Fixed by renaming the payload key to `answer`. See Observation 5.

## Observations / potential issues

1. **`Search for Assets:first item` (Step 2)** — without a visible constraint
   this resolves to the *first* asset in the database, not the inspected one.
   Confirm the search is constrained by the asset id from the request; an
   unconstrained search is a likely bug that would attach every inspection to
   the same asset.
2. **Step 1 creates an empty record** — no fields (date, inspector, asset
   reference) are set. Inspection-level metadata, if needed, must be added here.
   Currently the record's only meaning comes from the relationships built in
   Steps 2 and 3.
3. **Scheduled (async) question creation** — Step 3 schedules the per-question
   workflow rather than running it inline, with a `2`s interval. The API
   response (JSON Object) will return *before* the question records are created,
   so the client cannot assume the questions exist immediately after the call
   succeeds.
4. **No explicit "Return data from API" step shown** — the workflow ends at
   Step 3 in the canvas. Confirm whether a response/return step is expected
   (the trigger's response type is JSON Object).
5. **(RESOLVED) Empty answer records** — `app_create-completed-question` is
   wired correctly (`Answer text = answer text`, `Linked inspection =
   completed inspection`), but Step 3 here feeds it `This answer's answer`. The
   app was sending `answer_text`, not `answer`, so `answer text` resolved empty
   and every created Questions (answers) record was blank. Fixed on the **app**
   side by renaming the payload key `answer_text` → `answer` (the field Bubble
   already expects), rather than re-detecting request data in Bubble. The
   `question_text` field was dropped since the backend does not consume it.
