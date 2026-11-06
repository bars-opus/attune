#!/usr/bin/env bash
# Spec 1 §3.14 (W10b): what Spec 1 adds to the download, against its 1.5 MB
# budget. Builds the Android arm64 release APK (what Play delivers to most
# phones, per ABI) and the iOS release app (unsigned) twice: from the tree
# before Spec 1 (git archive of BASE, default 360db8d1~1, the commit before
# W1) and from a copy of the working tree (never in place: a release iOS
# build runs `pod install`, which can rewrite the tracked ios/Podfile.lock
# and project.pbxproj). Writes the sizes and the differences to
# OUT/size-report.txt (atomically: a failed run leaves no report). Nothing
# is uploaded or signed, and no secret is copied.
#
#   scripts/app_size_report.sh [BASE] [OUT]
#
#   IOS=0          skip the iOS half (each iOS build runs `pod install` and
#                  needs a few GB of free disk).
#   GRADLE_XMX=3G  low-memory mode for the copies only: Gradle heap 3G,
#                  Kotlin in-process, 2 workers (android/gradle.properties
#                  asks for -Xmx8G, which swaps hard on an 8 GB Mac). It
#                  changes how the APK is built, not what is in it.
#   KEEP_TREES=1   keep the two trees (default: removed at exit, also when a
#                  build fails; each tree's build/ is removed once measured).
#
# The script deletes only what it creates: OUT/base-tree and OUT/now-tree
# (it refuses to start if either already exists), its own logs, byte files
# and zips, and its report.
set -euo pipefail
BASE=${1:-360db8d1~1}
OUT=${2:-.superpowers/sdd/2026-11-04-spec1-w10-accessibility-docs/size}
ROOT=$(pwd)
IOS=${IOS:-1}
[[ "$(uname)" == Darwin ]] || IOS=0
mkdir -p "$OUT"
OUT=$(cd "$OUT" && pwd)
if [[ "$OUT" == "$ROOT" ]]; then
  echo "OUT must not be the repo root" >&2
  exit 2
fi
for tree in base-tree now-tree; do
  if [[ -e "$OUT/$tree" ]]; then
    echo "$OUT/$tree already exists; remove it first" >&2
    exit 2
  fi
done

CREATED=()
cleanup() {
  rm -f "$OUT/.size-report.txt.tmp" "$OUT/base-ios.zip" "$OUT/now-ios.zip"
  if [[ "${KEEP_TREES:-}" != 1 ]]; then
    for tree in ${CREATED[@]+"${CREATED[@]}"}; do rm -rf "$tree"; done
  fi
}
trap cleanup EXIT

# This run's own files, so nothing from an earlier run is read as a result.
for label in base now; do
  rm -f "$OUT/$label-apk.bytes" "$OUT/$label-ios.bytes" "$OUT/$label-apk.log" \
    "$OUT/$label-ios.log" "$OUT/$label-pub.log"
done
rm -f "$OUT/size-report.txt"

bytes() { wc -c < "$1" | tr -d ' '; }

low_memory() { # $1 = tree
  [[ -n "${GRADLE_XMX:-}" ]] || return 0
  local props="$1/android/gradle.properties"
  grep -v '^org\.gradle\.jvmargs=' "$props" > "$props.new" || true
  {
    echo "org.gradle.jvmargs=-Xmx$GRADLE_XMX -XX:MaxMetaspaceSize=1G -XX:ReservedCodeCacheSize=256m"
    echo "kotlin.compiler.execution.strategy=in-process"
    echo "org.gradle.workers.max=2"
  } >> "$props.new"
  mv "$props.new" "$props"
}

build() { # $1 = source tree, $2 = label
  (
    cd "$1"
    flutter build apk --release --target-platform android-arm64 \
      --split-per-abi > "$OUT/$2-apk.log" 2>&1
    bytes build/app/outputs/flutter-apk/app-arm64-v8a-release.apk \
      > "$OUT/$2-apk.bytes"
    rm -rf build
    if [[ "$IOS" == 1 ]]; then
      if flutter build ios --release --no-codesign > "$OUT/$2-ios.log" 2>&1 &&
        (cd build/ios/iphoneos && zip -qr -X "$OUT/$2-ios.zip" Runner.app) &&
        bytes "$OUT/$2-ios.zip" > "$OUT/$2-ios.bytes"; then
        :
      else
        rm -f "$OUT/$2-ios.bytes"
        echo "$2: iOS build failed (see $2-ios.log)" >&2
      fi
      rm -f "$OUT/$2-ios.zip"
      rm -rf build
    fi
  )
}

CREATED+=("$OUT/base-tree")
mkdir "$OUT/base-tree"
git archive "$BASE" | tar -x -C "$OUT/base-tree"
low_memory "$OUT/base-tree"
(cd "$OUT/base-tree" && flutter pub get --offline > "$OUT/base-pub.log" 2>&1)
build "$OUT/base-tree" base
[[ "${KEEP_TREES:-}" == 1 ]] || rm -rf "$OUT/base-tree"

# The working tree, copied without build outputs, root-level caches, git
# data, worktrees, the SDD folders (OUT among them), any .env file or any
# signing key. iOS pods are copied only when iOS is built.
CREATED+=("$OUT/now-tree")
pods=()
[[ "$IOS" == 1 ]] || pods=(--exclude /ios/Pods)
rsync -a --exclude build --exclude .dart_tool --exclude '.env*' \
  --exclude key.properties --exclude '*.jks' --exclude '*.keystore' \
  --exclude /.git --exclude /.tool-home --exclude /.worktrees \
  --exclude /.superpowers --exclude /reference --exclude /coverage \
  ${pods[@]+"${pods[@]}"} "$ROOT/" "$OUT/now-tree"
low_memory "$OUT/now-tree"
(cd "$OUT/now-tree" && flutter pub get --offline > "$OUT/now-pub.log" 2>&1)
build "$OUT/now-tree" now
[[ "${KEEP_TREES:-}" == 1 ]] || rm -rf "$OUT/now-tree"

mb() { awk -v b="$1" 'BEGIN { printf "%.2f", b / 1048576 }'; }
mbs() { awk -v b="$1" 'BEGIN { printf "%+.2f", b / 1048576 }'; }
{
  echo "Spec 1 download-size budget: 1.5 MB (spec section 3.14)"
  echo "base: $BASE ($(git rev-parse --short "$BASE")); now: copy of the working tree at $(git rev-parse --short HEAD)"
  for kind in apk ios; do
    if [[ "$kind" == ios && "$IOS" != 1 ]]; then
      echo "ios: skipped (IOS=0)"
      continue
    fi
    if [[ ! -f "$OUT/base-$kind.bytes" || ! -f "$OUT/now-$kind.bytes" ]]; then
      echo "$kind: not measured (see base-$kind.log / now-$kind.log)"
      continue
    fi
    b=$(cat "$OUT/base-$kind.bytes"); n=$(cat "$OUT/now-$kind.bytes")
    d=$((n - b))
    verdict=$([[ $d -le 1572864 ]] && echo within || echo OVER)
    echo "$kind: base $(mb "$b") MB, now $(mb "$n") MB, $(mbs "$d") MB ($verdict budget; $d bytes)"
  done
} > "$OUT/.size-report.txt.tmp"
mv "$OUT/.size-report.txt.tmp" "$OUT/size-report.txt"
cat "$OUT/size-report.txt"
