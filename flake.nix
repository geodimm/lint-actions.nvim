{
  inputs = {
    nixpkgs = {
      url = "github:nixos/nixpkgs/nixos-unstable";
    };
    # Neovim 0.11.x
    nixpkgs-neovim-0_11 = {
      url = "github:nixos/nixpkgs/nixos-25.11";
    };
    flake-utils = {
      url = "github:numtide/flake-utils";
    };
    neovim-nightly-overlay = {
      url = "github:nix-community/neovim-nightly-overlay";
    };
  };
  outputs =
    {
      nixpkgs,
      nixpkgs-neovim-0_11,
      flake-utils,
      neovim-nightly-overlay,
      ...
    }:
    flake-utils.lib.eachSystem
      [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ]
      (
        system:
        let
          pkgs = import nixpkgs { inherit system; };
          packages = with pkgs; [
            git
            stylua
            just
            panvimdoc
            neovim
            lua-language-server
            lua51Packages.luacheck
            lua51Packages.nlua
            lua51Packages.busted
          ];
          # Tests run inside nvim, which loads native Lua modules (e.g. busted's luasystem), so nlua
          # and busted must come from the nixpkgs that built this Neovim and share its glibc.
          testShell =
            name: neovim:
            let
              luaPkgs = neovim.lua.pkgs;
              nlua = pkgs.writeShellScriptBin "nlua" ''
                exec env NVIM_LOG_FILE="''${NVIM_LOG_FILE:-/dev/null}" \
                  ${neovim}/bin/nvim -u NONE -U NONE -N -i NONE -l ${luaPkgs.nlua}/bin/nlua "$@"
              '';
            in
            pkgs.mkShell {
              inherit name;
              packages = [
                pkgs.git
                pkgs.just
                neovim
                nlua
                luaPkgs.busted
              ];
            };
        in
        {
          devShells.default = pkgs.mkShell {
            name = "lint-actions.nvim";
            inherit packages;
          };
          devShells.ci = pkgs.mkShell {
            name = "ci";
            inherit packages;
          };
          devShells.ci-0_11 =
            testShell "ci-0_11"
              nixpkgs-neovim-0_11.legacyPackages.${system}.neovim-unwrapped;
          # The overlay's CI pushes `checks` (not `packages`) to nix-community.cachix.org.
          devShells.ci-nightly = testShell "ci-nightly" neovim-nightly-overlay.checks.${system}.neovim;
        }
      );
}
