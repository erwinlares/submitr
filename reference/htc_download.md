# Download files from an HTC submit node

`htc_download()` copies one or more files from a directory on an HTC
submit node to a local directory via `scp`. It is the final step in the
job submission workflow – called after
[`htc_status()`](https://erwinlares.github.io/submitr/reference/htc_status.md)
confirms all jobs have completed.

## Usage

``` r
htc_download(
  files = NULL,
  cluster_id = NULL,
  remote_path = "~/",
  local_path = ".",
  config = NULL,
  dry_run = FALSE,
  verbose = FALSE
)
```

## Arguments

- files:

  A character vector or `NULL`. One or more filenames or glob patterns
  to download from `remote_path` on the submit node. Examples:
  `"results.tar.gz"`, `c("job.log", "job.err")`, `"*.tar.gz"`. When
  `NULL`, the function uses `cluster_id` and the job manifest to
  determine which files to download. Defaults to `NULL`.

- cluster_id:

  A character string or `NULL`. The cluster ID returned by
  [`htc_submit()`](https://erwinlares.github.io/submitr/reference/htc_submit.md).
  When supplied without `files`, the function constructs the file list
  from the job manifest. When `NULL`, falls back to the most recently
  submitted cluster ID stored in the manifest. Defaults to `NULL`.

- remote_path:

  A character string. The directory on the submit node where the files
  are located. Defaults to `"~/"`. Should match the `remote_path` used
  in
  [`htc_upload()`](https://erwinlares.github.io/submitr/reference/htc_upload.md)
  and
  [`htc_submit()`](https://erwinlares.github.io/submitr/reference/htc_submit.md).

- local_path:

  A character string. The local directory where downloaded files will be
  saved. Defaults to `"."` (current working directory).

- config:

  A named list as returned by
  [`htc_config()`](https://erwinlares.github.io/submitr/reference/htc_config.md).
  Must contain `username` and `server`. If `NULL` (the default), uses
  the session config set by
  [`htc_start()`](https://erwinlares.github.io/submitr/reference/htc_start.md).
  If no session config is set, the function errors with instructions.

- dry_run:

  Logical. If `TRUE`, prints the `scp` command that would be executed
  without running it. Defaults to `FALSE`.

- verbose:

  Logical. If `TRUE`, prints progress messages. Defaults to `FALSE`.

## Value

Called for its side effects. Returns `invisible(NULL)`.

## Details

When `cluster_id` is supplied without `files`, the function uses the job
manifest built up by
[`htc_gen_submit()`](https://erwinlares.github.io/submitr/reference/htc_gen_submit.md),
[`htc_gen_executable()`](https://erwinlares.github.io/submitr/reference/htc_gen_executable.md),
and
[`htc_submit()`](https://erwinlares.github.io/submitr/reference/htc_submit.md)
to determine which files to download. For single-mode jobs, this
includes the results tarball and the log, error, and output files. For
multiple-mode jobs, the function reads the subset names from the
manifest and constructs per-job tarball names and per-process log file
patterns.

Glob patterns such as `"*.tar.gz"` are supported when using the `files`
argument and are evaluated on the remote server, not locally.

## Automatic file resolution

When `files` is `NULL`, the function resolves the file list from the job
manifest. The manifest is built automatically as you call
[`htc_gen_submit()`](https://erwinlares.github.io/submitr/reference/htc_gen_submit.md),
[`htc_gen_executable()`](https://erwinlares.github.io/submitr/reference/htc_gen_executable.md),
and
[`htc_submit()`](https://erwinlares.github.io/submitr/reference/htc_submit.md)
during the normal workflow. No extra steps are needed.

For a single-mode job:

- The results tarball (e.g. `"analysis-results.tar.gz"`)

- Log files: `"{cluster_id}-0-job.log"`, `".err"`, `".out"`

For a multiple-mode job:

- Per-subset tarballs (e.g. `"adelie.csv-results.tar.gz"`)

- Log files for each process: `"{cluster_id}-{0,1,...}-job.log"`, etc.

## Workflow

`htc_download()` is the final system-facing step in the submitr
workflow. Call it after
[`htc_status()`](https://erwinlares.github.io/submitr/reference/htc_status.md)
confirms all jobs have completed.

    # Automatic: uses the job manifest to determine what to download
    htc_start()
    htc_gen_submit(...)
    htc_gen_executable(...)
    htc_upload(...)
    job <- htc_submit("analysis.sub")
    htc_status(cluster_id = job, watch = TRUE)
    htc_download()

## Glob patterns

When using `files` directly, glob patterns are passed to the remote
shell for evaluation so they match files on the submit node, not on your
local machine. The pattern is single-quoted in the `scp` command to
prevent local shell expansion.

## SSH connection reuse

Each call to `htc_download()` opens a new SSH connection. If you have
not configured ControlMaster in your `~/.ssh/config`, this will trigger
a Duo MFA prompt. Run
[`htc_config()`](https://erwinlares.github.io/submitr/reference/htc_config.md)
for setup guidance.

## Examples

``` r
# \donttest{
# Preview the scp command without connecting to CHTC
cfg <- list(username = "netid", server = "ap2002.chtc.wisc.edu")
htc_download(files = "*.tar.gz", config = cfg, dry_run = TRUE)
#> ✔ Dry run -- command that would be executed:
#>   `scp 'netid@ap2002.chtc.wisc.edu:~/*.tar.gz' .`
# }

if (FALSE) { # \dontrun{
# All remaining examples require a live CHTC connection

# Automatic download after a workflow
htc_start()
htc_gen_submit(...)
htc_gen_executable(...)
htc_upload(...)
job <- htc_submit("job.sub")
htc_status(cluster_id = job, watch = TRUE)
htc_download()

# Download by cluster ID
htc_download(cluster_id = "6590895")

# Download specific files using globs
htc_download(files = "*.tar.gz", local_path = "results/")

# Download logs only
htc_download(files = c("*.log", "*.err", "*.out"), local_path = "logs/")
} # }
```
