#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# build.sh — build GoControl without installing anything system-wide.
#
# Everything (JDK 17, Android SDK, Gradle) is downloaded into a toolchain
# directory and used from there. Anything already present on the system, or
# already downloaded from a previous run, is reused instead of re-fetched.
#
#   ./build.sh                     # toolchain in ./.toolchain
#   ./build.sh /path/to/deps       # toolchain in that directory instead
#   TOOLCHAIN_DIR=/x ./build.sh    # same, via env var
#
# The toolchain dir can live on another disk. The script prefers to symlink it
# to ./.toolchain for convenience; if the filesystem refuses symlinks it just
# uses the absolute path directly, so passing a directory always works.
#
#   ./build.sh --release           # assembleRelease (unsigned)
#   ./build.sh --clean             # clean first
#   ./build.sh --install           # adb install the APK when done
# ---------------------------------------------------------------------------
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_DIR"

# ---- versions (bump here) ----
JDK_VER="17.0.11+9"
JDK_TAG="jdk-17.0.11%2B9"
JDK_FILE="OpenJDK17U-jdk_x64_linux_hotspot_17.0.11_9.tar.gz"
GRADLE_VER="8.7"
CMDLINE_VER="11076708"
ANDROID_PLATFORM="android-34"
BUILD_TOOLS="34.0.0"

GRADLE_TASK="assembleDebug"
DO_CLEAN=0
DO_INSTALL=0
ARG_DIR=""

while [ $# -gt 0 ]; do
  case "$1" in
    --release) GRADLE_TASK="assembleRelease" ;;
    --clean)   DO_CLEAN=1 ;;
    --install) DO_INSTALL=1 ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    -*) echo "unknown option: $1" >&2; exit 2 ;;
    *)  ARG_DIR="$1" ;;
  esac
  shift
done

# ---- pick the toolchain directory ----
TOOLCHAIN_DIR="${ARG_DIR:-${TOOLCHAIN_DIR:-$PROJECT_DIR/.toolchain}}"
mkdir -p "$TOOLCHAIN_DIR"
TOOLCHAIN_DIR="$(cd "$TOOLCHAIN_DIR" && pwd)"

# If the toolchain lives elsewhere, try to symlink it in for convenience.
# Not being able to symlink is fine — we use the absolute path either way.
LINK="$PROJECT_DIR/.toolchain"
if [ "$TOOLCHAIN_DIR" != "$LINK" ]; then
  if [ -L "$LINK" ]; then
    [ "$(readlink "$LINK")" = "$TOOLCHAIN_DIR" ] || ln -sfn "$TOOLCHAIN_DIR" "$LINK" 2>/dev/null || true
  elif [ ! -e "$LINK" ]; then
    ln -s "$TOOLCHAIN_DIR" "$LINK" 2>/dev/null \
      || echo "note: could not symlink .toolchain -> $TOOLCHAIN_DIR; using the path directly"
  fi
fi

echo "project   : $PROJECT_DIR"
echo "toolchain : $TOOLCHAIN_DIR"
echo

# ---- helpers ----
have() { command -v "$1" >/dev/null 2>&1; }

fetch() { # fetch <url> <dest>
  local url="$1" dest="$2"
  [ -s "$dest" ] && { echo "  reuse $(basename "$dest")"; return 0; }
  echo "  download $(basename "$dest")"
  if have curl;   then curl -fL --retry 3 -o "$dest.part" "$url"
  elif have wget; then wget -q -O "$dest.part" "$url"
  else echo "need curl or wget" >&2; exit 1; fi
  mv "$dest.part" "$dest"
}

DL="$TOOLCHAIN_DIR/downloads"; mkdir -p "$DL"

