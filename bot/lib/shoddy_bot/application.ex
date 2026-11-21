defmodule ShoddyBot.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      ShoddyBotWeb.Telemetry,
      ShoddyBot.Repo,
      ShoddyBot.Vault,
      # Loads (or on first boot, generates) secret_key_base and the token
      # signing secret, so it must start before the endpoint.
      ShoddyBot.Instance.Boot,
      {Phoenix.PubSub, name: ShoddyBot.PubSub},
      # Start a worker by calling: ShoddyBot.Worker.start_link(arg)
      # {ShoddyBot.Worker, arg},
      {AshAuthentication.Supervisor, [otp_app: :shoddy_bot]},
      # Start to serve requests, typically the last entry
      ShoddyBotWeb.Endpoint
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: ShoddyBot.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    ShoddyBotWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
