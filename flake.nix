{
  description = "RiteOpt: mruby RITE optimizer";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixpkgs-ruby = {
      url = "github:bobvanderlinden/nixpkgs-ruby";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, nixpkgs-ruby }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      eachSystem = nixpkgs.lib.genAttrs systems;
      environments = eachSystem (system:
        let
          pkgs = import nixpkgs {
            inherit system;
            overlays = [ nixpkgs-ruby.overlays.default ];
          };
          ruby = pkgs."ruby-4.0.7";
          # nixpkgs' mruby package contains both mrbc and mruby. It is marked
          # broken on Darwin because its test suite is not supported there.
          # RiteOpt only needs the built tools, so skip that check on Darwin.
          mruby = if pkgs.stdenv.isDarwin then
            pkgs.mruby.overrideAttrs (old: {
              doCheck = false;
              meta = old.meta // { broken = false; };
            })
          else
            pkgs.mruby;
          riteOpt = pkgs.writeShellApplication {
            name = "rite-opt";
            runtimeInputs = [ ruby ];
            text = ''
              exec ruby ${self}/exe/rite-opt "$@"
            '';
          };
        in { inherit pkgs ruby mruby riteOpt; });
    in {
      packages = eachSystem (system:
        let env = environments.${system}; in {
          default = env.riteOpt;
          "rite-opt" = env.riteOpt;
          mruby = env.mruby;
        });

      apps = eachSystem (system:
        let env = environments.${system}; in {
          default = {
            type = "app";
            program = "${env.riteOpt}/bin/rite-opt";
          };
          "rite-opt" = {
            type = "app";
            program = "${env.riteOpt}/bin/rite-opt";
          };
        });

      devShells = eachSystem (system:
        let env = environments.${system}; in {
          default = env.pkgs.mkShell {
            packages = [ env.ruby env.mruby env.pkgs.git ];
            MRBC = "${env.mruby}/bin/mrbc";
            MRUBY = "${env.mruby}/bin/mruby";
          };
        });

      checks = eachSystem (system:
        let env = environments.${system}; in {
          tests = env.pkgs.runCommand "rite-opt-tests" {
            nativeBuildInputs = [ env.ruby env.mruby ];
          } ''
            cp -R ${self} source
            chmod -R u+w source
            cd source
            export MRBC="${env.mruby}/bin/mrbc"
            export MRUBY="${env.mruby}/bin/mruby"
            ruby -Ilib -e 'Dir["test/**/*_test.rb"].sort.each { |file| require_relative file }'
            touch "$out"
          '';
        });
    };
}
