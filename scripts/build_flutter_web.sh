#!/bin/bash
set -e

echo "=== Checking Flutter SDK ==="
if [ ! -d "$HOME/flutter" ]; then
  echo "Cloning Flutter stable SDK..."
  git clone https://github.com/flutter/flutter.git -b stable --depth 1 "$HOME/flutter"
else
  echo "Using cached Flutter SDK."
fi

export PATH="$PATH:$HOME/flutter/bin"
flutter config --no-analytics
flutter --version

echo "=== Getting dependencies ==="
flutter pub get

echo "=== Building Flutter Web (Release) ==="
flutter build web --release

echo "=== Copying routing and headers ==="
cp web/_redirects build/web/_redirects 2>/dev/null || true
cp web/_headers build/web/_headers 2>/dev/null || true

echo "=== Build completed successfully! ==="
