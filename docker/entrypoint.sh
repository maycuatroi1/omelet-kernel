#!/bin/bash
# Make the build volume + workdirs writable by the unprivileged builder user,
# then drop privileges. bitbake refuses to run as root.
set -e

for d in /build /work; do
    if [ -d "$d" ]; then
        chown builder:builder "$d" 2>/dev/null || true
    fi
done

# Persisted build dir lives in the (case-sensitive ext4) Docker volume.
export KAS_WORK_DIR="${KAS_WORK_DIR:-/build}"
export KAS_BUILD_DIR="${KAS_BUILD_DIR:-/build/build}"
export HOME=/home/builder

exec gosu builder "$@"
