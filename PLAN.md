# submitr – Package Development Plan

## What is submitr?

`submitr` provides scaffolding tools to help researchers prepare and
submit computational jobs to high-throughput computing (HTC) schedulers.
The package guides users through generating the files required to run
containerized R analyses on HTCondor, including submit files and
executable scripts, and wraps the system commands needed to upload
files, submit jobs, monitor status, and retrieve results.

The package is explicitly HTC-first. HTCondor and CHTC are the initial
targets. HPC scheduler support (Slurm, PBS) is planned for a future
release.

The design mission is scaffolding and guidance, not just wrapping system
commands. Every function is written to help a researcher understand what
they are doing and why — the `comments` argument on generator functions
and the ControlMaster guidance in
[`htc_config()`](https://erwinlares.github.io/submitr/reference/htc_config.md)
reflect this directly.

The full workflow submitr supports:

    toolero::write_by_group()       -- split dataset into subsets + manifest
    toolero::create_qmd()           -- scaffold analysis.qmd
    knitr::purl()                   -- strip analysis.qmd to analysis.R
    containr::generate_dockerfile() -- generate Dockerfile
    containr::build_image()         -- build container image locally
    containr::list_images()         -- inspect local images, find image ID
    containr::push_image()          -- push container to registry
    submitr::htc_config()           -- configure HTC connection (htc.cfg)
    submitr::htc_gen_submit()       -- generate .sub file
    submitr::htc_gen_executable()   -- generate .sh file
    submitr::htc_upload()           -- copy files to CHTC submit node via scp
    submitr::htc_submit()           -- run condor_submit, returns cluster ID
    submitr::htc_status()           -- monitor via condor_q, optional watch loop
    submitr::htc_download()         -- retrieve results via scp, glob support

------------------------------------------------------------------------

## Package identity

- Name: submitr
- Standalone package, separate from containr and toolero
- CRAN target: yes
- HTCondor / CHTC first; HPC (Slurm, PBS) in a future release
- `containr` and `toolero` in `Suggests`, not `Imports`
- `yaml` in `Imports` for resource preset loading

------------------------------------------------------------------------

## Relationship to sibling packages

    toolero     -- research workflow toolkit (CRAN v0.3.0)
    containr    -- containerization toolkit (CRAN v0.1.3, dev v0.1.3.9000)
    curriculr   -- CV generation toolkit (CRAN v0.3.0 resubmission in progress)
    submitr     -- HTC job submission toolkit (dev v0.0.0.9000)

------------------------------------------------------------------------

## Naming conventions

- Exported functions: `htc_` prefix + descriptive verb phrase
- File names: kebab-case (`htc-gen-submit.R`, `htc-config.R`)
- Test files: mirror source files (`test-htc-gen-submit.R`)
- Internal helpers: dot prefix (`.htc_check_server()`,
  `.write_manifest()`)
- Future HPC functions: `hpc_` prefix
- Future scheduler-agnostic wrappers: no prefix
  (`gen_submit(scheduler = "htc")`)
- No `chtc_` prefix on anything — functions, files, or R objects

------------------------------------------------------------------------

## Completed: v0.0.0.9000

### `htc_config()`

Creates or reads `htc.cfg` in the project directory. On first use
prompts interactively for username and server, displays ControlMaster
SSH guidance, writes `htc.cfg`, adds it to `.gitignore`. Subsequent
calls read the existing file and validate server reachability. Returns a
named list with `username` and `server`.

Arguments: `username`, `server`, `path`, `overwrite`.

Config file format (YAML):

``` yaml
username: erwin.lares
server: ap2002.chtc.wisc.edu
```

### `htc_gen_submit()`

Generates an HTCondor `.sub` submit file. Supports single-job and
multiple-job submission modes. Multiple mode reads a manifest produced
by `toolero::write_by_group(manifest = TRUE)`, extracts bare filenames,
writes `subdatasets.csv`, and emits `queue file from subdatasets.csv`.

Resource presets loaded from `inst/extdata/htc-resources.yaml` at
runtime. A local `./htc-resources.yaml` takes precedence over the
package default. Preset name validation happens against
`names(resource_map)` from the YAML, not a hardcoded list.

Arguments: `output_file`, `container_image`, `executable`,
`input_files`, `output_files`, `mode`, `queue`, `queue_from`,
`resources`, `custom_resources`, `gpu`, `gpu_options`, `verbose`,
`comments`, `output`.

44 passing tests in `test-htc-gen-submit.R`.

### `htc_gen_executable()`

Generates an HTCondor executable bash script (`.sh`). The shebang line
(`#!/bin/bash`) is always the first line of the file — the permission
comment block follows only when `comments = TRUE`. `r_script` is
required with no default. `set_executable = TRUE` (default) sets
executable permissions via
[`Sys.chmod()`](https://rdrr.io/r/base/files2.html).

Arguments: `output_file`, `r_script`, `results_folder`, `mode`,
`set_executable`, `verbose`, `comments`, `output`.

25 passing tests in `test-htc-gen-executable.R`.

### `htc_upload()`

Copies files from the local machine to the CHTC submit node via `scp`.
Accepts a single file, a vector of files, or a directory path.
Directories are copied recursively. `remote_path` defaults to `"~/"`.

Arguments: `files`, `remote_path`, `config`, `dry_run`, `verbose`.

Confirmed working in live CHTC test on 2026-05-08.

### `htc_submit()`

Connects to the CHTC submit node via SSH and runs:
`cd remote_path && condor_submit submit_file`

The remote command is single-quoted to prevent local shell expansion of
`~/`. Parses and returns the cluster ID invisibly from `condor_submit`
output so it can be passed directly to
[`htc_status()`](https://erwinlares.github.io/submitr/reference/htc_status.md).

Arguments: `submit_file`, `remote_path`, `config`, `dry_run`, `verbose`.

Confirmed working in live CHTC test on 2026-05-08.

### `htc_status()`

Wraps `condor_q` over SSH. Optionally filters by cluster ID. When
`watch = TRUE`, polls repeatedly at `interval` seconds (default 60)
until the cluster ID disappears from the queue. Returns `condor_q`
output invisibly as a character vector.

Arguments: `cluster_id`, `config`, `watch`, `interval`, `dry_run`,
`verbose`.

Confirmed working in live CHTC test — watched cluster 6302877 complete
three jobs over four minutes.

### `htc_download()`

Copies files from the CHTC submit node back to the local machine via
`scp`. Supports single filenames, vectors of filenames, and glob
patterns (`"*.tar.gz"`, `"job.*"`). Globs are single-quoted to prevent
local shell expansion.

Arguments: `files`, `remote_path`, `local_path`, `config`, `dry_run`,
`verbose`.

Confirmed working in live CHTC test on 2026-05-08.

------------------------------------------------------------------------

## Source file organization

    R/
    +-- submitr-package.R         # package sentinel
    +-- htc-config.R              # htc_config()
    +-- htc-gen-submit.R          # htc_gen_submit()
    +-- htc-gen-executable.R      # htc_gen_executable()
    +-- htc-upload.R              # htc_upload()
    +-- htc-submit.R              # htc_submit()
    +-- htc-status.R              # htc_status()
    +-- htc-download.R            # htc_download()

    inst/extdata/
    +-- htc-resources.yaml        # default resource presets
    +-- hello-world.sub           # test submit file
    +-- hello-world.sh            # test executable script
    +-- sample.R                  # sample R script for examples

    tests/testthat/
    +-- test-htc-gen-submit.R     # 44 passing
    +-- test-htc-gen-executable.R # 25 passing
    +-- test-htc-config.R         # 14 passing
    +-- test-htc-upload.R         # 12 passing
    +-- test-htc-submit.R         # 11 passing
    +-- test-htc-status.R         # 10 passing
    +-- test-htc-download.R       # 17 passing

------------------------------------------------------------------------

## Resource presets

Stored in `inst/extdata/htc-resources.yaml`. Loaded at runtime by
[`htc_gen_submit()`](https://erwinlares.github.io/submitr/reference/htc_gen_submit.md).
A local `./htc-resources.yaml` in the project directory takes precedence
over the package default, allowing per-project customization.

Current defaults:

| preset | cpus | memory | disk |
|--------|------|--------|------|
| small  | 1    | 4GB    | 4GB  |
| medium | 4    | 16GB   | 15GB |
| large  | 8    | 64GB   | 32GB |

------------------------------------------------------------------------

## Testing strategy

See `on-testing.md` for the full three-layer strategy. Summary:

| Layer | What it tests        | Guard                   | Runs on CI |
|-------|----------------------|-------------------------|------------|
| 1     | Argument validation  | none                    | Yes        |
| 2     | Command construction | `dry_run`, mocks        | Yes        |
| 3     | End-to-end execution | `CHTC_USERNAME` env var | No         |

To run Layer 3 tests locally:

``` r

Sys.setenv(CHTC_USERNAME = "lares")
devtools::test()
Sys.unsetenv("CHTC_USERNAME")
```

153 tests passing, 5 Layer 3 integration tests skipping as expected. All
test files complete.

------------------------------------------------------------------------

## v0.2.0 roadmap

### `htc_compress()`

SSH into submit node, run `tar -czf archive.tar.gz files` on the remote
server, return the archive name for use with
[`htc_download()`](https://erwinlares.github.io/submitr/reference/htc_download.md).
Deferred because it requires two SSH operations and could leave debris
on the remote if something goes wrong mid-way.

### Staging file support

`osdf:///` and `file:///` syntax in
[`htc_gen_submit()`](https://erwinlares.github.io/submitr/reference/htc_gen_submit.md)
for input files over 1 GB that should live in `/staging` rather than
`/home`. Requires a `staging_files` argument on
[`htc_gen_submit()`](https://erwinlares.github.io/submitr/reference/htc_gen_submit.md)
and possibly a companion function for uploading to `/staging`.

### HPC scheduler support

`hpc_gen_submit()` and related functions for Slurm and PBS. Design
question: `scheduler` argument on existing functions, or separate
`hpc_*` family with a top-level dispatcher?

------------------------------------------------------------------------

## GitHub Actions

    .github/workflows/
    +-- R-CMD-check.yaml       # runs on every push and PR
    +-- pkgdown.yaml           # builds and deploys pkgdown site
    +-- test-coverage.yaml     # runs covr and uploads to Codecov

------------------------------------------------------------------------

## Open design questions

1.  When HPC support arrives, should the `htc_` functions gain a
    `scheduler` argument, or should parallel `hpc_*` functions be
    written separately and a top-level wrapper dispatch between them?

2.  Should
    [`htc_upload()`](https://erwinlares.github.io/submitr/reference/htc_upload.md)
    eventually support uploading directly to `/staging` via a
    `destination` argument (`"home"` or `"staging"`), or should a
    separate function handle that case?
