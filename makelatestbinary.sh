#!/bin/bash
# Build the NAPI ibm_db binary with the latest Node.js for the current non-Windows platform.
# Usage: ./makelatestbinary.sh [force]

CURR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IBMDB_DIR="$(dirname "$CURR_DIR")/ibm_db"
NODEWORK="$(dirname "$(dirname "$CURR_DIR")")"
FORCE_BINARY=false
[[ "$1" == "force" ]] && FORCE_BINARY=true

if [[ ! -e "$IBMDB_DIR/installer/driverInstall.js" ]]; then
  echo "Error: unable to find ibm_db directory at $IBMDB_DIR"
  exit 1
fi

for cmd in curl grep sed tar uname; do
  if ! command -v $cmd &> /dev/null; then
    echo "Required command '$cmd' not found. Please install it."
    exit 1
  fi
done

osname=$(uname)
arch=$(uname -m)
ARCHIVE_PATTERN=""
BINARY_NAME=""
case "$osname" in
  Darwin)
    if [[ "$arch" == "arm64" ]]; then
      ARCHIVE_PATTERN="darwin-arm64.tar.gz"
      BINARY_NAME="odbc_bindings_macarm.node"
      if command -v brew &> /dev/null; then
        export PYTHON="$(brew --prefix python@3.11)/bin/python3.11"
      fi
    else
      ARCHIVE_PATTERN="darwin-x64.tar.gz"
      BINARY_NAME="odbc_bindings_mac.node"
    fi
    ;;
  Linux)
    if [[ "$arch" == "x86_64" ]]; then
      ARCHIVE_PATTERN="linux-x64.tar.gz"
      BINARY_NAME="odbc_bindings_linux.node"
    elif [[ "$arch" == "s390x" ]]; then
      ARCHIVE_PATTERN="linux-s390x.tar.gz"
      BINARY_NAME="odbc_bindings_zlinux.node"
    fi
    ;;
  AIX)
    ARCHIVE_PATTERN="aix-ppc64.tar.gz"
    BINARY_NAME="odbc_bindings_aix.node"
    ;;
esac
if [[ -z "$BINARY_NAME" ]]; then
  echo "$arch for $osname platform is not supported."
  exit 1
fi

# Find the latest Node.js release
BASE_URL="https://nodejs.org/download/release/latest/"
TARBALL=$(curl -fs "$BASE_URL" | grep -Eo "node-v[0-9]+\.[0-9]+\.[0-9]+-$ARCHIVE_PATTERN" | head -n 1)
if [[ -z "$TARBALL" ]]; then
  echo "Failed to detect latest Node.js version."
  exit 1
fi
LATEST_VERSION=$(echo "$TARBALL" | sed -E "s/node-(v[0-9]+\.[0-9]+\.[0-9]+)-.*/\1/")
NODEDIR="$NODEWORK/node$LATEST_VERSION"
echo "Latest Node.js = $LATEST_VERSION"

if [[ -x "$NODEDIR/bin/node" ]]; then
  echo "Found $NODEDIR"
elif command -v node &> /dev/null && [[ "$(node -v)" == "$LATEST_VERSION" ]]; then
  NODEDIR="$(dirname "$(dirname "$(command -v node)")")"
  echo "Latest version is already installed at $NODEDIR"
else
  echo "Downloading ${BASE_URL}${TARBALL}"
  cd "$NODEWORK" || exit 1
  if ! curl -fLO "${BASE_URL}${TARBALL}"; then
    echo "Download failed!"
    exit 1
  fi
  tar xzf "$TARBALL" || exit 1
  mv "${TARBALL%.tar.gz}" "$NODEDIR"
  rm -f "$TARBALL"
  cd "$CURR_DIR" || exit 1
fi

# Make the latest node the effective one: $NODEWORK/nodejs, keeping the old one as node<version>
ACTIVE_DIR="$NODEWORK/nodejs"
if [[ "$(dirname "$NODEDIR")" == "$NODEWORK" && "$NODEDIR" != "$ACTIVE_DIR" ]]; then
  if [[ -d "$ACTIVE_DIR" ]]; then
    OLD_VERSION=$("$ACTIVE_DIR/bin/node" -v 2>/dev/null)
    if [[ -z "$OLD_VERSION" || -e "$NODEWORK/node$OLD_VERSION" ]]; then
      echo "Error: cannot preserve current $ACTIVE_DIR (version '$OLD_VERSION')."
      exit 1
    fi
    mv "$ACTIVE_DIR" "$NODEWORK/node$OLD_VERSION" || exit 1
    echo "Moved old nodejs to $NODEWORK/node$OLD_VERSION"
  fi
  mv "$NODEDIR" "$ACTIVE_DIR" || exit 1
  NODEDIR="$ACTIVE_DIR"
  echo "Latest node $LATEST_VERSION is now $ACTIVE_DIR"
fi

export PATH="$NODEDIR/bin:$PATH"
echo "Using node $(node -v)"

# Skip the build if the binary for this version already exists
VERSION_FILE="$CURR_DIR/binaryVersions.txt"
PATTERN="${osname} ${arch} NAPI Node Version = "
if ! $FORCE_BINARY && [[ -f "$CURR_DIR/$BINARY_NAME" && -f "$VERSION_FILE" ]] \
   && grep -qxF "${PATTERN}${LATEST_VERSION}" "$VERSION_FILE"; then
  echo "$BINARY_NAME is already built with $LATEST_VERSION. Use 'force' to rebuild."
  exit 0
fi

export IBM_DB_HOME=
export DOWNLOAD_CLIDRIVER=true
cd "$IBMDB_DIR" || exit 1
if ! npm install; then
  echo "npm install failed!"
  exit 1
fi

BUILT="$IBMDB_DIR/build/Release/odbc_bindings.node"
if [[ ! -f "$BUILT" ]]; then
  echo "Error: $BUILT was not created."
  exit 1
fi

cp "$BUILT" "$CURR_DIR/$BINARY_NAME" || exit 1
echo "Copied $BUILT to $CURR_DIR/$BINARY_NAME"
node "$IBMDB_DIR/test/test-basic-test.js"
echo ""

if [[ -f "$VERSION_FILE" ]]; then
  if grep -q "^${PATTERN}" "$VERSION_FILE"; then
    sed -i.bak -E "s/^${PATTERN}.*/${PATTERN}${LATEST_VERSION}/" "$VERSION_FILE" && rm -f "$VERSION_FILE.bak"
  else
    echo "${PATTERN}${LATEST_VERSION}" >> "$VERSION_FILE"
  fi
fi

cd "$CURR_DIR" || exit 1
git status
echo "Done!"
