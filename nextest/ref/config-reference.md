# Configuration Reference

Config file: `.config/nextest.toml` at the workspace root.

## Top-level

```toml
nextest-version = "0.9.50"
# or
nextest-version = { required = "0.9.20", recommended = "0.9.30" }

experimental = ["setup-scripts", "wrapper-scripts"]

[store]
dir = "target/nextest"    # Default store directory
```

## Profile Configuration

All settings below use `profile.<name>.<key>` notation. The default profile
is `profile.default`.

### Core Test Execution

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `inherits` | string | `"default"` | Profile to inherit from |
| `default-filter` | filterset | `"all()"` | Default set of tests to run |
| `global-timeout` | duration | none | Global timeout for entire run |
| `test-threads` | int/string | `"num-cpus"` | Number of concurrent tests |
| `threads-required` | int/string | `1` | Threads each test consumes |
| `run-extra-args` | string[] | `[]` | Extra args to test binary |

### Retry

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `retries` | int/object | `0` | Retry policy |

Retry object forms:
```toml
retries = 3
retries = { backoff = "fixed", count = 3, delay = "1s" }
retries = { backoff = "exponential", count = 4, delay = "2s", max-delay = "10s", jitter = true }
```

### Timeouts

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `slow-timeout` | duration/object | `60s` | Slow test threshold |
| `leak-timeout` | duration/object | `200ms` | Leak detection threshold |

Slow-timeout object:
```toml
slow-timeout = { period = "120s", terminate-after = 2, grace-period = "10s" }
slow-timeout = { period = "30s", terminate-after = 4, on-timeout = "pass" }
```

Leak-timeout object:
```toml
leak-timeout = { period = "500ms", result = "fail" }
```

### Reporter

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `status-level` | string | `"pass"` | Status levels to display during run |
| `final-status-level` | string | `"flaky"` | Status levels in final summary |
| `failure-output` | string | `"immediate"` | When to show failure output |
| `success-output` | string | `"never"` | When to show success output |

### Failure Handling

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `fail-fast` | bool/object | `true` | Stop on first failure |

```toml
fail-fast = true
fail-fast = false
fail-fast = { max-fail = 5 }
fail-fast = { max-fail = 1, terminate = "immediate" }
fail-fast = { max-fail = "all" }  # Equivalent to false
```

### Test Grouping

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `test-group` | string | `"@global"` | Assign test to a group |

### JUnit

```toml
[profile.ci.junit]
path = "junit.xml"
report-name = "nextest-run"
store-success-output = false
store-failure-output = true
```

### Archive

```toml
[profile.default]
archive.include = [
    { path = "fixtures", relative-to = "target", depth = 2, on-missing = "warn" },
]
```

## Override Configuration

```toml
[[profile.<name>.overrides]]
filter = 'test(pattern)'           # At least one of filter/platform required
platform = 'cfg(target_os = "linux")'
# Override settings:
retries = 3
slow-timeout = { period = "60s", terminate-after = 2 }
threads-required = 2
test-group = 'my-group'
priority = 50
leak-timeout = "500ms"
success-output = "immediate"
failure-output = "immediate-final"
run-extra-args = ["--test-threads", "1"]
```

## Test Groups

```toml
[test-groups]
serial-db = { max-threads = 1 }
rate-limited = { max-threads = 4 }
```

## Script Configuration

### Setup Scripts

```toml
experimental = ["setup-scripts"]

[scripts.setup.my-script]
command = 'my-script.sh'
# or: command = ['script.sh', '-c', 'arg']
# or: command = { command-line = "debug/my-setup", relative-to = "target" }
slow-timeout = { period = "60s", terminate-after = 2 }
leak-timeout = "1s"
capture-stdout = true
capture-stderr = false

[[profile.default.scripts]]
filter = 'rdeps(db-tests)'
setup = 'my-script'
# or: setup = ['script1', 'script2']
```

### Wrapper Scripts

```toml
experimental = ["wrapper-scripts"]

[scripts.wrapper.my-wrapper]
command = 'sudo'
target-runner = "ignore"  # ignore | overrides-wrapper | within-wrapper | around-wrapper

[[profile.ci.scripts]]
filter = 'binary_id(pkg::bin) and test(=root_test)'
platform = 'cfg(target_os = "linux")'
run-wrapper = 'my-wrapper'
```

## Default Embedded Configuration

The following defaults are built into nextest and apply unless overridden:

```toml
[store]
dir = "target/nextest"

[profile.default]
default-filter = "all()"
retries = 0
test-threads = "num-cpus"
threads-required = 1
run-extra-args = []
status-level = "pass"
final-status-level = "flaky"
failure-output = "immediate"
success-output = "never"
fail-fast = true
slow-timeout = { period = "60s", on-timeout = "fail" }
leak-timeout = "200ms"
global-timeout = "30y"
```
