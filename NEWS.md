# submitr 0.1.0.9000

* Development version following initial release.

### New features

* `htc_start()` -- start an HTC session by reading the project config and
  storing it for the duration of the R session. Subsequent calls to
  `htc_upload()`, `htc_submit()`, `htc_status()`, and `htc_download()` use
  the stored config automatically when `config = NULL`, eliminating the need
  to pass `config = cfg` on every call. Call `options(submitr.config = NULL)`
  to clear the session manually, or let it expire when R restarts.

* `.resolve_config()` -- internal helper that checks for an explicit `config`
  argument, falls back to the session option set by `htc_start()`, and errors
  with instructions if neither is available. Used by all four system-facing
  functions.

* `htc_upload()` and `htc_download()` now print a success confirmation
  message unconditionally after a successful transfer, rather than only
  when `verbose = TRUE`.

### Bug fixes

* `htc_gen_submit()` now prepends `docker://` to `container_image` if the
  prefix is missing. Previously, omitting the prefix caused HTCondor to
  treat the image path as a local file.
* `htc_gen_submit()` now includes `should_transfer_files = YES` and
  `when_to_transfer_output = ON_EXIT` in the transfer section. These
  directives are required by HTCondor for the file transfer mechanism to
  work.
* `htc_gen_executable()` now includes `set -euo pipefail` after the shebang
  line, causing the script to exit immediately on errors instead of
  silently continuing.
* `htc_gen_executable()` now includes `cd /home` before any file operations,
  ensuring the script runs from the container's working directory where
  `containr::generate_dockerfile()` placed the baked-in files.

# submitr 0.1.0

## Initial release

`submitr` is the third package in the **From the Notebook to the Cluster**
family, alongside `toolero` and `containr`. It provides a workflow for
submitting containerized R analyses to the UW-Madison Center for High
Throughput Computing (CHTC) from inside R.

## New functions

### Connection management

* `htc_config()` -- create or read a project-level `htc.cfg` configuration
  file. On first use, prompts interactively for username and server, displays
  ControlMaster SSH setup guidance to reduce Duo MFA prompts, writes
  `htc.cfg`, and adds it to `.gitignore`. Subsequent calls read the existing
  file and validate server reachability. Returns a named list with `username`
  and `server`. Errors informatively when `username` or `server` are supplied
  as empty strings.

### Job scaffolding

* `htc_gen_submit()` -- generate an HTCondor `.sub` submit file from
  project parameters. Supports single-job and multiple-job modes. Multiple
  mode reads a manifest from `toolero::write_by_group(manifest = TRUE)`,
  extracts filenames, writes `subdatasets.csv`, and emits
  `queue file from subdatasets.csv`. Resource presets (`small`, `medium`,
  `large`, `custom`) are loaded at runtime from
  `inst/extdata/htc-resources.yaml`; a local `./htc-resources.yaml` takes
  precedence over the package default. GPU support via `gpu = TRUE` and
  `gpu_options`. `comments = TRUE` annotates each section of the generated
  file with explanatory text.

* `htc_gen_executable()` -- generate the `.sh` executable script that
  HTCondor runs inside the container. Produces a four-element script:
  shebang, `mkdir`, `Rscript`, and `tar`. In multiple-job mode, passes
  `${1}` as a positional argument to the R script. `r_script` must be
  supplied explicitly -- there is no default. `set_executable = TRUE`
  (default) sets executable permissions via `Sys.chmod()`.

### File transfer and job control

* `htc_upload()` -- copy files to the CHTC submit node via `scp`. Accepts
  single files, vectors of files, directories (transferred recursively),
  and glob patterns. `remote_path` defaults to `"~/"`. `dry_run = TRUE`
  previews the command without executing it.

* `htc_submit()` -- run `condor_submit` on the remote submit node via SSH
  from the remote directory where files were uploaded. Returns the cluster
  ID invisibly for use with `htc_status()`. Supports `dry_run = TRUE`.

* `htc_status()` -- check job progress via `condor_q`. Optionally filters
  by cluster ID. `watch = TRUE` polls at `interval` seconds (default 60)
  until the cluster ID leaves the queue. Returns `condor_q` output invisibly
  as a character vector. Supports `dry_run = TRUE`.

* `htc_download()` -- copy result files back from the submit node via `scp`.
  Supports single filenames, vectors of filenames, and glob patterns
  (`"*.tar.gz"`, `"job.*"`). Glob patterns are single-quoted to prevent
  local shell expansion. `local_path` defaults to `"."`.
  Supports `dry_run = TRUE`.

## Package infrastructure

* `inst/extdata/htc-resources.yaml` ships with the package and provides
  default resource presets for `htc_gen_submit()`.

* `inst/extdata/hello-world.sub` and `inst/extdata/hello-world.sh` included
  as test files for end-to-end workflow verification.

* `inst/extdata/sample.R` included as a sample R script for use in examples.

## Testing

The test suite uses a three-layer strategy to handle the fact that end-to-end
testing requires a live HTCondor environment and SSH access. Layer 1 covers
argument validation. Layer 2 covers command construction using `dry_run = TRUE`
and mocked bindings. Layer 3 integration tests are opt-in via
`Sys.setenv(CHTC_USERNAME = "your.netid")` and never run on CRAN or CI.
153 tests passing across seven test files.
