#!/bin/bash

# ibmdb-binaries repo should be cloned in the same directory where node-ibm_db is cloned. 
CURR_DIR=`pwd`
IBMDB_DIR="$(dirname $CURR_DIR)/ibm_db"
if [[ ! -e "$IBMDB_DIR/installer/driverInstall.js" ]]; then
  echo "Error: unable to find ibm_db directory!"
  exit 1
fi

# Dependencies check
for cmd in node curl grep sed awk head; do
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
versionFound=false
LATEST_VER=37.1.0
MAJOR_VER=37
NODEWORK=$(dirname $(dirname $(dirname `which node`)))
echo "Installed node = $INSTALLED_NODE_V"
export IBM_DB_HOME=

CREATE_BINARY="true"
FORCE_BINARY=false
if [[ "$1" == "force" ]]; then
  FORCE_BINARY=true
  echo "FORCE_BINARY = $FORCE_BINARY"
fi

PLAT="linux"
OSDIR="linuxx64"
if [[ "$osname" == "Darwin" ]]; then
  if [[ "$arch" == "arm64" ]]; then
    PLAT="macarm"
    OSDIR="macarm64"
    export PYTHON=$(brew --prefix python@3.11)/bin/python3.11
  else
    PLAT="mac"
    OSDIR="macx64"
  fi
else
  if [[ "$arch" != "x86_64" ]]; then
    echo "$arch for $osname platform is not supported."
    exit 1
  fi
fi

