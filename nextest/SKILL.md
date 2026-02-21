---
name: nextest
description: "Use when running Rust tests with cargo-nextest. Keywords: cargo nextest, nextest, test runner, run tests, test parallelism, test threads, flaky test, retry, slow test, timeout, test group, filterset, test partition, sharding, continuous integration (CI) testing, nextest profile, nextest config, .config/nextest.toml, cargo nextest run, cargo nextest list, test archive, JUnit, stress test, miri, test coverage, cargo-mutants, criterion, debugger, tracer"
globs: ["**/Cargo.toml", "**/.config/nextest.toml"]
user-invocable: false
---

# cargo-nextest: The Rust Test Runner

cargo-nextest runs each test in its own process, in parallel. It builds test
binaries, queries them for tests, then executes each test individually. This
eliminates bottlenecks from long-pole tests and provides structured per-test
results. Custom test harnesses may need adaptation for this model.

## Quick Reference

### Running Tests

```
cargo nextest run                          # Run all tests
cargo nextest run test_name                # Run tests matching substring
cargo nextest run -p my-crate              # Run tests in a specific package
cargo nextest run --workspace              # Run all workspace tests
cargo nextest run -j 4                     # Limit to 4 concurrent tests
cargo nextest run -j 1                     # Run tests serially
cargo nextest run --no-fail-fast           # Don't stop on first failure
cargo nextest run --retries 2              # Retry failures up to 2 times
cargo nextest run --no-capture             # Show output live (serial)
cargo nextest run -P ci                    # Use the "ci" profile
```

### Listing and Selecting Tests

```
cargo nextest list                         # List all tests
cargo nextest list -T json-pretty          # List in JSON format
cargo nextest run -E 'package(my-crate)'   # Filterset: by package
cargo nextest run -E 'test(/regex/)'       # Filterset: by regex
cargo nextest run -E 'deps(my-crate)'      # Filterset: crate + dependencies
cargo nextest run -- --skip slow --exact test_foo  # Skip/exact matching
```

### CI Essentials

```
cargo nextest run -P ci --no-fail-fast     # CI profile, run all tests
cargo nextest run --partition slice:1/3    # Shard across 3 runners
cargo nextest archive --archive-file a.tar.zst  # Archive for reuse
cargo nextest run --archive-file a.tar.zst      # Run from archive
```

---

## Parallelism and Thread Control

By default, nextest runs `num-cpus` tests concurrently. Control this with:

- **CLI**: `-j N` or `--test-threads N` (also `num-cpus`)
- **Env**: `NEXTEST_TEST_THREADS=N`
- **Config**: `test-threads = N` or `test-threads = "num-cpus"`

Negative values are relative to CPU count (e.g., `-2` means `num_cpus - 2`).

### Heavy tests (`threads-required`)

Mark resource-intensive tests to consume multiple thread slots:

```toml
# .config/nextest.toml
[[profile.default.overrides]]
filter = 'test(/^tests::heavy::/)'
threads-required = 2        # Each takes 2 of the thread budget

# Special values:
# threads-required = "num-cpus"          — effectively serial
# threads-required = "num-test-threads"  — monopolise all slots
```

### Test groups (mutual exclusion / rate-limiting)

Logical semaphores/mutexes for subsets of tests:

```toml
[test-groups]
serial-db = { max-threads = 1 }      # Mutex
rate-limited = { max-threads = 4 }    # Semaphore with 4 permits

[[profile.default.overrides]]
filter = 'package(db-tests)'
test-group = 'serial-db'

[[profile.default.overrides]]
filter = 'test(api_)'
test-group = 'rate-limited'
```

Inspect with `cargo nextest show-config test-groups`.

---

## Configuration

Config file: `.config/nextest.toml` in the workspace root.

### Profiles

Profiles provide named sets of options. Select with `-P <name>` or
`NEXTEST_PROFILE=<name>`.

```toml
[profile.default]
fail-fast = true
retries = 0
test-threads = "num-cpus"
slow-timeout = { period = "60s" }

[profile.ci]
fail-fast = false
retries = 2
failure-output = "immediate-final"

[profile.ci.junit]
path = "junit.xml"
```

