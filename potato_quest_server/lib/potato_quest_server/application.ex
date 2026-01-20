defmodule PotatoQuestServer.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      PotatoQuestServerWeb.Telemetry,
      PotatoQuestServer.Repo,
      {DNSCluster, query: Application.get_env(:potato_quest_server, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: PotatoQuestServer.PubSub},
      # Presence tracking for multiplayer
      PotatoQuestServerWeb.Presence,
      # Game-specific registries and supervisors
      {Registry, keys: :unique, name: PotatoQuestServer.Game.PlayerRegistry},
      {Registry, keys: :unique, name: PotatoQuestServer.Game.ZoneRegistry},
      {DynamicSupervisor, strategy: :one_for_one, name: PotatoQuestServer.Game.PlayerSupervisor},
      {DynamicSupervisor, strategy: :one_for_one, name: PotatoQuestServer.Game.ZoneSupervisor},
      # Start the spawn town zone
      {PotatoQuestServer.Game.ZoneServer, zone_id: "spawn_town", zone_type: "town_square"},
      # Start to serve requests, typically the last entry
      PotatoQuestServerWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: PotatoQuestServer.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    PotatoQuestServerWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
