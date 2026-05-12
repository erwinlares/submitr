# Changelog

## submitr 0.1.0

### Initial release

`submitr` is the third package in the **From the Notebook to the
Cluster** family, alongside `toolero` and `containr`. It provides a
workflow for submitting containerized R analyses to the UW-Madison
Center for High Throughput Computing (CHTC) from inside R.

### New functions

#### Connection management

- [`htc_config()`](https://erwinlares.github.io/submitr/reference/htc_config.md)
  – create or read a project-level `htc.cfg` configuration file,
  validate SSH connectivity to a CHTC submit node, and display
  ControlMaster setup guidance on first use.

#### Job scaffolding

- [`htc_gen_submit()`](https://erwinlares.github.io/submitr/reference/htc_gen_submit.md)
  – generate an HTCondor `.sub` submit file from project parameters.
  Supports single-job and multiple-job modes. Resource presets (`small`,
  `medium`, `large`) cover the most common job sizes. `comments = TRUE`
  annotates each section of the generated file.

- [`htc_gen_executable()`](https://erwinlares.github.io/submitr/reference/htc_gen_executable.md)
  – generate the `.sh` executable script that HTCondor runs inside the
  container. Handles results directory creation, `Rscript` invocation,
  and result archiving. Supports single-job and multiple-job modes.

#### File transfer and job control

- [`htc_upload()`](https://erwinlares.github.io/submitr/reference/htc_upload.md)
  – copy files to the CHTC submit node via `scp`. Accepts single files,
  vectors of files, and glob patterns. `dry_run = TRUE` previews the
  command without executing it.

- [`htc_submit()`](https://erwinlares.github.io/submitr/reference/htc_submit.md)
  – run `condor_submit` on the remote submit node via SSH and return the
  cluster ID for use with
  [`htc_status()`](https://erwinlares.github.io/submitr/reference/htc_status.md).

- [`htc_status()`](https://erwinlares.github.io/submitr/reference/htc_status.md)
  – check job progress via `condor_q`. `watch = TRUE` polls until all
  jobs in the cluster leave the queue.

- [`htc_download()`](https://erwinlares.github.io/submitr/reference/htc_download.md)
  – copy result files back from the submit node via `scp`. Supports glob
  patterns such as `"*.tar.gz"` and `"job.*"`.

### Testing

The test suite uses a three-layer strategy to handle the fact that
end-to-end testing requires a live HTCondor environment and SSH access.
Layer 1 covers argument validation. Layer 2 covers command construction
using `dry_run = TRUE` and mocked bindings. Layer 3 covers integration
tests, which are opt-in via
`Sys.setenv(SUBMITR_INTEGRATION_TESTS = "true")` and never run on CRAN
or CI.

------------------------------------------------------------------------

## submitr 0.0.0.9000

### New functions

- [`htc_config()`](https://erwinlares.github.io/submitr/reference/htc_config.md)
  creates or reads `htc.cfg` in the project directory, managing the
  connection details passed to all system-facing functions. On first use
  it prompts interactively for username and server, displays
  ControlMaster SSH setup guidance to reduce Duo MFA prompts, writes
  `htc.cfg`, and adds it to `.gitignore`. Subsequent calls read the
  existing file and validate server reachability. Returns a named list
  with `username` and `server`.

- [`htc_gen_submit()`](https://erwinlares.github.io/submitr/reference/htc_gen_submit.md)
  writes a ready-to-use HTCondor submit file (`.sub`) for running a
  containerized R job. Supports single-job and multiple-job submission
  modes. Multiple mode reads a manifest from
  `toolero::write_by_group(manifest = TRUE)`, extracts filenames, writes
  `subdatasets.csv`, and emits `queue file from subdatasets.csv`.
  Resource presets (`"small"`, `"medium"`, `"large"`, `"custom"`) are
  loaded at runtime from `inst/extdata/htc-resources.yaml`. A local
  `./htc-resources.yaml` takes precedence over the package default. GPU
  support via `gpu = TRUE` and `gpu_options`. The `comments = TRUE`
  argument annotates each section with explanatory text.

- [`htc_gen_executable()`](https://erwinlares.github.io/submitr/reference/htc_gen_executable.md)
  writes the bash script (`.sh`) that HTCondor runs inside the
  container. Generates a four-element script: shebang, `mkdir`,
  `Rscript`, and `tar`. In multiple-job mode, passes `${1}` as a
  positional argument to the R script. `r_script` must be supplied
  explicitly – there is no default. `set_executable = TRUE` (default)
  sets executable permissions via
  [`Sys.chmod()`](https://rdrr.io/r/base/files2.html).

- [`htc_upload()`](https://erwinlares.github.io/submitr/reference/htc_upload.md)
  copies files from the local machine to the CHTC submit node via `scp`.
  Accepts a single file, a vector of files, or a directory path.
  Directories are transferred recursively. `remote_path` defaults to
  `"~/"`. Supports `dry_run = TRUE` to preview the `scp` command without
  executing it.

- [`htc_submit()`](https://erwinlares.github.io/submitr/reference/htc_submit.md)
  connects to the CHTC submit node via SSH and runs `condor_submit` from
  the remote directory where files were uploaded. Returns the cluster ID
  invisibly so it can be passed directly to
  [`htc_status()`](https://erwinlares.github.io/submitr/reference/htc_status.md).
  Supports `dry_run = TRUE`.

- [`htc_status()`](https://erwinlares.github.io/submitr/reference/htc_status.md)
  runs `condor_q` on the remote server to report job queue status.
  Optionally filters by cluster ID. When `watch = TRUE`, polls
  repeatedly at `interval` seconds (default 60) until the cluster ID
  disappears from the queue, signaling job completion. Returns
  `condor_q` output invisibly as a character vector. Supports
  `dry_run = TRUE`.

- [`htc_download()`](https://erwinlares.github.io/submitr/reference/htc_download.md)
  copies files from the CHTC submit node back to the local machine via
  `scp`. Accepts single filenames, vectors of filenames, and glob
  patterns (`"*.tar.gz"`, `"job.*"`). Glob patterns are single-quoted to
  prevent local shell expansion. `local_path` defaults to `"."`.
  Supports `dry_run = TRUE`.

### Bug fixes

- [`htc_config()`](https://erwinlares.github.io/submitr/reference/htc_config.md)
  now errors informatively when `username` or `server` are supplied as
  empty strings. Previously, empty strings passed validation silently
  and were written to `htc.cfg`.

- [`htc_upload()`](https://erwinlares.github.io/submitr/reference/htc_upload.md)
  fixed a `cli` pluralization error in the missing-files error message.
  The `{?s}` pluralization token now receives the correct numeric
  quantity.

### Package infrastructure

- `inst/extdata/htc-resources.yaml` ships with the package and provides
  default resource presets for
  [`htc_gen_submit()`](https://erwinlares.github.io/submitr/reference/htc_gen_submit.md).

- `inst/extdata/hello-world.sub` and `inst/extdata/hello-world.sh` are
  included as test files for end-to-end workflow verification.

- `inst/extdata/sample.R` included as a sample R script for use in
  examples.

- Three-layer testing strategy documented in `on-testing.md`: argument
  validation (Layer 1, always runs), command construction via `dry_run`
  and mocked [`system2()`](https://rdrr.io/r/base/system2.html) (Layer
  2, always runs), and integration tests guarded by `CHTC_USERNAME`
  environment variable (Layer 3, local only).

- 153 tests passing across seven test files, 5 Layer 3 integration tests
  skipping as expected.
