# submitr (development version)

## Breaking changes

* The results folder written by `htc_gen_executable()` is now `output/`
  rather than `results/`, matching the folder convention used across
  `toolero` and `containr`. Analysis scripts that write to `results/` will
  produce an empty tarball until they are updated; `toolero::save_output()`
  handles this for you.

* Results tarballs are named `<script stem>[-<subset stem>]-results.tar.gz`,
  with directories and extensions stripped from both stems. A single job
  running `analysis.R` still produces `analysis-results.tar.gz`, and
  `r_script = "R/analysis.R"` now does too, but a multiple-mode job over
  `adelie.csv` produces `analysis-adelie-results.tar.gz` where it previously
  produced `adelie.csv-results.tar.gz`. This is a clean break: a job
  submitted with 0.1.0 and collected with this version will have
  `htc_download()` looking for names that do not exist on the submit node.
  Download those results before upgrading, or pass `files` explicitly. See
  the README section "A note on the results naming change" for the
  rationale.

* `htc_gen_submit()` gains an `r_script` argument, positioned after
  `executable`. It is used to derive the default `output_files` name, which
  has to match the tarball `htc_gen_executable()` tells the job to build,
  and to check that the script is among the uploaded inputs (see below).
  The function never reads the executable script or the Dockerfile, so the
  script's name cannot be inferred and has to be supplied. In multiple
  mode, omitting it warns. Code calling `htc_gen_submit()` with positional
  arguments past `executable` will need updating.

* Single-mode submit files now carry a `transfer_output_files` line derived
  from `r_script`, where previously they carried only a placeholder comment
  unless `output_files` was supplied. This is what makes `htc_download()`
  bring back the results tarball in single mode rather than log files
  alone.

* The analysis script now travels to the execute node as an uploaded job
  input rather than being baked into the container image.
  `htc_gen_executable()` runs it by bare name (e.g. `Rscript analysis.R`)
  rather than by an absolute, `home_dir`-prefixed path, because HTCondor's
  file transfer does not preserve subdirectories: a script listed in
  `transfer_input_files` always lands flat in the scratch directory. List
  the script in `input_files` when calling `htc_gen_submit()`, and
  `htc_upload()` sends it along with everything else; `htc_gen_submit()`
  warns when `r_script` is known but its basename is missing from
  `input_files`. `data_files` are unaffected: they remain baked
  into the image under `home_dir` and are still read by absolute path.
  The practical benefit is that editing the analysis script now requires
  only re-uploading and resubmitting, not a container rebuild and registry
  push. A Dockerfile built with
  `containr::generate_dockerfile(code_file = r_script)` should drop that
  argument and add the script to `input_files` instead; see the updated
  vignettes.

* The option controlling `htc_config()`'s progress messages is renamed from
  `htc_config_verbose` to `submitr.verbose`, matching the namespacing of
  `submitr.config` and `submitr.check_server`. It was undocumented, so this
  is unlikely to affect anyone; both options are now documented under
  `?htc_config`.

