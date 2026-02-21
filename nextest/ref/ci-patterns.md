# CI/CD Patterns for cargo-nextest

## Recommended CI Profile

```toml
# .config/nextest.toml
[profile.ci]
fail-fast = false                   # Run all tests even after failures
retries = 2                         # Handle flaky tests
failure-output = "immediate-final"  # Show failures as they happen AND at end
slow-timeout = { period = "120s", terminate-after = 5 }

[profile.ci.junit]
path = "junit.xml"                  # JUnit report for CI tools
```

## Partitioning / Sharding

Split large test suites across multiple CI runners.

### Sliced partitioning (recommended)

Round-robin across all tests; even distribution.

```
cargo nextest run --partition slice:1/3
cargo nextest run --partition slice:2/3
cargo nextest run --partition slice:3/3
```

### Hashed sharding

Deterministic bucketing: adding/removing tests doesn't shift other tests
between buckets. Better for caching, but may be less evenly distributed for
small test counts.

```
cargo nextest run --partition hash:1/3
```

Partitioning applies after all other filters. For example:
```
cargo nextest run --partition slice:1/3 -E 'package(my-crate)'
```

## Build/Run Split (Archiving)

Build once, distribute archive, run on multiple machines.

### Build machine

```bash
cargo nextest archive --workspace --all-features --archive-file tests.tar.zst
```

### Target machine

```bash
# Source must be checked out at the same revision
cargo nextest run --archive-file tests.tar.zst
# If workspace path differs:
cargo nextest run --archive-file tests.tar.zst --workspace-remap /new/path
```

Cargo does NOT need to be installed on the target machine. If unavailable,
use `cargo-nextest nextest run` instead of `cargo nextest run`.

### Archive extras

```toml
[profile.default]
archive.include = [
    { path = "fixtures", relative-to = "target" },
    { path = "test-data.json", relative-to = "target", on-missing = "error" },
]
```

### Filtering archive contents

```bash
cargo nextest archive --workspace -E 'rdeps(db-tests)' --archive-file archive.tar.zst
```

## GitHub Actions Example

### Basic with JUnit

```yaml
- name: Run tests
  run: cargo nextest run -P ci
- name: Upload JUnit
  if: always()
  uses: actions/upload-artifact@v4
  with:
    name: junit-results
    path: target/nextest/ci/junit.xml
```

### Build once, shard across matrix

```yaml
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: cargo nextest archive --workspace --archive-file tests.tar.zst
      - uses: actions/upload-artifact@v4
        with:
          name: nextest-archive
          path: tests.tar.zst

  test:
    needs: build
    runs-on: ubuntu-latest
    strategy:
      fail-fast: false
      matrix:
        partition: [1, 2, 3]
    steps:
      - uses: actions/checkout@v4
      - uses: actions/download-artifact@v4
        with:
          name: nextest-archive
      - run: cargo nextest run -P ci --archive-file tests.tar.zst --partition slice:${{ matrix.partition }}/3
```

### Cross-compilation

```bash
# Build machine: run host tests, archive for target
cargo nextest run --target aarch64-unknown-linux-gnu -E 'platform(host)'
cargo nextest archive --target aarch64-unknown-linux-gnu --archive-file tests.tar.zst

# Target machine: run target tests
cargo nextest run -E 'platform(target)' \
    --archive-file tests.tar.zst \
    --workspace-remap /path/to/checkout
```

## GitLab CI Example

```yaml
test:
  stage: test
  parallel: 3
  script:
    - cargo nextest run --workspace --partition slice:${CI_NODE_INDEX}/${CI_NODE_TOTAL}
```

## Portable Recordings (Experimental)

Export test results from CI for local replay:

```bash
# In CI:
cargo nextest store export latest --archive-file nextest-run.zip
# Upload as artifact

# Locally:
cargo nextest replay -R nextest-run.zip
cargo nextest run -R nextest-run.zip    # Rerun failures
```

## Making Tests Relocatable

For archived test runs where workspace paths differ:

- Use `std::env::var("CARGO_MANIFEST_DIR")` (runtime), not
  `env!("CARGO_MANIFEST_DIR")` (compile-time)
- For binary paths in integration tests, use `NEXTEST_BIN_EXE_<name>`
  (underscored variant preferred: `NEXTEST_BIN_EXE_my_program`)
- Fall back to `CARGO_BIN_EXE_<name>` for `cargo test` compat

## Agent Sandbox Tips

When running tests in a constrained sandbox environment:

- Limit parallelism: `-j 2` or `-j 4`
- Set generous timeouts for slower environments
- Disable interactive features: `NEXTEST_NO_INPUT_HANDLER=1`
- Use `--show-progress=counter` for non-interactive output
- Prefer `--no-fail-fast` to see all failures in one run
- Consider `--no-tests pass` if some test targets may be empty
