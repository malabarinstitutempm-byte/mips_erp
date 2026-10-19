#!/bin/bash
set -e

FLUTTER_VERSION="3.35.5"

echo "=== Checking Flutter SDK ($FLUTTER_VERSION) ==="
if [ ! -d "$HOME/flutter" ]; then
  echo "Cloning Flutter $FLUTTER_VERSION SDK..."
  git clone https://github.com/flutter/flutter.git -b "$FLUTTER_VERSION" --depth 1 "$HOME/flutter"
else
  echo "Checking Flutter SDK version..."
  cd "$HOME/flutter"
  git fetch --depth 1 origin "$FLUTTER_VERSION" 2>/dev/null || true
  git checkout "$FLUTTER_VERSION" 2>/dev/null || true
  cd - > /dev/null
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
