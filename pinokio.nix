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
    mkdir -p "$out/opt/Pinokio" "$out/bin" "$out/share"
    cp -r opt/Pinokio/* "$out/opt/Pinokio/"

    # Desktop file and icons
    cp -r usr/share/* "$out/share/"

    # Fix paths inside the .desktop file
    substituteInPlace "$out/share/applications/pinokio.desktop" \
      --replace-fail "/opt/Pinokio/pinokio" "$out/bin/pinokio" \
      --replace-fail "/opt/Pinokio" "$out/opt/Pinokio"

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
