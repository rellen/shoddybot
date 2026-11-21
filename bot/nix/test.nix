# NixOS VM test for services.shoddybot: the service starts against a local
# PostgreSQL, runs its migrations and serves the home page.
{ self }:
{
  name = "shoddybot";

  nodes.machine =
    { pkgs, ... }:
    {
      imports = [ self.nixosModules.shoddybot ];

      virtualisation.memorySize = 2048;
      environment.systemPackages = [ pkgs.curl ];

      # Test-only secrets. Real deployments keep these out of the Nix store,
      # for example with sops-nix or agenix.
      environment.etc = {
        "shoddybot/secret-key-base".text =
          "test-secret-key-base-0123456789abcdef0123456789abcdef0123456789abcdef";
        "shoddybot/token-signing-secret".text = "test-token-signing-secret-0123456789abcdef";
        "shoddybot/github-client-secret".text = "test-github-client-secret";
      };

      services.postgresql.package = pkgs.postgresql_18;

      services.shoddybot = {
        enable = true;
        host = "localhost";
        secretKeyBaseFile = "/etc/shoddybot/secret-key-base";
        tokenSigningSecretFile = "/etc/shoddybot/token-signing-secret";
        github = {
          clientId = "test-github-client-id";
          clientSecretFile = "/etc/shoddybot/github-client-secret";
        };
      };
    };

  testScript = ''
    machine.wait_for_unit("shoddybot.service")
    machine.wait_for_open_port(4000)
    machine.succeed("curl --fail --silent http://localhost:4000/ | grep -i '<html'")
    machine.succeed(
      "sudo -u postgres psql -d shoddybot -tAc 'SELECT count(*) FROM schema_migrations' | grep -qv '^0$'"
    )
  '';
}
