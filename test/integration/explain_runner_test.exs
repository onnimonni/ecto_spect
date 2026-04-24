defmodule EctoSpect.Integration.ExplainRunnerTest do
  use ExUnit.Case, async: false

  @moduletag :integration

  defp pg_config do
    [
      hostname: System.get_env("PG_HOST", "localhost"),
      port: String.to_integer(System.get_env("PG_PORT", "5432")),
      username: System.get_env("PG_USER", "postgres"),
      password: System.get_env("PG_PASSWORD", "postgres"),
      database: System.get_env("PG_DATABASE", "postgres")
    ]
  end

  setup_all do
    {:ok, conn} = Postgrex.start_link(pg_config())

    Postgrex.query!(
      conn,
      """
      CREATE TABLE IF NOT EXISTS ecto_spect_test_users (
        id SERIAL PRIMARY KEY,
        email VARCHAR(255)
      )
      """,
      []
    )

    on_exit(fn ->
      Postgrex.query!(conn, "DROP TABLE IF EXISTS ecto_spect_test_users", [])
      GenServer.stop(conn)
    end)

    {:ok, conn: conn}
  end

  test "EXPLAIN output is parseable for simple SELECT", %{conn: conn} do
    {:ok, %{rows: [[plan_json]]}} =
      Postgrex.query(conn, "EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) SELECT 1", [])

    nodes = EctoSpect.PlanParser.parse(plan_json)

    assert length(nodes) >= 1
    assert hd(nodes).node_type != nil
  end

  test "EXPLAIN output is parseable for table scan", %{conn: conn} do
    {:ok, %{rows: [[plan_json]]}} =
      Postgrex.query(
        conn,
        "EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) SELECT * FROM ecto_spect_test_users WHERE id = $1",
        [1]
      )

    nodes = EctoSpect.PlanParser.parse(plan_json)

    assert length(nodes) >= 1
    node = hd(nodes)
    assert node.node_type in ["Seq Scan", "Index Scan", "Index Only Scan", "Bitmap Heap Scan"]
    assert node.relation_name == "ecto_spect_test_users"
  end

  test "ExplainRunner.explain_entry/3 returns violations list", %{conn: conn} do
    entry = %{
      sql: ~s[SELECT * FROM ecto_spect_test_users WHERE id = $1],
      params: [1],
      source: "ecto_spect_test_users",
      stacktrace: nil,
      repo: nil,
      total_time_us: 1000
    }

    config = %EctoSpect.Config{rules: [], thresholds: %{}}

    violations = EctoSpect.ExplainRunner.explain_entry(conn, entry, config)
    assert is_list(violations)
  end

  test "ExplainRunner handles INSERT with rollback", %{conn: conn} do
    entry = %{
      sql: ~s[INSERT INTO ecto_spect_test_users (email) VALUES ($1)],
      params: ["test@example.com"],
      source: "ecto_spect_test_users",
      stacktrace: nil,
      repo: nil,
      total_time_us: 500
    }

    config = %EctoSpect.Config{rules: [], thresholds: %{}}

    violations = EctoSpect.ExplainRunner.explain_entry(conn, entry, config)
    assert is_list(violations)

    # Verify INSERT was rolled back
    {:ok, %{rows: rows}} =
      Postgrex.query(conn, "SELECT COUNT(*) FROM ecto_spect_test_users WHERE email = $1", [
        "test@example.com"
      ])

    assert [[0]] == rows
  end

  test "PlanParser extracts node fields from plan", %{conn: conn} do
    {:ok, %{rows: [[plan_json]]}} =
      Postgrex.query(
        conn,
        "EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) SELECT * FROM ecto_spect_test_users",
        []
      )

    [node | _] = EctoSpect.PlanParser.parse(plan_json)

    assert is_binary(node.node_type)
    assert is_integer(node.actual_rows) or is_nil(node.actual_rows)
    assert is_integer(node.plan_rows) or is_nil(node.plan_rows)
    assert node.depth == 0
    assert node.parent_node_type == nil
  end
end
