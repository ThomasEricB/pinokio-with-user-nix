{
  description = "Pinokio - AI Browser";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

  outputs = { self, nixpkgs }: let
    pkgs = nixpkgs.legacyPackages.x86_64-linux;
  in {
    packages.x86_64-linux = {
      pinokio = pkgs.callPackage ./pinokio.nix {};
      default = self.packages.x86_64-linux.pinokio;
    };
  };
}
