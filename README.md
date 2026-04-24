# EctoVerify

Analyzes PostgreSQL query plans during ExUnit tests and fails tests on bad query patterns.
Inspired by [Credo](https://github.com/rrrene/credo), [squawk](https://github.com/sbdchd/squawk), and [excellent_migrations](https://github.com/Artur-Sulej/excellent_migrations).

## What it detects

### Runtime rules (per query, via EXPLAIN ANALYZE)

| Rule | Severity | Description |
|------|----------|-------------|
| `SequentialScan` | Error | Full table scans on non-trivial tables (missing index) |
| `NPlusOne` | Error | Same query repeated N+ times in one test |
| `RedundantQuery` | Warning | Identical `{sql, params}` executed more than once |
| `MissingLimit` | Warning | Unbounded SELECT returning many rows |
| `OrderWithoutLimit` | Warning | `ORDER BY` without `LIMIT` on a large result set |
| `NonSargable` | Warning | Predicates that cannot use indexes (`LIKE '%...'`, `LOWER(col)`) |
| `ImplicitCast` | Warning | Type mismatch forces a CAST in WHERE/JOIN, disabling index use |
| `UnparameterizedQuery` | Error | Literal values in SQL instead of `$1` placeholders |
| `CartesianJoin` | Error | Cartesian products from missing join conditions |
| `NotInSubquery` | Warning | `NOT IN (SELECT …)` — becomes slow with NULLs, prefer `NOT EXISTS` |
| `SelectStar` | Warning | `SELECT *` — fetches unused columns, breaks cached plans on schema change |
| `OffsetPagination` | Warning | `OFFSET` on large tables — full scan to skip rows |
| `SortWithoutIndex` | Warning | In-memory sort on a non-indexed column |
| `SortSpillToDisk` | Error | Sort exceeded `work_mem` and spilled to disk |
| `HashJoinSpill` | Error | Hash join spilled to disk due to insufficient `work_mem` |
| `PlannerEstimationError` | Warning | Planner row estimate off by 10× or more — stale statistics |
| `IndexFilterRatio` | Warning | Index scan removes many rows in a recheck filter — index selectivity poor |
| `IndexCount` | Warning | Tables with too many indexes (slows writes) |
| `UnusedIndexes` | Warning | Indexes with zero scans in this test run |
| `MissingFkIndex` | Warning | Foreign key column has no supporting index |
| `SerialOverflow` | Error | `SERIAL`/`BIGSERIAL` sequence over 80% full |

### Migration rules (once per suite, via AST analysis)

| Rule | Severity | Description |
|------|----------|-------------|
| `MigrationIndexNotConcurrent` | Error | `create index` without `concurrently: true` — locks table |
| `MigrationColumnNotNull` | Error | `add :col, null: false` without `default:` — rewrites table |
| `MigrationFkNotValid` | Error | `references(...)` without `validate: false` — locks both tables |
| `MigrationChangeColumnType` | Error | `modify :col, :new_type` — rewrites entire table |

---

## Installation

### With Igniter (recommended)

```sh
mix igniter.install ecto_verify
```

This automatically patches `test/test_helper.exs` and your `DataCase`.

### Manual

Add to `mix.exs`:

```elixir
def deps do
  [
    {:ecto_verify, "~> 0.1", only: [:test, :dev]}
  ]
end
```

Then run:

```sh
mix deps.get
mix ecto_verify.install
```

---

## Phoenix project setup

### 1. `test/test_helper.exs`

Call `EctoVerify.setup/1` **before** `ExUnit.start/0`:

```elixir
EctoVerify.setup(
  repos: [MyApp.Repo],
  thresholds: [
    seq_scan_min_rows: 100,   # rows before seq scan is flagged
    n_plus_one: 5,            # repeated queries before N+1 is flagged
    max_indexes: 10,          # max indexes per table
    estimation_error_ratio: 10 # plan/actual rows ratio threshold
  ],
  ignore_rules: [EctoVerify.Rules.MissingLimit],
  filter_parameters: [:password, :token]  # redact from diagnostics
)
ExUnit.start()
```

### 2. `test/support/data_case.ex`

Add `use EctoVerify.Case` inside the `quote do` block:

```elixir
defmodule MyApp.DataCase do
  use ExUnit.CaseTemplate

  using do
    quote do
      use EctoVerify.Case, repo: MyApp.Repo  # <-- add this

      import Ecto
      import Ecto.Changeset
      import Ecto.Query
      import MyApp.DataCase
      alias MyApp.Repo
    end
  end

  setup tags do
    MyApp.DataCase.setup_sandbox(tags)
  end

  def setup_sandbox(tags) do
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(MyApp.Repo, shared: not tags[:async])
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)
  end
end
```

### 3. Optional — SQL comments in dev/test logs

Add caller info as SQL comments to identify slow queries in PG logs:

```elixir
# lib/my_app/repo.ex
defmodule MyApp.Repo do
  use Ecto.Repo, otp_app: :my_app, adapter: Ecto.Adapters.Postgres

  if Mix.env() in [:dev, :test] do
    @impl true
    def default_options(_op), do: [stacktrace: true]

    @impl true
    def prepare_query(_op, query, opts) do
      comment = EctoVerify.SqlAnnotator.build_comment(opts)
      {query, [comment: comment, prepare: :unnamed] ++ opts}
    end
  end
end
```

Queries in logs will look like:

```sql
/* ecto_verify: lib/my_app/accounts.ex:42 MyApp.Accounts.list_users/0 */
SELECT u0."id", u0."email" FROM "users" AS u0
```

---

## Output

When a violation is found the test fails with a Credo-style message:

```
EctoVerify found 1 violation(s):

  [E] Sequential scan on `users` touching 1,432 rows — EctoVerify.Rules.SequentialScan

  Query:
    SELECT u0."id", u0."email" FROM "users" AS u0 WHERE (u0."active" = $1)

  Advice:
    Add an index on the filtered column(s).
    Filter applied: (active = true)

    Example:
      CREATE INDEX CONCURRENTLY idx_users_active ON users(active);

    For boolean columns, use a partial index:
      CREATE INDEX CONCURRENTLY idx_users_active ON users(id) WHERE active = true;

  Caller: lib/my_app/accounts.ex:42

  ──────────────────────────────────────────────────────────
```

---

## Custom rules

Implement `EctoVerify.Rule`:

```elixir
defmodule MyApp.Rules.NoFullTableExport do
  @behaviour EctoVerify.Rule

  def name, do: "no-full-table-export"
  def description, do: "Prevents SELECT * without WHERE on large tables"

  def check(nodes, entry, _thresholds) do
    top = hd(nodes)
    if top.node_type == "Seq Scan" and not String.contains?(entry.sql, "WHERE") do
      [%EctoVerify.Violation{
        rule: __MODULE__,
        severity: :error,
        message: "Full table export on `#{top.relation_name}`",
        advice: "Add a WHERE clause or use Repo.stream/2 with pagination.",
        entry: entry,
        details: %{}
      }]
    else
      []
    end
  end
end
```

Register in `EctoVerify.setup/1`:

```elixir
EctoVerify.setup(
  repos: [MyApp.Repo],
  rules: EctoVerify.Config.default_rules() ++ [MyApp.Rules.NoFullTableExport]
)
```

---

## How it works

1. **Telemetry hook** — attaches to `[:your_app, :repo, :query]` events
2. **Query capture** — stores `{sql, params, stacktrace}` per test PID (async-safe via `$callers`)
3. **Migration scan** — once per suite, parses migration files with `Code.string_to_quoted!/1` and runs AST rules
4. **EXPLAIN runner** — after each test, runs `EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)` via a dedicated Postgrex connection separate from the Ecto sandbox
5. **Plan parser** — normalizes the JSON plan tree into a flat node list
6. **Rules engine** — each rule inspects nodes/SQL and returns violations
7. **Formatter** — prints Credo-style output and raises `ExUnit.AssertionError`

The EXPLAIN connection is separate from the Ecto sandbox so it works correctly with `async: true` tests.
