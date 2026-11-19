#!/bin/sh
# Build the web version into build/web: the Godot export, plus the boot
# intro video the page plays while the engine loads (web/intro.mp4).
set -e
cd "$(dirname "$0")/.."
godot --headless --path . --export-release Web build/web/index.html
cp web/intro.mp4 build/web/index.intro.mp4
echo "web build ready in build/web"
