defmodule EctoVerify.Rules.OffsetPagination do
  @moduledoc """
  Warns when OFFSET-based pagination is used.

  `OFFSET N` forces PostgreSQL to read and discard the first N rows before
  returning results. At page 1 this is fast; at page 1000 (OFFSET 10000)
  PostgreSQL reads 10,000 rows to throw them away. Performance degrades
  linearly with page number.

  Cursor-based (keyset) pagination — `WHERE id > last_seen_id` — is O(1)
  regardless of how deep into the result set you are.

  This rule fires whenever OFFSET appears in a SELECT query, regardless of the
  actual offset value (which is typically a parameter and unknown at plan time).
  """

  @behaviour EctoVerify.Rule

  @impl true
  def name, do: "offset-pagination"

  @impl true
  def description, do: "Warns on OFFSET-based pagination — degrades at scale"

  @impl true
  def check(_nodes, entry, _thresholds) do
    if select?(entry.sql) and has_offset?(entry.sql) do
      [
        %EctoVerify.Violation{
          rule: __MODULE__,
          severity: :warning,
          message: "OFFSET pagination degrades linearly — page 1000 reads 10K+ rows to discard",
          advice: """
          Use cursor-based (keyset) pagination instead of OFFSET.

          Instead of:
            from(q in Query, limit: ^limit, offset: ^offset)

          Use:
            from(q in Query, where: q.id > ^last_id, order_by: q.id, limit: ^limit)

          Store the last seen `id` (or any ordered unique column) and use it as
          the cursor for the next page. Performance stays constant regardless of
          page depth.

          If you need random page access (not just next/prev), OFFSET may be
          acceptable — add `ignore_rules: [EctoVerify.Rules.OffsetPagination]`
          to your EctoVerify.setup/1 call.
          """,
          entry: entry,
          details: %{}
        }
      ]
    else
      []
    end
  end

  defp select?(sql), do: Regex.match?(~r/\ASELECT/i, String.trim_leading(sql))
  defp has_offset?(sql), do: Regex.match?(~r/\bOFFSET\b/i, sql)
end
