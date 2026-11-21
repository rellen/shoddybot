# NixOS module: services.shoddybot runs the ShoddyBot server as a systemd
# service, optionally with a local PostgreSQL database.
{ self }:
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.shoddybot;

  inherit (lib)
    literalExpression
    mkEnableOption
    mkIf
    mkOption
    optional
    types
    ;

  # Secrets are read at runtime from an absolute path outside the Nix store,
  # which is world-readable.
  secretPath = types.pathWith {
    inStore = false;
    absolute = true;
  };

  localDatabaseUrl = "ecto://${cfg.database.user}@localhost/${cfg.database.name}?socket_dir=/run/postgresql";

  environment = {
    PHX_HOST = cfg.host;
    PORT = toString cfg.port;
    POOL_SIZE = toString cfg.database.poolSize;
    # The release writes its generated runtime configuration here. The
    # default, inside the release, is the read-only Nix store.
    RELEASE_TMP = "/run/shoddybot";
    # A single node: no Erlang distribution, so no epmd or distribution port
    # is opened. Override in `environment` to attach remote shells.
    RELEASE_DISTRIBUTION = "none";
    LANG = "C.UTF-8";
    GITHUB_CLIENT_ID = cfg.github.clientId;
  }
  // lib.optionalAttrs (cfg.github.redirectUri != null) {
    GITHUB_REDIRECT_URI = cfg.github.redirectUri;
  }
  // lib.optionalAttrs (cfg.mailFrom != null) { MAIL_FROM = cfg.mailFrom; }
  // lib.optionalAttrs (cfg.database.url != null) { DATABASE_URL = cfg.database.url; }
  // cfg.environment;

  # Reads secrets from systemd credentials into the environment the release
  # expects, then runs the given release command.
  withSecrets = pkgs.writeShellScript "shoddybot-with-secrets" ''
    set -euo pipefail
    SECRET_KEY_BASE="$(< "$CREDENTIALS_DIRECTORY/secret_key_base")"
    TOKEN_SIGNING_SECRET="$(< "$CREDENTIALS_DIRECTORY/token_signing_secret")"
    GITHUB_CLIENT_SECRET="$(< "$CREDENTIALS_DIRECTORY/github_client_secret")"
    export SECRET_KEY_BASE TOKEN_SIGNING_SECRET GITHUB_CLIENT_SECRET
    exec "$@"
  '';
