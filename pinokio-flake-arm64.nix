{
  description = "Pinokio - AI Browser";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

  outputs = { self, nixpkgs }: let
    pkgs = nixpkgs.legacyPackages.aarch64-linux;
  in {
    packages.aarch64-linux = {
      pinokio = pkgs.callPackage ./pinokio-arm64.nix {};
      default = self.packages.aarch64-linux.pinokio;
    };
  };
}
