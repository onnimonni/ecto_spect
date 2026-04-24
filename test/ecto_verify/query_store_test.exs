defmodule EctoVerify.QueryStoreTest do
  use ExUnit.Case, async: true

  alias EctoVerify.QueryStore

  setup do
    # Each test gets its own isolated PID-keyed entries.
    # QueryStore is a named Agent started by EctoVerify.setup/1 — start it
    # only if not already running (test_helper may have started it).
    case QueryStore.start_link() do
      {:ok, _} -> :ok
      {:error, {:already_started, _}} -> :ok
    end

    :ok
  end

  describe "register/1 and take_for/1" do
    test "register creates empty slot for pid" do
      pid = self()
      QueryStore.register(pid)
      assert QueryStore.take_for(pid) == []
    end

    test "take_for returns empty list for unknown pid" do
      assert QueryStore.take_for(self()) == []
    end

    test "take_for removes entries (idempotent second call)" do
      pid = self()
      QueryStore.register(pid)
      QueryStore.record(%{sql: "SELECT 1", params: []})
      assert length(QueryStore.take_for(pid)) == 1
      assert QueryStore.take_for(pid) == []
    end
  end

  describe "record/1" do
    test "records entry for current test pid" do
      pid = self()
      QueryStore.register(pid)
      entry = %{sql: "SELECT 1", params: [], cast_params: []}
      QueryStore.record(entry)
      assert QueryStore.take_for(pid) == [entry]
    end

    test "records multiple entries in capture order (oldest first)" do
      pid = self()
      QueryStore.register(pid)
      QueryStore.record(%{sql: "SELECT 1"})
      QueryStore.record(%{sql: "SELECT 2"})
      QueryStore.record(%{sql: "SELECT 3"})
      sqls = QueryStore.take_for(pid) |> Enum.map(& &1.sql)
      assert sqls == ["SELECT 1", "SELECT 2", "SELECT 3"]
    end

    test "ignores entry when pid not registered" do
      # Record without registering — should not crash
      unregistered = spawn(fn -> :ok end)
      # Simulate recording from a different process that falls back to self()
      # but self() was not registered (we consumed or never registered it)
      QueryStore.take_for(unregistered)
      QueryStore.record(%{sql: "SELECT 1"})
      # The record goes to self() bucket; unregistered is clean
      assert QueryStore.take_for(unregistered) == []
    end
  end

  describe "resolve_test_pid/0" do
    test "returns self() when no callers" do
      assert QueryStore.resolve_test_pid() == self()
    end

    test "returns last caller when callers present" do
      parent = self()
      fake_caller = spawn(fn -> :ok end)

      task =
        Task.async(fn ->
          # Simulate ExUnit's $callers injection
          Process.put(:"$callers", [fake_caller, parent])
          QueryStore.resolve_test_pid()
        end)

      result = Task.await(task)
      # Last in list is the root test pid
      assert result == parent
    end
  end
end
