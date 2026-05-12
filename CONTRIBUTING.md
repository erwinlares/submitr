# Contributing to submitr

Thank you for your interest in contributing to `submitr`. This document
covers how to set up for development, how the test suite is organized, and
what to expect from the review process.

---

## Development setup

`submitr` uses the standard R package development workflow:

```r
# Install development dependencies
install.packages(c("devtools", "testthat", "usethis"))

# Clone and open the project
usethis::create_from_github("erwinlares/submitr")

# Run the standard loop
devtools::document()
devtools::test()
devtools::check()
```

---

## Testing

`submitr` wraps system commands (`ssh`, `scp`, `condor_submit`, `condor_q`)
that cannot be tested end-to-end without SSH access to a CHTC submit node
and a live HTCondor environment. The test suite addresses this with a
three-layer strategy.

**Layer 1 -- Argument validation.** Pure R checks that bad arguments error
correctly and required arguments are enforced. These tests run on every
platform, including CRAN, with no external dependencies.

**Layer 2 -- Command construction.** Tests that the correct system command
is assembled from the supplied arguments. `dry_run = TRUE` causes functions
to print the command without running it. Mocked bindings intercept internal
system checks so these tests run without SSH, HTCondor, or a live submit
node.

**Layer 3 -- Integration.** Tests that call real system commands against a
live CHTC environment. These tests are guarded by the `CHTC_USERNAME`
environment variable. They run only when `CHTC_USERNAME` is set to a
non-empty value -- your CHTC NetID. They never run on CRAN or CI where
this variable is unset.

To run Layer 3 integration tests locally, set your CHTC NetID before
running the test suite:

```r
Sys.setenv(CHTC_USERNAME = "your.netid")
devtools::test()
```

Unset it afterward to return to the default skip behavior:

```r
Sys.unsetenv("CHTC_USERNAME")
```

Before running integration tests, confirm that:

- you have SSH access to a CHTC submit node such as `ap2002.chtc.wisc.edu`;
- ControlMaster is configured in `~/.ssh/config` to avoid repeated Duo MFA
  prompts (see `htc_config()` documentation for setup guidance);
- `htc_config()` can connect to the submit node without error.

---

## Code style

- Exported functions: `snake_case`
- Internal helpers: `.dot_prefix()`
- File names: `kebab-case.R`
- `cli` for all user-facing messages -- no bare `message()`, `warning()`,
  or `stop()` calls in exported functions
- Double hyphens (`--`) in cli messages rather than em dashes
- `dry_run = TRUE` must be supported on all functions that call system
  commands

---

## Submitting changes

1. Fork the repository and create a branch from `main`.
2. Make your changes and add tests for any new behavior.
3. Run `devtools::check()` and confirm 0 errors, 0 warnings, 0 notes.
4. Open a pull request with a clear description of what changed and why.

For significant changes, open an issue first to discuss the approach before
writing code.

---

## Reporting issues

Use the [GitHub issue tracker](https://github.com/erwinlares/submitr/issues).
Include a minimal reproducible example where possible, the output of
`sessionInfo()`, and the version of your SSH client and HTCondor installation
if the issue involves system command behavior.
