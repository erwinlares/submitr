# Upload files to an HTC submit node

`htc_upload()` copies one or more local files or directories to a
directory on an HTC submit node via `scp`. It is the first step in the
job submission workflow – files must be present on the submit node
before
[`htc_submit()`](https://erwinlares.github.io/submitr/reference/htc_submit.md)
can run `condor_submit`.

## Usage

``` r
htc_upload(
  files = NULL,
  remote_path = NULL,
  config = NULL,
  dry_run = FALSE,
  verbose = FALSE,
  path = ".",
  check = FALSE
)
```

## Arguments

- files:

  A character vector or `NULL`. One or more local file paths or
  directory paths to copy to the submit node. A single file, a vector of
  files, and a directory path are all accepted. Directories are copied
  recursively. When `NULL` (the default), the function resolves the
  files to upload from the job manifest built up by
  [`htc_gen_submit()`](https://erwinlares.github.io/submitr/reference/htc_gen_submit.md)
  and
  [`htc_gen_executable()`](https://erwinlares.github.io/submitr/reference/htc_gen_executable.md):
  the submit file, the executable script, any shared input files, and –
  in `"multiple"` mode – the subdatasets manifest and the individual
  subset data files.

- remote_path:

  A character string or `NULL`. The destination directory on the submit
  node. When `NULL` (the default), resolves to the `remote_path`
  recorded in the job manifest by a previous call to `htc_upload()`,
  falling back to `"~/"` if no manifest value is available. On a
  successful (non-`dry_run`) upload, the resolved value is recorded back
  to the manifest, so
  [`htc_submit()`](https://erwinlares.github.io/submitr/reference/htc_submit.md)
  and
  [`htc_download()`](https://erwinlares.github.io/submitr/reference/htc_download.md)
  can pick it up automatically without retyping it.

- config:

  A named list as returned by
  [`htc_config()`](https://erwinlares.github.io/submitr/reference/htc_config.md).
  Must contain `username` and `server`. If `NULL` (the default), uses
  the session config set by
  [`htc_start()`](https://erwinlares.github.io/submitr/reference/htc_start.md).
  If no session config is set, the function errors with instructions.

- dry_run:

  Logical. If `TRUE`, prints the `scp` command that would be executed
  without running it. Useful for verifying the command before
  transferring files. Defaults to `FALSE`.

- verbose:

  Logical. If `TRUE`, prints progress messages. Defaults to `FALSE`.

- path:

  A character string. Directory holding the job manifest
  (`htc-manifest.yaml`), consulted only when `files` is `NULL`. Defaults
  to `"."`, which matches the generator functions' own default. If you
  passed a non-default `output` or `path` to
  [`htc_gen_submit()`](https://erwinlares.github.io/submitr/reference/htc_gen_submit.md)
  and
  [`htc_gen_executable()`](https://erwinlares.github.io/submitr/reference/htc_gen_executable.md),
  pass that same directory here.

- check:

  Logical. If `TRUE`, runs
  [`htc_check()`](https://erwinlares.github.io/submitr/reference/htc_check.md)
  before uploading and aborts if it finds an `"error"`-level issue (a
  missing file, or a `"multiple"`-mode subset mismatch) – catching it
  here rather than an hour later as a held job on the cluster (S-G4).
  Warning-level issues (a resource request that looks large, an
  unconfirmed image) are reported but do not block the upload. Defaults
  to `FALSE`.

## Value

Called for its side effects. Returns `invisible(NULL)`.

## Workflow

`htc_upload()` is the first system-facing step in the submitr workflow.
Call it after generating your submit file and executable script with
[`htc_gen_submit()`](https://erwinlares.github.io/submitr/reference/htc_gen_submit.md)
and
[`htc_gen_executable()`](https://erwinlares.github.io/submitr/reference/htc_gen_executable.md),
and before calling
[`htc_submit()`](https://erwinlares.github.io/submitr/reference/htc_submit.md).

The typical sequence relies on automatic resolution from the job
manifest, so `files` can usually be omitted:

    cfg <- htc_config()

    htc_gen_submit(executable = "job.sh", r_script = "R/analysis.R",
                   input_files = "R/analysis.R")
    htc_gen_executable(r_script = "R/analysis.R")

    htc_upload(config = cfg)

    htc_submit(submit_file = "job.sub", config = cfg)

Pass `files` explicitly to upload a specific set of files instead:

    htc_upload(
      files  = c("job.sub", "job.sh", "analysis.R", "data.csv"),
      config = cfg
    )

## SSH connection reuse

Each call to `htc_upload()` opens a new SSH connection. If you have not
configured ControlMaster in your `~/.ssh/config`, this will trigger a
Duo MFA prompt. Run
[`htc_config()`](https://erwinlares.github.io/submitr/reference/htc_config.md)
for setup guidance.

## Examples

``` r
# \donttest{
# Preview the scp command without connecting to CHTC
cfg <- list(username = "netid", server = "ap2002.chtc.wisc.edu")
tmp <- tempfile(fileext = ".sub")
writeLines("queue 1", tmp)
htc_upload(files = tmp, config = cfg, dry_run = TRUE)
#> ✔ Dry run -- command that would be executed:
#>   `scp /tmp/Rtmpye778X/file4a034ca033aa.sub netid@ap2002.chtc.wisc.edu:~/`
# }

if (FALSE) { # \dontrun{
# All remaining examples require a live CHTC connection
cfg <- htc_config()

# Resolve files automatically from the job manifest
htc_gen_submit(executable = "job.sh", r_script = "R/analysis.R",
               input_files = "R/analysis.R")
htc_gen_executable(r_script = "R/analysis.R")
htc_upload(config = cfg)

# Upload a single file
htc_upload(files = "job.sub", config = cfg)

# Upload multiple files
htc_upload(
  files  = c("job.sub", "job.sh", "analysis.R"),
  config = cfg
)

# Upload a directory
htc_upload(files = "jobs/", config = cfg)

# Upload to a specific remote directory
htc_upload(
  files       = c("job.sub", "job.sh"),
  remote_path = "~/projects/penguins/",
  config      = cfg
)
} # }
```
