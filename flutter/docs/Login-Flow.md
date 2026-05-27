# How Login Works

This guide explains, in plain language, what happens when you sign in to the BlockPro app — from the moment you tap **Sign In** to when you land on your list of buildings.

---

## The short version

1. You enter your email and password and tap **Sign In**.
2. The app sends those details to BlockPro's servers to check you're a real user.
3. If your details are correct, the server sends back a secure "pass" (a token) that proves who you are.
4. The app saves that pass on your device so you don't have to log in again next time.
5. The app then downloads your buildings, your assets, and your inspection checklists so you can work offline.
6. Once everything is downloaded, you land on the home screen.

---

## Step 1 — Tapping "Sign In"

When you open the app, it first checks whether you've logged in before. If it finds a valid saved pass from a previous session, it skips the login screen entirely and takes you straight in.

If not, you'll see the login screen. You type your email and password and tap **Sign In**. The button shows a spinner while the app talks to the server.

---

## Step 2 — Checking your credentials

The app calls the first API:

### `app_login`
**What it does:** Sends your email and password to BlockPro's servers. If they match an account, the server replies with:

- A **security token** — think of it as a temporary pass that proves you're logged in. Every later request includes this pass.
- Your **user ID**.
- An **expiry time** — how long the pass is valid for.

If your details are wrong, you'll see a message like "Failed to login. Please check your email and password." If there's no internet, you'll see "Unable to connect. Please check your internet connection."

The app stores the pass securely on your device so you stay logged in between sessions.

---

## Step 3 — Deciding what to do next

Once you're logged in, the app checks: **do I already have your data on this device?**

- **Yes** (you've used the app before on this device) → it takes you straight to the home screen. No downloading needed.
- **No** (first time logging in, or you've logged out since) → it shows the **Initial Sync** screen and starts downloading your data.

---

## Step 4 — Downloading your data

The sync happens in three phases. You'll see progress on screen for each one.

### Phase 1 — Your buildings

**API called:** `app_fetchbuildings`

**What it does:** Returns the list of all buildings linked to your account — their names, addresses, and basic details. These are saved to the app so you can see your buildings even without internet.

---

### Phase 2 — Assets in each building

**API called:** `app_fetch_all_assets` (called once for each building)

**What it does:** For each building, returns every asset inside it — things like fire doors, extinguishers, lifts, boilers, and so on. Each asset comes with its name, location, due date, and a "last modified" stamp for its checklist.

The "last modified" stamp is important — the app uses it in the next phase to avoid downloading checklists it already has up to date.

---

### Phase 3 — Inspection checklists

**API called:** `app_fetch_checklist_single` (called once per asset that needs it)

**What it does:** Returns the full inspection checklist for a single asset — the chapters, the individual questions, and any existing remedial actions raised against it.

The app is smart here: it only downloads checklists for assets that are new or have changed since your last sync. If a checklist hasn't changed, it's skipped. This keeps sync fast — especially on later logins when most of your data is already up to date.

To speed things up even more, the app downloads up to 5 checklists at the same time.

---

## Step 5 — All done

Once everything's downloaded and saved locally, the app takes you to the home screen and you're ready to start inspecting. Everything you've just downloaded is available even if you lose signal.

---

## What happens next time you open the app

The app remembers your pass from Step 2. When you reopen it:

1. It checks whether the saved pass is still valid.
2. If it is — you go straight to the home screen, no login needed, no downloading needed.
3. If the pass has expired — you're asked to sign in again.

When you explicitly **log out**, the app deletes your pass and wipes the local data from the device, so the next login starts fresh.

---

## Quick reference — APIs used during login

| API | Purpose |
|---|---|
| `app_login` | Verifies your email and password, returns a security token. |
| `app_fetchbuildings` | Downloads the list of buildings on your account. |
| `app_fetch_all_assets` | Downloads the assets inside a building (called once per building). |
| `app_fetch_checklist_single` | Downloads the inspection checklist for an asset (only called for assets that are new or have changed). |

---

## If something goes wrong

| Message | What it means |
|---|---|
| "Failed to login. Please check your email and password." | The email or password didn't match an account. |
| "Unable to connect. Please check your internet connection." | The app couldn't reach the server — likely a network issue. |
| "The request timed out. Please try again." | The server took too long to respond. |
| "Your session has expired. Please sign in again." | Your saved pass is no longer valid. |
| "Something went wrong. Please try again." | An unexpected error — retrying usually works. |

If the initial sync fails partway through, you'll see a **Retry** button that restarts the download from where it's needed. Any data already downloaded is kept.
