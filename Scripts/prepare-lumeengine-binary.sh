#!/usr/bin/env bash
set -euo pipefail

ENGINE_DIR="${1:?usage: prepare-lumeengine-binary.sh <LumeEngine directory>}"
ARTIFACT_URL="https://github.com/bilipp/LumeEngine/releases/download/v0.3.0/FFmpeg.xcframework.zip"
ARTIFACT_SHA256="4aed787a0cf05067395bb5b07f1af96c25e1314a841bc1597e37964dd009b5b0"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

FFMPEG_DIR="$ENGINE_DIR/BinaryDependencies/FFmpeg.xcframework"
if [ ! -d "$FFMPEG_DIR" ]; then
    mkdir -p "$ENGINE_DIR/BinaryDependencies"
    curl --fail --location --silent --show-error "$ARTIFACT_URL" \
        --output "$WORK_DIR/FFmpeg.xcframework.zip"
    echo "$ARTIFACT_SHA256  $WORK_DIR/FFmpeg.xcframework.zip" | shasum --algorithm 256 --check --status
    unzip -q "$WORK_DIR/FFmpeg.xcframework.zip" -d "$ENGINE_DIR/BinaryDependencies"
fi

for headers in "$FFMPEG_DIR"/*/Headers; do
    [ -d "$headers" ] || continue
    if [ -f "$headers/module.modulemap" ]; then
        mkdir -p "$headers/CFFmpeg"
        mv "$headers/module.modulemap" "$headers/CFFmpeg/module.modulemap"
        mv "$headers/CFFmpeg.h" "$headers/CFFmpeg/CFFmpeg.h"
        mv "$headers/CFFmpegShim.h" "$headers/CFFmpeg/CFFmpegShim.h"
    fi
done
