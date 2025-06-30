#!/bin/bash

# ibmdb-binaries repo should be cloned in the same directory where node-ibm_db is cloned. 
CURR_DIR=`pwd`
IBMDB_DIR="$(dirname $CURR_DIR)/ibm_db"
if [[ ! -e "$IBMDB_DIR/installer/driverInstall.js" ]]; then
  echo "Error: unable to find ibm_db directory!"
  exit 1
fi

# Dependencies check
for cmd in node curl grep sed awk; do
  if ! command -v $cmd &> /dev/null; then
    echo "Required command '$cmd' not found. Please install it."
    exit 1
  fi
done

# Config
osname=`uname`
arch=`uname -m`
INSTALLED_NODE_V=`node -v`
LATEST_VERSION=""
downloaded=false
MAJOR_VER=24
NODEWORK=$(dirname $(dirname $(dirname `which node`)))
echo "Installed node = $INSTALLED_NODE_V"
export IBM_DB_HOME=
export DOWNLOAD_CLIDRIVER=true

CREATE_BINARY="true"
FORCE_BINARY=false
if [[ "$1" == "force" ]]; then
  FORCE_BINARY=true
fi

ARCHIVE_PATTERN="linux-x64.tar.gz"
PLAT="linuxx64"
if [[ "$osname" == "Darwin" ]]; then
  if [[ "$arch" == "arm64" ]]; then
    ARCHIVE_PATTERN="darwin-arm64.tar.gz"
    PLAT="macarm64"
    export PYTHON=$(brew --prefix python@3.11)/bin/python3.11
  else
    ARCHIVE_PATTERN="darwin-x64.tar.gz"
    PLAT="macx64"
  fi
else
  if [[ "$arch" != "x86_64" ]]; then
    echo "$arch for $osname platform is not supported."
    exit 1
  fi
fi

function downloadLatestNodejs {
  BASE_URL="https://nodejs.org/download/release/latest-v$MAJOR_VER.x/"
  # Get latest version filename
  TARBALL=$(curl -s "$BASE_URL" | grep -Eo "node-v$MAJOR_VER\.[0-9]+\.[0-9]+-$ARCHIVE_PATTERN" | head -n 1)
  UNTAR_NAME="${TARBALL:0:$((${#TARBALL} - 7))}"
  downloaded=false

  if [[ -z "$TARBALL" ]]; then
    echo "Failed to detect latest Node.js version."
    return 1
  fi

  # Extract version string from filename
  LATEST_VERSION=$(echo "$TARBALL" | sed -E "s/node-(v$MAJOR_VER\.[0-9]+\.[0-9]+).*/\1/")
  NODEDIR_NAME="$NODEWORK/node$LATEST_VERSION"

  # Check if we already have this version
  if [[ "$LATEST_VERSION" == "$INSTALLED_NODE_V" ]]; then
    echo "No new version found. Latest version ($LATEST_VERSION) already installed."
    downloaded=true
    return 0
  fi
  if [[ -d "$NODEDIR_NAME" ]]; then
    echo "No new version found. Latest version ($LATEST_VERSION) already exist."
    downloaded=true
    return 0
  fi

  # Download new version
  DOWNLOAD_URL="${BASE_URL}${TARBALL}"
  echo "New version detected: $LATEST_VERSION"
  echo "Downloading from: $DOWNLOAD_URL"
  cd $NODEWORK

  # Use curl for cross-platform compatibility
  curl -LO "$DOWNLOAD_URL"

  if [[ $? -eq 0 ]]; then
    echo "Download complete: $TARBALL"
  else
    echo "Download failed!"
    return 1
  fi

  # Extract tar.gz file
  tar xzf "$TARBALL"
  mv "$UNTAR_NAME" "$NODEDIR_NAME"
  rm "$TARBALL"
  ls "$NODEWORK"
  downloaded=true
  cd "$CURR_DIR"
  return 1
}

function createBinary {
    if command -v node &> /dev/null; then
        NODEVER=`node -v`
        mv "$NODEWORK/nodejs" "$NODEWORK/node$NODEVER"
    else
        echo "Unable to find installed nodejs version."
    fi
    mv "$NODEWORK/node$LATEST_VERSION" "$NODEWORK/nodejs"
    cd $IBMDB_DIR
    npm install
    if [ ! -d "$CURR_DIR/$PLAT" ]; then
        mkdir "$CURR_DIR/$PLAT"
    fi
    if [ -f "$IBMDB_DIR/build/Release/odbc_bindings.node" ]; then
      cp "$IBMDB_DIR/build/Release/odbc_bindings.node" "$CURR_DIR/$PLAT/odbc_bindings.node.$MAJOR_VER"
      echo "Coppied $CURR_DIR/$PLAT/odbc_bindings.node.$MAJOR_VER for $LATEST_VERSION"
      echo ""
      updateReadmeFile
      updateVersionFile
    fi
    cd $CURR_DIR
}

