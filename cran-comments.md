# CRAN submission comments -- submitr 0.1.0

## New submission

This is a new submission. submitr is not currently on CRAN.

## System commands

This package wraps system commands (`ssh`, `scp`, `condor_submit`, `condor_q`)
to interact with CHTC (UW-Madison's high-throughput computing infrastructure)
and HTCondor job schedulers. These commands are called via `system2()` and are
necessary because no R-native interface exists for HTCondor job submission or
SSH-based file transfer.

All functions that invoke system commands accept a `dry_run = TRUE` argument
that prints the command that would be executed without running it. This allows
testing and documentation without requiring a live compute environment.

The package checks for the availability of required system tools before
attempting to call them and errors with informative messages if they are not
found.

## Test environments

- macOS aarch64 (local), R 4.x.x        [update before submission]
- GitHub Actions: macOS-latest (release)
- GitHub Actions: windows-latest (release)
- GitHub Actions: ubuntu-latest (devel)
- GitHub Actions: ubuntu-latest (release)
- GitHub Actions: ubuntu-latest (oldrel-1)
- win-builder: R-devel                   [run before submission]

## Test strategy

The test suite uses a three-layer strategy to handle the fact that end-to-end
testing requires a live HTCondor environment, SSH access to a submit node, and
a running container daemon -- none of which are available on CRAN or CI.

Layer 1 -- Argument validation: pure R checks that bad arguments error
correctly and required arguments are enforced. These tests run on every
platform including CRAN with no external dependencies.

Layer 2 -- Command construction: tests that the correct system command is
assembled from the supplied arguments. `dry_run = TRUE` causes functions to
return the command string without executing it. Mocked bindings intercept
internal system checks so these tests run without SSH, Podman, Docker, or
HTCondor installed.

Layer 3 -- Integration: tests that call real system commands against a live
environment. These are guarded behind an explicit opt-in environment variable:

    Sys.setenv(CHTC_USERNAME = "your.netid")

Integration tests are guarded by the CHTC_USERNAME environment variable.
They run only when CHTC_USERNAME is set to a non-empty value (the developer's
NetID). They never run on CRAN or CI where this variable is unset.

## R CMD check results

0 errors | 0 warnings | 0 notes

## Examples

All examples that require SSH access to a CHTC submit node, a running
container daemon, or a live HTCondor environment are wrapped in \dontrun{}.
The `dry_run = TRUE` argument is demonstrated in examples where applicable to
show expected behavior without requiring external infrastructure.

## Downstream dependencies

There are no reverse dependencies on CRAN.
