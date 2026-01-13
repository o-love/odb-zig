{
  description = "An empty project that uses Zig.";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-23.05";
    flake-utils.url = "github:numtide/flake-utils";
    zig.url = "github:mitchellh/zig-overlay";
    zls.url = "github:zigtools/zls";
  };

  outputs = {
    self,
    nixpkgs,
    flake-utils,
    ...
  } @ inputs: let
    overlays = [
      # Other overlays
      (final: prev: {
        zigpkgs = inputs.zig.packages.${prev.system};
        zlspkgs = inputs.zls.packages.${prev.system};
      })
    ];

    # Our supported systems are the same supported systems as the Zig binaries
    systems = builtins.attrNames inputs.zig.packages;
  in
    flake-utils.lib.eachSystem systems (
      system: let
        pkgs = import nixpkgs {inherit overlays system;};
      in rec {
        packages.default = pkgs.stdenv.mkDerivation {
          pname = "odb-zig";
          version = "0.1.0";
          src = ./.;
          nativeBuildInputs = [pkgs.zigpkgs.master];

          preBuild = ''
            # Necessary for zig cache to work
            export HOME=$TMPDIR
          '';

          installPhase = ''
            runHook preInstall
            zig build -Doptimize=ReleaseSafe
            runHook postInstall
          '';
        };

        # This runs during 'nix flake check'
        checks = {
          # 1. Check that it builds and passes internal tests
          build = self.packages.${system}.default.overrideAttrs (old: {
            doCheck = true;
            checkPhase = ''
              export HOME=$TMPDIR
              zig build test
            '';
          });

          # 2. Check formatting
          format =
            pkgs.runCommand "check-format" {
              nativeBuildInputs = [pkgs.zigpkgs.master];
            } ''
              export HOME=$TMPDIR
              cd ${./.}
              zig fmt . --check
              touch $out # Nix needs a file output to consider it a success
            '';
        };

        devShells.default = pkgs.mkShell {
          inputsFrom = [self.packages.${system}.default];
          packages = [pkgs.zlspkgs.zls];
        };
      }
    );
}
