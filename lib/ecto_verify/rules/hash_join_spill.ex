defmodule EctoVerify.Rules.HashJoinSpill do
  @moduledoc """
  Detects Hash Join nodes that spilled to disk during query execution.

  PostgreSQL hash joins build an in-memory hash table from the smaller side of
  the join. When this hash table exceeds `work_mem`, PostgreSQL splits the data
  into multiple batches and spills them to disk (temp files). This is extremely
  slow and means either `work_mem` is too low or the join is unexpectedly large.

  In EXPLAIN output, `"Batches" > 1` on a Hash node indicates a disk spill.
  `"Batches": 1` means the hash table fit in memory (normal).

  This should never happen in a test environment with small datasets — if it
  does, there is a data volume problem or `work_mem` is unusually low.
  """

  @behaviour EctoVerify.Rule

  @impl true
  def name, do: "hash-join-spill"

  @impl true
  def description, do: "Detects Hash Join spills to disk (Batches > 1)"

  @impl true
  def check(nodes, entry, _thresholds) do
    nodes
    |> Enum.filter(fn node ->
      node.node_type == "Hash" and
        is_integer(node.hash_batches) and
        node.hash_batches > 1
    end)
    |> Enum.map(fn node ->
      %EctoVerify.Violation{
        rule: __MODULE__,
        severity: :error,
        message:
          "Hash Join spilled to disk — #{node.hash_batches} batches (expected 1, in-memory)",
        advice: """
        Hash join spills happen when the hash table exceeds work_mem.

        Options:
        1. Increase work_mem for this query (session-level):
             SET work_mem = '256MB';
             -- then run query

        2. Reduce the join's inner side with a more selective WHERE clause.

        3. Switch join strategy: if one side is small and indexed, a Nested Loop
           with an index scan may be more efficient than a Hash Join.

        4. In production, increase shared work_mem via postgresql.conf:
             work_mem = 64MB  # careful — per-sort, per-join, per-session

        Seeing this in tests means your test data volume is unusually large or
        work_mem is set very low.
        """,
        entry: entry,
        details: %{hash_batches: node.hash_batches}
      }
    end)
  end
end
