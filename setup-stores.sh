#!/usr/bin/env bash
# ==============================================================================
# First-Boot Unified Store Automation Provisioner
# Runs smoothly on the user's first desktop log-in to setup the apps.
# ==============================================================================

# Guard check: Only run once ever for the user
if [ -f "$HOME/.config/stores-setup-done" ]; then
    exit 0
fi

# Ensure flatpak remote is safely configured under user scope parameters
flatpak remote-add --user --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo

# Silently deploy the unified store applications into the user space
flatpak install --user flathub com.heroicgameslauncher.hgl -y --noninteractive
flatpak install --user net.lutris.Lutris -y --noninteractive
flatpak install --user com.usebottles.bottles -y --noninteractive
flatpak install --user net.davidotek.pupgui2 -y --noninteractive
flatpak install --user com.valvesoftware.Steam -y --noninteractive

# Mark setup as successfully complete so it never loops or runs again
mkdir -p "$HOME/.config"
touch "$HOME/.config/stores-setup-done"
