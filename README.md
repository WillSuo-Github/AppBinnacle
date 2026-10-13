# AppBinnacle

AppBinnacle is an open-source macOS app and command-line tool that puts your App Store Connect and Firebase numbers side by side. It shows downloads, proceeds, engagement, stability, and reviews for each of your apps, and it turns the same data into a short brief you can hand to an AI agent.

Everything runs on your Mac. Your App Store Connect key and Google service account stay in your login Keychain, and AppBinnacle talks directly to Apple and Google.

## What version 0.1 does

- **Dashboards:** Overview, Downloads & Revenue, Engagement, Stability, Reviews, and AI Brief, for 7, 14, 30, or 90 days, each compared with the period before it.
- **App Store Connect:** daily sales reports (first downloads, redownloads, updates, in-app purchases, proceeds by currency, top countries) and the latest customer reviews.
- **Firebase:** active users, new users, sessions, and crash-free users from the Google Analytics Data API, plus the top open issues from the Crashlytics API.
- **`binnacle` CLI:** the same data as Markdown or JSON, designed to be pasted into an AI conversation or used by an agent.

## Requirements

- macOS 14 or later
- Xcode 16 or later
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`). The Xcode project is generated from `project.yml` and is not checked in.

## Build

```sh
./script/build_and_run.sh      # generate the project, build, and launch the app
./script/test.sh               # run the unit tests
./script/build_cli.sh          # build binnacle and print its path
```

To work in Xcode, run `./script/generate_project.sh` and open `AppBinnacle.xcodeproj`. Set `BINNACLE_DERIVED_DATA` to choose where the scripts put build products.

## Connect your accounts

Open **AppBinnacle → Settings…**, or use `binnacle config`.

**App Store Connect.** Create a team API key in App Store Connect → Users and Access → Integrations. Sales reports need the Sales, Finance, or Admin role. Enter the issuer ID and key ID, import the `.p8` file, and add your vendor number from Payments and Financial Reports.

**Firebase and Google Analytics.** Create a service account in the Google Cloud project behind your Firebase project and download a JSON key. Then:

1. Enable the Google Analytics Data API and the Firebase Crashlytics API for that Cloud project.
2. Add the service account's email as a **Viewer** on each GA4 property (Google Analytics → Admin → Property access management).
3. Give it the **Firebase Crashlytics Viewer** role in the Firebase project.

**Apps.** Import your apps from App Store Connect, then fill in each app's GA4 property ID and Firebase app ID (Firebase → Project settings → Your apps). Set a GA4 stream ID when one property holds several platforms.

```sh
binnacle config set-asc --issuer-id <issuer> --private-key ~/Downloads/AuthKey_ABC123DEFG.p8 --vendor-number 80012345
binnacle config set-google --service-account ~/Downloads/my-project-123abc.json
binnacle apps --import
binnacle config set-app 1234567890 --ga4-property 987654321 --firebase-app-id 1:1234567890:ios:abc123
binnacle doctor
```

## Use the CLI

```sh
binnacle brief                                   # every tracked app, last 7 days, Markdown
binnacle brief --app com.example.app --days 30   # one app, last 30 days
binnacle brief --format json                     # structured output for agents
binnacle snapshot --app com.example.app          # every daily value behind the dashboards
```

A brief looks like this:

```markdown
# Weather Pal — 2026-10-06 to 2026-10-12
com.example.weatherpal · Apple ID 1234567890 · compared with 2026-09-29 to 2026-10-05

## Highlights
- Active users fell 20.0% (1,000 → 800).
- Crash-free users fell 1.00 pp to 98.50%.
- Version 3.2.0 has 98.00% crash-free users (500 active users).
- Top open Crashlytics issue: EXC_BAD_ACCESS in WeatherStore.refresh() (120 events, 33 users).
- 1 new 1–2★ review.
```

`binnacle` reads the credentials the app saved in your Keychain. macOS asks whether `binnacle` may read them; choose **Always Allow**. A newly built copy of `binnacle` may be asked again. For CI, scripts, or agents you can skip the Keychain with environment variables:

| Variable | Meaning |
|---|---|
| `BINNACLE_ASC_ISSUER_ID`, `BINNACLE_ASC_KEY_ID`, `BINNACLE_ASC_VENDOR_NUMBER` | Override saved App Store Connect settings |
| `BINNACLE_ASC_PRIVATE_KEY_PATH` | Path to the `.p8` key |
| `BINNACLE_GOOGLE_SERVICE_ACCOUNT_PATH` | Path to the service account JSON key |
| `BINNACLE_CONFIG` | Use a different configuration file |

`binnacle brief` and `binnacle snapshot` exit with status 1 when no data source could be loaded, and `binnacle doctor` exits with status 1 when a check fails.

## How the numbers are counted

- **First downloads** count the Product Type Identifiers `1`, `1F`, `1T`, and `F1`. Redownloads are `3` and `3F`; updates are `7`, `7F`, `7T`, and `F7`; in-app purchases are `IA1`, `IA9`, `IAY`, and `FI1`. Any other code, such as app bundles (`1-B`), is listed separately as unclassified instead of being guessed. See Apple's [product type identifiers](https://developer.apple.com/help/app-store-connect/reference/reporting/product-type-identifiers/).
- **In-app purchases and proceeds** are matched to an app through its SKU, because sales reports list the parent app's SKU on in-app purchase rows.
- **Report timing.** Sales reports use Pacific Time and are usually published the next day. When the last day or two are not published yet, the sales comparison ends at the latest published day instead of counting those days as zero. Periods end yesterday in Pacific Time, and reviews are grouped by the same Pacific Time day.
- **Proceeds** are shown per currency of proceeds, without exchange-rate conversion. Your region's currency is listed first, then USD.
- **Active users** for a period are de-duplicated by Google Analytics; they are not the sum of daily values. **Crash-free users** come from GA4's `crashFreeUsersRate`.
- **Crashlytics issues** come from the Crashlytics REST API, which is still `v1alpha` and may change.

## Privacy

AppBinnacle has no server and no telemetry. Credentials are stored as generic passwords under the `dev.appbinnacle.credentials` service in your login Keychain. Settings live in `~/Library/Application Support/AppBinnacle/config.json` (without secrets), and downloaded reports are cached in `~/Library/Caches/AppBinnacle`.

## Project layout

| Path | Contents |
|---|---|
| `Shared/` | Credentials, API clients, report parsing, snapshots, and the brief. Compiled into the app, the CLI, and the tests. |
| `App/` | SwiftUI app |
| `CLI/` | `binnacle`, built with Swift Argument Parser |
| `Tests/` | Swift Testing unit tests with recorded fixtures |
| `script/` | Build, run, and test scripts |

## License

MIT
