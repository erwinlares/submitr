# submitr (development version)

### Breaking changes

* `r_script` is no longer baked into the container image. `htc_gen_executable()`
  now runs it by bare relative name (e.g. `Rscript analysis.R`) rather than by
  an absolute, `home_dir`-prefixed path, because HTCondor's file transfer does
  not preserve subdirectories -- a script listed in `transfer_input_files`
  always lands flat in the scratch directory. The script now travels to the
  execute node as an uploaded job input file instead: list its basename in
  `input_files` when calling `htc_gen_submit()`, and `htc_upload()` will send
  it along with everything else. `htc_gen_submit()` now warns when `r_script`
  is known but its basename is missing from `input_files`. `data_files` are
  unaffected -- they remain baked into the image under `home_dir` and are
  still referenced by absolute path. This resolves a standing ambiguity
  (previously flagged as S-I4) where the documented `htc_upload()` workflow
  uploaded the analysis script as an input file that the executable script
  never actually read, because it was reading a baked-in copy instead. The
  practical benefit: editing the analysis script now only requires
  re-uploading and resubmitting, not a container rebuild and registry push.
  Existing calls that rely on the script being baked in under `home_dir` (for
  example, a Dockerfile built with `containr::generate_dockerfile(code_file =
  r_script)`) should drop that argument and add the script to `input_files`
  instead; see the updated vignettes.

* `htc_gen_executable()` and `htc_gen_submit()` now default `path = "."`
  rather than `path = output`. Previously, writing generated files to a
  non-default `output` directory silently moved the job manifest there too,
  while `htc_upload()`, `htc_submit()`, and `htc_download()` kept looking for
  it in the project root -- so tidying generated files into a subfolder (the
  exact organizational habit the family otherwise encourages) broke the
  pipeline the moment `output` and `path` diverged (previously flagged as
  S-I2). All five pipeline functions now share the same `"."` default, and
  the manifest's location is fully decoupled from `output`: pass `path`
  explicitly to every function in the pipeline if you want the manifest to
  travel with files written elsewhere.


## Bug fixes

* `htc_gen_submit()`'s and `htc_gen_executable()`'s `@examples` no longer
  write `htc-manifest.yaml` into the current working directory during
  `R CMD check`. Both functions' runnable examples set `output = tempdir()`
  but left `path` at its default -- harmless while `path` defaulted to
  `output`, but S-I2 decoupled the two arguments (`path` now always
  defaults to `"."`), and the examples were never updated to match. Every
  example that generates a submit file or executable script now passes a
  shared `tmp <- tempdir()` as both `output` and `path` (S22).

* `htc_upload()` now records the resolved `remote_path` in the job manifest
  after a successful (non-`dry_run`) upload, and `remote_path` defaults to
  `NULL`, resolving to that recorded value on a later call before falling
  back to `"~/"`. `htc_submit()` now reads the job manifest for its own
  defaults: `submit_file` and `remote_path` both default to `NULL` and
  resolve, in order, from an explicit argument, the value the manifest
  already holds, and finally the old hardcoded literal. `htc_status()` gains
  a `path` argument and resolves `cluster_id` from the manifest when omitted.
  Previously, `htc_submit()` did not consult the manifest at all and
  `htc_status()` neither read nor wrote it, so any deviation from the default
  filenames or paths (previously flagged as S-I1) -- for instance, uploading
  to a non-default `remote_path` -- broke `htc_submit()` silently, and the
  cluster ID `htc_submit()` had just printed had to be retyped by hand for
  every `htc_status()` call.

### New features

* `htc_cancel()` and `htc_release()` -- cancel a submitted cluster with
  `condor_rm`, or release jobs held by HTCondor back into the queue with
  `condor_release` (S-G2). Both resolve `cluster_id` from the job manifest
  when not supplied, but -- unlike `htc_status()` -- refuse to proceed when
  no `cluster_id` can be resolved, rather than falling back to acting on
  every job in the queue: canceling or releasing everything is a much more
  consequential default than merely showing everything. `htc_cancel()`
  additionally accepts a `reason` argument recorded against the removed
  jobs. Both support `dry_run` and `verbose`.

* `htc_status()` gains a `show_hold_reason` argument (default `TRUE`). When
  any held jobs are present, it now automatically runs a follow-up
  `condor_q -hold` query and prints the hold reason, so diagnosing a held
  job no longer requires leaving R to run `condor_q -hold` by hand. Set
  `show_hold_reason = FALSE` to skip the extra query.

* `htc_check()` -- a preflight check that catches, locally and in seconds,
  several problems that would otherwise only surface an hour later as a
  held or failed job on the cluster (S-G4): a missing input or data file, a
  `"multiple"`-mode job whose subset files no longer match
  `subdatasets.csv`, an implausible resource request, and a `container_image`
  tagged `latest` (or carrying no tag at all). When a container tool
  (`podman` or `docker`) is available locally, it also makes a best-effort
  attempt to confirm the image is pullable. Every argument resolves from the
  job manifest, so the common case is `htc_check()` with no arguments,
  run after the generators and before `htc_upload()`. Returns a tibble of
  issues (possibly zero rows), each tagged `"error"` or `"warning"`.