Profiles inherit from `default` unless `inherits` is specified.

### Hierarchical resolution

1. CLI arguments
2. Environment variables
3. Per-test overrides (in profile, then default)
4. Profile configuration
5. Default configuration

### Per-test overrides

```toml
[[profile.default.overrides]]
filter = 'test(test_e2e)'
retries = 3
slow-timeout = { period = "120s", terminate-after = 5 }
threads-required = 2
```

Overrides support: `retries`, `slow-timeout`, `leak-timeout`,
`threads-required`, `test-group`, `success-output`, `failure-output`,
`priority`, `run-extra-args`, `default-filter`.

---

## Retries and Flaky Tests

```toml
retries = 3                                              # Simple
retries = { backoff = "fixed", count = 3, delay = "1s" } # Fixed delay
retries = { backoff = "exponential", count = 4, delay = "2s", max-delay = "10s", jitter = true }
```

CLI `--retries N` and env `NEXTEST_RETRIES=N` override all config including
per-test overrides, and disable backoff delays.

A test that fails then succeeds on retry is marked **flaky** (ultimately
passes, exit code 0).

---

## Timeouts

### Slow test warnings

```toml
slow-timeout = "60s"             # Warn after 60s
```

### Terminating hung tests

```toml
slow-timeout = { period = "30s", terminate-after = 4 }
# Warns at 30s, terminates at 120s (4 x 30s)
# Grace period before SIGKILL: default 10s
slow-timeout = { period = "30s", terminate-after = 4, grace-period = "5s" }
```

### Global timeout

```toml
global-timeout = "2h"      # Entire test run must finish in 2 hours
```

### Timeout as success (fuzz tests)

```toml
[[profile.default.overrides]]
filter = 'package(fuzz-targets)'
slow-timeout = { period = "30s", terminate-after = 1, on-timeout = "pass" }
```

---

## Filtersets (Domain-specific language, DSL)

Specified with `-E` / `--filterset`. Combinable with set operators.

### Predicates

| Predicate | Matches |
|-----------|---------|
| `all()` | All tests |
| `none()` | No tests |
| `test(name)` | Tests containing `name` (default: substring) |
| `test(/regex/)` | Tests matching regex |
| `package(glob)` | Tests in packages matching glob |
| `deps(glob)` | Package + transitive deps |
| `rdeps(glob)` | Package + reverse transitive deps |
| `binary(glob)` | By binary name |
| `binary_id(glob)` | By binary ID |
| `kind(lib\|test\|bench\|proc-macro\|bin\|example)` | By binary kind |
| `platform(host\|target)` | By build platform |
| `default()` | The configured default filter |

### Name matchers

| Prefix | Meaning | Example |
|--------|---------|---------|
| (none) | Default for predicate | `test(foo)` = contains |
| `=` | Exact match | `test(=my::test)` |
| `~` | Contains | `package(~serde)` |
| `/regex/` | Regex (any part) | `test(/^init_/)` |
| `#` | Glob | `package(#my-*)` |

### Operators (precedence high to low)

`()` > `not`/`!` > `and`/`&`/`-` > `or`/`|`/`+`

### Interaction with default filter

CLI filtersets are intersected with `default-filter`. Override with
`--ignore-default-filter`.

---

## Environment-Aware Configuration

### Per-platform overrides

```toml
[[profile.default.overrides]]
platform = 'cfg(target_os = "linux")'
slow-timeout = "120s"

[[profile.default.overrides]]
platform = { host = "cfg(unix)", target = "aarch64-apple-darwin" }
threads-required = 2
```

### Agent sandbox considerations

When running inside an agent sandbox (constrained CPU/memory):

- Use `-j 2` or `-j 4` to limit parallelism
- Set generous timeouts: `slow-timeout = { period = "120s", terminate-after = 3 }`
- Consider `--no-fail-fast` to gather all failures in one run
- Use `--show-progress=counter` for non-interactive output
- Set `NEXTEST_NO_INPUT_HANDLER=1` to disable terminal key handling

