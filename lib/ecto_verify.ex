defmodule EctoVerify do
  @moduledoc """
  EctoVerify analyzes PostgreSQL query plans during ExUnit tests and fails tests
  when bad patterns are detected.

  ## Setup

  In `test_helper.exs`, call `EctoVerify.setup/1` **before** `ExUnit.start/0`:

      EctoVerify.setup(
        repos: [MyApp.Repo],
        thresholds: [seq_scan_min_rows: 100, n_plus_one: 5, max_indexes: 10],
        ignore_rules: [EctoVerify.Rules.MissingLimit]
      )
      ExUnit.start()

  Then in test modules, add `use EctoVerify.Case`:

      defmodule MyApp.AccountsTest do
        use ExUnit.Case, async: true
        use EctoVerify.Case, repo: MyApp.Repo

        test "lists active users" do
          # After the test body, EctoVerify runs EXPLAIN on each captured query
          # and fails the test if rule violations are found.
        end
      end

  ## Options

  - `:repos` — (required) list of `Ecto.Repo` modules to monitor
  - `:rules` — `:all` (default) or a list of rule modules
  - `:ignore_rules` — rule modules to exclude
  - `:thresholds` — keyword list of threshold overrides:
    - `:seq_scan_min_rows` (default: 100) — min rows for seq scan to be flagged
    - `:n_plus_one` (default: 5) — min repeat count for N+1 detection
    - `:max_indexes` (default: 10) — max indexes before write-slowness warning
    - `:index_filter_ratio` (default: 10) — ratio of removed/returned rows to flag
  - `:output` — `:ansi` (default), `:plain`, or `:silent`

  ## Dev-mode SQL Comments

  Add caller info as SQL comments in dev/test by adding to your `Repo`:

      if Mix.env() in [:dev, :test] do
        @impl true
        def default_options(_op), do: [stacktrace: true]

        @impl true
        def prepare_query(_op, query, opts) do
          comment = EctoVerify.SqlAnnotator.build_comment(opts)
          {query, [comment: comment, prepare: :unnamed] ++ opts}
        end
      end
  """

  @doc """
  Set up EctoVerify. Call before `ExUnit.start()` in `test_helper.exs`.
  """
  @spec setup(keyword()) :: :ok
  def setup(opts) do
    config = EctoVerify.Config.new(opts)
    EctoVerify.Config.store(config)

    {:ok, _} = EctoVerify.QueryStore.start_link()

    # ETS table for atomic "run schema checks only once" guard across async modules
    if :ets.info(:ecto_verify_schema_run) == :undefined do
      :ets.new(:ecto_verify_schema_run, [:public, :named_table, :set])
    end

    EctoVerify.TelemetryHandler.attach(config)

    # Run migration AST checks (no DB connection needed — pure file analysis).
    migration_violations = EctoVerify.MigrationChecker.check(config)

    # Open a persistent suite-level connection for rules that need it
    # (setup_suite/1 and check_suite_end/2 lifecycle).
    suite_conn = open_suite_connection(config)

    if suite_conn do
      config.rules
      |> Enum.filter(&function_exported?(&1, :setup_suite, 1))
      |> Enum.each(& &1.setup_suite(suite_conn))
    end

    ExUnit.after_suite(fn _results ->
      # Report migration violations (collected at setup time, shown after suite)
      if migration_violations != [] do
        EctoVerify.Formatter.print_schema(migration_violations, config)
      end

      if suite_conn do
        suite_violations =
          config.rules
          |> Enum.filter(&function_exported?(&1, :check_suite_end, 2))
          |> Enum.flat_map(& &1.check_suite_end(suite_conn, config.thresholds))

        if suite_violations != [] do
          EctoVerify.Formatter.print_schema(suite_violations, config)
        end

        EctoVerify.ExplainRunner.close_connection(suite_conn)
      end

      EctoVerify.TelemetryHandler.detach(config)
    end)

    :ok
  end

  # Open one persistent Postgrex connection for the full suite lifecycle.
  # Only opened when at least one rule needs it.
  defp open_suite_connection(config) do
    needs_conn =
      Enum.any?(config.rules, fn rule ->
        function_exported?(rule, :setup_suite, 1) or
          function_exported?(rule, :check_suite_end, 2)
      end)

    if needs_conn do
      repo = hd(config.repos)

      case EctoVerify.ExplainRunner.open_connection(repo) do
        {:ok, conn} ->
          conn

        {:error, reason} ->
          require Logger

          Logger.warning(
            "[EctoVerify] Could not open suite connection: #{inspect(reason)}. " <>
              "Suite-level rules (UnusedIndexes) will be skipped."
          )

          nil
      end
    end
  end
end