function checkLatestVersionInFile {
    README="$CURR_DIR/binaryVersions.txt"
    CREATE_BINARY="true"
    if [[ ! -f "$README" ]]; then
      echo "Error: File '$README' not found."
      exit 1
    fi

    PATTERN="${osname} ${arch} Node ${MAJOR_VER} Version = "
    REGEX_PATTERN="^${PATTERN}"
    MATCHING_LINE=$(grep -E "$REGEX_PATTERN" "$README")

    if [[ -n "$MATCHING_LINE" ]]; then
      # Extract current version from version file
      CURRENT_VERSION=$(echo "$MATCHING_LINE" | sed -E "s/$REGEX_PATTERN//")

      if [[ "$CURRENT_VERSION" == "$LATEST_VERSION" ]]; then
        echo "Node version $CURRENT_VERSION is present in version file."
        CREATE_BINARY="false"
      fi
    fi

    # Check if force option is used
    if $FORCE_BINARY; then
      CREATE_BINARY="true"
    fi

    # Check for binary file
    if [[ "$CREATE_BINARY" == "false" && ! -e "$CURR_DIR/$PLAT/odbc_bindings.node.$MAJOR_VER" ]]; then
      CREATE_BINARY="true"
    fi
}

function updateVersionFile {
    README="$CURR_DIR/binaryVersions.txt"
    if [[ ! -f "$README" ]]; then
      echo "Error: File '$README' not found."
      exit 1
    fi

    PATTERN="${osname} ${arch} Node ${MAJOR_VER} Version = "
    REGEX_PATTERN="^${PATTERN}"
    MATCHING_LINE=$(grep -E "$REGEX_PATTERN" "$README")

    if [[ -n "$MATCHING_LINE" ]]; then
      # Extract current version from version file
      CURRENT_VERSION=$(echo "$MATCHING_LINE" | sed -E "s/$REGEX_PATTERN//")

      if [[ "$CURRENT_VERSION" == "$LATEST_VERSION" ]]; then
        return 0
      fi

      # Replace existing line
      TMP_FILE=$(mktemp)
      sed -E "s/$REGEX_PATTERN.*/${PATTERN}${LATEST_VERSION}/" "$README" > "$TMP_FILE"
      mv "$TMP_FILE" "$README"
      echo "Updated Node $MAJOR_VER Version from $CURRENT_VERSION to $LATEST_VERSION in version file"
    else
      # Add new line at the end
      echo "${PATTERN}${LATEST_VERSION}" >> "$README"
      echo "Added new line: ${PATTERN}${LATEST_VERSION} to version file"
    fi
}

function updateReadmeFile {
    README="$CURR_DIR/README.md"
    if [[ ! -f "$README" ]]; then
      echo "Error: File '$README' not found."
      exit 1
    fi

    # Escape asterisk for grep/sed use
    REGEX_PATTERN="^\* Node ${MAJOR_VER} Version = "
    PATTERN="* Node ${MAJOR_VER} Version = "
    MATCHING_LINE=$(grep -E "$REGEX_PATTERN" "$README")

    if [[ -n "$MATCHING_LINE" ]]; then
      # Extract current version from readme file
      CURRENT_VERSION=$(echo "$MATCHING_LINE" | sed -E "s/$REGEX_PATTERN//")

      if [[ "$CURRENT_VERSION" == "$LATEST_VERSION" ]]; then
        echo "Node $MAJOR_VER Version is already $LATEST_VERSION. No update needed."
        return 0
      fi

      # Replace existing line
      TMP_FILE=$(mktemp)
      sed -E "s/$REGEX_PATTERN.*/${PATTERN}${LATEST_VERSION}/" "$README" > "$TMP_FILE"
      mv "$TMP_FILE" "$README"
      echo "Updated Node $MAJOR_VER Version from $CURRENT_VERSION to $LATEST_VERSION in Readme.md file"
    else
      # Add new line at the end
      echo "${PATTERN}${LATEST_VERSION}" >> "$README"
      echo "Added new line: ${PATTERN}${LATEST_VERSION} to Readme.md file"
    fi
}

for ver in 16 17 18 19 20 21 22 23 24; do
  MAJOR_VER=$ver
  downloadLatestNodejs
  if $downloaded; then
    checkLatestVersionInFile
    if [[ "$CREATE_BINARY" == "true" ]]; then
      createBinary
    fi
  fi
done
# Create Electron binaries too
./makeelectronbinaries.sh

#ls -l "$CURR_DIR/$PLAT"
git status
echo "Done!"

