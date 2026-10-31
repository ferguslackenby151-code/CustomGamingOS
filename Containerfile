# ==============================================================================
# Universal Blue custom image
#   Fedora Silverblue + CachyOS kernel (BORE scheduler)
#   + Windows-Style Desktop Environment & Unified Store Layout
#   + gamemode / mangohud / steam / flatpak
#   + local-only accounts, Fedora/GNOME/rpm-ostree telemetry disabled
# ==============================================================================

ARG BASE_IMAGE=ghcr.io/ublue-os/silverblue-main
ARG FEDORA_VERSION=latest

FROM ${BASE_IMAGE}:${FEDORA_VERSION}

ARG FEDORA_VERSION=latest

LABEL org.opencontainers.image.title="silverblue-cachyos" \
      org.opencontainers.image.description="uBlue Silverblue with CachyOS (BORE) kernel and gaming stack"

# ------------------------------------------------------------------------------
# 1. Repositories: Safely enable the official CachyOS kernel COPR repo
# ------------------------------------------------------------------------------
RUN <<'EOF'
set -euxo pipefail

# Enable the repository natively using Fedora's built-in package utilities
dnf copr enable -y bieszczaders/kernel-cachyos
EOF

# ------------------------------------------------------------------------------
# 2. Swap the stock Fedora kernel for kernel-cachyos (BORE scheduler built in)
# ------------------------------------------------------------------------------
RUN <<'EOF'
set -euxo pipefail

# Let kernel scriptlets and deployment run smoothly inside a container build
rpm-ostree cliwrap install-to-root /

# Dynamically query and completely strip out default fallback kernel layers
REMOVE=""
for p in kernel kernel-core kernel-modules kernel-modules-core kernel-modules-extra; do
    if rpm -q --quiet "$p"; then REMOVE="$REMOVE $p"; fi
done

# Perform an atomic infrastructure layer shift directly to kernel-cachyos
rpm-ostree override remove $REMOVE --install kernel-cachyos
EOF

# Pin down BORE scheduler parameters explicitly into host network parameters
COPY <<'EOF' /usr/lib/sysctl.d/70-bore.conf
# BORE (Burst-Oriented Response Enhancer) scheduler activation
kernel.sched_bore = 1
EOF

# ------------------------------------------------------------------------------
# 3. Gaming stack + Windows Layout extensions + flatpak
# ------------------------------------------------------------------------------
RUN rpm-ostree install --idempotent \
        gamemode \
        mangohud \
        steam \
        flatpak \
        zenity \
        gnome-extensions-app \
        gnome-shell-extension-dash-to-panel \
        gnome-shell-extension-arc-menu \
        gnome-shell-extension-appindicator

RUN mkdir -p /etc/flatpak/remotes.d \
 && curl -fsSL --retry 3 -o /etc/flatpak/remotes.d/flathub.flatpakrepo \
        https://flathub.org

COPY unified-store.sh /tmp/unified-store.sh
COPY unified-store.desktop /tmp/unified-store.desktop
COPY setup-stores.sh /tmp/setup-stores.sh
RUN chmod +x /tmp/setup-stores.sh && /tmp/setup-stores.sh --system --foreground && rm /tmp/setup-stores.sh

# ------------------------------------------------------------------------------
# 4. Local-only user accounts (Locks out online directory integrations)
# ------------------------------------------------------------------------------
RUN <<'EOF'
set -euxo pipefail
authselect select local --force
systemctl mask sssd.service realmd.service
EOF

# ------------------------------------------------------------------------------
# 5. Zero online telemetry (Completely isolates your users from data tracking)
# ------------------------------------------------------------------------------
# 5a. Disable DNF/rpm-ostree repo beacon hits and automatic crash reporters
RUN <<'EOF'
set -euxo pipefail
sed -i '/^countme=/d' /etc/yum.repos.d/*.repo
systemctl mask \
    rpm-ostree-countme.timer rpm-ostree-countme.service \
    abrtd.service abrt-journal-core.service abrt-oops.service \
    abrt-xorg.service abrt-vmcore.service abrt-pstoreoops.service
EOF

# 5b. Force NetworkManager to check connection state completely locally
COPY <<'EOF' /etc/NetworkManager/conf.d/99-no-connectivity-check.conf
[connectivity]
enabled=false
EOF

# 5c. Absolute GNOME privacy lockdown (Stops problem reporting, geo-tracking, and cloud linking)
COPY <<'EOF' /etc/dconf/profile/user
user-db:user
system-db:local
EOF

COPY <<'EOF' /etc/dconf/db/local.d/00-no-telemetry
[org/gnome/desktop/privacy]
report-technical-problems=false
send-software-usage-stats=false

[org/gnome/system/location]
enabled=false

[org/gnome/online-accounts]
whitelisted-providers=@as []
EOF

COPY <<'EOF' /etc/dconf/db/local.d/locks/00-no-telemetry
/org/gnome/desktop/privacy/report-technical-problems
/org/gnome/desktop/privacy/send-software-usage-stats
/org/gnome/system/location/enabled
/org/gnome/online-accounts/whitelisted-providers
EOF

# Inject your custom Windows-style taskbar and single app store configuration
COPY 01-desktop-defaults /etc/dconf/db/local.d/01-desktop-defaults
RUN dconf update

# ------------------------------------------------------------------------------
# 6. Finalise image layer structure
# ------------------------------------------------------------------------------
RUN <<'EOF'
set -euxo pipefail
rpm-ostree cleanup -m
rm -rf /tmp/* /var/tmp/*
ostree container commit
EOF

RUN if command -v bootc >/dev/null 2>&1; then bootc container lint; fi


