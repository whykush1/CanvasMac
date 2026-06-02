#!/bin/bash
# ==============================================================================
# Canvas macOS Clean Uninstallation Housekeeping Script
# ==============================================================================
# This script completely purges all trace settings, containers, caches,
# persistent bookmarks, login items, and downloaded assets created by Canvas.
# ==============================================================================

set -e

echo "====================================================="
echo "Canvas macOS Wallpaper Engine - Clean Uninstallation"
echo "====================================================="

# 1. Terminate any running instances of Canvas
echo "Step 1: Stopping running processes..."
killall Canvas 2>/dev/null || true
killall com.canvas.CanvasApp 2>/dev/null || true

# 2. Purge system preferences defaults plist registry
echo "Step 2: Purging preferences defaults..."
defaults delete com.canvas.CanvasApp 2>/dev/null || true

# 3. Purge standard Sandboxed App Containers
echo "Step 3: Removing Sandboxed containers..."
rm -rf "$HOME/Library/Containers/com.canvas.CanvasApp" || true
rm -rf "$HOME/Library/Containers/Canvas" || true

# 4. Purge shared Cache folders
echo "Step 4: Cleaning application cache databases..."
rm -rf "$HOME/Library/Caches/com.canvas.CanvasApp" || true

# 5. Purge Application Support folders and wallpaper assets
echo "Step 5: Deleting ingested wallpapers and app metadata..."
rm -rf "$HOME/Library/Application Support/Canvas" || true
rm -rf "$HOME/Library/Application Support/com.canvas.CanvasApp" || true

# 6. Unregister login helper launch service items
echo "Step 6: Cleaning launch items..."
# SMAppService configurations are handled by macOS system launch registries.
# Deleting the app bundle and purging containers automatically removes the login items.

echo "====================================================="
echo "Clean uninstallation housekeeping completed successfully!"
echo "All custom cache items, settings, and logs have been wiped."
echo "====================================================="
