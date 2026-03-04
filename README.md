# tla-native

Builds [TLC](https://github.com/tlaplus/tlaplus) — the TLA+ model checker — as a self-contained
native executable using [GraalVM Native Image](https://www.graalvm.org/native-image/).

The result is a single binary (`tlc-native`) that starts instantly with no JVM overhead, making
it convenient for use in CI pipelines and developer tooling.

## Prerequisites

| Requirement | macOS | Linux |
|-------------|-------|-------|
| `tla2tools.jar` | required (place alongside scripts) | required |
| GraalVM JDK with `native-image` | required for native build; not needed for Docker path | required |
| Docker | required for the `docker-*.sh` scripts | not needed |
| `unzip` | built-in on macOS | must be installed |
| `jq` | for test scripts (`brew install jq`) | must be installed |
| `git` | for test scripts (clones Examples repo) | must be installed |

The Docker scripts use `container-registry.oracle.com/graalvm/native-image:24` (Oracle GraalVM 24,
Oracle Linux). Pull it once with:

```sh
docker pull container-registry.oracle.com/graalvm/native-image:24
```

## Quick start (macOS)

```sh
# Build and install to ~/.local/bin
./install-osx.sh

# Test the installed binary
tlc /path/to/MySpec
```

`install-osx.sh` builds a Mach-O native binary if one is not already present, then installs:

```
~/.local/bin/tlc-native
~/.local/bin/tlc
~/Library/Application Support/tlc/tla2sany/StandardModules/
```

To uninstall:

```sh
./uninstall-osx.sh
```

## Quick start (Linux)

```sh
# Build and install to ~/.local/bin
./install-linux.sh

# Test the installed binary
tlc /path/to/MySpec
```

Installs to:

```
~/.local/bin/tlc-native
~/.local/bin/tlc
~/.local/share/tlc/tla2sany/StandardModules/   # respects $XDG_DATA_HOME
```

To uninstall:

```sh
./uninstall-linux.sh
```

## Building and testing without installing

```sh
# macOS native build + test
./build-osx.sh
./test-osx.sh

# Linux native build + test
./build-linux.sh
./test-linux.sh

# Build a Linux binary from a macOS host (via Docker)
./docker-build.sh
./docker-test.sh
```

---

## Script reference

### Install scripts

| Script | Platform | Notes |
|--------|----------|-------|
| `install-osx.sh` | macOS | Builds if needed; installs to `~/.local/bin` + `~/Library/Application Support/tlc` |
| `install-linux.sh` | Linux | Builds if needed; installs to `~/.local/bin` + `$XDG_DATA_HOME/tlc` |
| `uninstall-osx.sh` | macOS | Removes all files installed by `install-osx.sh` |
| `uninstall-linux.sh` | Linux | Removes all files installed by `install-linux.sh` |

### Build scripts

| Script | Platform | Notes |
|--------|----------|-------|
| `build-osx.sh` | macOS | Requires GraalVM in `JAVA_HOME` or `PATH` |
| `build-linux.sh` | Linux | Same as above; uses `--gc=G1` for runtime GC |
| `docker-build.sh` | macOS host | Runs `build-linux.sh` inside the Oracle GraalVM 24 container |

All build scripts support two modes:

```sh
./build-linux.sh           # build the native image (default)
./build-linux.sh --trace   # collect reflection config via native-image-agent
./build-linux.sh --build   # explicit synonym for default

BUILD_MEMORY=12g ./build-linux.sh   # override compiler heap (default: 8g)
```

### Test scripts

| Script | Platform | Notes |
|--------|----------|-------|
| `test-osx.sh` | macOS | Tests the macOS binary |
| `test-linux.sh` | Linux | Tests the Linux binary |
| `docker-test.sh` | macOS host | Runs `test-linux.sh` inside the Oracle GraalVM 24 container |

All test scripts accept the same environment variables:

```sh
MAX_RUNTIME=30 ./docker-test.sh      # skip models whose expected runtime exceeds 30s
MODEL_TIMEOUT=60 ./docker-test.sh    # hard kill timeout per model in seconds (default: 120)
VERBOSE=1 ./docker-test.sh           # print full TLC output for every model
```

Tests are sourced from a shallow clone of
[tlaplus/Examples](https://github.com/tlaplus/Examples). The clone is removed after the run
unless it was already present before the script started.

---

## The wrapper script (`tlc`)

After a successful build you will find two files next to the native binary:

```
tlc-native   ← the compiled binary
tlc          ← thin shell wrapper (use this one)
```

**Always invoke `tlc`, not `tlc-native` directly.**

### Why the wrapper is necessary

TLC locates standard library modules (Naturals, Sequences, FiniteSets, …) by searching a
filesystem directory. The code responsible is `util.SimpleFilenameToStream`, which resolves
paths relative to what it calls the *installation base path*. It determines that path by calling
`Class.getProtectionDomain().getCodeSource().getLocation()` on itself and treating the result as
a filesystem URI.

When running on the JVM, that URI points to `tla2tools.jar` and everything works. Inside a
GraalVM native image the same call returns a `resource:/…` URI — a scheme that
`java.io.File` does not understand — so the path resolution silently fails and TLC cannot find
any standard module.

The standard library files **are** embedded in the native binary as resources (via
`-H:IncludeResources`), but they are embedded under a `resource:` URI that TLC's own path
resolution code is not equipped to handle.

The workaround is to extract the standard library files to a real directory on disk (done by the
build script with `unzip`) and tell TLC where they are via the `TLA-Library` Java system
property, which `SimpleFilenameToStream` checks as a fallback:

```sh
# What the wrapper does internally
exec ./tlc-native "-DTLA-Library=$(pwd)/tla2sany/StandardModules" "$@"
```

The wrapper injects that property automatically on every invocation, making the binary
*self-contained from the caller's perspective*: you just call `./tlc MySpec` and standard modules
are found without any additional setup.

### Distributing the build output

The three artifacts below must be kept together:

```
tlc-native                        ← compiled binary
tlc                               ← wrapper (regenerated by every build)
tla2sany/StandardModules/*.tla    ← standard library files on disk
```

The wrapper uses its own location to derive the library path, so the three can be moved
anywhere as a group and will continue to work.

---

## Re-running the tracing pass

The `graal-config/reachability-metadata.json` file committed in this repository was generated by
running TLC under the GraalVM native-image agent and records every reflection, resource, and JNI
access TLC makes at runtime. The build uses this file to know what to include in the native image.

You only need to re-run tracing if you update `tla2tools.jar` or encounter a
`MissingReflectionRegistrationError` / `ClassNotFoundException` at runtime:

```sh
# macOS: trace on JVM, then rebuild
./build-osx.sh --trace
./build-osx.sh

# Linux / Docker: trace then rebuild
./docker-build.sh --trace
./docker-build.sh
```

The trace merges into `graal-config/reachability-metadata.json` (existing entries are preserved).
Commit the updated file so future builds pick it up.
