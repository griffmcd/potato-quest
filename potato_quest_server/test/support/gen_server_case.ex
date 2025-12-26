defmodule PotatoQuestServer.GenServerCase do
  @moduledoc """
  This module defines the test case for GenServer tests.
  Provides utilities for testing Registry-based GenServers.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      import PotatoQuestServer.GenServerCase
    end
  end

  @doc """
  Wait for a GenServer to reach a specific state condition.
  Useful for async operations.
  """
  def wait_until(fun, timeout \\ 1000) do
    wait_until(fun, timeout, System.monotonic_time(:millisecond))
  end

  defp wait_until(fun, timeout, start_time) do
    case fun.() do
      true ->
        :ok

      false ->
        current_time = System.monotonic_time(:millisecond)

        if current_time - start_time > timeout do
          {:error, :timeout}
        else
          Process.sleep(10)
          wait_until(fun, timeout, start_time)
        end
    end
  end

  @doc """
  Get the current state of a GenServer for assertions.
  """
  def get_genserver_state(pid) do
    :sys.get_state(pid)
  end
end
