defmodule EctoSpect.TelemetryHandlerTest do
  use ExUnit.Case, async: true

  alias EctoSpect.TelemetryHandler

  @fake_event [:ecto_spect, :test_repo, :query]

  # Minimal fake repo module for telemetry event resolution
  defmodule FakeRepo do
    def config, do: [telemetry_prefix: [:ecto_spect, :test_repo]]
  end

  defp fake_config(opts \\ []) do
    %EctoSpect.Config{
      repos: [__MODULE__.FakeRepo],
      filter_parameters: Keyword.get(opts, :filter_parameters, [])
    }
  end

  describe "handle_event/4" do
    test "does not record when ecto_spect_active is false" do
      case EctoSpect.QueryStore.start_link() do
        {:ok, _} -> :ok
        {:error, {:already_started, _}} -> :ok
      end

      pid = self()
      EctoSpect.QueryStore.register(pid)
      # Do NOT set :ecto_spect_active

      TelemetryHandler.handle_event(
        @fake_event,
        %{total_time: 1000},
        %{
          query: "SELECT 1",
          params: [],
          cast_params: [],
          source: "test",
          stacktrace: [],
          repo: FakeRepo
        },
        []
      )

      assert EctoSpect.QueryStore.take_for(pid) == []
    end

    test "records entry when ecto_spect_active is true" do
      case EctoSpect.QueryStore.start_link() do
        {:ok, _} -> :ok
        {:error, {:already_started, _}} -> :ok
      end

      pid = self()
      EctoSpect.QueryStore.register(pid)
      Process.put(:ecto_spect_active, true)

      TelemetryHandler.handle_event(
        @fake_event,
        %{total_time: 5_000_000},
        %{
          query: "SELECT 1",
          params: [1],
          cast_params: [],
          source: "users",
          stacktrace: nil,
          repo: FakeRepo
        },
        []
      )

      entries = EctoSpect.QueryStore.take_for(pid)
      assert length(entries) == 1
      assert hd(entries).sql == "SELECT 1"
      assert hd(entries).source == "users"
      assert hd(entries).total_time_us != nil
    after
      Process.delete(:ecto_spect_active)
    end

    test "redacts filtered cast_params keys" do
      case EctoSpect.QueryStore.start_link() do
        {:ok, _} -> :ok
        {:error, {:already_started, _}} -> :ok
      end

      pid = self()
      EctoSpect.QueryStore.register(pid)
      Process.put(:ecto_spect_active, true)

      TelemetryHandler.handle_event(
        @fake_event,
        %{total_time: nil},
        %{
          query: "SELECT 1",
          params: [],
          cast_params: [{"password", "secret123"}, {"email", "user@example.com"}],
          source: "users",
          stacktrace: nil,
          repo: FakeRepo
        },
        [:password]
      )

      entries = EctoSpect.QueryStore.take_for(pid)
      cast = hd(entries).cast_params
      assert {"password", "[FILTERED]"} in cast
      assert {"email", "user@example.com"} in cast
    after
      Process.delete(:ecto_spect_active)
    end
  end

  describe "attach/1 and detach/1" do
    test "attach returns :ok and detach cleans up" do
      config = fake_config()
      assert :ok = TelemetryHandler.attach(config)
      assert :ok = TelemetryHandler.detach(config)
    end

    test "attach is idempotent (already_exists is silently handled)" do
      config = fake_config()
      TelemetryHandler.attach(config)
      # Second attach should not crash
      assert :ok = TelemetryHandler.attach(config)
      TelemetryHandler.detach(config)
    end
  end
end
