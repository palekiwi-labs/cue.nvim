{
  description = "cue.nvim - Telescope pickers and tooling for cue artifacts";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { nixpkgs, flake-utils, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
      in
      {
        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            # Lua runtime matching Neovim (LuaJIT = Lua 5.1 + JIT).
            luajit
            # LSP server - produces the diagnostics surfaced in the editor.
            lua-language-server
            # Code formatter (de-facto for nvim plugins).
            stylua
            # Static analyzer / linter for Lua 5.1 / LuaJIT semantics.
            # Only available via the Lua package scope (luarocks-generated),
            # not as a top-level attribute; pin to luajitPackages so the
            # devshell ships exactly one Lua interpreter.
            luajitPackages.luacheck
          ];
        };
      });
}
