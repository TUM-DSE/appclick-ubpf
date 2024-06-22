{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-23.11";
    unstablepkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, unstablepkgs, flake-utils }:
    (flake-utils.lib.eachDefaultSystem
        (system:
            let
              pkgs = import nixpkgs {
                  inherit system;
              };
              unstable = import unstablepkgs {
                   inherit system;
              };
              buildDeps = with pkgs; [
                pkg-config
                gnumake
                flex
                bison
                git
                wget
                libuuid
                gcc
                qemu
                qemu_kvm
                cmake
                unzip
                clang
                openssl
                ncurses
                bridge-utils
                python3Packages.numpy
                python3Packages.matplotlib
                python3Packages.scipy
                gnuplot
                llvmPackages_15.bintools
              ];
            in
            {
              devShells.default = pkgs.mkShell {
                name = "devShell";
                buildInputs = buildDeps ++ [
                    unstable.kraft
                    unstable.rustup
                    unstable.bmon
                    unstable.gh
                ];
                KRAFTKIT_NO_WARN_SUDO = "1";
                KRAFTKIT_NO_CHECK_UPDATES = "true";
              };
            }
        )
    );
}
