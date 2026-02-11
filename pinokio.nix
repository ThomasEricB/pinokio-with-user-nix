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
    url = "https://github.com/pinokiocomputer/pinokio/releases/download/v${version}/Pinokio_${version}_amd64.deb";
    hash = "sha256-DN1KUp/N9E47c7leVfh3pXNtRbNMnxZ/3atH9jAprbg=";
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

  unpackPhase = "dpkg-deb -x $src .";

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    # Main application files (mirrors PKGBUILD's /opt/Pinokio layout)
    mkdir -p "$out/opt/Pinokio" "$out/bin" "$out/share/applications"
    cp -r opt/Pinokio/* "$out/opt/Pinokio/"

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
    # The upstream .deb periodically changes internal paths, which breaks
    # substituteInPlace. Generating our own avoids that fragility entirely.
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
    platforms = [ "x86_64-linux" ];
    mainProgram = "pinokio";
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
  };
}
