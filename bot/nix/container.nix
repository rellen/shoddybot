# OCI image of the ShoddyBot server, for Docker, Podman and similar.
#
#   nix build .#container
#   docker load < result
#   docker run --rm -p 4000:4000 \
#     -e DATABASE_URL=ecto://user:pass@db/shoddybot \
#     -e SECRET_KEY_BASE=... -e PHX_HOST=shoddybot.example.com \
#     shoddybot:<version>
#
# The entrypoint runs pending migrations, then starts the server.
{
  lib,
  dockerTools,
  writeShellApplication,
  cacert,
  shoddybot,
}:

let
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

  contents = [ dockerTools.fakeNss ];

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
