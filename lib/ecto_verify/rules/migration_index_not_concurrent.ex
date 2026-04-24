defmodule EctoVerify.Rules.MigrationIndexNotConcurrent do
  @moduledoc """
  Detects indexes created in migrations without `concurrently: true`.

  Creating an index without CONCURRENTLY acquires an exclusive lock on the table
  that blocks all reads AND writes for the duration of the index build. On large
  tables this can take minutes and cause full application downtime.

  `CREATE INDEX CONCURRENTLY` builds the index in the background without locking.
  It takes longer but is safe to run on live production tables.

  Note: concurrent index creation cannot run inside a transaction. Ecto migrations
  require disabling the DDL transaction:
      @disable_ddl_transaction true
      @disable_migration_lock true

  Migration-level check: runs once per test suite via AST analysis.
  """

  @behaviour EctoVerify.Rule

  @impl true
  def name, do: "migration-index-not-concurrent"

  @impl true
  def description,
    do: "Detects non-concurrent index creation in migrations — blocks reads and writes"

  @impl true
  def check(_nodes, _entry, _thresholds), do: []

  @impl true
  def check_migration(ast, _source, path) do
    {_, violations} =
      Macro.postwalk(ast, [], fn node, acc ->
        case node do
          # create index(:table, [:col]) — no options
          {:create, meta, [{:index, _, [_table, _cols]}]} ->
            v = build_violation(path, meta[:line])
            {node, [v | acc]}

          # create index(:table, [:col], opts) — options present but no concurrently: true
          {:create, meta, [{:index, _, [_table, _cols, opts]}]} when is_list(opts) ->
            if Keyword.get(opts, :concurrently, false) do
              {node, acc}
            else
              v = build_violation(path, meta[:line])
              {node, [v | acc]}
            end

          _ ->
            {node, acc}
        end
      end)

    Enum.reverse(violations)
  end

  defp build_violation(path, line) do
    location = format_location(path, line)

    %EctoVerify.Violation{
      rule: __MODULE__,
      severity: :error,
      message: "Index created without CONCURRENTLY at #{location}",
      advice: """
      Non-concurrent index creation holds an exclusive table lock blocking all reads
      and writes. On large tables this causes downtime.

      Fix — use concurrent index creation:
        # In your migration:
        @disable_ddl_transaction true
        @disable_migration_lock true

        def change do
          create index(:users, [:email], concurrently: true)
        end

      Both module attributes are required — CONCURRENTLY cannot run inside a
      transaction, and @disable_migration_lock prevents Ecto acquiring a lock
      for concurrent operations.
      """,
      entry: %{sql: "(migration check)", source: path, params: [], stacktrace: nil},
      details: %{path: path, line: line}
    }
  end

  defp format_location(path, nil), do: Path.basename(path)
  defp format_location(path, line), do: "#{Path.basename(path)}:#{line}"
end
