#!/bin/bash
# Glove80 firmware update script
# Downloads latest build artifact and flashes to left hand

set -e

REPO="fix-fox/glove80-zmk-config-west"
MOUNT_POINT="/mnt/d"
FIRMWARE_PATTERN="glove80_lh*.uf2"
TEMP_DIR=$(mktemp -d)

cleanup() {
    rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

echo "Checking for workflow runs..."

# Get the latest workflow run
RUN_INFO=$(gh run list --repo "$REPO" --limit 1 --json databaseId,status,conclusion,headBranch,createdAt,displayTitle)
RUN_ID=$(echo "$RUN_INFO" | jq -r '.[0].databaseId')
STATUS=$(echo "$RUN_INFO" | jq -r '.[0].status')
CONCLUSION=$(echo "$RUN_INFO" | jq -r '.[0].conclusion')
BRANCH=$(echo "$RUN_INFO" | jq -r '.[0].headBranch')
CREATED_AT=$(echo "$RUN_INFO" | jq -r '.[0].createdAt')
TITLE=$(echo "$RUN_INFO" | jq -r '.[0].displayTitle')

# Convert timestamp to human readable
CREATED_HUMAN=$(date -d "$CREATED_AT" "+%Y-%m-%d %H:%M:%S" 2>/dev/null || echo "$CREATED_AT")

if [ "$STATUS" = "in_progress" ] || [ "$STATUS" = "queued" ]; then
    echo "Build in progress: $TITLE"
    echo "Waiting for build to complete..."
    gh run watch "$RUN_ID" --repo "$REPO" --exit-status
    # Refresh conclusion after watch
    CONCLUSION=$(gh run view "$RUN_ID" --repo "$REPO" --json conclusion -q '.conclusion')
fi

if [ "$CONCLUSION" != "success" ]; then
    echo "Error: Latest build failed or was cancelled (status: $CONCLUSION)"
    echo "Check: https://github.com/$REPO/actions/runs/$RUN_ID"
    exit 1
fi

echo ""
echo "=== Latest successful build ==="
echo "  Commit:  $TITLE"
echo "  Branch:  $BRANCH"
echo "  Time:    $CREATED_HUMAN"
echo "  Run:     https://github.com/$REPO/actions/runs/$RUN_ID"
echo ""

read -p "Download and flash this firmware? [y/N] " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 0
fi

echo "Downloading firmware artifact..."
gh run download "$RUN_ID" --repo "$REPO" --dir "$TEMP_DIR"

# Find the firmware file
FIRMWARE_FILE=$(find "$TEMP_DIR" -name "$FIRMWARE_PATTERN" -type f | head -1)

if [ -z "$FIRMWARE_FILE" ]; then
    echo "Error: Could not find left hand firmware ($FIRMWARE_PATTERN)"
    echo "Contents of download:"
    find "$TEMP_DIR" -type f
    exit 1
fi

echo "Found firmware: $(basename "$FIRMWARE_FILE")"
echo ""
echo "Put the LEFT hand in bootloader mode:"
echo "  1. Hold the bottom-left key (magic key)"
echo "  2. While holding, tap the top-left key"
echo "  3. Release both - keyboard should mount as GLV80LHBOOT"
echo ""
read -p "Press Enter when ready..." -r

echo "Waiting for device at $MOUNT_POINT..."
TIMEOUT=60
ELAPSED=0
while [ ! -d "$MOUNT_POINT" ] || [ -z "$(ls -A "$MOUNT_POINT" 2>/dev/null)" ]; do
    sleep 1
    ELAPSED=$((ELAPSED + 1))
    if [ $ELAPSED -ge $TIMEOUT ]; then
        echo "Error: Timeout waiting for device to mount at $MOUNT_POINT"
        echo "Make sure the keyboard is in bootloader mode and the drive is accessible."
        exit 1
    fi
    printf "\r  Waiting... %ds" $ELAPSED
done
echo ""

echo "Device detected! Copying firmware..."
cp "$FIRMWARE_FILE" "$MOUNT_POINT/"

echo ""
echo "Firmware copied. The keyboard will reboot automatically."
echo "Done!"