function getLatestElectronVersion {
    electronVerFile="$CURR_DIR/electronVersions.txt"
    echo "Fetching the latest Electron v${MAJOR_VER}.x versions..."

    # Fetch release info and extract matching versions
    version=$(curl -s "https://api.github.com/repos/electron/electron/releases?per_page=100" \
      | grep '"tag_name":' \
      | grep -E "\"v${MAJOR_VER}\.[0-9]+\.[0-9]+"\" \
      | sed -E 's/.*"v([0-9]+\.[0-9]+\.[0-9]+)".*/\1/' \
      | head -n 1)

    # Output results
    if [ -z "$version" ]; then
        echo "❌ No stable Electron v${MAJOR_VER}.x version found."
        versionFound=false
    else
        echo "✅ Latest stable Electron v${MAJOR_VER}.x version: $version"
        versionFound=true
        LATEST_VER=$version
    fi
}

function createBinary {
    if command -v $cmd &> /dev/null; then
        NODEVER=`node -v`
    else
        echo "Unable to find installed nodejs version."
        return 1
    fi

    cd $IBMDB_DIR
    ELECTRON=$LATEST_VER npm install
    echo "$?"
    if [ ! -d "$CURR_DIR/$OSDIR" ]; then
        mkdir "$CURR_DIR/$OSDIR"
    fi
    if [ -f "$IBMDB_DIR/build/Release/odbc_bindings.node" ]; then
      cp "$IBMDB_DIR/build/Release/odbc_bindings.node" "$CURR_DIR/$OSDIR/odbc_bindings_${PLAT}_${MAJOR_VER}.node"
      echo "Coppied $CURR_DIR/$OSDIR/odbc_bindings_${PLAT}_${MAJOR_VER}.node for electron $LATEST_VER"
      echo ""
      updateReadmeFile
      updateVersionFile
    fi
    cd $CURR_DIR
}

function checkForNewVersion {
    FILE_NAME="$CURR_DIR/binaryVersions.txt"
    CREATE_BINARY="true"
    if [[ ! -f "$FILE_NAME" ]]; then
      echo "Error: File '$FILE_NAME' not found."
      exit 1
    fi

    PATTERN="${osname} ${arch} Electron ${MAJOR_VER} Version = "
    REGEX_PATTERN="^${PATTERN}"
    MATCHING_LINE=$(grep -E "$REGEX_PATTERN" "$FILE_NAME")

    if [[ -n "$MATCHING_LINE" ]]; then
      # Extract current version from version file
      CURRENT_VERSION=$(echo "$MATCHING_LINE" | sed -E "s/$REGEX_PATTERN//")

      if [[ "$CURRENT_VERSION" == "$LATEST_VER" ]]; then
        echo "Electron $MAJOR_VER Version is already $LATEST_VER. No update needed."
        CREATE_BINARY="false"
      fi
    fi

    # Check if force option is used
    if $FORCE_BINARY; then
      CREATE_BINARY="true"
    fi

    # Check for binary file
    if [[ "$CREATE_BINARY" == "false" && ! -e "$CURR_DIR/$OSDIR/odbc_bindings_${PLAT}_${MAJOR_VER}.node" ]]; then
      CREATE_BINARY="true"
    fi
}

function updateVersionFile {
    FILE_NAME="$CURR_DIR/binaryVersions.txt"
    if [[ ! -f "$FILE_NAME" ]]; then
      echo "Error: File '$FILE_NAME' not found."
      exit 1
    fi

    PATTERN="${osname} ${arch} Electron ${MAJOR_VER} Version = "
    REGEX_PATTERN="^${PATTERN}"
    MATCHING_LINE=$(grep -E "$REGEX_PATTERN" "$FILE_NAME")

    if [[ -n "$MATCHING_LINE" ]]; then
      # Extract current version from version file
      CURRENT_VERSION=$(echo "$MATCHING_LINE" | sed -E "s/$REGEX_PATTERN//")

      if [[ "$CURRENT_VERSION" == "$LATEST_VER" ]]; then
        echo "Electron $MAJOR_VER Version is already $LATEST_VER. No update needed."
        return 0
      fi

      # Replace existing line
      TMP_FILE=$(mktemp)
      sed -E "s/$REGEX_PATTERN.*/${PATTERN}${LATEST_VER}/" "$FILE_NAME" > "$TMP_FILE"
      mv "$TMP_FILE" "$FILE_NAME"
      echo "Updated Electron $MAJOR_VER Version from $CURRENT_VERSION to $LATEST_VER in version file"
    else
      # Add new line at the end
      echo "${PATTERN}${LATEST_VER}" >> "$FILE_NAME"
      echo "Added new line: ${PATTERN}${LATEST_VER} to version file"
    fi
}

function updateReadmeFile {
    FILE_NAME="$CURR_DIR/README.md"
    if [[ ! -f "$FILE_NAME" ]]; then
      echo "Error: File '$FILE_NAME' not found."
      exit 1
    fi

    # Escape asterisk for grep/sed use
    REGEX_PATTERN="^\* Electron ${MAJOR_VER} Version = "
    PATTERN="* Electron ${MAJOR_VER} Version = "
    MATCHING_LINE=$(grep -E "$REGEX_PATTERN" "$FILE_NAME")

    if [[ -n "$MATCHING_LINE" ]]; then
      # Extract current electron version from readme file
      CURRENT_VERSION=$(echo "$MATCHING_LINE" | sed -E "s/$REGEX_PATTERN//")

      if [[ "$CURRENT_VERSION" == "$LATEST_VER" ]]; then
        echo "Electron $MAJOR_VER Version is already $LATEST_VER. No update needed."
        return 0
      fi

      # Replace existing line
      TMP_FILE=$(mktemp)
      sed -E "s/$REGEX_PATTERN.*/${PATTERN}${LATEST_VER}/" "$FILE_NAME" > "$TMP_FILE"
      mv "$TMP_FILE" "$FILE_NAME"
      echo "Updated Electron $MAJOR_VER Version from $CURRENT_VERSION to $LATEST_VER in Readme.md file"
    else
      # Add new line at the end
      echo "${PATTERN}${LATEST_VER}" >> "$FILE_NAME"
      echo "Added new line: ${PATTERN}${LATEST_VER} to Readme.md file"
    fi
}

for ver in 32 33 34 35 36 37 38; do
  MAJOR_VER=$ver
  getLatestElectronVersion

  if $versionFound; then
    checkForNewVersion
  fi
  if [[ "$CREATE_BINARY" == "true" ]]; then
    createBinary
  fi
done
ls -l "$CURR_DIR/$OSDIR"
echo "Done!"

