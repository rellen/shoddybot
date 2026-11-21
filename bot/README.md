# ShoddyBot

To start your Phoenix server:

* Run `mix setup` to install and setup dependencies
* Start Phoenix endpoint with `mix phx.server` or inside IEx with `iex -S mix phx.server`

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

## Configuration

ShoddyBot keeps environment variables to what it needs before it can reach
its database. Everything else lives in the database as Ash resources and is
set up by root in the admin pages at `/admin`:

- **Settings**: the public URL people reach ShoddyBot at, and the sender of
  outgoing mail.
- **Mail**: an SMTP server, Postmark, Mailgun or SendGrid. Until one is set
  up, ShoddyBot cannot email sign-in links (development falls back to the
  mailbox preview at <http://localhost:4000/dev/mailbox>).
- **GitHub sign-in**: a GitHub OAuth app. Until one is set up, the sign-in
  page does not offer GitHub.
- **Tenants**: see [Tenants and roles](#tenants-and-roles).

Passwords, API keys and client secrets are encrypted at rest with the
master key (`ShoddyBot.Vault`, AES-256-GCM), and the admin pages never show
them again after they are saved. Leaving a secret field blank keeps the
stored value.

On first boot in production, ShoddyBot generates its own `secret_key_base`
and token signing secret and stores them, encrypted, in the database.

### Environment variables

| Variable | Required | Purpose |
| --- | --- | --- |
| `DATABASE_URL` | Yes | PostgreSQL connection URL, `ecto://USER:PASS@HOST/DATABASE` |
| `SHODDYBOT_MASTER_KEY` | Yes | Encrypts every secret ShoddyBot stores. 32 random bytes, Base64: `openssl rand -base64 32` |
| `PORT` | No | HTTP port. Defaults to `4000` |
| `POOL_SIZE` | No | Database connections. Defaults to `10` |
| `ECTO_IPV6` | No | `true` to reach the database over IPv6 |
| `PHX_SERVER` | For releases | Set by `bin/server` to start the web server |

Back up the master key apart from the database. Without it, nothing
encrypted in the database can be read, including the generated secrets.

Development and test need none of these; `config/dev.exs` and
`config/test.exs` hold local values.

## Onboarding root

A fresh install has no users and no mail provider, so the first sign-in
link is printed rather than emailed. Run this against the release, with the
same environment as the server:

```sh
bin/shoddy_bot eval 'ShoddyBot.Release.create_root("you@example.com", public_url: "https://shoddybot.example.com")'
```

It makes that address root (creating the user if needed), saves the public
URL, and prints a single-use link that is valid for 10 minutes. Open it to
sign in, then set up mail, GitHub sign-in and tenants in the admin pages.
`public_url` is only needed the first time.

If you are ever locked out, print a fresh link for any existing user:

```sh
bin/shoddy_bot eval 'ShoddyBot.Release.sign_in_link("you@example.com")'
```

`eval` starts only the database connection and the vault, so it works
while the server is running and without Erlang distribution. In
development, call the same functions from `iex -S mix phx.server`.

## Signing in

People sign in with a magic link sent by email, or with GitHub once root
has set it up. Both create an account on first use. The pages are at
`/sign-in`.

For GitHub sign-in, create an OAuth app in GitHub under Settings, Developer
settings, OAuth Apps, with the authorization callback URL that the admin
page shows (the public URL followed by `/auth/user/github/callback`). Enter
its client ID and secret on the GitHub sign-in admin page. Use one OAuth app
per environment.

GitHub sign-in only accepts accounts whose primary email is verified on
GitHub. A GitHub sign-in whose verified email matches an existing account
signs in to that account. ShoddyBot does not keep GitHub's OAuth access token.

## Tenants and roles

One ShoddyBot install can hold several tenants. Each tenant gets its own
PostgreSQL schema, `tenant_<slug>`, created with the tenant, so tenant data
is separated at the database level. The tenant list and memberships live in
the `public` schema.

There are three roles:

- **Root** is install-wide. Root manages settings, mail, GitHub sign-in and
  tenants, and can do everything in every tenant. Root is granted only from
  the console (`ShoddyBot.Release.create_root/2`).
- **Administrator** is per tenant: everything inside that tenant, including
  its members.
- **Engineer** is per tenant: works in the tenant and sees its members.

Members are managed at `/tenants/<slug>/members`. Adding someone by email
creates their account if needed; they can then sign in with that address.

## Self-hosting

The repository's `flake.nix` builds the server as a Mix release, configured
by the [environment variables](#environment-variables) above. The release's
`bin/migrate` runs pending migrations (the `public` schema, then each tenant
schema) and `bin/server` starts the server. Requests for any host other than
`localhost` are redirected to HTTPS, so run it behind a reverse proxy that
terminates TLS and sets `X-Forwarded-Proto`.

### NixOS

```nix
{
  inputs.shoddybot.url = "github:rellen/shoddybot";

  outputs = { nixpkgs, shoddybot, ... }: {
    nixosConfigurations.myhost = nixpkgs.lib.nixosSystem {
      modules = [
        shoddybot.nixosModules.default
        ({ pkgs, ... }: {
          services.postgresql.package = pkgs.postgresql_18;
          services.shoddybot = {
            enable = true;
            # Outside the Nix store, for example from sops-nix or agenix.
            # Generate it once with `openssl rand -base64 32` and back it up.
            masterKeyFile = "/run/secrets/shoddybot-master-key";
          };
        })
      ];
    };
  };
}
```

Then onboard root as the machine's root user. `shoddybot-eval` runs
`bin/shoddy_bot eval` as the service user with the service's environment:

```sh
shoddybot-eval 'ShoddyBot.Release.create_root("you@example.com", public_url: "https://shoddybot.example.com")'
```

By default the module creates a local PostgreSQL database and role, connects
over the Unix socket, and runs migrations before each start. Set
`services.shoddybot.database.createLocally = false` and provide a
`DATABASE_URL` through `database.url` or `environmentFile` to use another
server. The server listens on port 4000 on all interfaces; open it with
`openFirewall` only if no reverse proxy sits on the same machine.

The module's earlier `host`, `secretKeyBaseFile`, `tokenSigningSecretFile`,
`github.*` and `mailFrom` options are gone: those settings now live in the
database.

### Container

```sh
nix build .#container
docker load < result
docker run --name shoddybot -p 4000:4000 \
  -e DATABASE_URL=ecto://user:pass@db.example.com/shoddybot \
  -e SHODDYBOT_MASTER_KEY=... \
  shoddybot:0.1.0
docker exec shoddybot shoddy_bot eval 'ShoddyBot.Release.create_root("you@example.com", public_url: "https://shoddybot.example.com")'
```

The entrypoint runs migrations, then starts the server. The database role
needs to be able to create the `citext` extension, which the database owner
can do, and to create schemas, one per tenant.

## Learn more

* Official website: https://www.phoenixframework.org/
* Guides: https://phoenix.hexdocs.pm/overview.html
* Docs: https://phoenix.hexdocs.pm
* Forum: https://elixirforum.com/c/phoenix-forum
* Source: https://github.com/phoenixframework/phoenix