### GitHub CI configuration

```toml
[profile.ci]
fail-fast = false
retries = 2
failure-output = "immediate-final"
slow-timeout = { period = "120s", terminate-after = 5 }

[profile.ci.junit]
path = "junit.xml"
```

For sharding across matrix jobs:

```yaml
strategy:
  matrix:
    partition: [1, 2, 3]
steps:
  - run: cargo nextest run -P ci --partition slice:${{ matrix.partition }}/3
```

For build/run split:

```yaml
jobs:
  build:
    steps:
      - run: cargo nextest archive --archive-file tests.tar.zst
      - uses: actions/upload-artifact@v4
        with: { name: nextest-archive, path: tests.tar.zst }
  test:
    needs: build
    strategy:
      matrix:
        partition: [1, 2, 3]
    steps:
      - uses: actions/download-artifact@v4
        with: { name: nextest-archive }
      - run: cargo nextest run --archive-file tests.tar.zst --partition slice:${{ matrix.partition }}/3
```

---

## Archiving and Reusing Builds

Build once, run anywhere (same platform):

```
cargo nextest archive --archive-file tests.tar.zst
cargo nextest run --archive-file tests.tar.zst
```

The archive contains test binaries, dynamic libraries, build script outputs,
and metadata. Source code is NOT included; it must be checked out at the same
revision on the target machine.

Use `--workspace-remap <path>` if the workspace is at a different path on the
target machine.

Include extra files:

```toml
[profile.default]
archive.include = [
    { path = "fixtures", relative-to = "target" },
    { path = "data.json", relative-to = "target", on-missing = "error" },
]
```

---

## Stress Testing

```
cargo nextest run --stress-count 10 test_flaky    # Run 10 times each
cargo nextest run --stress-count infinite test_x   # Run indefinitely
cargo nextest run --stress-duration 5m test_x      # Run for 5 minutes
```

---

## Record, Replay, and Rerun (Experimental)

Enable in `~/.config/nextest/config.toml`:

```toml
[experimental]
record = true

[record]
enabled = true
```

Then:

```
cargo nextest run                   # Automatically recorded
cargo nextest run -R latest         # Rerun only failures
cargo nextest replay                # Replay last run's output
cargo nextest store list            # List recorded runs
cargo nextest store export latest   # Export portable recording
```

---

## Test Priorities

```toml
[[profile.default.overrides]]
filter = 'test(smoke_)'
priority = 50          # Run early (range: -100 to 100, default: 0)

[[profile.default.overrides]]
filter = 'test(slow_e2e_)'
priority = -50         # Run late
```

---

## Reporter and Output Control

| Option | Values | Default |
|--------|--------|---------|
| `--failure-output` | `immediate`, `final`, `immediate-final`, `never` | `immediate` |
| `--success-output` | `immediate`, `final`, `immediate-final`, `never` | `never` |
| `--status-level` | `none`, `fail`, `retry`, `slow`, `leak`, `pass`, `skip`, `all` | `pass` |
| `--final-status-level` | `none`, `fail`, `flaky`, `slow`, `skip`, `pass`, `all` | `flaky` |
| `--show-progress` | `auto`, `none`, `bar`, `counter`, `only` | `auto` |

Press `t` during a run to dump status of currently-running tests (interactive
terminals only). On macOS, Ctrl-T also works. On any Unix, send `SIGUSR1`.

---

## Setup Scripts (Experimental)

Pre-test scripts that can set environment variables for tests:

```toml
experimental = ["setup-scripts"]

[scripts.setup.db-seed]
command = 'cargo run -p seed-db'
slow-timeout = { period = "60s", terminate-after = 2 }

[[profile.default.scripts]]
filter = 'rdeps(db-tests)'
setup = 'db-seed'
```

Scripts write env vars to `$NEXTEST_ENV`:
```bash
echo "DATABASE_URL=postgres://localhost/test" >> "$NEXTEST_ENV"
```

---

## Key Environment Variables

