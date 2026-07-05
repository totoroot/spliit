# Nix packaging for Spliit

## Result

This repo now contains:

- a pure `buildNpmPackage` package in `flake.nix`
- flake apps: `nix run .#spliit` or `nix run .#default`
- a NixOS module: `nixosModules.default`
- service option: `services.spliit`

The package uses Prisma 6 from nixpkgs:

- `prisma_6`
- `prisma-engines_6`

This is intentional. Newer Prisma packages in nixpkgs caused packaging/runtime friction for this app.

## Build

```bash
nix build .#default
```

## Run locally

You need PostgreSQL reachable through Prisma connection env vars.

Example against a local PostgreSQL on TCP:

```bash
POSTGRES_PRISMA_URL='postgresql://postgres:password@127.0.0.1/spliit?host=127.0.0.1' \
POSTGRES_URL_NON_POOLING='postgresql://postgres:password@127.0.0.1/spliit?host=127.0.0.1' \
NEXT_PUBLIC_DEFAULT_CURRENCY_CODE=EUR \
./result/share/spliit/run
```

Then check:

```bash
curl -i http://127.0.0.1:3000/api/health/liveness
curl -i http://127.0.0.1:3000/api/health/readiness
```

The runtime wrapper automatically runs:

- `prisma migrate deploy`
- then `next start`

## Notes about Prisma and OpenSSL

The package explicitly exports Prisma engine paths and `LD_LIBRARY_PATH` so Prisma can find:

- schema engine
- query engine
- `libquery_engine.node`
- OpenSSL 3 runtime libraries

If you still see Prisma OpenSSL warnings on a target machine, verify actual runtime behavior before assuming failure. Earlier failures in this packaging effort were caused by connection URL and launcher issues, not only the warning itself.

## NixOS module

Example flake usage:

```nix
{
  inputs.spliit.url = "github:totoroot/spliit";

  outputs = { nixpkgs, spliit, ... }: {
    nixosConfigurations.myhost = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        spliit.nixosModules.default
        ({ ... }: {
          services.spliit = {
            enable = true;
            settings = {
              PORT = 3000;
              NEXT_PUBLIC_BASE_URL = "https://spliit.example.test";
            };
            database = {
              createLocally = true;
              name = "spliit";
              user = "spliit";
            };
          };
        })
      ];
    };
  };
}
```

## Module behavior

If `database.createLocally = true`, the module:

- enables PostgreSQL
- creates the database and user
- generates Prisma connection URLs automatically
- starts the service as `systemd.services.spliit`

The generated local DB URL uses the PostgreSQL Unix socket with an explicit host component:

```text
postgresql://USER@localhost/DB?host=/run/postgresql
```

## Secrets

For the base setup with local PostgreSQL, no secret env file is required.

Use `environmentFile` only for optional secret-backed features such as:

- `OPENAI_API_KEY`
- `S3_UPLOAD_KEY`
- `S3_UPLOAD_SECRET`

Example:

```nix
services.spliit.environmentFile = "/run/secrets/spliit.env";
```
