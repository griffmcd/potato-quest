defmodule PotatoQuestServerWeb.Router do
  use PotatoQuestServerWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/api", PotatoQuestServerWeb do
    pipe_through :api
  end
end
