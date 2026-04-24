defmodule EctoVerify.Rules.SortSpillToDisk do
  @moduledoc """
  Detects Sort nodes that spilled to disk due to insufficient `work_mem`.

  When PostgreSQL cannot fit a sort operation in memory, it writes temporary
  files to disk ("external merge"). This is drastically slower than in-memory
  sorting and means either `work_mem` is too low or the result set is larger
  than expected.

  In EXPLAIN output, `"Sort Method": "external merge Disk: NkB"` on a Sort
  node indicates a disk spill. Contrast with `"quicksort"` (in-memory).

  Note: we already have `HashJoinSpill` for Hash node disk spills. This rule
  handles the Sort node equivalent.
  """

  @behaviour EctoVerify.Rule

  @impl true
  def name, do: "sort-spill-to-disk"

  @impl true
  def description, do: "Detects Sort nodes that spill to disk (external merge) — low work_mem"

  @impl true
  def check(nodes, entry, _thresholds) do
    nodes
    |> Enum.filter(fn node ->
      node.node_type == "Sort" and
        is_binary(node.sort_method) and
        String.contains?(node.sort_method, "external merge")
    end)
    |> Enum.map(fn node ->
      sort_cols =
        case node.sort_key do
          [_ | _] = keys -> Enum.join(keys, ", ")
          _ -> "unknown column(s)"
        end

      %EctoVerify.Violation{
        rule: __MODULE__,
        severity: :error,
        message: "Sort spilled to disk (#{node.sort_method}) on: #{sort_cols}",
        advice: """
        The sort exceeded work_mem and wrote temporary files to disk — very slow.

        Options:

        1. Add an index on the ORDER BY column(s) — no sort needed at all:
             CREATE INDEX CONCURRENTLY idx_<table>_<col> ON <table>(<col>);

        2. Increase work_mem for this session (test or production):
             SET work_mem = '256MB';

        3. Reduce the result set with a more selective WHERE clause before sorting.

        4. In production, tune work_mem in postgresql.conf:
             work_mem = 64MB  # applies per-sort, per-session — be careful

        Sort key: #{sort_cols}
        """,
        entry: entry,
        details: %{sort_method: node.sort_method, sort_key: node.sort_key}
      }
    end)
  end
end
