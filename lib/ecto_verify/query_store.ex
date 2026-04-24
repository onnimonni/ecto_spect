defmodule EctoVerify.QueryStore do
  @moduledoc """
  Agent that accumulates captured Ecto queries per test process.

  Keyed by test PID. Uses `$callers` process dictionary to correctly
  attribute queries from spawned Tasks back to their owning test.
  Works correctly with `async: true` tests.
  """

  use Agent

  @spec start_link(keyword()) :: Agent.on_start()
  def start_link(_opts \\ []) do
    Agent.start_link(fn -> %{} end, name: __MODULE__)
  end

  @doc """
  Record a captured query entry for the current test process.
  Resolves the test PID via `$callers` chain.
  """
  @spec record(map()) :: :ok
  def record(entry) do
    case resolve_test_pid() do
      nil ->
        :ok

      test_pid ->
        Agent.update(__MODULE__, fn state ->
          Map.update(state, test_pid, [entry], &[entry | &1])
        end)
    end
  end

  @doc """
  Take (remove and return) all entries captured for the given test PID.
  Returns entries in capture order (oldest first).
  """
  @spec take_for(pid()) :: [map()]
  def take_for(test_pid) do
    Agent.get_and_update(__MODULE__, fn state ->
      entries = state |> Map.get(test_pid, []) |> Enum.reverse()
      {entries, Map.delete(state, test_pid)}
    end)
  end

  @doc """
  Register a test PID explicitly (call at start of each test via setup).
  """
  @spec register(pid()) :: :ok
  def register(test_pid) do
    Agent.update(__MODULE__, fn state ->
      Map.put_new(state, test_pid, [])
    end)
  end

  # Walk $callers to find the root test process (set by ExUnit for async tests).
  # Falls back to self() if no callers are present.
  @spec resolve_test_pid() :: pid() | nil
  def resolve_test_pid do
    callers = Process.get(:"$callers", [])
    # Last caller in chain is the root test process
    List.last(callers) || self()
  end
end
