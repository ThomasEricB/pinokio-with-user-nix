{
  lib,
  stdenv,
  fetchurl,
  dpkg,
  autoPatchelfHook,
  makeWrapper,
  # Electron / Chromium runtime dependencies
  alsa-lib,
  at-spi2-core,
  cairo,
  cups,
  dbus,
  expat,
  gdk-pixbuf,
  glib,
  gtk3,
  libdrm,
  libGL,
  libnotify,
  libsecret,
  libxkbcommon,
  mesa,
  nspr,
  nss,
  pango,
  systemd,
  xdg-utils,
  xorg,
}:

stdenv.mkDerivation rec {
  pname = "pinokio";
  version = "6.0.10";

  src = fetchurl {
    url = "https://github.com/pinokiocomputer/pinokio/releases/download/v${version}/Pinokio_${version}_arm64.deb";
    hash = "sha256-6T5Mu80R50chhL8W/RG7/LswPmqc6K7ibhtrqBJlNAE=";
  };

  nativeBuildInputs = [
    dpkg
    autoPatchelfHook
    makeWrapper
  ];

  # Libraries that autoPatchelfHook resolves at build time via ELF headers.
  buildInputs = [
    alsa-lib
    at-spi2-core
    cairo
    cups
    dbus
    expat
    gdk-pixbuf
    glib
    gtk3
    libdrm
    libxkbcommon
    mesa
    nspr
    nss
    pango
    xorg.libX11
    xorg.libXcomposite
    xorg.libXdamage
    xorg.libXext
    xorg.libXfixes
    xorg.libXrandr
    xorg.libXScrnSaver
    xorg.libXtst
    xorg.libxcb
  ];

  # Libraries loaded at runtime via dlopen() that autoPatchelfHook cannot
  # detect from ELF headers. This is the standard workaround for Electron
  # apps on Nix (see nixpkgs#282749).
  runtimeDependencies = [
    libGL
    libnotify
    libsecret
    systemd          # libudev.so.1
    xdg-utils
  ];

  # The .deb bundles prebuilt musl-linked .node binaries (for Alpine)
  # alongside the glibc ones. They will never run on a glibc system,
  # but autoPatchelfHook fails trying to resolve libc.musl. Ignore it.
  autoPatchelfIgnoreMissingDeps = [ "libc.musl-aarch64.so.1" ];

  unpackPhase = "dpkg-deb -x $src .";

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    # Main application files (mirrors PKGBUILD's /opt/Pinokio layout)
    mkdir -p "$out/opt/Pinokio" "$out/bin" "$out/share/applications"
    cp -r opt/Pinokio/* "$out/opt/Pinokio/"

    # Remove musl-linked prebuilt binaries. These are for Alpine Linux
    # and are non-functional on glibc systems. Removing them also stops
    # autoPatchelfHook from scanning them at all.
    find "$out/opt/Pinokio" -name '*.musl.node' -delete
    rm -rf "$out/opt/Pinokio/resources/app.asar.unpacked/node_modules/@parcel/watcher-linux-arm64-musl" || true

    # ── ARM64-specific fixes ──────────────────────────────────────────
    # The arm64 .deb ships with two broken module paths that cause
    # Pinokio to crash on launch. See:
    # https://www.youtube.com/watch?v=mSQVdyvHzFU
    #
    # Fix 1: node-pty — the app expects the native binding at
    # build/Release/pty.node but the .deb only ships prebuilds/.
    # Pick the highest glibc ABI prebuilt for linux-arm64.
    pty_mod="$out/opt/Pinokio/resources/app.asar.unpacked/node_modules/@homebridge/node-pty-prebuilt-multiarch"
    if [ -d "$pty_mod/prebuilds/linux-arm64" ]; then
      mkdir -p "$pty_mod/build/Release"
      # Grab the highest-numbered glibc ABI build (not musl).
      pty_src=$(find "$pty_mod/prebuilds/linux-arm64" -name 'node.abi*.node' ! -name '*.musl.node' | sort -t'.' -k1 -V | tail -n1)
      if [ -n "$pty_src" ]; then
        cp "$pty_src" "$pty_mod/build/Release/pty.node"
      fi
    fi

    # Fix 2: @parcel/watcher — the app looks for the native binding at
    # @parcel/watcher/build/Release/watcher.node, but the .deb only
    # ships the platform-specific package @parcel/watcher-linux-arm64-glibc.
    watcher_glibc="$out/opt/Pinokio/resources/app.asar.unpacked/node_modules/@parcel/watcher-linux-arm64-glibc"
    watcher_dest="$out/opt/Pinokio/resources/app.asar.unpacked/node_modules/@parcel/watcher/build/Release"
    if [ -f "$watcher_glibc/watcher.node" ]; then
      mkdir -p "$watcher_dest"
      cp "$watcher_glibc/watcher.node" "$watcher_dest/watcher.node"
    fi

    # Copy icons from the upstream .deb (if present)
    if [ -d usr/share/icons ]; then
      mkdir -p "$out/share/icons"
      cp -r usr/share/icons/* "$out/share/icons/"
    fi
    if [ -d usr/share/pixmaps ]; then
      mkdir -p "$out/share/pixmaps"
      cp -r usr/share/pixmaps/* "$out/share/pixmaps/"
    fi

    # Write a clean .desktop file instead of patching the upstream one.
    cat > "$out/share/applications/pinokio.desktop" <<DESKTOP
    [Desktop Entry]
    Name=Pinokio
    Exec=$out/bin/pinokio %U
    Terminal=false
    Type=Application
    Icon=pinokio
    StartupWMClass=Pinokio
    Comment=AI browser that can install, run, and control any application automatically
    Categories=Utility;Development;
    MimeType=x-scheme-handler/pinokio;
    DESKTOP

    # Wrapper: --no-sandbox is required inside nix-user-chroot because
    # Chromium's CLONE_NEWUSER namespace sandbox cannot work without
    # real root or unprivileged user namespaces (absent in most chroots).
    # --disable-gpu-sandbox prevents a secondary sandbox failure for the
    # GPU process, which would otherwise cause a silent black window.
    makeWrapper "$out/opt/Pinokio/pinokio" "$out/bin/pinokio" \
      --add-flags "--no-sandbox" \
      --add-flags "--disable-gpu-sandbox" \
      --prefix LD_LIBRARY_PATH : "${lib.makeLibraryPath runtimeDependencies}"

    runHook postInstall
  '';

  meta = {
    homepage = "https://pinokio.computer";
    description = "AI browser that can install, run, and control any application automatically";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [ ByteSudoer ];
    platforms = [ "aarch64-linux" ];
    mainProgram = "pinokio";
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
  };
}
