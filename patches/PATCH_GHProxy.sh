#!/bin/sh

PATCH_NAME="GHProxy Patch"
PATCH_DEST="$FOUNDRY_HOME/resources/app/dist"
PATCH_URL="https://fvtt-cn.coding.net/p/FoundryDeploy/d/FoundryDeploy/git/raw/master/patches/PATCH_GHProxy.js"

log "Applying \"${PATCH_NAME}\""

patch_js=$(mktemp -t patch.js.XXXXXX)
curl --output "${patch_js}" "${PATCH_URL}" 2>&1 | tr "\r" "\n"

node "${patch_js}" "${PATCH_DEST}"