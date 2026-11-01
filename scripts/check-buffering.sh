#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
check_dir="$(mktemp -d /tmp/narrateify-checks.XXXXXX)"
python3 - "$check_dir/silence.wav" <<'PY'
import sys,wave
with wave.open(sys.argv[1],'wb') as w:
 w.setnchannels(1);w.setsampwidth(2);w.setframerate(24000);w.writeframes(b'\x00\x00'*24000)
PY
swiftc -module-cache-path "${SWIFT_MODULE_CACHE_PATH:-$check_dir/cache}" Sources/BufferedTextChunker.swift Checks/Chunking.swift -o "$check_dir/chunking"
"$check_dir/chunking"
swiftc -module-cache-path "${SWIFT_MODULE_CACHE_PATH:-$check_dir/cache}" Sources/AudioController.swift Checks/Playback.swift -o "$check_dir/playback"
"$check_dir/playback" "$check_dir/silence.wav"
