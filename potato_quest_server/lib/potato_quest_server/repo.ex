defmodule PotatoQuestServer.Repo do
  use Ecto.Repo,
    otp_app: :potato_quest_server,
    adapter: Ecto.Adapters.Postgres
end
