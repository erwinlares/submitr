# Download files from an HTC submit node

`htc_download()` copies one or more files from a directory on an HTC
submit node to a local directory via `scp`. It is the final step in the
job submission workflow – called after
[`htc_status()`](https://erwinlares.github.io/submitr/reference/htc_status.md)
confirms all jobs have completed.

## Usage

``` r
htc_download(
  files,
  remote_path = "~/",
  local_path = ".",
  config = NULL,
  dry_run = FALSE,
  verbose = FALSE
)
```

## Arguments

- files:

  A character vector. One or more filenames or glob patterns to download
  from `remote_path` on the submit node. Examples: `"results.tar.gz"`,
  `c("job.log", "job.err")`, `"*.tar.gz"`. Required.

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
  Must contain `username` and `server`. If `NULL`, the function errors
  with instructions to call
  [`htc_config()`](https://erwinlares.github.io/submitr/reference/htc_config.md)
  first.

- dry_run:

  Logical. If `TRUE`, prints the `scp` command that would be executed
  without running it. Defaults to `FALSE`.

- verbose:

  Logical. If `TRUE`, prints progress messages. Defaults to `FALSE`.

## Value

Called for its side effects. Returns `invisible(NULL)`.

## Details

Glob patterns such as `"*.tar.gz"` are supported and are evaluated on
the remote server, not locally, so they match files that exist on the
submit node regardless of what is present on your local machine.

## Workflow

`htc_download()` is the final system-facing step in the submitr
workflow. Call it after
[`htc_status()`](https://erwinlares.github.io/submitr/reference/htc_status.md)
confirms all jobs have completed.

    cfg <- htc_config()

    htc_status(cluster_id = 6302877, config = cfg, watch = TRUE)

    # Download all result tarballs
    htc_download(
      files      = "*.tar.gz",
      config     = cfg,
      local_path = "results/"
    )

## Glob patterns

Glob patterns are passed to the remote shell for evaluation so they
match files on the submit node, not on your local machine. The pattern
is single-quoted in the `scp` command to prevent local shell expansion.

Common patterns:

- `"*.tar.gz"` – all result tarballs

- `"*.log"` – all log files

- `"*.out"` – all output files

- `"*.err"` – all error files

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
cfg <- htc_config()

# Download a single file
htc_download(files = "r <- esults.tar.gz", config = cfg)

# Download multiple specific files
htc_download(
  files  = c("job.log", "job.err", "results.tar.gz"),
  config = cfg
)

# Download all result tarballs using a glob pattern
htc_download(
  files      = "*.tar.gz",
  config     = cfg,
  local_path = "results/"
)

# Download all log files from a specific remote directory
htc_download(
  files       = "*.log",
  remote_path = "~/projects/penguins/",
  local_path  = "logs/",
  config      = cfg
)
} # }
```
