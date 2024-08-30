{
  description = "Functional tests for cardano-node";

  inputs = {
    cardano-node = {
      url = "github:IntersectMBO/cardano-node";
      inputs = {
        node-measured.follows = "cardano-node";
        membench.follows = "/";
      };
    };
    poetry2nix = {
      inputs.nixpkgs.follows = "nixpkgs";
    };
    poetry2nix-old = {
      # pin poetry2nix to 2023.10.05.49422, sometime after
      # there is a change in the boostrap packages that expects
      # wheel to take a flint-core argument, but it doesn't. It
      # doesn't with the nixpkgs reference from cardano-node.
      # Hence we need to make sure we pin it to an old enough
      # version to work with our nixpkgs ref from cardano-node.
      url = "github:nix-community/poetry2nix?ref=2023.10.05.49422";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixpkgs.follows = "cardano-node/nixpkgs";
    flake-utils = {
      url = "github:numtide/flake-utils";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, flake-utils, cardano-node, poetry2nix, poetry2nix-old }:
    flake-utils.lib.eachDefaultSystem
      (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};

          # As we are using [poetry](https://python-poetry.org) as the python dependency manager for cardano-node-tests, we will be using
          # [poetry2nix](https://github.com/nix-community/poetry2nix) to convert the poetry project (pyproject.toml,
          # and poetry.lock) into a nix-buildable expression. This is preferable over using `pkgs.python3.withPackages`
          # as it adheres to the poetry setup instead of replicating it in nix again.
          p2n-for-nixpkgs =
            # if we are using an old nixpkgs (<23.11) then pin poetry2nix to
            # 2023.10.05.49422, sometime after there is a change in the boostrap
            # packages that expects wheel to take a flit-core argument, but it
            # doesn't. It doesn't with the nixpkgs reference from cardano-node.
            # Hence we need to make sure we pin it to an old enough version to
            # work with our nixpkgs ref from cardano-node.

            # see https://github.com/NixOS/nixpkgs/commit/3cd71e0ae67cc48f1135e55bf78cb0d67b53ff86
            # for why we do this check.
            if pkgs.lib.versionAtLeast pkgs.python3Packages.wheel.version "0.41.1"
            then (__trace "using NEW poetry2nix" poetry2nix)
            else (__trace "using OLD poetry2nix" poetry2nix-old);
          p2n = (import p2n-for-nixpkgs { inherit pkgs; });

          # base config of poetry2nix for our local project:
          p2nConfig = {
            projectDir = self;
            # We use sdist by default for faster build. Also avoid having to manually inject dependencies on build-tools:
            preferWheels = true;
            # Because we transitively depend on `py`, (through `pytest-html`), we need to drop the module from `pytest`:
            overrides = p2n.overrides.withDefaults (self: super: {
              # we remove py.py shim fallback in pytest, which might accidentally take precedence over actual py lib
              # due to the multiple site-packages in $PYTHONPATH generated by nix:
              pytest = (super.pytest.override {
                # Build from source so that we can patch:
                preferWheel = false;
              }).overridePythonAttrs (
                old: {
                  postPatch = old.postPatch or "" + ''
                    rm src/py.py
                  '';
                }
              );
            });
          };

          # Packaging of [tool.poetry.scripts] as applications:
          cardano-nodes-tests-apps = p2n.mkPoetryApplication p2nConfig;

          # All python dependencies of our local project:
          cardano-nodes-tests-env = p2n.mkPoetryEnv (p2nConfig // {
            groups = [ "dev" "docs" ];
          });

        in
        {
          packages = {
            inherit cardano-nodes-tests-apps;
            default = cardano-nodes-tests-apps;
          };
          devShells = rec {
            dev = pkgs.mkShell {
              # for local python dev:
              nativeBuildInputs = with pkgs; [ poetry cardano-nodes-tests-env ];
            };
            base = pkgs.mkShell {
              nativeBuildInputs = with pkgs; [ bash coreutils curl git gnugrep gnumake gnutar python3Packages.supervisor xz ];
            };
            python = pkgs.mkShell {
              nativeBuildInputs = with pkgs; with python39Packages; [ python39Full virtualenv pip matplotlib pandas requests xmltodict psutil GitPython pymysql ];
            };
            postgres = pkgs.mkShell {
              nativeBuildInputs = with pkgs; [ glibcLocales postgresql lsof procps ];
            };
            venv = (
              cardano-node.devShells.${system}.devops
            ).overrideAttrs (oldAttrs: rec {
              nativeBuildInputs = base.nativeBuildInputs ++ postgres.nativeBuildInputs ++ oldAttrs.nativeBuildInputs ++ [
                cardano-node.packages.${system}.cardano-submit-api
                pkgs.python3Packages.pip
                pkgs.python3Packages.virtualenv
              ];
            });
            default = (
              cardano-node.devShells.${system}.devops or (
                # Compat with 1.34.1:
                (import (cardano-node + "/shell.nix") {
                  pkgs = cardano-node.legacyPackages.${system}.extend (self: prev: {
                    workbench-supervisord =
                      { useCabalRun, profileName, haskellPackages }:
                      self.callPackage (cardano-node + "/nix/supervisord-cluster")
                        {
                          inherit profileName useCabalRun haskellPackages;
                          workbench = self.callPackage (cardano-node + "/nix/workbench") { inherit useCabalRun; };
                        };
                  });
                }).devops
              )
            ).overrideAttrs (oldAttrs: rec {
              nativeBuildInputs = base.nativeBuildInputs ++ postgres.nativeBuildInputs ++ oldAttrs.nativeBuildInputs ++ [
                cardano-node.packages.${system}.cardano-submit-api
                cardano-nodes-tests-apps
                #TODO: can be removed once tests scripts do not rely on cardano-nodes-tests-apps dependencies:
                cardano-nodes-tests-apps.dependencyEnv
              ];
            });
          };
        });

  # --- Flake Local Nix Configuration ----------------------------
  nixConfig = {
    # This sets the flake to use the IOG nix cache.
    # Nix should ask for permission before using it,
    # but remove it here if you do not want it to.
    extra-substituters = [ "https://cache.iog.io" ];
    extra-trusted-public-keys = [ "hydra.iohk.io:f/Ea+s+dFdN+3Y/G+FDgSq+a5NEWhJGzdjvKNGv0/EQ=" ];
    allow-import-from-derivation = "true";
  };
}
