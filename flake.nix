{
  description = "ShoddyBot: self-hosted management of software repositories and the applications running from them";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      inherit (nixpkgs) lib;

      linuxSystems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      systems = linuxSystems ++ [
        "aarch64-darwin"
      ];

      forSystems = systems: f: lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});

      # The Erlang/OTP and Elixir versions from the toolchain table in
      # AGENTS.md. Change them here and in AGENTS.md together.
      #
      # The release uses `beam_minimal` (no wxWidgets, ODBC or systemd), which
      # keeps the server closure small. The development shell uses the full
      # `beam` so tools such as :observer work.
      beamPackagesFor =
        beam: beam.packages.erlang_29.overrideScope (_final: prev: { elixir = prev.elixir_1_20; });
    in
    {
      packages =
        lib.recursiveUpdate
          (forSystems systems (pkgs: rec {
            shoddybot = pkgs.callPackage ./bot/nix/package.nix {
              beamPackages = beamPackagesFor pkgs.beam_minimal;
            };
            default = shoddybot;
          }))
          (
            forSystems linuxSystems (pkgs: {
              container = pkgs.callPackage ./bot/nix/container.nix {
                shoddybot = self.packages.${pkgs.stdenv.hostPlatform.system}.shoddybot;
              };
            })
          );

      nixosModules = rec {
        shoddybot = import ./bot/nix/module.nix { inherit self; };
        default = shoddybot;
      };

      devShells = forSystems systems (pkgs: rec {
        bot = pkgs.callPackage ./bot/nix/shell.nix { beamPackages = beamPackagesFor pkgs.beam; };
        default = bot;
      });

      checks =
        lib.recursiveUpdate
          (forSystems systems (pkgs: {
            inherit (self.packages.${pkgs.stdenv.hostPlatform.system}) shoddybot;
            formatting = pkgs.runCommand "check-nix-formatting" { nativeBuildInputs = [ pkgs.nixfmt ]; } ''
              cd ${self}
              nixfmt --check $(find . -name '*.nix')
              touch $out
            '';
          }))
          (
            forSystems linuxSystems (pkgs: {
              inherit (self.packages.${pkgs.stdenv.hostPlatform.system}) container;
              nixos-module = pkgs.testers.runNixOSTest (import ./bot/nix/test.nix { inherit self; });
            })
          );

      formatter = forSystems systems (pkgs: pkgs.nixfmt-tree);
    };
}
