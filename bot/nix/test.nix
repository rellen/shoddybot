# NixOS VM test for services.shoddybot: the service starts against a local
# PostgreSQL, runs its migrations, generates its secrets on first boot and
# serves the home page, and root can be onboarded with shoddybot-eval.
{ self }:
{
  name = "shoddybot";

  nodes.machine =
    { pkgs, ... }:
    {
      imports = [ self.nixosModules.shoddybot ];

      virtualisation.memorySize = 2048;
      environment.systemPackages = [ pkgs.curl ];

      # Test-only master key. Real deployments keep it out of the Nix store,
      # for example with sops-nix or agenix.
      environment.etc."shoddybot/master-key".text = "dGVzdC1tYXN0ZXIta2V5LTAxMjM0NTY3ODlhYmNkZWY=";

      services.postgresql.package = pkgs.postgresql_18;

      services.shoddybot = {
        enable = true;
        masterKeyFile = "/etc/shoddybot/master-key";
      };
    };

  testScript = ''
    machine.wait_for_unit("shoddybot.service")
    machine.wait_for_open_port(4000)
    machine.succeed("curl --fail --silent http://localhost:4000/ | grep -i '<html'")
    machine.succeed(
      "sudo -u postgres psql -d shoddybot -tAc 'SELECT count(*) FROM schema_migrations' | grep -qv '^0$'"
    )

    # First boot generated and stored the secrets.
    machine.succeed(
      "sudo -u postgres psql -d shoddybot -tAc 'SELECT count(*) FROM instance_boot_secrets' | grep -q '^1$'"
    )

    # Onboard root without email, with distribution off.
    output = machine.succeed(
      "shoddybot-eval 'ShoddyBot.Release.create_root(\"root@example.com\", public_url: \"http://localhost:4000\")'"
    )
    assert "root@example.com is now root." in output, output
    link = next(line.strip() for line in output.splitlines() if "/magic_link/" in line)
    machine.succeed(f"curl --fail --silent '{link}' | grep -q 'Sign in to ShoddyBot'")
  '';
}