* `htc_upload()` gains a `check` argument (default `FALSE`). When `TRUE`, it
  runs `htc_check()` before uploading and aborts if any `"error"`-level
  issue is found; `"warning"`-level issues are reported but do not block
  the upload.

* `htc_collect()` -- stitch the tarballs from one or more completed jobs
  back into a single tibble (S-G1), the HTC-side counterpart to
  `toolero::run_by_group()`'s local return value. Resolves the tarballs to
  collect from the job manifest (or accepts an explicit named
  `tarballs` vector), extracts each into its own subdirectory, and reads the
  `project-manifest.json` that `toolero::generate_manifest()` writes inside
  each one (falling back to `accumulator.csv` with a warning) to assemble a
  combined tibble carrying a `group_id` column for `"multiple"`-mode jobs.
  Deliberately does not attempt to load the saved R objects themselves,
  since their type varies by analysis -- it returns metadata plus a
  `local_path` column so you can read each one yourself.

* `htc_ssh_setup()` -- write the ControlMaster block described in
  `htc_config()`'s own setup guidance to `~/.ssh/config`, and create the
  connections directory it references, without leaving R (S-G3). Leaves the
  file untouched if a matching `Host` block already exists. Supports
  `dry_run = TRUE` to preview the change first.

* `htc_gen_submit()`'s `executable` argument and `htc_gen_executable()`'s
  `output_file` argument now default to the `executable_file` the other
  generator already recorded in the job manifest (S-I3), so the executable
  script's name only has to be typed once regardless of which of the two
  generators is called first. If an explicit value disagrees with the one
  already recorded, both warn rather than silently preferring one over the
  other -- the explicit value is still used.

* `htc_gen_submit()` and `htc_gen_executable()` gain a `config` argument (a
  named list as returned by `htc_config()`). When `config` was built with
  `project_config` set, `htc_gen_submit()`'s `queue_from` defaults to
  `file.path(config$project$conventions$split_dir, "manifest.csv")` and
  `htc_gen_executable()`'s `results_folder` defaults to
  `config$project$conventions$output_dir` (S-G5) -- the `_toolero.yml` hook
  `htc_config(project_config = )` has parsed since Phase 3, previously
  unused by anything in `submitr`. Both remain fully optional: everything
  can still be passed explicitly.

# submitr 0.1.0.9000

* Development version following initial release.

### Breaking changes

* The results folder written by `htc_gen_executable()` is now `output/`
  rather than `results/`, matching the folder convention used across
  `toolero` and `containr`. Analysis scripts that write to `results/` will
  produce an empty tarball until they are updated; `toolero::save_output()`
  handles this for you.

* Results tarballs are named `<script stem>[-<subset stem>]-results.tar.gz`,
  with directories and extensions stripped from both stems. A single job
  running `analysis.R` now produces `analysis-results.tar.gz` as before, but
  a multiple-mode job over `adelie.csv` produces
  `analysis-adelie-results.tar.gz` where it previously produced
  `adelie.csv-results.tar.gz`. This is a clean break: a job submitted with an
  earlier version and collected with this one will have `htc_download()`
  looking for names that do not exist on the submit node. Download those
  results before upgrading, or pass `files` explicitly. See the README
  section "A note on the results naming change" for the rationale.

* `htc_gen_submit()` gains an `r_script` argument, positioned after
  `executable`. It is used only to derive the default `output_files` name,
  which has to match the tarball `htc_gen_executable()` tells the job to
  build. The function never reads the executable script or the Dockerfile,
  so the script's name cannot be inferred and has to be supplied. In
  multiple mode, omitting it now warns. Code calling `htc_gen_submit()` with
  positional arguments past `executable` will need updating.

* Single-mode submit files now carry a `transfer_output_files` line derived
  from `r_script`, where previously they carried only a placeholder comment
  unless `output_files` was supplied. This is what makes `htc_download()`
  bring back the results tarball in single mode rather than log files alone.

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

* `htc_config()` gains a `project_config` argument. Pass the path to a
  `_toolero.yml` file (the resolved project configuration
  `toolero::init_project()` writes to a project's root) and its `folders`
  and `conventions` sections are parsed once and folded into the returned
  list as `config$project$folders` and `config$project$conventions`, kept
  separate from the connection details `config` has always held. Never
  written into `htc.cfg` on disk. `containr::generate_dockerfile()` already
  reads the same file through its own `config` argument.

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

### Testing

* New `tests/testthat/test-readme-workflow.R`, a documentation-regression
  suite rather than a code-correctness one. It reproduces the documented
  code blocks in `README.md` (the first workflow, scaling to many jobs)
  using their literal argument values in a temporary directory, and checks
  the result against claims made elsewhere in the README: the job manifest's
  example YAML, the resource preset table, the results-naming table, and
  the quick function reference. It exists because the README silently went
  stale once already (S20) after Phase 4 changed the output folder and the
  tarball naming convention.

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
