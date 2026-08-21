{
  description = "ff2ppress - ffmpeg 2-pass video compression script";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
      in {
        packages.default = pkgs.stdenv.mkDerivation {
          pname = "ff2p-press";
          version = "0-unstable-${self.shortRev or "dirty"}";

          src = ./.;

          nativeBuildInputs = [ pkgs.makeWrapper ];

          dontConfigure = true;
          dontBuild = true;

          installPhase = ''
            runHook preInstall

            install -Dm644 ff2ppress.ps1 $out/share/ff2p-press/ff2ppress.ps1

            makeWrapper ${pkgs.powershell}/bin/pwsh $out/bin/ff2ppress \
              --add-flags "-NoProfile -File $out/share/ff2p-press/ff2ppress.ps1" \
              --prefix PATH : ${pkgs.lib.makeBinPath [ pkgs.ffmpeg ]}

            runHook postInstall
          '';

          meta = with pkgs.lib; {
            description = "PowerShell script using ffmpeg 2-pass to compress videos to a target size";
            homepage = "https://github.com/Mot0193/ff2p-press";
            license = licenses.gpl3Only;
            mainProgram = "ff2ppress";
            platforms = platforms.unix;
          };
        };
      });
}
