#!/usr/bin/env bash
# ==============================================================================
# Unified Store Hub - Orchestrates All Digital Storefronts Under One App Icon
# Provides a consolidated dashboard for software installs, games, and wine tools.
# ==============================================================================
set -euo pipefail

# Fallback check to ensure flatpak repositories are loaded dynamically
flatpak remote-add --if-not-exists flathub https://flathub.org

# Verify display server initialization before popping graphical assets
if [ -z "${DISPLAY:-}" ] && [ -z "${WAYLAND_DISPLAY:-}" ]; then
    echo "CRITICAL: No active graphical display server environment found."
    exit 1
fi

# Multi-Store Management Engine: Launches a consolidated hub with interactive selectors
CHOICE=$(zenity --list --title="Unified App & Game Store" \
    --column="Icon" --column="Storefront Mode" --column="Description" \
    --window-icon="system-software-install" --width=680 --height=440 \
    "🛍️" "Universal App Store" "Browse apps, tools, web apps, and system extensions" \
    "🎮" "Epic / GOG / Amazon Games Store" "Install and run your full Epic Games, GOG, and Prime libraries" \
    "🍷" "Windows App Compatibility Core" "Deploy standalone Windows software (.exe/.msi) invisibly" \
    "💨" "Steam PC Gaming Client" "Open the primary local and Proton compatibility platform")

case "$CHOICE" in
    *"Universal App Store"*)
        flatpak run org.gnome.Software ;;
    *"Epic / GOG"*)
        flatpak run com.heroicgameslauncher.hgl ;;
    *"Windows App"*)
        flatpak run com.usebottles.bottles ;;
    *"Steam"*)
        steam ;;
    *)
        exit 0 ;;
esac
