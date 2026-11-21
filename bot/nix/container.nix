# OCI image of the ShoddyBot server, for Docker, Podman and similar.
#
#   nix build .#container
#   docker load < result
#   docker run --rm -p 4000:4000 \
#     -e DATABASE_URL=ecto://user:pass@db/shoddybot \
#     -e SHODDYBOT_MASTER_KEY=... \
#     shoddybot:<version>
#
# Generate the master key once with `openssl rand -base64 32` and keep it.
# The entrypoint runs pending migrations, then starts the server. The release
# commands are on PATH, so root is onboarded with
# `docker exec <container> shoddy_bot eval 'ShoddyBot.Release.create_root(...)'`;
# see bot/README.md.
{
  lib,
  dockerTools,
  writeShellApplication,
  runCommand,
  cacert,
  shoddybot,
}:

let
  # Puts the release command on PATH as `shoddy_bot`, for `docker exec`. The
  # script resolves the symlink to find the release.
  releaseCommands = runCommand "shoddybot-commands" { } ''
    mkdir -p $out/bin
    ln -s ${lib.getBin shoddybot}/bin/shoddy_bot $out/bin/shoddy_bot
  '';

  entrypoint = writeShellApplication {
    name = "shoddybot-entrypoint";
    text = ''
      ${lib.getBin shoddybot}/bin/migrate
      exec ${lib.getBin shoddybot}/bin/server
    '';
  };
in
dockerTools.buildLayeredImage {
  name = "shoddybot";
  tag = shoddybot.version;

  contents = [
    dockerTools.fakeNss
    releaseCommands
  ];

  # The release writes its generated runtime configuration to RELEASE_TMP,
  # and the Nix store is read-only, so give it a writable /tmp.
  extraCommands = ''
    mkdir -m 1777 tmp
  '';

  config = {
    Entrypoint = [ (lib.getExe entrypoint) ];
    User = "nobody:nogroup";
    ExposedPorts."4000/tcp" = { };
    Env = [
      "LANG=C.UTF-8"
      "PORT=4000"
      "RELEASE_TMP=/tmp"
      # A single node: no Erlang distribution, so no epmd or distribution
      # port is opened in the container.
      "RELEASE_DISTRIBUTION=none"
      "SSL_CERT_FILE=${cacert}/etc/ssl/certs/ca-bundle.crt"
    ];
    Labels = {
      "org.opencontainers.image.source" = "https://github.com/rellen/shoddybot";
      "org.opencontainers.image.licenses" = "Apache-2.0";
      "org.opencontainers.image.version" = shoddybot.version;
    };
  };
}
