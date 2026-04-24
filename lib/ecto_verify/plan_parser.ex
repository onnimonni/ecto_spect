defmodule EctoVerify.PlanParser do
  @moduledoc """
  Parses PostgreSQL EXPLAIN FORMAT JSON output into a flat list of normalized nodes.

  Each node retains key fields from the plan tree plus `depth` and `parent_node_type`
  for context. Rules operate on this flat list rather than the raw JSON tree.
  """

  @type plan_node :: %{
          node_type: String.t(),
          relation_name: String.t() | nil,
          alias: String.t() | nil,
          index_name: String.t() | nil,
          index_cond: String.t() | nil,
          filter: String.t() | nil,
          join_type: String.t() | nil,
          sort_key: [String.t()] | nil,
          actual_rows: non_neg_integer() | nil,
          plan_rows: non_neg_integer() | nil,
          actual_loops: non_neg_integer() | nil,
          rows_removed_by_filter: non_neg_integer() | nil,
          actual_total_time_ms: float() | nil,
          total_cost: float() | nil,
          shared_hit_blocks: non_neg_integer() | nil,
          shared_read_blocks: non_neg_integer() | nil,
          shared_dirtied_blocks: non_neg_integer() | nil,
          hash_batches: non_neg_integer() | nil,
          parent_node_type: String.t() | nil,
          depth: non_neg_integer()
        }

  @doc """
  Parse the JSON result from EXPLAIN FORMAT JSON.

  The JSON result is a list containing one plan object:
  `[%{"Plan" => root_node, "Execution Time" => ..., ...}]`
  """
  @spec parse(list()) :: [plan_node()]
  def parse([%{"Plan" => root} | _]) do
    walk(root, nil, 0)
  end

  def parse(_), do: []

  # Recursive walk — returns flat list with parent/depth context.
  defp walk(_node, _parent_type, depth) when depth > 1000, do: []

  defp walk(node, parent_type, depth) do
    normalized = %{
      node_type: node["Node Type"],
      relation_name: node["Relation Name"],
      alias: node["Alias"],
      index_name: node["Index Name"],
      index_cond: node["Index Cond"],
      filter: node["Filter"],
      join_type: node["Join Type"],
      sort_key: node["Sort Key"],
      actual_rows: node["Actual Rows"],
      plan_rows: node["Plan Rows"],
      actual_loops: node["Actual Loops"],
      rows_removed_by_filter: node["Rows Removed by Filter"],
      actual_total_time_ms: node["Actual Total Time"],
      total_cost: node["Total Cost"],
      shared_hit_blocks: node["Shared Hit Blocks"],
      shared_read_blocks: node["Shared Read Blocks"],
      shared_dirtied_blocks: node["Shared Dirtied Blocks"],
      # Hash batches > 1 means hash join spilled to disk
      hash_batches: node["Batches"],
      # "external merge Disk: NkB" means sort spilled to disk
      sort_method: node["Sort Method"],
      parent_node_type: parent_type,
      depth: depth
    }

    child_nodes =
      (node["Plans"] || [])
      |> Enum.flat_map(&walk(&1, node["Node Type"], depth + 1))

    [normalized | child_nodes]
  end
end
