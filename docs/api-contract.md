# MVP API contract

All user-owned tables use the authenticated Supabase user ID and Row Level Security. Exercise `name` is the only required prescription field; all targets and media are optional.

## Authentication

### Request SMS code

`POST /auth/v1/otp`

```json
{ "phone": "+12125550123", "create_user": true }
```

### Verify SMS code

`POST /auth/v1/verify`

```json
{ "phone": "+12125550123", "token": "123456", "type": "sms" }
```

The returned access and refresh tokens are stored in the iOS Keychain. Phone numbers remain in Supabase Auth and are not duplicated into health-data tables.

## Current routine

`GET /rest/v1/routines?scheduled_for=lte.2026-11-06&order=scheduled_for.desc&limit=1&select=*,routine_items(*,exercise:exercises(*))`

For the MVP, `scheduled_for` is the routine version's effective date. The most recent routine whose effective date is today or earlier is the user's current prescription and remains active until a newer version is created. Routine items are ordered by `position`. Exercise logs are date-specific, so changing the current prescription does not rewrite past adherence.

## Exercise log

`POST /rest/v1/exercise_logs`

```json
{
  "session_id": "uuid",
  "exercise_id": "uuid",
  "routine_item_id": "uuid-or-null",
  "performed_at": "2026-11-06T15:20:00Z",
  "sets_completed": 3,
  "reps_per_set": 10,
  "duration_seconds": null,
  "band_resistance": "Red band",
  "weight_value": null,
  "weight_unit": null,
  "notes": null
}
```

Only `exercise_id` is required. Repetition, duration, resistance, weight, and symptom fields may all be omitted.

## Retained voice note

1. Generate an `audio_recordings` ID on the client.
2. Upload the source recording to the private `session-audio` bucket at `{user_id}/{recording_id}.m4a`.
3. Apple speech recognition transcribes the local recording and the MVP parser extracts structured values.
4. The user confirms or edits those values in the normal exercise form.
5. Upload the raw audio and create the linked row with `transcript`, `structured_data`, and a completed `transcription_status`.

If local transcription is unavailable, the raw audio is still uploaded with a pending status so a future server worker can retry it.

Raw audio is retained for the MVP. Access is restricted to its owner.

## History

`GET /rest/v1/exercise_logs?select=*,exercise:exercises(name)&order=performed_at.desc`

## Weekly report

The `weekly_adherence` view aggregates prescribed and completed routine items by week. Symptom notes remain available separately so a report can distinguish adherence from response to exercise.
