# submitr (development version)

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
  
* `htc_download()` gains a `cluster_id` parameter and can now resolve
  files automatically from the job manifest. When called without `files`,
  it constructs the download list from metadata recorded by
  `htc_gen_submit()`, `htc_gen_executable()`, and `htc_submit()` during
  the normal workflow. Works for both single and multiple mode jobs.

* Job manifest system: `htc_gen_submit()`, `htc_gen_executable()`, and
  `htc_submit()` now record job metadata (mode, output files, subset
  names, cluster ID, remote path) in `htc-manifest.yaml`, written to the
  `path` directory alongside `htc.cfg`. `htc_upload()` and `htc_download()`
  read this manifest to determine which files to transfer.

* The job manifest is stored on disk rather than in a session option, so it
  survives an R restart. This matters for the case it was built for: a long
  job submitted in one session and collected in another. `htc_start()` no
  longer clears the manifest, since doing so destroyed exactly the state a
  restart needs.

* `htc_upload()` gains a `files = NULL` default. When `files` is omitted,
  the upload list is resolved from the job manifest -- the submit file, the
  executable script, any shared input files, and, in `"multiple"` mode,
  `subdatasets.csv` together with the individual subset data files. This
  closes the asymmetry with `htc_download()`, which already resolved its
  own file list.

* `htc_download()` gains a `remote_path = NULL` default, resolving in order
  of explicit argument, the `remote_path` recorded by `htc_submit()`, then
  `"~/"`. Previously the automatic mode assumed `"~/"` even when the job had
  been submitted from somewhere else.

* `htc_gen_submit()`, `htc_gen_executable()`, `htc_upload()`, `htc_submit()`,
  and `htc_download()` all gain a `path` argument naming the directory that
  holds `htc-manifest.yaml`. The generators default it to their `output`
  directory; the rest default to `"."`. Non-default directories must match
  across the five.

* `htc_config()` gains a `check_server` argument controlling whether it
  opens an SSH connection to report the server's reachability. It previously
  did so unconditionally, which meant that merely reading a config file
  required a network, and that scripts, test suites and `R CMD check` all
  paid for a probe with no one to read it. The argument defaults to the new
  `submitr.check_server` option, so it can be set once for a session or a
  CI job rather than passed at every call, and `htc_start()` accepts it
  through `...`.

* The option controlling `htc_config()`'s progress messages is renamed from
  `htc_config_verbose` to `submitr.verbose`, matching the namespacing of
  `submitr.config` and `submitr.check_server`. It was undocumented, so this
  is unlikely to affect anyone; both options are now documented under
  `?htc_config`.

### Bug fixes

* `htc_gen_executable()` now always writes `#!/bin/bash` as the first line of
  the generated script. With `comments = TRUE` the shebang section's
  explanatory comment was written ahead of it, putting `#!/bin/bash` on line
  two, where the kernel does not look for it. The script would then run under
  whatever shell happened to invoke it rather than the one it asked for. The
  section is now split so that the shebang carries no comment of its own and
  the comment sits with `set -euo pipefail`, which is what it was describing
  all along.

* `htc_status(watch = TRUE)` now decides when to stop polling by reading the
  job count from `condor_q`'s own `Total for query:` line, falling back to
  matching the cluster ID against the `JOB_IDS` column. It previously searched
  the whole report for the cluster ID as a substring, which could match the
  address or port in the schedd header, or a count in the `Total for all
  users:` line. Because that test drives the loop's exit, a false match did
  not give a wrong answer, it left the loop polling forever.

* `htc_submit()` now quotes `remote_path` and `submit_file` for the remote
  shell rather than typing quote characters around the assembled command. A
  filename or path containing a space or an apostrophe previously truncated
  the command at that character, producing a shell syntax error or, in the
  worst case, running the remainder as separate commands. A leading `~` is
  held outside the quoting so that the remote shell still expands it.

* Remote commands in `htc_submit()` and `htc_status()` are assembled with a
  single POSIX quoting idiom rather than `shQuote()`. This is not a fix for
  a known failure: `shQuote()` was checked and does escape a dollar sign
  when it switches to double quotes, so the previous arrangement held. It
  was, though, relying on a choice `shQuote()` makes from its own input and
  on a dialect that follows the platform R is running on, neither of which
  suits a command destined for the POSIX shell at the far end of an SSH
  connection and quoted twice on the way there. Quoting is now the same
  whatever the input and whatever the local platform.

* `htc_submit()` prints `condor_submit` output with `cat()` rather than
  passing it to `cli`, which treats braces in a message as inline markup and
  would try to evaluate anything an HTCondor message happened to wrap in
  them. Error details from both `htc_submit()` and `htc_status()` are escaped
  for the same reason. This also matches how `htc_status()` already printed
  `condor_q` output.

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
* `htc_gen_executable()` now changes to HTCondor's scratch directory
  (`cd "${_CONDOR_SCRATCH_DIR:-$PWD}"`) before any file operations, and reads
  the R script and data files by absolute path under `home_dir` (default
  `/home`), where `containr::generate_dockerfile()` baked them in. Outputs
  are therefore written where HTCondor looks for `transfer_output_files`,
  while inputs are read from where the image actually holds them.

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
