---
name: yocto-build-macos-docker
description: Build Yocto projects on macOS using Docker with case-sensitive volume isolation
pattern_type: workaround
learned_at: 2026-06-22T21:51:56
source_session: 701c6df9-3e57-48d3-83b1-c6853651133e
---

## When to use
Building Yocto/BitBake-based embedded projects on macOS (Raspberry Pi, etc.) when encountering case-sensitivity errors or when Docker credential helper blocks pulls in headless sessions.

## How
1. Create a Docker volume for the build directory: `docker volume create omelet-build`
2. Build a custom builder image from locally cached base images (e.g., `debian:stable-slim`, `node:20-slim`) to avoid pull failures
3. Mount the volume into the builder container and run all Yocto operations inside the container
4. All layer clones (poky, meta-openembedded, meta-raspberrypi) and build artifacts stay in the ext4 volume (case-sensitive)
5. Copy built images back to macOS with a deploy script after completion

Example: `docker run --rm -v omelet-build:/build omelet-builder:latest ./scripts/build.sh checkout && ./scripts/build.sh build`

## Why
APFS (macOS default filesystem) is case-insensitive, but Yocto recipe parsing requires case-sensitive paths. Layer names like `meta-omelet` vs `META-OMELET` cause build failures. Docker volumes use Linux ext4 (case-sensitive), isolating the build from APFS limitations without modifying the host filesystem.
