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
  files,
  remote_path = "~/",
  config = NULL,
  dry_run = FALSE,
  verbose = FALSE
)
```

## Arguments

- files:

  A character vector. One or more local file paths or directory paths to
  copy to the submit node. A single file, a vector of files, and a
  directory path are all accepted. Directories are copied recursively.

- remote_path:

  A character string. The destination directory on the submit node.
  Defaults to `"~/"` (the user's home directory). This should match the
  path used in the subsequent call to
  [`htc_submit()`](https://erwinlares.github.io/submitr/reference/htc_submit.md).

- config:

  A named list as returned by
  [`htc_config()`](https://erwinlares.github.io/submitr/reference/htc_config.md).
  Must contain `username` and `server`. If `NULL`, the function errors
  with instructions to call
  [`htc_config()`](https://erwinlares.github.io/submitr/reference/htc_config.md)
  first.

- dry_run:

  Logical. If `TRUE`, prints the `scp` command that would be executed
  without running it. Useful for verifying the command before
  transferring files. Defaults to `FALSE`.

- verbose:

  Logical. If `TRUE`, prints progress messages. Defaults to `FALSE`.

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

The typical sequence is:

    cfg <- htc_config()

    htc_upload(
      files  = c("job.sub", "job.sh", "analysis.R", "data.csv"),
      config = cfg
    )

    htc_submit(submit_file = "job.sub", config = cfg)

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
#>   `scp /tmp/RtmpX6TRTq/file4a5f41c67399.sub netid@ap2002.chtc.wisc.edu:~/`
# }

if (FALSE) { # \dontrun{
# All remaining examples require a live CHTC connection
cfg <- htc_config()

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