# ---------------------------------------------------------------- 1. Java 17
find_system_java() {
  local c
  for c in "${JAVA_HOME:-}/bin/java" "$(command -v java 2>/dev/null || true)"; do
    [ -x "$c" ] || continue
    local v
    v="$("$c" -version 2>&1 | head -1 | sed -n 's/.*version "\([0-9]*\).*/\1/p')"
    if [ "${v:-0}" -ge 17 ] 2>/dev/null; then
      # Resolve symlinks first: /usr/bin/java points into /usr/lib/jvm/..., and
      # without this JAVA_HOME would come out as /usr.
      c="$(readlink -f "$c" 2>/dev/null || echo "$c")"
      echo "$(cd "$(dirname "$c")/.." && pwd)"; return 0
    fi
  done
  return 1
}

echo "[1/4] Java 17+"
if JDK_HOME="$(find_system_java)"; then
  echo "  using system JDK at $JDK_HOME"
else
  JDK_HOME="$(find "$TOOLCHAIN_DIR" -maxdepth 2 -name 'jdk-17*' -type d 2>/dev/null | head -1 || true)"
  if [ -z "$JDK_HOME" ]; then
    fetch "https://github.com/adoptium/temurin17-binaries/releases/download/${JDK_TAG}/${JDK_FILE}" \
          "$DL/$JDK_FILE"
    echo "  extracting JDK"
    tar -xzf "$DL/$JDK_FILE" -C "$TOOLCHAIN_DIR"
    JDK_HOME="$(find "$TOOLCHAIN_DIR" -maxdepth 2 -name 'jdk-17*' -type d | head -1)"
  else
    echo "  reuse local JDK"
  fi
fi
export JAVA_HOME="$JDK_HOME"
export PATH="$JAVA_HOME/bin:$PATH"
echo "  JAVA_HOME=$JAVA_HOME"

# ---------------------------------------------------------------- 2. Android SDK
echo "[2/4] Android SDK ($ANDROID_PLATFORM, build-tools $BUILD_TOOLS)"
SDK_DIR="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-}}"
if [ -n "$SDK_DIR" ] && [ -d "$SDK_DIR/platforms/$ANDROID_PLATFORM" ]; then
  echo "  using system SDK at $SDK_DIR"
else
  SDK_DIR="$TOOLCHAIN_DIR/android-sdk"
  mkdir -p "$SDK_DIR"
  SDKMGR="$SDK_DIR/cmdline-tools/latest/bin/sdkmanager"
  if [ ! -x "$SDKMGR" ]; then
    ZIP="commandlinetools-linux-${CMDLINE_VER}_latest.zip"
    fetch "https://dl.google.com/android/repository/$ZIP" "$DL/$ZIP"
    echo "  extracting command-line tools"
    rm -rf "$SDK_DIR/cmdline-tools/tmp"
    mkdir -p "$SDK_DIR/cmdline-tools/tmp"
    if have unzip; then unzip -q "$DL/$ZIP" -d "$SDK_DIR/cmdline-tools/tmp"
    else python3 -c "import zipfile,sys;zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])" \
           "$DL/$ZIP" "$SDK_DIR/cmdline-tools/tmp"; fi
    mkdir -p "$SDK_DIR/cmdline-tools"
    rm -rf "$SDK_DIR/cmdline-tools/latest"
    mv "$SDK_DIR/cmdline-tools/tmp/cmdline-tools" "$SDK_DIR/cmdline-tools/latest"
    rmdir "$SDK_DIR/cmdline-tools/tmp" 2>/dev/null || true
    chmod +x "$SDK_DIR/cmdline-tools/latest/bin/"* 2>/dev/null || true
  else
    echo "  reuse command-line tools"
  fi

  # Google's bin/sdkmanager wrapper sets
  #     DEFAULT_JVM_OPTS='-Dcom.android.sdklib.toolsdir=$APP_HOME'
  # and expands it *unquoted* through `eval`, so any SDK path containing a space
  # word-splits and java ends up treating a fragment of the path as the main class
  # ("Could not find or load main class ..."). Drive the CLI class directly, where
  # normal shell quoting applies.
  CMDLINE_HOME="$SDK_DIR/cmdline-tools/latest"
  sdkmgr() {
    "$JAVA_HOME/bin/java" \
      -Dcom.android.sdklib.toolsdir="$CMDLINE_HOME" \
      -classpath "$CMDLINE_HOME/lib/sdkmanager-classpath.jar" \
      com.android.sdklib.tool.sdkmanager.SdkManagerCli "$@"
  }

  if [ ! -d "$SDK_DIR/platforms/$ANDROID_PLATFORM" ]; then
    echo "  accepting licences + installing packages (a few minutes)"
    yes 2>/dev/null | sdkmgr --sdk_root="$SDK_DIR" --licenses >/dev/null 2>&1 || true
    sdkmgr --sdk_root="$SDK_DIR" \
      "platform-tools" "platforms;$ANDROID_PLATFORM" "build-tools;$BUILD_TOOLS" >/dev/null
  else
    echo "  reuse SDK packages"
  fi
