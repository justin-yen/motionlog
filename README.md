# PT Tracker

Native iOS and Supabase scaffold for the PT Tracker MVP.

## Hosted backend

- Project: `PT Tracker`
- Project reference: `wctyjzivvpudiydvkkcs`
- Region: `us-east-1`
- Dashboard: https://supabase.com/dashboard/project/wctyjzivvpudiydvkkcs

The workspace is linked and the versioned migrations have been applied to the hosted database.

### Development phone login

- Phone: `+1 202-555-0147`
- Code: `123456`

This is a fictional test number. Supabase accepts its fixed code without sending a message. A development-only Send SMS Hook rejects every real phone number, preventing accidental SMS charges. Remove `[auth.sms.test_otp]`, replace the hook with a real provider, and expire the test user before beta.

## First vertical slice

1. Sign in with a phone number and SMS code.
2. View today's prescribed routine.
3. Select an exercise in any order.
4. Log reps, duration, band resistance, or weight.
5. Optionally retain a voice note with the log.
6. Review the saved exercise history.

Voice notes are transcribed with Apple's speech recognition after recording stops. The MVP parser recognizes common phrases for sets/reps, seconds or minutes, band color/resistance, pounds or kilograms, and “each side.” Extracted values populate the normal editable fields so the user confirms or corrects them before saving. The raw audio, transcript, and confirmed structured data are retained together.

### Seeded development prescription

The hosted test account has a routine effective November 6, 2026. It remains the current routine on subsequent days until a newer prescription replaces it:

- Shoulder flexion wall slide (facing wall), 3 × 10
- Shoulder flexion wall slide (facing forward), 3 × 10
- Thoracic twist, 3 × 10 each side
- Plank into downward dog, 3 × 10

The iOS app runs with seeded local data when Supabase configuration is absent. That keeps UI development and previews independent from the hosted backend.

## Layout

- `supabase/` contains the local configuration and versioned database migrations.
- `docs/api-contract.md` documents the data boundary shared by iOS and the backend.
- `ios/PTTracker/` contains the SwiftUI application source.
- `ios/project.yml` is the reproducible XcodeGen project definition.

## Local backend

From this directory:

```sh
supabase start
supabase db reset
```

Phone auth can use Supabase test phone numbers locally. A hosted environment will need an SMS provider and rate limits before real OTP delivery is enabled.

## iOS configuration

Copy `ios/Config/Secrets.xcconfig.example` to `ios/Config/Secrets.xcconfig` and set the public Supabase URL and anon key. Never place the service-role key in the app.

If XcodeGen is installed, generate the project with:

```sh
cd ios
xcodegen generate
```

`PTTracker.xcodeproj` is already generated and can be opened directly. Regenerate it after changing `project.yml`.

Until a hosted backend is configured, launch with `PT_USE_MOCK_DATA = YES` to use the included sample routine.

## Verification

The project is configured to build without code signing for CI-style checks:

```sh
xcodebuild -project PTTracker.xcodeproj -scheme PTTracker \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/PTTrackerDerivedData CODE_SIGNING_ALLOWED=NO build
```