in
{
  options.services.shoddybot = {
    enable = mkEnableOption "the ShoddyBot server";

    package = mkOption {
      type = types.package;
      default = self.packages.${pkgs.stdenv.hostPlatform.system}.shoddybot;
      defaultText = literalExpression "shoddybot.packages.\${pkgs.stdenv.hostPlatform.system}.shoddybot";
      description = "The ShoddyBot release to run.";
    };

    host = mkOption {
      type = types.str;
      example = "shoddybot.example.com";
      description = ''
        Public host name ShoddyBot is served from, used to build URLs. The
        server expects to sit behind a reverse proxy that terminates TLS and
        sets `X-Forwarded-Proto`; requests for any other host than
        `localhost` are redirected to HTTPS.
      '';
    };

    port = mkOption {
      type = types.port;
      default = 4000;
      description = "Port the HTTP server listens on, on all interfaces.";
    };

    openFirewall = mkOption {
      type = types.bool;
      default = false;
      description = "Whether to open {option}`services.shoddybot.port` in the firewall.";
    };

    secretKeyBaseFile = mkOption {
      type = secretPath;
      example = "/run/secrets/shoddybot-secret-key-base";
      description = ''
        File holding the secret used to sign and encrypt cookies and
        pagination keys. Generate one with `openssl rand -base64 48`. It is
        passed to the service as a systemd credential, so it can be readable
        by root only, and it never enters the Nix store.
      '';
    };

    tokenSigningSecretFile = mkOption {
      type = secretPath;
      example = "/run/secrets/shoddybot-token-signing-secret";
      description = ''
        File holding the secret that signs sign-in tokens. Generate one with
        `openssl rand -base64 48`. Passed as a systemd credential, like
        {option}`services.shoddybot.secretKeyBaseFile`.
      '';
    };

    github = {
      clientId = mkOption {
        type = types.str;
        description = "Client ID of the GitHub OAuth app used for sign-in.";
      };

      clientSecretFile = mkOption {
        type = secretPath;
        example = "/run/secrets/shoddybot-github-client-secret";
        description = ''
          File holding the client secret of the GitHub OAuth app. Passed as a
          systemd credential.
        '';
      };

      redirectUri = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = ''
          Base URL of the auth routes registered with the GitHub OAuth app.
          `null` uses `https://<host>/auth`.
        '';
      };
    };

    mailFrom = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "shoddybot@example.com";
      description = "Sender address for sign-in emails. `null` uses `noreply@<host>`.";
    };

    environmentFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      example = "/run/secrets/shoddybot.env";
      description = ''
        Optional file of `NAME=value` lines added to the service environment.
        Use it for secrets such as a `DATABASE_URL` that holds a password.
      '';
    };

    environment = mkOption {
      type = types.attrsOf types.str;
      default = { };
      example = {
        ECTO_IPV6 = "true";
      };
      description = ''
        Extra environment variables for the server. They end up in the Nix
        store, so do not put secrets here; use
        {option}`services.shoddybot.environmentFile` instead.
      '';
    };

    database = {
      createLocally = mkOption {
        type = types.bool;
        default = true;
        description = ''
          Whether to run PostgreSQL on this machine and create the database
          and role for ShoddyBot. The server connects over the Unix socket
          with peer authentication, so no password is needed.
        '';
      };

      name = mkOption {
        type = types.str;
        default = "shoddybot";
        description = "Name of the PostgreSQL database.";
      };

      user = mkOption {
        type = types.str;
        default = "shoddybot";
        description = ''
          PostgreSQL role and system user the server runs as. With
          {option}`services.shoddybot.database.createLocally`, the role owns
          the database.
        '';
      };

      url = mkOption {
        type = types.nullOr types.str;
        default = if cfg.database.createLocally then localDatabaseUrl else null;
        defaultText = literalExpression ''
          if config.services.shoddybot.database.createLocally
          then "ecto://''${user}@localhost/''${name}?socket_dir=/run/postgresql"
          else null
        '';
        description = ''
          Ecto URL of the database. Set it to `null` and put `DATABASE_URL`
          in {option}`services.shoddybot.environmentFile` when the URL holds
          a password.
        '';
      };

      poolSize = mkOption {
        type = types.ints.positive;
        default = 10;
        description = "Number of database connections in the pool.";
      };
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.database.url != null || cfg.environmentFile != null;
        message = "services.shoddybot needs database.url, or a DATABASE_URL in environmentFile.";
      }
      {
        assertion =
          cfg.database.createLocally -> lib.versionAtLeast config.services.postgresql.package.version "18";
        message = "services.shoddybot needs PostgreSQL 18 or later. Set services.postgresql.package = pkgs.postgresql_18 (migrate any existing cluster first).";
      }
    ];

    users.users.${cfg.database.user} = {
      isSystemUser = true;
      group = cfg.database.user;
      description = "ShoddyBot server";
    };
    users.groups.${cfg.database.user} = { };

    services.postgresql = mkIf cfg.database.createLocally {
      enable = true;
      ensureDatabases = [ cfg.database.name ];
      ensureUsers = [
        {
          name = cfg.database.user;
          ensureDBOwnership = true;
        }
      ];
    };

    networking.firewall.allowedTCPPorts = optional cfg.openFirewall cfg.port;

    systemd.services.shoddybot = {
      description = "ShoddyBot server";
      wantedBy = [ "multi-user.target" ];
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ] ++ optional cfg.database.createLocally "postgresql.target";
      requires = optional cfg.database.createLocally "postgresql.target";

      inherit environment;

      serviceConfig = {
        Type = "exec";
        User = cfg.database.user;
        Group = cfg.database.user;
        ExecStartPre = "${withSecrets} ${cfg.package}/bin/migrate";
        ExecStart = "${withSecrets} ${cfg.package}/bin/server";
        ExecStop = "${withSecrets} ${cfg.package}/bin/shoddy_bot stop";
        EnvironmentFile = mkIf (cfg.environmentFile != null) cfg.environmentFile;
        LoadCredential = [
          "secret_key_base:${cfg.secretKeyBaseFile}"
          "token_signing_secret:${cfg.tokenSigningSecretFile}"
          "github_client_secret:${cfg.github.clientSecretFile}"
        ];
        Restart = "on-failure";
        RestartSec = 5;

        StateDirectory = "shoddybot";
        StateDirectoryMode = "0750";
        RuntimeDirectory = "shoddybot";
        RuntimeDirectoryMode = "0750";
        WorkingDirectory = "/var/lib/shoddybot";

        # Hardening. The BEAM JIT needs writable and executable memory, so
        # MemoryDenyWriteExecute stays off.
        CapabilityBoundingSet = "";
        DevicePolicy = "closed";
        LockPersonality = true;
        NoNewPrivileges = true;
        PrivateDevices = true;
        PrivateTmp = true;
        PrivateUsers = true;
        ProtectClock = true;
        ProtectControlGroups = true;
        ProtectHome = true;
        ProtectHostname = true;
        ProtectKernelLogs = true;
        ProtectKernelModules = true;
        ProtectKernelTunables = true;
        ProtectProc = "invisible";
        ProcSubset = "pid";
        ProtectSystem = "strict";
        RemoveIPC = true;
        RestrictAddressFamilies = [
          "AF_INET"
          "AF_INET6"
          "AF_UNIX"
        ];
        RestrictNamespaces = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        SystemCallArchitectures = "native";
        SystemCallFilter = [
          "@system-service"
          "~@privileged"
        ];
        UMask = "0077";
      };
    };
  };
}
