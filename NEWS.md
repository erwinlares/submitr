# submitr (development version)

# submitr 0.0.0.9000

## New functions

* `htc_config()` creates or reads `htc.cfg` in the project directory,
  managing the connection details passed to all system-facing functions.
  On first use it prompts interactively for username and server, displays
  ControlMaster SSH setup guidance to reduce Duo MFA prompts, writes
  `htc.cfg`, and adds it to `.gitignore`. Subsequent calls read the existing
  file and validate server reachability. Returns a named list with `username`
  and `server`.

* `htc_gen_submit()` writes a ready-to-use HTCondor submit file (`.sub`)
  for running a containerized R job. Supports single-job and multiple-job
  submission modes. Multiple mode reads a manifest from
  `toolero::write_by_group(manifest = TRUE)`, extracts filenames, writes
  `subdatasets.csv`, and emits `queue file from subdatasets.csv`. Resource
  presets (`"small"`, `"medium"`, `"large"`, `"custom"`) are loaded at
  runtime from `inst/extdata/htc-resources.yaml`. A local
  `./htc-resources.yaml` takes precedence over the package default. GPU
  support via `gpu = TRUE` and `gpu_options`. The `comments = TRUE` argument
  annotates each section with explanatory text.

* `htc_gen_executable()` writes the bash script (`.sh`) that HTCondor runs
  inside the container. Generates a four-element script: shebang, `mkdir`,
  `Rscript`, and `tar`. In multiple-job mode, passes `${1}` as a positional
  argument to the R script. `r_script` must be supplied explicitly — there
  is no default. `set_executable = TRUE` (default) sets executable
  permissions via `Sys.chmod()`.

* `htc_upload()` copies files from the local machine to the CHTC submit
  node via `scp`. Accepts a single file, a vector of files, or a directory
  path. Directories are transferred recursively. `remote_path` defaults to
  `"~/"`. Supports `dry_run = TRUE` to preview the `scp` command without
  executing it.

* `htc_submit()` connects to the CHTC submit node via SSH and runs
  `condor_submit` from the remote directory where files were uploaded.
  Returns the cluster ID invisibly so it can be passed directly to
  `htc_status()`. Supports `dry_run = TRUE`.

* `htc_status()` runs `condor_q` on the remote server to report job queue
  status. Optionally filters by cluster ID. When `watch = TRUE`, polls
  repeatedly at `interval` seconds (default 60) until the cluster ID
  disappears from the queue, signaling job completion. Returns `condor_q`
  output invisibly as a character vector. Supports `dry_run = TRUE`.

* `htc_download()` copies files from the CHTC submit node back to the local
  machine via `scp`. Accepts single filenames, vectors of filenames, and
  glob patterns (`"*.tar.gz"`, `"job.*"`). Glob patterns are single-quoted
  to prevent local shell expansion. `local_path` defaults to `"."`.
  Supports `dry_run = TRUE`.

## Bug fixes

* `htc_config()` now errors informatively when `username` or `server` are
  supplied as empty strings. Previously, empty strings passed validation
  silently and were written to `htc.cfg`.

* `htc_upload()` fixed a `cli` pluralization error in the missing-files
  error message. The `{?s}` pluralization token now receives the correct
  numeric quantity.

## Package infrastructure

* `inst/extdata/htc-resources.yaml` ships with the package and provides
  default resource presets for `htc_gen_submit()`.

* `inst/extdata/hello-world.sub` and `inst/extdata/hello-world.sh` are
  included as test files for end-to-end workflow verification.

* `inst/extdata/sample.R` included as a sample R script for use in examples.

* Three-layer testing strategy documented in `on-testing.md`: argument
  validation (Layer 1, always runs), command construction via `dry_run`
  and mocked `system2()` (Layer 2, always runs), and integration tests
  guarded by `CHTC_USERNAME` environment variable (Layer 3, local only).

* 153 tests passing across seven test files, 5 Layer 3 integration tests
  skipping as expected.
