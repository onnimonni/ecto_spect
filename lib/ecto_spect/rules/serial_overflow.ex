defmodule EctoSpect.Rules.SerialOverflow do
  @moduledoc """
  Detects sequences approaching integer overflow.

  PostgreSQL SERIAL and INTEGER GENERATED AS IDENTITY columns use 4-byte integer
  sequences with a maximum of 2,147,483,647. When this limit is reached, INSERT
  statements start failing with:
    `ERROR: nextval: reached maximum value of sequence "..."`

  This is a silent production disaster — there is no warning before the sequence
  exhausts. Tables with high INSERT rates can hit this limit in months or years.

  This rule flags sequences that have consumed >80% of their maximum value.

  Schema-level check: runs once per test suite, not per test.
  """

  @behaviour EctoSpect.Rule

  @int4_max 2_147_483_647
  @int2_max 32_767

  @sql """
  SELECT
    sequencename,
    schemaname,
    last_value,
    max_value,
    ROUND(100.0 * last_value / NULLIF(max_value, 0), 1) AS pct_used
  FROM pg_sequences
  WHERE schemaname = 'public'
    AND last_value IS NOT NULL
    AND last_value > max_value * 0.8
  ORDER BY pct_used DESC
  """

  @impl true
  def name, do: "serial-overflow"

  @impl true
  def description, do: "Detects sequences >80% full — approaching integer overflow"

  @impl true
  def check(_nodes, _entry, _thresholds), do: []

  @impl true
  def check_schema(conn, _thresholds) do
    case Postgrex.query(conn, @sql, []) do
      {:ok, %{rows: rows}} ->
        Enum.map(rows, fn [seq_name, schema, last_value, max_value, pct_used] ->
          type =
            cond do
              max_value == @int2_max -> "SMALLINT"
              max_value == @int4_max -> "INTEGER (SERIAL)"
              true -> "BIGINT"
            end

          %EctoSpect.Violation{
            rule: __MODULE__,
            severity: :error,
            message:
              "Sequence `#{schema}.#{seq_name}` is #{pct_used}% full " <>
                "(#{last_value}/#{max_value}, type: #{type})",
            advice: """
            This sequence is approaching its maximum value. When it exhausts, all
            INSERTs to the table will fail with a nextval error — no graceful degradation.

            Immediate fix — widen the sequence to BIGINT:
              ALTER SEQUENCE #{schema}.#{seq_name} AS BIGINT MAXVALUE 9223372036854775807;
              -- Also widen the column:
              ALTER TABLE <table> ALTER COLUMN <id_col> TYPE BIGINT;

            For new tables, always use BIGSERIAL or BIGINT identity:
              # In Ecto migrations:
              create table(:events, primary_key: false) do
                add :id, :bigserial, primary_key: true
              end
              # Or with generated identity:
              add :id, :bigint, primary_key: true, generated: :always

            Check when it will run out:
              SELECT last_value, max_value - last_value AS remaining
              FROM pg_sequences
              WHERE sequencename = '#{seq_name}';
            """,
            entry: %{sql: "(schema check)", source: seq_name, params: [], stacktrace: nil},
            details: %{
              sequence: seq_name,
              schema: schema,
              last_value: last_value,
              max_value: max_value,
              pct_used: pct_used,
              type: type
            }
          }
        end)

      {:error, reason} ->
        require Logger
        Logger.debug("[EctoSpect] SerialOverflow schema check failed: #{inspect(reason)}")
        []
    end
  end
end
