#!/bin/zsh

# Xcode Run pre-action for the iOS Simulator's local Whisper fallback.
set -u

readonly health_url="http://127.0.0.1:55330/health"
readonly log_file="/tmp/motionlog-transcription.log"
readonly script_dir="${0:A:h}"

if /usr/bin/curl --fail --silent --max-time 1 "$health_url" >/dev/null 2>&1; then
    exit 0
fi

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:${PATH:-}"
python_bin="$(command -v python3)"

/usr/bin/nohup "$python_bin" "$script_dir/dev_transcription_server.py" >>"$log_file" 2>&1 &

for attempt in {1..20}; do
    if /usr/bin/curl --fail --silent --max-time 1 "$health_url" >/dev/null 2>&1; then
        exit 0
    fi
    /bin/sleep 0.25
done

echo "MotionLog transcription server did not start. See $log_file" >&2
# Do not block unrelated builds or tests if localhost networking is unavailable.
# The app surfaces a targeted retry message if voice transcription needs it.
exit 0
