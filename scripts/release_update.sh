#!/bin/bash
# ==============================================================================
# Canvas macOS - Premium Sparkle Auto-Update Release Packaging System
# ==============================================================================
# This script automates compiling the application in professional Release
# configuration, compressing it, measuring metadata, and generating the Sparkle
# signing commands and Appcast XML structures for instant user delivery.
# ==============================================================================

set -e

# ANSI styling
BOLD="\033[1m"
GREEN="\033[32m"
BLUE="\033[34m"
YELLOW="\033[33m"
RESET="\033[0m"

echo -e "${BOLD}${BLUE}======================================================================${RESET}"
echo -e "${BOLD}${BLUE}   Canvas macOS Wallpaper Engine - Sparkle Release Packaging System   ${RESET}"
echo -e "${BOLD}${BLUE}======================================================================${RESET}"

WORKSPACE_DIR="/Users/kushhooda/Documents/Applications/CanvasMac"
PROJECT_DIR="$WORKSPACE_DIR/app"
BUILD_DIR="$PROJECT_DIR/build"
ZIP_OUT="$WORKSPACE_DIR/Canvas.zip"

# 1. Clean previous build folders
echo -e "\n${BOLD}${YELLOW}[1/4] Cleaning previous release folders...${RESET}"
rm -rf "$BUILD_DIR"
rm -f "$ZIP_OUT"
echo "Done cleaning."

# 2. Compile in Release Mode
echo -e "\n${BOLD}${YELLOW}[2/4] Compiling Canvas in high-performance Release Mode...${RESET}"
xcodebuild -project "$PROJECT_DIR/Canvas.xcodeproj" \
           -scheme Canvas \
           -configuration Release \
           -derivedDataPath "$BUILD_DIR" \
           clean build

# 3. Locate and Zip the Release Bundle
RELEASE_APP_PATH="$BUILD_DIR/Build/Products/Release/Canvas.app"
if [ ! -d "$RELEASE_APP_PATH" ]; then
    echo -e "${BOLD}\033[31mError: Compiled app not found at expected path: $RELEASE_APP_PATH${RESET}"
    exit 1
fi

echo -e "\n${BOLD}${YELLOW}[3/4] Compressing Canvas.app into distribution ZIP archive...${RESET}"
cd "$BUILD_DIR/Build/Products/Release"
zip -ry "$ZIP_OUT" Canvas.app > /dev/null
echo -e "${GREEN}SUCCESS: Created distribution archive at ${BOLD}$ZIP_OUT${RESET}"

# 4. Measure Size and Date for Appcast Feed
FILE_SIZE=$(stat -f %z "$ZIP_OUT")
PUB_DATE=$(date -R)

echo -e "\n${BOLD}${YELLOW}[4/4] Generating Sparkle Deployment Metadata...${RESET}"
echo -e "${BOLD}Archive Size (Bytes):${RESET} $FILE_SIZE"
echo -e "${BOLD}Release Date (RFC-2822):${RESET} $PUB_DATE"

echo -e "\n${BOLD}${GREEN}======================================================================${RESET}"
echo -e "${BOLD}${GREEN}                   SPARKLE CODESIGNING & DEPLOYMENT INSTRUCTIONS      ${RESET}"
echo -e "${BOLD}${GREEN}======================================================================${RESET}"
echo -e "To make this update discoverable and secure for all users, follow these steps:"
echo -e ""
echo -e "${BOLD}Step A: Generate Sparkle Signature Keys (Do this ONCE if you haven't already)${RESET}"
echo -e "Run the following command in terminal to generate your private & public keys:"
echo -e "   ${YELLOW}./app/Canvas.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved${RESET} (or find Sparkle bin directory)"
echo -e "   Typically Sparkle's binaries reside in your local build derived data. Run:"
echo -e "   ${YELLOW}find ~/Library/Developer/Xcode/DerivedData -name \"generate_keys\" -type f${RESET}"
echo -e "   Once located, run: ${YELLOW}path/to/generate_keys${RESET}"
echo -e "   This will save a public key and prompt you to store the private key securely in your Keychain."
echo -e ""
echo -e "${BOLD}Step B: Sign the Zip Archive${RESET}"
echo -e "Locate the '${YELLOW}sign_update${RESET}' binary (same directory as generate_keys). Run:"
echo -e "   ${YELLOW}find ~/Library/Developer/Xcode/DerivedData -name \"sign_update\" -type f${RESET}"
echo -e "   Once located, sign your ZIP file:"
echo -e "   ${YELLOW}path/to/sign_update \"$ZIP_OUT\"${RESET}"
echo -e "   This will output your cryptographically secure ${BOLD}sparkle:edSignature${RESET} value."
echo -e ""
echo -e "${BOLD}Step C: Copy-Paste this Item Block into your hosted 'appcast.xml' feed file:${RESET}"
echo -e "======================================================================="
cat <<EOF
        <item>
            <title>Version 1.0.1</title>
            <sparkle:releaseNotesLink>
                https://raw.githubusercontent.com/kushhooda/CanvasMac/main/CHANGELOG.html
            </sparkle:releaseNotesLink>
            <pubDate>$PUB_DATE</pubDate>
            <enclosure url="https://github.com/kushhooda/CanvasMac/releases/download/v1.0.1/Canvas.zip"
                       sparkle:version="1.0.1"
                       sparkle:shortVersionString="1.0.1"
                       length="$FILE_SIZE"
                       type="application/octet-stream"
                       sparkle:edSignature="PASTE_THE_OUTPUT_FROM_SIGN_UPDATE_HERE" />
        </item>
EOF
echo -e "======================================================================="
echo -e ""
echo -e "Once you edit your ${BOLD}appcast.xml${RESET}, upload both ${BOLD}Canvas.zip${RESET} and ${BOLD}appcast.xml${RESET} to your hosting server (e.g., GitHub Releases / Pages)."
echo -e "${BOLD}${BLUE}======================================================================${RESET}"