fi
export ANDROID_SDK_ROOT="$SDK_DIR"
export ANDROID_HOME="$SDK_DIR"
echo "  ANDROID_SDK_ROOT=$SDK_DIR"

# Gradle reads the SDK location from here.
printf 'sdk.dir=%s\n' "$SDK_DIR" > "$PROJECT_DIR/local.properties"

# ---------------------------------------------------------------- 3. Gradle
echo "[3/4] Gradle $GRADLE_VER"
GRADLE_BIN=""
if have gradle; then
  gv="$(gradle --version 2>/dev/null | sed -n 's/^Gradle \([0-9.]*\).*/\1/p' | head -1)"
  case "$gv" in 8.*|9.*) GRADLE_BIN="$(command -v gradle)"; echo "  using system Gradle $gv" ;; esac
fi
if [ -z "$GRADLE_BIN" ]; then
  GRADLE_BIN="$TOOLCHAIN_DIR/gradle-$GRADLE_VER/bin/gradle"
  if [ ! -x "$GRADLE_BIN" ]; then
    ZIP="gradle-${GRADLE_VER}-bin.zip"
    fetch "https://services.gradle.org/distributions/$ZIP" "$DL/$ZIP"
    echo "  extracting Gradle"
    if have unzip; then unzip -q "$DL/$ZIP" -d "$TOOLCHAIN_DIR"
    else python3 -c "import zipfile,sys;zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])" \
           "$DL/$ZIP" "$TOOLCHAIN_DIR"; fi
    chmod +x "$GRADLE_BIN"
  else
    echo "  reuse local Gradle"
  fi
fi

# keep Gradle's own caches inside the toolchain dir too, so nothing leaks into $HOME
export GRADLE_USER_HOME="$TOOLCHAIN_DIR/gradle-home"
mkdir -p "$GRADLE_USER_HOME"

# ---------------------------------------------------------------- 4. build
echo "[4/4] Building ($GRADLE_TASK)"
[ "$DO_CLEAN" = 1 ] && "$GRADLE_BIN" --project-dir "$PROJECT_DIR" clean
"$GRADLE_BIN" --project-dir "$PROJECT_DIR" "$GRADLE_TASK"

APK="$(find "$PROJECT_DIR/app/build/outputs/apk" -name '*.apk' -newer "$PROJECT_DIR/build.gradle.kts" 2>/dev/null | head -1)"
[ -z "$APK" ] && APK="$(find "$PROJECT_DIR/app/build/outputs/apk" -name '*.apk' 2>/dev/null | head -1)"

echo
if [ -n "$APK" ]; then
  echo "APK: $APK"
  if [ "$DO_INSTALL" = 1 ]; then
    ADB="$SDK_DIR/platform-tools/adb"
    have adb && ADB="$(command -v adb)"
    echo "installing with $ADB"
    "$ADB" install -r "$APK"
  else
    echo "install it with:"
    echo "  $SDK_DIR/platform-tools/adb install -r \"$APK\""
  fi
else
  echo "build finished but no APK was found under app/build/outputs/apk" >&2
  exit 1
fi
