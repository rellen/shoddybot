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
    PORT = toString cfg.port;
    POOL_SIZE = toString cfg.database.poolSize;
    # The release writes its generated runtime configuration here. The
    # default, inside the release, is the read-only Nix store.
    RELEASE_TMP = "/run/shoddybot";
    # A single node: no Erlang distribution, so no epmd or distribution port
    # is opened. Override in `environment` to attach remote shells.
    RELEASE_DISTRIBUTION = "none";
    LANG = "C.UTF-8";
  }
  // lib.optionalAttrs (cfg.database.url != null) { DATABASE_URL = cfg.database.url; }
  // cfg.environment;

  # Reads the master key from its systemd credential into the environment the
  # release expects, then runs the given release command.
  withSecrets = pkgs.writeShellScript "shoddybot-with-secrets" ''
    set -euo pipefail
    SHODDYBOT_MASTER_KEY="$(< "$CREDENTIALS_DIRECTORY/master_key")"
    export SHODDYBOT_MASTER_KEY
    exec "$@"
  '';

  # `shoddybot-eval EXPR` runs an Elixir expression with
  # `bin/shoddy_bot eval`, as the service user, with the service's
  # environment and master key, in a transient systemd unit. Erlang
  # distribution is off, so `rpc` cannot reach the running server; `eval`
  # starts only what the expression needs. Used to onboard root.
  evalEnvironment = environment // {
    RELEASE_TMP = "/run/shoddybot-eval";
  };

  shoddybotEval = pkgs.writeShellScriptBin "shoddybot-eval" ''
    set -euo pipefail
    if [ "$#" -ne 1 ]; then
      echo "usage: shoddybot-eval 'ShoddyBot.Release.create_root(\"you@example.com\", public_url: \"https://shoddybot.example.com\")'" >&2
      exit 64
    fi
    exec ${config.systemd.package}/bin/systemd-run --quiet --wait --pipe --collect \
      --uid=${cfg.database.user} --gid=${cfg.database.user} \
      --property=LoadCredential=master_key:${cfg.masterKeyFile} \
      --property=RuntimeDirectory=shoddybot-eval \
      --property=WorkingDirectory=/var/lib/shoddybot \
      ${
        lib.optionalString (cfg.environmentFile != null) "--property=EnvironmentFile=${cfg.environmentFile}"
      } \
      ${
        lib.concatStringsSep " " (
          lib.mapAttrsToList (name: value: lib.escapeShellArg "--setenv=${name}=${value}") evalEnvironment
        )
      } \
      -- ${withSecrets} ${cfg.package}/bin/shoddy_bot eval "$1"
  '';
in
{
  # These moved into the database, where root manages them in the admin pages.
  imports =
    map
      (
        path:
        lib.mkRemovedOptionModule
          (
            [
              "services"
              "shoddybot"
            ]
            ++ path
          )
          ''
            ShoddyBot now keeps this in its database: sign in as root and set it in the
            admin pages. The service only needs services.shoddybot.masterKeyFile.
          ''
      )
      [
        [ "host" ]
        [ "secretKeyBaseFile" ]
        [ "tokenSigningSecretFile" ]
        [
          "github"
          "clientId"
        ]
        [
          "github"
          "clientSecretFile"
        ]
        [
          "github"
          "redirectUri"
        ]
        [ "mailFrom" ]
      ];

  options.services.shoddybot = {
    enable = mkEnableOption "the ShoddyBot server";

    package = mkOption {
      type = types.package;
      default = self.packages.${pkgs.stdenv.hostPlatform.system}.shoddybot;
      defaultText = literalExpression "shoddybot.packages.\${pkgs.stdenv.hostPlatform.system}.shoddybot";
      description = "The ShoddyBot release to run.";
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

    masterKeyFile = mkOption {
      type = secretPath;
      example = "/run/secrets/shoddybot-master-key";
      description = ''
        File holding the master key: 32 random bytes, Base64-encoded, from
        `openssl rand -base64 32`. It encrypts every secret ShoddyBot stores
        in its database, including the ones it generates on first boot, so
        back it up apart from the database: without it they cannot be read.
        It is passed to the service as a systemd credential, so it can be
        readable by root only, and it never enters the Nix store.

        Everything else (the public URL, mail, GitHub sign-in, tenants) is
        configured by root in the admin pages. Onboard root with
        `shoddybot-eval`, which this module installs:

            shoddybot-eval 'ShoddyBot.Release.create_root("you@example.com", public_url: "https://shoddybot.example.com")'
      '';
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

    environment.systemPackages = [ shoddybotEval ];

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
        LoadCredential = [ "master_key:${cfg.masterKeyFile}" ];
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
