defmodule EctoSpect.ExplainRunnerTest do
  use ExUnit.Case, async: false

  @moduletag :integration

  # Connection options — match devenv.nix defaults (Unix socket) or CI (TCP).
  defp pg_opts do
    if url = System.get_env("POSTGRES_URL") do
      url |> URI.parse() |> uri_to_opts()
    else
      [
        hostname: "localhost",
        database: "ecto_verify_test",
        username: System.get_env("USER", "postgres"),
        password: ""
      ]
    end
  end

  defp uri_to_opts(%URI{host: host, path: "/" <> db, userinfo: userinfo, port: port}) do
    [username, password] =
      case userinfo do
        nil -> ["postgres", ""]
        info -> String.split(info, ":", parts: 2)
      end

    opts = [hostname: host, database: db, username: username, password: password]
    if port, do: Keyword.put(opts, :port, port), else: opts
  end

  defp open_conn do
    {:ok, conn} = Postgrex.start_link(pg_opts())
    conn
  end

  defp entry(sql, params \\ []) do
    %{
      sql: sql,
      params: params,
      source: nil,
      stacktrace: nil,
      repo: nil,
      total_time_us: 100
    }
  end

  setup_all do
    conn = open_conn()
    on_exit(fn -> GenServer.stop(conn) end)
    {:ok, conn: conn}
  end

  describe "explain_entry/3 with SELECT" do
    test "returns empty violations list for a simple SELECT", %{conn: conn} do
      sql = "SELECT 1"
      config = %EctoSpect.Config{rules: [], thresholds: %{}}
      violations = EctoSpect.ExplainRunner.explain_entry(conn, entry(sql), config)
      assert violations == []
    end

    test "parses plan without crashing on PG 17+ native json response", %{conn: conn} do
      # We can't directly control whether PG returns text or native json, but we can
      # verify the full path works end-to-end regardless of PG version.
      sql = "SELECT 1"
      config = %EctoSpect.Config{rules: [], thresholds: %{}}
      # If decode_plan handles both string and already-decoded types, this won't crash.
      assert EctoSpect.ExplainRunner.explain_entry(conn, entry(sql), config) == []
    end
  end

  describe "decode_plan compatibility" do
    test "explain_entry handles plan returned as string (PG < 17 simulation)", %{conn: conn} do
      # We test the full public API; the decode_plan private function is exercised internally.
      config = %EctoSpect.Config{rules: [], thresholds: %{}}
      sql = ~S[SELECT 1]
      result = EctoSpect.ExplainRunner.explain_entry(conn, entry(sql), config)
      assert is_list(result)
    end
  end

  describe "explain_entry/3 with mutations (no ANALYZE)" do
    setup %{conn: conn} do
      # Create a temp table for mutation tests — dropped at end of test.
      Postgrex.query!(
        conn,
        "CREATE TEMP TABLE explain_runner_test_items (id serial PRIMARY KEY, val text)",
        []
      )

      on_exit(fn ->
        Postgrex.query(conn, "DROP TABLE IF EXISTS explain_runner_test_items", [])
      end)

      :ok
    end

    test "INSERT uses EXPLAIN without ANALYZE — no FK lock contention", %{conn: conn} do
      sql = ~S[INSERT INTO explain_runner_test_items (val) VALUES ($1)]
      config = %EctoSpect.Config{rules: [], thresholds: %{}}
      # Should complete quickly (no deadlock) and return no violations.
      violations = EctoSpect.ExplainRunner.explain_entry(conn, entry(sql, ["test"]), config)
      assert is_list(violations)
    end

    test "DELETE uses EXPLAIN without ANALYZE", %{conn: conn} do
      sql = ~S[DELETE FROM explain_runner_test_items WHERE id = $1]
      config = %EctoSpect.Config{rules: [], thresholds: %{}}
      violations = EctoSpect.ExplainRunner.explain_entry(conn, entry(sql, [1]), config)
      assert is_list(violations)
    end

    test "rows are not actually inserted after mutation explain", %{conn: conn} do
      sql = ~S[INSERT INTO explain_runner_test_items (val) VALUES ($1)]
      config = %EctoSpect.Config{rules: [], thresholds: %{}}
      EctoSpect.ExplainRunner.explain_entry(conn, entry(sql, ["should_not_exist"]), config)

      %{rows: rows} =
        Postgrex.query!(conn, "SELECT val FROM explain_runner_test_items WHERE val = $1", [
          "should_not_exist"
        ])

      assert rows == []
    end
  end
end
