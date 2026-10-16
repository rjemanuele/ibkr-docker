#!/bin/bash

# Prepares Dockerfile and image files for later build step

if [ $# -ne 2 ]; then
	echo "Usage: ./build.sh <stable|latest> <version>"
	exit 1
fi

CHANNEL=$1
VERSION=$2
# Repo whose releases host the IB Gateway installers (owner/name)
REPO=${REPO:-${GITHUB_REPOSITORY:-rjemanuele/ibkr-docker}}

if [[ "$CHANNEL" != "stable" ]] && [[ "$CHANNEL" != "latest" ]]; then
	echo "'${CHANNEL}' must be either 'stable' or 'latest'"
	exit 1
fi

OUTPUT_DIR="./$CHANNEL"
rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR/image-files"
cp -R image-files/. "$OUTPUT_DIR/image-files/"

CHANNEL="$CHANNEL" VERSION="$VERSION" REPO="$REPO" envsubst '$CHANNEL $VERSION $REPO' <"Dockerfile.template" >"$OUTPUT_DIR/Dockerfile"
