{
  description = "Pure Nix packaging for Spliit";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
        lib = pkgs.lib;
        prisma = pkgs.prisma_6;
        prismaEngines = pkgs.prisma-engines_6;
      in {
        packages.default = pkgs.buildNpmPackage {
          pname = "spliit";
          version = "1.19.1";

          src = ./.;
          npmDepsHash = "sha256-XBaFjoJpB6jE97G4hADdHRyywUn8gcgY0fb3DpV3NsE=";

          nativeBuildInputs = with pkgs; [ makeWrapper ];
          buildInputs = with pkgs; [ openssl ];

          npmFlags = [ "--ignore-scripts" ];
          npmPruneFlags = [ "--ignore-scripts" "--omit=dev" "--omit=optional" ];

          env = {
            NEXT_TELEMETRY_DISABLED = "1";
            NEXT_PUBLIC_BASE_URL = "http://127.0.0.1:3000";
            NEXT_PUBLIC_ENABLE_EXPENSE_DOCUMENTS = "false";
            NEXT_PUBLIC_ENABLE_RECEIPT_EXTRACT = "false";
            NEXT_PUBLIC_ENABLE_CATEGORY_EXTRACT = "false";
            POSTGRES_PRISMA_URL = "postgresql://postgres:1234@db/postgres";
            POSTGRES_URL_NON_POOLING = "postgresql://postgres:1234@db/postgres";
            PRISMA_ENGINES_CHECKSUM_IGNORE_MISSING = "1";
            PRISMA_SKIP_POSTINSTALL_GENERATE = "1";
            PRISMA_GENERATE_SKIP_AUTOINSTALL = "1";
            PRISMA_CLI_QUERY_ENGINE_TYPE = "binary";
            PRISMA_SCHEMA_ENGINE_BINARY = "${prismaEngines}/bin/schema-engine";
            PRISMA_QUERY_ENGINE_BINARY = "${prismaEngines}/bin/query-engine";
            PRISMA_QUERY_ENGINE_LIBRARY = "${prismaEngines}/lib/libquery_engine.node";
            PRISMA_FMT_BINARY = "${prismaEngines}/bin/prisma-fmt";
          };

          preBuild = ''
            ${prisma}/bin/prisma generate --schema=prisma/schema.prisma
          '';

          postBuild = ''
            rm -rf .next/cache
          '';

          installPhase = ''
            runHook preInstall
            mkdir -p $out/lib/node_modules/spliit $out/bin $out/share/spliit
            cp package.json package-lock.json next.config.mjs $out/lib/node_modules/spliit/
            cp -r node_modules .next public prisma messages scripts $out/lib/node_modules/spliit/

            makeWrapper ${lib.getExe pkgs.nodejs} $out/bin/spliit \
              --chdir $out/lib/node_modules/spliit \
              --set NODE_ENV production \
              --set NEXT_TELEMETRY_DISABLED 1 \
              --set PRISMA_ENGINES_CHECKSUM_IGNORE_MISSING 1 \
              --set PRISMA_SKIP_POSTINSTALL_GENERATE 1 \
              --set PRISMA_GENERATE_SKIP_AUTOINSTALL 1 \
              --set PRISMA_CLI_QUERY_ENGINE_TYPE binary \
              --set PRISMA_SCHEMA_ENGINE_BINARY ${prismaEngines}/bin/schema-engine \
              --set PRISMA_QUERY_ENGINE_BINARY ${prismaEngines}/bin/query-engine \
              --set PRISMA_QUERY_ENGINE_LIBRARY ${prismaEngines}/lib/libquery_engine.node \
              --set PRISMA_FMT_BINARY ${prismaEngines}/bin/prisma-fmt \
              --add-flags $out/lib/node_modules/spliit/node_modules/next/dist/bin/next \
              --add-flags start

            cat > $out/share/spliit/run <<EOF
#!${pkgs.runtimeShell}
set -euo pipefail
cd "$out/lib/node_modules/spliit"
export NODE_ENV=production
export NEXT_TELEMETRY_DISABLED=1
export PRISMA_ENGINES_CHECKSUM_IGNORE_MISSING=1
export PRISMA_SKIP_POSTINSTALL_GENERATE=1
export PRISMA_GENERATE_SKIP_AUTOINSTALL=1
export PRISMA_CLI_QUERY_ENGINE_TYPE=binary
export PRISMA_SCHEMA_ENGINE_BINARY=${prismaEngines}/bin/schema-engine
export PRISMA_QUERY_ENGINE_BINARY=${prismaEngines}/bin/query-engine
export PRISMA_QUERY_ENGINE_LIBRARY=${prismaEngines}/lib/libquery_engine.node
export PRISMA_FMT_BINARY=${prismaEngines}/bin/prisma-fmt
if [ -n "''${POSTGRES_PRISMA_URL:-}" ] && [ -n "''${POSTGRES_URL_NON_POOLING:-}" ]; then
  ./node_modules/.bin/prisma migrate deploy
fi
exec ${lib.getExe pkgs.nodejs} ./node_modules/next/dist/bin/next start
EOF
            chmod +x $out/share/spliit/run

            runHook postInstall
          '';

          meta = {
            description = "Free and open source Splitwise alternative";
            homepage = "https://github.com/spliit-app/spliit";
            license = lib.licenses.mit;
            mainProgram = "spliit";
            platforms = lib.platforms.unix;
          };
        };

        packages.spliit = self.packages.${system}.default;

        apps.default = {
          type = "app";
          program = "${self.packages.${system}.default}/share/spliit/run";
        };

        apps.spliit = self.apps.${system}.default;

        devShells.default = pkgs.mkShell {
          packages = with pkgs; [ nodejs prisma postgresql ];
        };

        formatter = pkgs.nixfmt-rfc-style;
      }) // {
        nixosModules.default = { config, lib, pkgs, ... }:
          let
            cfg = config.services.spliit;
            mergedSettings = cfg.settings // lib.optionalAttrs cfg.database.createLocally {
              POSTGRES_PRISMA_URL = "postgresql://${cfg.database.user}@localhost/${cfg.database.name}?host=/run/postgresql";
              POSTGRES_URL_NON_POOLING = "postgresql://${cfg.database.user}@localhost/${cfg.database.name}?host=/run/postgresql";
            };
            generatedEnvFile = pkgs.writeText "spliit.env" (
              lib.concatStringsSep "\n" (lib.mapAttrsToList (name: value: "${name}=${toString value}") mergedSettings) + "\n"
            );
          in {
            options.services.spliit = with lib; {
              enable = mkEnableOption "Spliit service";
              package = mkOption {
                type = types.package;
                default = self.packages.${pkgs.system}.default;
              };
              settings = mkOption {
                type = types.attrsOf (types.oneOf [ types.str types.int types.bool ]);
                default = {
                  PORT = 3000;
                  HOSTNAME = "127.0.0.1";
                  NEXT_PUBLIC_BASE_URL = "http://127.0.0.1:3000";
                  NEXT_PUBLIC_ENABLE_EXPENSE_DOCUMENTS = false;
                  NEXT_PUBLIC_ENABLE_RECEIPT_EXTRACT = false;
                  NEXT_PUBLIC_ENABLE_CATEGORY_EXTRACT = false;
                };
                description = "Non-secret environment variables for Spliit.";
              };
              environmentFile = mkOption {
                type = types.nullOr types.path;
                default = null;
                description = "Optional extra EnvironmentFile for secrets like OPENAI_API_KEY or S3 credentials.";
              };
              openFirewall = mkOption {
                type = types.bool;
                default = false;
              };
              database = {
                createLocally = mkOption {
                  type = types.bool;
                  default = true;
                };
                name = mkOption {
                  type = types.str;
                  default = "spliit";
                };
                user = mkOption {
                  type = types.str;
                  default = "spliit";
                };
              };
            };

            config = lib.mkIf cfg.enable {
              services.postgresql = lib.mkIf cfg.database.createLocally {
                enable = true;
                ensureDatabases = [ cfg.database.name ];
                ensureUsers = [
                  {
                    name = cfg.database.user;
                    ensureDBOwnership = true;
                  }
                ];
              };

              systemd.services.spliit = {
                description = "Spliit service";
                after = [ "network.target" ] ++ lib.optional cfg.database.createLocally "postgresql.service";
                wants = lib.optional cfg.database.createLocally "postgresql.service";
                wantedBy = [ "multi-user.target" ];
                serviceConfig = {
                  Type = "simple";
                  EnvironmentFile = [ generatedEnvFile ] ++ lib.optional (cfg.environmentFile != null) cfg.environmentFile;
                  ExecStart = "${cfg.package}/share/spliit/run";
                  Restart = "on-failure";
                  DynamicUser = true;
                  StateDirectory = "spliit";
                  WorkingDirectory = "%S/spliit";
                };
              };

              networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall [ (cfg.settings.PORT or 3000) ];
            };
          };
      };
}
