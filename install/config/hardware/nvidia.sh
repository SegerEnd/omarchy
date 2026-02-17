NVIDIA="$(lspci | grep -i 'nvidia')"

if [ -n "$NVIDIA" ]; then
  # Detect running kernel and matching headers (Omarchy-safe)
  KERNEL_VERSION="$(uname -r)"
  KERNEL_PKG="$(pacman -Qqo "/usr/lib/modules/$KERNEL_VERSION" 2>/dev/null)"
  KERNEL_HEADERS="${KERNEL_PKG}-headers"

  # Select driver branch
  if echo "$NVIDIA" | grep -qE "RTX [2-9][0-9]|GTX 16"; then
    # Turing (16xx, 20xx), Ampere (30xx), Ada (40xx)
    PACKAGES=(nvidia-open-dkms nvidia-utils lib32-nvidia-utils libva-nvidia-driver)
  elif echo "$NVIDIA" | grep -qE "GTX 9|GTX 10|Quadro P|MX1|MX2|MX3"; then
    # Pascal (10xx, Quadro Pxxx, MX150, MX2xx, and MX3xx) and Maxwell (9xx, MX110, and MX130) use legacy branch that can only be installed from AUR
    PACKAGES=(nvidia-580xx-dkms nvidia-580xx-utils lib32-nvidia-580xx-utils)
  fi
  # Bail if no supported GPU
  if [ -z "${PACKAGES+x}" ]; then
    echo "No compatible driver for your NVIDIA GPU. See: https://wiki.archlinux.org/title/NVIDIA"
    exit 0
  fi

  # Install kernel headers + drivers (safe if already installed)
  omarchy-pkg-add "$KERNEL_HEADERS" "${PACKAGES[@]}"

  # Build DKMS modules (idempotent)
  sudo dkms autoinstall >/dev/null 2>&1 || true

  # Enable early KMS ONLY if NVIDIA modules exist for this kernel
  if ls "/usr/lib/modules/$KERNEL_VERSION"/**/nvidia.ko* >/dev/null 2>&1; then
    # modprobe config (idempotent overwrite)
    sudo tee /etc/modprobe.d/nvidia.conf >/dev/null <<EOF
options nvidia_drm modeset=1
EOF

    # mkinitcpio config (idempotent overwrite)
    sudo tee /etc/mkinitcpio.conf.d/nvidia.conf >/dev/null <<EOF
MODULES+=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)
EOF

    # Rebuild initramfs (safe)
    sudo mkinitcpio -P >/dev/null 2>&1 || true
  fi

  # Add NVIDIA environment variables (idempotent append)
  mkdir -p "$HOME/.config/hypr"
  grep -q "# NVIDIA" "$HOME/.config/hypr/envs.conf" 2>/dev/null || cat >>"$HOME/.config/hypr/envs.conf" <<'EOF'

# NVIDIA
env = NVD_BACKEND,direct
env = LIBVA_DRIVER_NAME,nvidia
env = __GLX_VENDOR_LIBRARY_NAME,nvidia
EOF
fi
