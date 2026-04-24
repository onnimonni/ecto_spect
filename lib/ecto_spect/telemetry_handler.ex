defmodule EctoSpect.TelemetryHandler do
  @moduledoc """
  Attaches to Ecto telemetry events and captures queries into `EctoSpect.QueryStore`.

  One handler is attached per configured Repo. The handler runs synchronously
  in the process that executed the Ecto query, so `$callers` correctly resolves
  the owning test process even with `async: true` tests.
  """

  require Logger

  @doc "Attach telemetry handlers for all configured repos."
  @spec attach(EctoSpect.Config.t()) :: :ok
  def attach(%EctoSpect.Config{repos: repos} = config) do
    Enum.each(repos, fn repo ->
      event = telemetry_event(repo)
      handler_id = handler_id(repo)

      case :telemetry.attach(handler_id, event, &handle_event/4, config.filter_parameters) do
        :ok ->
          :ok

        {:error, :already_exists} ->
          Logger.debug("[EctoSpect] Handler #{handler_id} already attached, skipping")
      end
    end)

    :ok
  end

  @doc "Detach all handlers attached by EctoSpect."
  @spec detach(EctoSpect.Config.t()) :: :ok
  def detach(%EctoSpect.Config{repos: repos}) do
    Enum.each(repos, fn repo ->
      :telemetry.detach(handler_id(repo))
    end)

    :ok
  end

  @doc false
  def handle_event(_event_name, measurements, metadata, filter_parameters) do
    sql = metadata.query

    # Only capture when a test is marked as active (set by EctoSpect.Case setup).
    # Skip transaction control statements (BEGIN/COMMIT/ROLLBACK/SAVEPOINT) — they
    # are not user queries and cannot be EXPLAINed.
    if Process.get(:ecto_spect_active, false) and not transaction_control?(sql) do
      entry = %{
        sql: sql,
        params: metadata.params || [],
        cast_params: filter_cast_params(metadata.cast_params || [], filter_parameters || []),
        source: metadata.source,
        stacktrace: metadata.stacktrace,
        repo: metadata.repo,
        total_time_us: to_microseconds(measurements[:total_time])
      }

      EctoSpect.QueryStore.record(entry)
    end
  end

  @transaction_control ~w(begin commit rollback savepoint release)
  defp transaction_control?(sql) when is_binary(sql) do
    downcased = sql |> String.trim() |> String.downcase()
    Enum.any?(@transaction_control, &String.starts_with?(downcased, &1))
  end

  defp transaction_control?(_), do: false

  # Redact sensitive cast_params values based on key name.
  defp filter_cast_params(cast_params, []), do: cast_params

  defp filter_cast_params(cast_params, filter_parameters) when is_list(cast_params) do
    filter_set = MapSet.new(filter_parameters, &to_string/1)

    Enum.map(cast_params, fn
      {k, v} when is_binary(k) ->
        if MapSet.member?(filter_set, k), do: {k, "[FILTERED]"}, else: {k, v}

      other ->
        other
    end)
  end

  defp filter_cast_params(cast_params, _), do: cast_params

  # Build the telemetry event name for a repo.
  # Ecto uses `telemetry_prefix ++ [:query]`. The prefix defaults to
  # `[:my_app, :repo]` derived from the repo module name.
  defp telemetry_event(repo) do
    prefix =
      if function_exported?(repo, :config, 0) do
        repo.config()[:telemetry_prefix] || default_prefix(repo)
      else
        default_prefix(repo)
      end

    prefix ++ [:query]
  end

  defp default_prefix(repo) do
    repo
    |> Module.split()
    |> Enum.map(&(&1 |> Macro.underscore() |> String.to_existing_atom()))
  end

  defp handler_id(repo), do: "ecto_spect_#{inspect(repo)}"

  defp to_microseconds(nil), do: nil
  defp to_microseconds(native), do: System.convert_time_unit(native, :native, :microsecond)
end
