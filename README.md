# AppBinnacle

AppBinnacle is an open-source macOS app and command-line tool that brings your App Store Connect and Firebase metrics together into a unified, privacy-first developer cockpit. It tracks sales, downloads, proceeds, active users, stability, and customer reviews across your entire product portfolio, and turns complex telemetry into compact, actionable digests ready for AI agents or spreadsheet exports.

Everything runs locally on your Mac. Your App Store Connect private keys and Google service accounts remain securely in your macOS Keychain, and AppBinnacle communicates directly with Apple and Google APIs with zero third-party intermediaries.

---

## Features

### 1. Studio-Wide "All Apps" Portfolio & Deep-Dive Navigation
* **All Apps Macro Overview**: Select **All Apps** in the app menu to aggregate total downloads, proceeds, GA4 active users, studio-wide crash-free rate, and reviews across all tracked applications.
* **All Products Matrix**: A multi-app overview table displaying key performance indicators (Downloads, Revenue, Active Users, Crash-Free %, and Review Counts) for every product with one-click drilldown into individual dashboards.
* **Click-to-Detail Navigation**: Click any top metric card or chart in the Overview to push directly into that section's detailed report, with native macOS Back navigation (`<`) and keyboard shortcut (`⌘[`).

### 2. Multi-Dimensional Dashboards & Analytics
* **Downloads & Revenue**:
  * Track First Downloads, Redownloads, In-App Purchases, and Updates.
  * Monitor business health ratios: **Redownload Ratio** (`% of total installs`) and **IAP Conversion Rate**.
  * Switch between **Daily Units** (stacked bar breakdown) and **Cumulative Growth** (smooth cumulative install trajectory curve).
  * **Top Markets & Geography**: Ranked country breakdown with country flags, download volumes, and global percentage share bars.
* **Engagement & Retention**:
  * Track Total Active Users, New Users, and Total Sessions.
  * Evaluate user quality with **User Stickiness** (`Sessions per Active User`, e.g., `3.6x`) and **New User Ratio** (`% of active users`).
  * Switch between **Active Users** (with dashed previous-period comparison curve) and **Sessions & Frequency** usage intensity.
* **Stability & Crash Diagnostics**:
  * View daily Crash-Free Users % and crash-affected user counts.
  * **Version Adoption & Stability Health Matrix**: Track active users, adoption share percentage bars, crash-affected users, and health status badges (`Healthy`, `Monitor`, `High Risk`) across app versions.
  * **Crashlytics Issue Filter**: Filter open issues by severity (`All Issues`, `Fatal Crashes`, `Non-Fatal`, `ANRs`) with direct links to Firebase Console.
* **Customer Reviews & Sentiment**:
  * Monitor sentiment health: **Positive Sentiment %** (4–5★) vs. **Critical Feedback %** (1–2★).
  * Rating distribution bar chart and **Feedback by Territory** breakdown.
  * Filter reviews by star ratings and read complete user feedback with territory flags.
* **Report Center & AI Brief**:
  * Render reports in **Markdown**, **JSON**, or **CSV Table**.
  * Shows character counts and estimated AI prompt token usage.

---

## Exporting Reports & Datasets

AppBinnacle provides full data export capabilities for both GUI and CLI workflows.

### GUI Exporting
* **Dedicated CSV Export on Every Report**:
  * **Downloads & Revenue**: Click **Export Sales CSV** in the header to export the full daily time-series of downloads, redownloads, updates, IAP, and proceeds.
  * **Engagement**: Click **Export Engagement CSV** to save daily active users, new users, sessions, and crash-free rates.
  * **Stability**: Click **Export Stability CSV** to export version adoption metrics and Crashlytics open issue reports.
  * **Reviews**: Click **Export Reviews CSV** to download all customer reviews with date, rating, title, reviewer, country, and body.
* **Report Center File Export**:
  * In the **AI Brief** tab, choose your preferred format (**Markdown**, **JSON**, or **CSV Table**), then click **Export to File…** to save directly via native macOS `NSSavePanel` (`.md`, `.json`, or `.csv`).

### CLI Exporting (`binnacle`)

The `binnacle` command-line tool supports structured CSV, JSON, and Markdown formats:

