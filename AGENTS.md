# MotionLog project instructions

## Verification

- For every iOS app fix, a successful build is not sufficient. Rebuild and reinstall the app, then exercise the affected user flow end to end in the iOS Simulator before reporting completion.
- After an app crash, stop the existing run, rebuild, reinstall, and relaunch the app in the simulator automatically.
- Report any part of the flow that could not be exercised; do not describe an untested fix as complete.
- After any UX change, run the end-to-end test by driving the simulator yourself (taps, swipes, typing) the way a user would, and record the run as a video (`xcrun simctl io <device> recordVideo`). Afterwards, review the recording (for example by extracting frames) to confirm every step looks right before reporting the change as done.

## User working preferences

- When the user gives a durable, project-specific instruction about how the agent should work on MotionLog, add that preference to this `AGENTS.md` so it applies in future sessions.
- Whenever the audio-to-structure evaluation pipeline changes, update `docs/prds/audio-to-structure-eval-pipeline.md` in the same change. Review and update its Mermaid pipeline diagram, implementation details, and `Last updated` date so the PRD remains an accurate reference.
- Treat one-off task directions as temporary. Do not persist secrets, credentials, sensitive personal information, or instructions unrelated to this project.
- When a new preference is persisted, tell the user that `AGENTS.md` was updated and briefly state what was added.