* The resource presets file is now `htc-resources.yml`, following the
  family-wide rule (toolero's `CONVENTIONS.md`, section 8) that every YAML
  file a family package names for itself ends in `.yml`. The copy shipped in
  `inst/extdata/` is renamed. A project's own `htc-resources.yaml`, as
  submitr 0.1.0 documented it, is still read for this release, with a
  warning asking for it to be renamed; the old name will stop being read in
  the next release. When both names are present, `htc-resources.yml` is
  used and the old file is ignored, also with a warning.

## New features

* `htc_start()` starts an HTC session by reading the project's `htc.cfg`
  and storing it for the rest of the R session. `htc_upload()`,
  `htc_submit()`, `htc_status()`, and `htc_download()` then use the stored
  config automatically when `config = NULL`, so `config = cfg` no longer
  has to be passed on every call. Each of them checks for an explicit
  `config` first, falls back to the session, and errors with instructions
  if neither is available. Call `options(submitr.config = NULL)` to clear
  the session manually, or let it expire when R restarts.

* `htc_config()` gains a `project_config` argument. Pass the path to a
  `_toolero.yml` file (the project config `toolero::init_project()` writes
  to a project's root) and its `folders` and `conventions` sections are
  parsed once and folded into the returned list as `config$project$folders`
  and `config$project$conventions`, kept separate from the connection
  details `config` has always held and never written into `htc.cfg`.
  `containr::generate_dockerfile()` reads the same file through its own
  `config` argument.

* `htc_config()` gains a `check_server` argument controlling whether it
  opens an SSH connection to report the server's reachability. It
  previously did so unconditionally, which meant that merely reading a
  config file required a network, and that scripts, test suites, and
  `R CMD check` all paid for a probe with no one to read it. The argument
  defaults to the new `submitr.check_server` option, so it can be set once
  for a session or a CI job rather than passed at every call, and
  `htc_start()` accepts it through `...`.

* `htc_ssh_setup()` writes the ControlMaster block described in
  `htc_config()`'s setup guidance to `~/.ssh/config`, and creates the
  connections directory it references, without leaving R. It leaves the
  file untouched if a matching `Host` block already exists, and supports
  `dry_run = TRUE` to preview the change first.

* submitr now keeps a *submission state* file, `htc-manifest.yml`, in the
  project root beside `htc.cfg`. `htc_gen_submit()`, `htc_gen_executable()`,
  `htc_upload()`, and `htc_submit()` record what they know as they run (mode,
  submit and executable file names, input and output files, subset names,
  remote path, cluster ID), and every later step reads it back for its
  defaults, so values typed once flow through the rest of the workflow. The
  file lives on disk rather than in a session option, so it survives an R
  restart: a long job can be submitted in one session and collected in
  another. Every function that reads or writes it takes a `path` argument
  naming the directory that holds it, defaulting to `"."`. The generators'
  `path` is independent of their `output` argument, so generated job files
  can be written to a subfolder while the submission state stays in the
  project root; to keep it elsewhere, pass the same `path` to every call.
  Development versions before 0.2.0 wrote the file as `htc-manifest.yaml`.
  It is now `htc-manifest.yml`, following the family's `.yml` rule, with no
  fallback to the old name since no release ever wrote it: in a project set
  up with a development version, rename the file or regenerate the job
  files.

* `htc_gen_submit()` and `htc_gen_executable()` gain a `config` argument (a
  named list as returned by `htc_config()`). When `config` was built with
  `project_config`, `htc_gen_submit()`'s `queue_from` defaults to
  `file.path(config$project$conventions$split_dir, "manifest.csv")` and
  `htc_gen_executable()`'s `results_folder` defaults to
  `config$project$conventions$output_dir`. Both remain fully optional:
  everything can still be passed explicitly.

* `htc_gen_submit()`'s `executable` argument and `htc_gen_executable()`'s
  `output_file` argument default to the executable name the other generator
  already recorded in the submission state, so the name only has to be
  typed once, whichever generator runs first. If an explicit value
  disagrees with the recorded one, both functions warn rather than silently
  preferring one over the other; the explicit value is still used.

* `htc_check()` is a preflight check that catches, locally and in seconds,
  problems that would otherwise surface an hour later as a held or failed
  job on the cluster: a missing input or data file, a `"multiple"`-mode job
  whose subset files no longer match `subdatasets.csv`, an implausible
  resource request, and a `container_image` tagged `latest` (or carrying no
  tag at all). When `podman` or `docker` is available locally, it also
  makes a best-effort attempt to confirm the image is pullable;
  `check_image = FALSE` skips that probe, which contacts the registry.
  Every other argument resolves from the submission state, so the common
  case is `htc_check()` with no arguments, run after the generators and
  before `htc_upload()`. Returns a tibble of issues (possibly zero rows), each
  tagged `"error"` or `"warning"`.

* `htc_upload()` gains a `files = NULL` default. When `files` is omitted,
  the upload list is resolved from the submission state: the submit file,
  the executable script, any shared input files, and, in `"multiple"` mode,
  `subdatasets.csv` together with the individual subset files.
  `remote_path` also defaults to `NULL`, resolving from an explicit
  argument, then the value already recorded, then `"~/"`, and is recorded
  after a successful (non-`dry_run`) upload.

* `htc_upload()` gains a `check` argument (default `FALSE`). When `TRUE`, it
  runs `htc_check()` before uploading and aborts if any `"error"`-level
  issue is found; `"warning"`-level issues are reported but do not block
  the upload.

* `htc_submit()` reads the submission state for its own defaults.
  `submit_file` and `remote_path` both default to `NULL` and resolve, in
  order, from an explicit argument, the recorded value, and finally the old
  hardcoded literal, so uploading to a non-default `remote_path` no longer
  breaks the submit step. The cluster ID it prints is recorded for the
  functions that follow.

* `htc_status()` gains a `path` argument and resolves `cluster_id` from the
  submission state when omitted, so the cluster ID `htc_submit()` just
  printed no longer has to be retyped.

* `htc_status()` gains a `show_hold_reason` argument (default `TRUE`). When
  any held jobs are present, it automatically runs a follow-up
  `condor_q -hold` query and prints the hold reason, so diagnosing a held
  job no longer means leaving R. Set `show_hold_reason = FALSE` to skip the
  extra query.

* `htc_cancel()` and `htc_release()` cancel a submitted cluster with
  `condor_rm`, or release jobs HTCondor has held back into the queue with
  `condor_release`. Both resolve `cluster_id` from the submission state
  when not supplied but, unlike `htc_status()`, refuse to proceed when no
  `cluster_id` can be resolved rather than acting on every job in the
  queue: canceling or releasing everything is a much more consequential
  default than merely showing everything. `htc_cancel()` also accepts a
  `reason` recorded against the removed jobs. Both support `dry_run` and
  `verbose`.

* `htc_download()` gains a `cluster_id` argument and a `files = NULL`
  default. When `files` is omitted, it builds the download list from what
  `htc_gen_submit()`, `htc_gen_executable()`, and `htc_submit()` recorded,
  for both single and multiple mode. `remote_path` defaults to `NULL`,
  resolving from an explicit argument, then the value recorded in the
  submission state, then `"~/"`; previously it assumed `"~/"` even when the
  job had been submitted from somewhere else.

* `htc_collect()` unpacks the results tarballs `htc_download()` brought back,
  one subfolder per job, and returns the *job index*: a tibble with one row
  per job giving its group, HTCondor process and cluster numbers, whether
  its tarball was extracted, how many files its results folder holds and
  what they are (a list column of paths relative to `output_dir`), whether
  it includes an output record, the paths to its `.log`, `.err`, and `.out`
  files, and the container image it ran in. It resolves the tarballs from
  the submission state, or accepts an explicit named `tarballs` vector. It
  works for any analysis, whatever the script wrote, and never opens the
  files themselves: the output record (`project-manifest.json`) is only
  checked for, not read, since interpreting it is `toolero`'s job. A job
  whose tarball is missing or will not extract still gets a row, with
  `extracted = FALSE`, and one warning covers all such jobs, so a failed job
  no longer stops the collection. An existing extraction folder is an error
  raised before anything is extracted, unless `overwrite = TRUE`.

## Minor improvements

* `htc_upload()` and `htc_download()` print a success confirmation after
  every successful transfer, rather than only when `verbose = TRUE`.

* Remote commands in `htc_submit()` and `htc_status()` are assembled with a
  single POSIX quoting idiom rather than `shQuote()`. This does not fix a
  known failure: `shQuote()` does escape a dollar sign when it switches to
  double quotes, so the previous arrangement held. But it relied on a
  choice `shQuote()` makes from its own input, and on a dialect that follows
  the local platform, neither of which suits a command bound for the POSIX
  shell at the far end of an SSH connection and quoted twice on the way.
  Quoting is now the same whatever the input and whatever the local
  platform.

## Bug fixes

* `htc_gen_submit()` lists input files by basename in
  `transfer_input_files`. `htc_upload()` sends every file flat into one
  directory on the submit node, so `input_files = "R/analysis.R"` put a
  path in the submit file that did not exist there, and the job failed
  before it started. The submission state still records the paths as
  given, which is how `htc_upload()` finds the files on this machine. Two
  input files that share a basename (`R/utils.R` and `scripts/utils.R`)
  would overwrite each other on the submit node, so they are now an error,
  raised before anything is written.

* The script `htc_gen_executable()` writes now packs the results folder
  even when the R script fails, and then exits with R's own exit status.
  Previously `set -euo pipefail` stopped the script at the failing
  `Rscript` line, so no tarball was built: whatever the analysis had
  written was lost, and HTCondor held the job for a missing
  `transfer_output_files` entry rather than letting it finish. A failed job
  now returns its partial results and is reported by HTCondor as failed,
  not held.

* `htc_gen_executable()` always writes `#!/bin/bash` as the first line of
  the generated script. With `comments = TRUE`, the shebang section's
  explanatory comment was written ahead of it, putting `#!/bin/bash` on
  line two, where the kernel does not look for it, so the script ran under
  whatever shell happened to invoke it. The shebang now carries no comment
  of its own, and the comment sits with `set -euo pipefail`, which is what
  it was describing all along.

* `htc_gen_executable()` includes `set -euo pipefail` after the shebang, so
  the script exits on the first error instead of silently continuing.

* `htc_gen_executable()` changes to HTCondor's scratch directory
  (`cd "${_CONDOR_SCRATCH_DIR:-$PWD}"`) before any file operations, and
  reads baked-in data files by absolute path under `home_dir` (default
  `/home`), where `containr::generate_dockerfile()` put them. Outputs are
  therefore written where HTCondor looks for `transfer_output_files`, while
  data is read from where the image actually holds it.

* `htc_gen_submit()` prepends `docker://` to `container_image` when the
  prefix is missing. Previously, omitting it caused HTCondor to treat the
  image as a local file.

* `htc_gen_submit()` includes `should_transfer_files = YES` and
  `when_to_transfer_output = ON_EXIT` in the transfer section. HTCondor
  requires both for its file transfer mechanism to work.

* `htc_status(watch = TRUE)` decides when to stop polling by reading the job
  count from `condor_q`'s own `Total for query:` line, falling back to
  matching the cluster ID against the `JOB_IDS` column. It previously
  searched the whole report for the cluster ID as a substring, which could
  match the address or port in the schedd header, or a count in the
  `Total for all users:` line. Because that test drives the loop's exit, a
  false match did not give a wrong answer; it left the loop polling
  forever.

* `htc_submit()` quotes `remote_path` and `submit_file` for the remote shell
  rather than typing quote characters around the assembled command. A
  filename or path containing a space or an apostrophe previously truncated
  the command at that character, producing a shell syntax error or, in the
  worst case, running the remainder as separate commands. A leading `~` is
  held outside the quoting so the remote shell still expands it.

* `htc_submit()` prints `condor_submit` output with `cat()` rather than
  passing it to `cli`, which treats braces as inline markup and would try
  to evaluate anything an HTCondor message happened to wrap in them. Error
  details from `htc_submit()` and `htc_status()` are escaped for the same
  reason. This matches how `htc_status()` already printed `condor_q`
  output.

## Documentation

* Documentation, vignettes, and user-facing messages now use the family's
  shared vocabulary (see toolero's `CONVENTIONS.md`). `htc-manifest.yml`
  is the *submission state* and `manifest.csv` from
  `toolero::write_by_group()` is the *job manifest*. Earlier development
  versions called the submission state the "job manifest", which collided
  with the toolero file of the same name. Messages across the package now
  say "submission state" wherever they mean `htc-manifest.yml` and "job
  manifest" only when they mean `manifest.csv`. Function names and
  arguments are unchanged.

## Testing

* New `tests/testthat/test-readme-workflow.R`, a documentation-regression
  suite rather than a code-correctness one. It reproduces the documented
  code blocks in `README.md` (the first workflow, scaling to many jobs)
  with their literal argument values in a temporary directory, and checks
  the result against claims made elsewhere in the README: the submission
  state's example YAML, the resource preset table, the results-naming
  table, and the quick function reference. It exists because the README
  has already gone stale once, after the output folder and the tarball
  naming convention changed.

# submitr 0.1.0

`submitr` is the third package in the **From the Notebook to the Cluster**
family, alongside `toolero` and `containr`. It provides a workflow for
submitting containerized R analyses to the UW-Madison Center for High
Throughput Computing (CHTC) from inside R.

## Connection management

* `htc_config()` -- create or read a project-level `htc.cfg` configuration
  file. On first use, prompts interactively for username and server,
  displays ControlMaster SSH setup guidance to reduce Duo MFA prompts,
  writes `htc.cfg`, and adds it to `.gitignore`. Subsequent calls read the
  existing file and validate server reachability. Returns a named list with
  `username` and `server`. Errors informatively when `username` or `server`
  are supplied as empty strings.

## Job scaffolding

* `htc_gen_submit()` -- generate an HTCondor `.sub` submit file from
  project parameters. Supports single-job and multiple-job modes. Multiple
  mode reads the job manifest from `toolero::write_by_group(manifest = TRUE)`,
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

## File transfer and job control

* `htc_upload()` -- copy files to the CHTC submit node via `scp`. Accepts
  single files, vectors of files, directories (transferred recursively),
  and glob patterns. `remote_path` defaults to `"~/"`. `dry_run = TRUE`
  previews the command without executing it.

* `htc_submit()` -- run `condor_submit` on the remote submit node via SSH
  from the remote directory where files were uploaded. Returns the cluster
  ID invisibly for use with `htc_status()`. Supports `dry_run = TRUE`.

* `htc_status()` -- check job progress via `condor_q`. Optionally filters
  by cluster ID. `watch = TRUE` polls at `interval` seconds (default 60)
  until the cluster ID leaves the queue. Returns `condor_q` output
  invisibly as a character vector. Supports `dry_run = TRUE`.

* `htc_download()` -- copy result files back from the submit node via
  `scp`. Supports single filenames, vectors of filenames, and glob patterns
  (`"*.tar.gz"`, `"job.*"`). Glob patterns are single-quoted to prevent
  local shell expansion. `local_path` defaults to `"."`. Supports
  `dry_run = TRUE`.

## Package infrastructure

* `inst/extdata/htc-resources.yaml` ships with the package and provides
  default resource presets for `htc_gen_submit()`.

* `inst/extdata/hello-world.sub` and `inst/extdata/hello-world.sh` are
  included as test files for end-to-end workflow verification.

* `inst/extdata/sample.R` is included as a sample R script for use in
  examples.

## Testing

* The test suite uses a three-layer strategy to handle the fact that
  end-to-end testing requires a live HTCondor environment and SSH access.
  Layer 1 covers argument validation. Layer 2 covers command construction
  using `dry_run = TRUE` and mocked bindings. Layer 3 integration tests are
  opt-in via `Sys.setenv(CHTC_USERNAME = "your.netid")` and never run on
  CRAN or CI. 153 tests passing across seven test files.
