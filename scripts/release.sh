#!/usr/bin/env bash
# Builds a release APK locally and publishes it as a GitHub release asset.
# Signed with the committed debug.keystore, so it still installs as an update
# over anything built before.
#
# The tag is exactly the app's version, with no "v" and no commit suffix, so it
# matches the versionName inside the APK. Obtainium compares the version a
# release advertises against the version Android reports for the installed app,
# and can only do that when the two are the same shape.
set -euo pipefail

cd "$(dirname "$0")/.."

app_name=$(basename "$(pwd)")

current=$(grep '^version:' pubspec.yaml | head -1 | awk '{print $2}')
current_version=${current%%+*}
current_build=${current##*+}

# Every release gets its own version. Shipping the same version twice leaves
# Obtainium nothing to compare, and Android no reason to treat the APK as an
# update.
major=$(echo "$current_version" | cut -d. -f1)
minor=$(echo "$current_version" | cut -d. -f2)
patch=$(echo "$current_version" | cut -d. -f3)
next_version="$major.$minor.$((patch + 1))"
next_build=$((current_build + 1))
tag="$next_version"

# Release, not debug: a debug build has no AOT snapshot, starts far slower and
# is four times the size. arm64-v8a covers every real Android phone from the
# last ~8 years.
apk_path="build/app/outputs/flutter-apk/app-arm64-v8a-release.apk"

echo "==> $app_name $current_version -> $next_version"

if gh release view "$tag" >/dev/null 2>&1; then
  echo "!! Release $tag already exists; bump past it or delete it first." >&2
  exit 1
fi

sed -i "s/^version: .*/version: $next_version+$next_build/" pubspec.yaml

flutter pub get
flutter analyze
flutter test
flutter build apk --release --target-platform android-arm64 --split-per-abi

git add pubspec.yaml
git commit -m "Release $next_version"

# gh release create --target takes a commit the remote already has.
git push origin HEAD

gh release create "$tag" "$apk_path" \
  --title "$app_name $next_version" \
  --notes "$(git log -1 --pretty=%s)" \
  --target "$(git rev-parse HEAD)"

gh release view "$tag" --json url --jq .url