### Nextest reads

| Variable | Purpose |
|----------|---------|
| `NEXTEST_TEST_THREADS` | Override test thread count |
| `NEXTEST_RETRIES` | Override retry count |
| `NEXTEST_PROFILE` | Select profile |
| `NEXTEST_FAILURE_OUTPUT` | Override failure output mode |
| `NEXTEST_VERBOSE` | Verbose output |

### Nextest sets (at test runtime)

| Variable | Value |
|----------|-------|
| `NEXTEST` | Always `"1"` |
| `NEXTEST_RUN_ID` | UUID for the run |
| `NEXTEST_EXECUTION_MODE` | `"process-per-test"` |
| `NEXTEST_ATTEMPT` | 1-indexed attempt number |
| `NEXTEST_TEST_GROUP` | Group name or `"@global"` |
| `NEXTEST_BIN_EXE_<name>` | Path to binary target (integration tests) |
| `NEXTEST_BINARY_ID` | Binary ID of the current test |
| `NEXTEST_ATTEMPT_ID` | Globally unique attempt identifier |
| `NEXTEST_TEST_GLOBAL_SLOT` | Global slot number (0-indexed, unique among running tests) |
| `NEXTEST_TEST_GROUP_SLOT` | Group slot number (`"none"` if not in a group) |

Slot numbers are useful for assigning resources like port numbers to tests.
They are unique for the lifetime of the test, stable across retries, and
compact (each test gets the smallest available slot).

### Environment safety

Because nextest runs each test in its own process, calling `std::env::set_var`
at the beginning of a test is safe in practice (before spawning threads).

---

## Debugger and Tracer Support

```
cargo nextest run --debugger "rust-gdb --args" test_name
cargo nextest run --debugger "rust-lldb --" test_name
cargo nextest run --tracer strace test_name
cargo nextest run --tracer "strace -f" test_name     # Follow child processes
```

Both modes disable timeouts and output capture, and require exactly one test
to be selected. Key differences:

- `--debugger`: Passes stdin through, disables signal handling and process
  groups (interactive debugging with gdb, lldb, WinDbg, CodeLLDB)
- `--tracer`: Null stdin, standard signal handling, process groups for
  isolation (non-interactive tracing with strace, dtruss, truss)

---

## Integrations

### Miri (undefined behaviour detection)

```
cargo miri nextest run
cargo miri nextest run --target mips64-unknown-linux-gnuabi64  # Cross-interpretation
```

Nextest auto-selects the `default-miri` profile under Miri. Configure it in
`.config/nextest.toml`:

```toml
[profile.default-miri]
slow-timeout = { period = "60s", terminate-after = 2 }
```

Miri tests run in parallel with nextest (Miri itself is single-threaded, so
`cargo miri test` is limited to serial execution). Archiving is not supported
under Miri.

### Test coverage

```
cargo llvm-cov nextest
```

Merge with doctests (nextest doesn't run doctests):

```bash
cargo llvm-cov --no-report nextest
cargo llvm-cov --no-report --doc
cargo llvm-cov report --doctests --lcov --output-path lcov.info
```

### Mutation testing (cargo-mutants)

```
cargo mutants --test-tool=nextest
```

Or set permanently in `.cargo/mutants.toml`:

```toml
test_tool = "nextest"
```

### Criterion benchmarks in test mode

By default, `cargo nextest run` excludes benchmarks. To verify benchmarks
compile and don't panic (single iteration, no measurement):

```
cargo nextest run --all-targets   # Include benchmarks
cargo nextest run --benches       # Only benchmarks
```

Requires Criterion 0.5.0+. For actual performance measurement, use the
experimental `cargo nextest bench` (requires `experimental = ["benchmarks"]`).

---

## Reference

For detailed reference on specific topics, see the `ref/` directory in this
skill:

- `ref/config-reference.md` — Full configuration parameter reference
- `ref/filterset-dsl.md` — Complete filterset DSL reference
- `ref/ci-patterns.md` — CI/CD patterns for archiving, sharding, and GitHub Actions
