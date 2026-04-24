defmodule EctoSpect.Rules.MissingFkIndex do
  @compile {:no_warn_undefined, Postgrex}

  @moduledoc """
  Detects foreign key columns that have no supporting index.

  PostgreSQL does NOT automatically create indexes on foreign key columns
  (unlike MySQL). Without an index on the FK column:
  - JOIN queries scan the entire referencing table — O(N) instead of O(log N)
  - CASCADE DELETE operations scan the entire referencing table per deleted row
  - `RESTRICT` / `NO ACTION` constraint checks are slow

  This is one of the most common performance mistakes on PostgreSQL, especially
  for teams migrating from MySQL.

  Example: `orders.user_id` references `users.id`. Without an index on
  `orders.user_id`, every `JOIN orders ON orders.user_id = users.id` does a
  full sequential scan of `orders`.
  """

  @behaviour EctoSpect.Rule

  # Finds FK columns (single-column FKs only) with no index covering that column.
  @sql """
  SELECT
    conrelid::regclass::text AS table_name,
    a.attname AS column_name,
    confrelid::regclass::text AS references_table
  FROM pg_constraint c
  JOIN pg_attribute a
    ON a.attrelid = c.conrelid
    AND a.attnum = c.conkey[1]
  WHERE c.contype = 'f'
    AND c.connamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'public')
    AND array_length(c.conkey, 1) = 1
    AND NOT EXISTS (
      SELECT 1
      FROM pg_index i
      WHERE i.indrelid = c.conrelid
        AND c.conkey[1] = ANY(i.indkey)
    )
  ORDER BY table_name, column_name
  """

  @impl true
  def name, do: "missing-fk-index"

  @impl true
  def description,
    do: "Detects FK columns without a supporting index (PostgreSQL doesn't auto-create them)"

  @impl true
  def check(_nodes, _entry, _thresholds), do: []

  @impl true
  def check_schema(conn, _thresholds) do
    case Postgrex.query(conn, @sql, []) do
      {:ok, %{rows: rows}} ->
        Enum.map(rows, fn [table, column, ref_table] ->
          %EctoSpect.Violation{
            rule: __MODULE__,
            severity: :error,
            message: "`#{table}.#{column}` is a FK referencing `#{ref_table}` but has no index",
            advice: """
            PostgreSQL does not auto-create indexes on foreign key columns (unlike MySQL).
            Without this index, JOINs and CASCADE operations do full table scans.

            Fix:
              CREATE INDEX CONCURRENTLY idx_#{table}_#{column}
                ON #{table}(#{column});

            In an Ecto migration:
              create index(:#{table}, [:#{column}])

            Or with concurrent creation (safe for production):
              create index(:#{table}, [:#{column}], concurrently: true)
            """,
            entry: %{sql: "(schema check)", source: table, params: [], stacktrace: nil},
            details: %{table: table, column: column, references_table: ref_table}
          }
        end)

      {:error, reason} ->
        require Logger
        Logger.debug("[EctoSpect] MissingFkIndex check failed: #{inspect(reason)}")
        []
    end
  end
end