```sh
# Export portfolio summary as CSV (ideal for Numbers / Excel)
binnacle brief --format csv > studio-report.csv

# Export 30-day report for a specific app as CSV
binnacle brief --app Countly --days 30 --format csv > countly-30d.csv

# Default compact Markdown brief for AI prompts
binnacle brief --days 7

# Structured JSON for automation pipelines and agent tools
binnacle brief --format json

# Export raw daily snapshot behind all charts
binnacle snapshot --app com.example.app > snapshot.json
```

---

## Requirements

* macOS 14.0 or later
* Xcode 16.0 or later
* [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`). The Xcode project is generated from `project.yml` and is not checked into git.

---

## Build & Install

```sh
# Generate project, build Release app, and launch
./script/build_and_run.sh

# Run the automated test suite (42 unit tests)
./script/test.sh

# Build the binnacle CLI binary
./script/build_cli.sh --release
```

To install `AppBinnacle.app` into your macOS Applications folder:
```sh
cp -R $(./script/build_cli.sh --release | sed 's|/binnacle|/AppBinnacle.app|') /Applications/
```

To install `binnacle` CLI into your user PATH:
```sh
cp $(./script/build_cli.sh --release) ~/.local/bin/binnacle
```

---

## Connect Your Accounts

Configure accounts via **AppBinnacle → Settings…** (⌘,) or via the CLI `binnacle config`.

### App Store Connect
Create a team API key in **App Store Connect → Users and Access → Integrations**:
1. Role required: **Sales**, **Finance**, or **Admin** (needed to download sales reports).
2. Note your **Issuer ID** and **Key ID**.
3. Import your `.p8` private key file into Keychain.
4. Fill in your **Vendor Number** (found in App Store Connect under Payments and Financial Reports).

### Firebase & Google Analytics
Create a Service Account in the Google Cloud project associated with your Firebase project and download a JSON key:
1. Enable the **Google Analytics Data API** and **Firebase Crashlytics API** in Google Cloud Console.
2. In Google Analytics (Admin → Property access management), add the service account email as a **Viewer** on each GA4 property.
3. In Firebase (Project settings → Users and permissions), assign the service account the **Firebase Crashlytics Viewer** role.

### Apps Configuration
Import apps automatically or configure them via CLI:
```sh
binnacle config set-asc --issuer-id <issuer-id> --private-key ~/Downloads/AuthKey_ABC123DEFG.p8 --vendor-number 80012345
binnacle config set-google --service-account ~/Downloads/service-account.json
binnacle apps --import
binnacle config set-app 6529533104 --ga4-property 510279366 --firebase-app-id 1:810843356157:ios:com.ws.MenuCounter
binnacle doctor
```

---

## CLI Environment Overrides

For automated CI/CD runs, headless servers, or agent sandboxes, you can bypass Keychain prompts with environment variables:

| Variable | Description |
|---|---|
| `BINNACLE_ASC_ISSUER_ID` | App Store Connect API Issuer ID |
| `BINNACLE_ASC_KEY_ID` | App Store Connect API Key ID |
| `BINNACLE_ASC_VENDOR_NUMBER` | App Store Connect Vendor Number for sales reports |
| `BINNACLE_ASC_PRIVATE_KEY_PATH` | Path to the `.p8` private key file |
| `BINNACLE_GOOGLE_SERVICE_ACCOUNT_PATH` | Path to Google Cloud Service Account JSON key |
| `BINNACLE_CONFIG` | Path to custom `config.json` configuration file |

---

## Privacy & Security

* **Local-First Architecture**: AppBinnacle has no backend server and collects zero analytics or telemetry.
* **Encrypted Keychain Storage**: Secrets are stored as generic passwords under `dev.appbinnacle.credentials` in your login Keychain.
* **Isolated File Caches**: Non-sensitive settings are stored in `~/Library/Application Support/AppBinnacle/config.json`, and gzip sales reports are cached in `~/Library/Caches/AppBinnacle`.

---

## Project Structure

| Path | Description |
|---|---|
| `Shared/` | Core models, API clients (App Store Connect, GA4, Crashlytics), report generators, portfolio aggregators, and CSV exporters. Shared across App, CLI, and Tests. |
| `App/` | Native macOS SwiftUI application and view components. |
| `CLI/` | `binnacle` command-line tool built with Swift Argument Parser. |
| `Tests/` | Swift Testing test suite with recorded API fixtures. |
| `script/` | Project generation, build, run, and test triage scripts. |

---

## License

MIT License. Copyright © 2026 AppBinnacle contributors.
