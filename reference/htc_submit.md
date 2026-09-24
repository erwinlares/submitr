# Submit an HTCondor job from a remote submit node

`htc_submit()` connects to an HTC submit node via SSH and runs
`condor_submit` on a submit file that has already been uploaded with
[`htc_upload()`](https://erwinlares.github.io/submitr/reference/htc_upload.md).
It changes into the remote directory before submitting so that relative
paths in the submit file resolve correctly.

## Usage

``` r
htc_submit(
  submit_file = NULL,
  remote_path = NULL,
  config = NULL,
  dry_run = FALSE,
  verbose = FALSE,
  path = "."
)
```

## Arguments

- submit_file:

  A character string or `NULL`. Name of the submit file on the remote
  node, e.g. `"job.sub"`. Must end in `".sub"`. When `NULL` (the
  default), resolves to the `submit_file` recorded in the job manifest
  by
  [`htc_gen_submit()`](https://erwinlares.github.io/submitr/reference/htc_gen_submit.md),
  falling back to `"job.sub"` if no manifest value is available.

- remote_path:

  A character string or `NULL`. The directory on the submit node where
  the submit file was uploaded. When `NULL` (the default), resolves to
  the `remote_path` recorded in the job manifest by the preceding call
  to
  [`htc_upload()`](https://erwinlares.github.io/submitr/reference/htc_upload.md),
  falling back to `"~/"` if no manifest value is available.

- config:

  A named list as returned by
  [`htc_config()`](https://erwinlares.github.io/submitr/reference/htc_config.md).
  Must contain `username` and `server`. If `NULL` (the default), uses
  the session config set by
  [`htc_start()`](https://erwinlares.github.io/submitr/reference/htc_start.md).
  If no session config is set, the function errors with instructions.

- dry_run:

  Logical. If `TRUE`, prints the SSH command that would be executed
  without running it. Useful for verifying the command before
  submitting. Defaults to `FALSE`.

- verbose:

  Logical. If `TRUE`, prints progress messages and the `condor_submit`
  output. Defaults to `FALSE`.

- path:

  A character string. Directory holding the job manifest
  (`htc-manifest.yaml`), where the cluster ID and `remote_path` are
  recorded on a successful submission. Defaults to `"."`. If you passed
  a non-default `output` or `path` to
  [`htc_gen_submit()`](https://erwinlares.github.io/submitr/reference/htc_gen_submit.md),
  pass that same directory here, or the cluster ID will be written to a
  second, separate manifest and
  [`htc_download()`](https://erwinlares.github.io/submitr/reference/htc_download.md)
  will not find it alongside the job metadata it needs.

## Value

The cluster ID assigned by HTCondor as a character string, returned
invisibly. Pass it directly to
[`htc_status()`](https://erwinlares.github.io/submitr/reference/htc_status.md)
to monitor job progress. Returns `invisible(NULL)` if the cluster ID
cannot be parsed from the `condor_submit` output.

## Workflow

`htc_submit()` is the second system-facing step in the submitr workflow.
Call it after uploading your files with
[`htc_upload()`](https://erwinlares.github.io/submitr/reference/htc_upload.md).
The returned cluster ID can be passed directly to
[`htc_status()`](https://erwinlares.github.io/submitr/reference/htc_status.md).

    cfg <- htc_config()

    htc_upload(
      files  = c("job.sub", "job.sh", "analysis.R"),
      config = cfg
    )

    cluster_id <- htc_submit(submit_file = "job.sub", config = cfg)
    htc_status(cluster_id = cluster_id, config = cfg, watch = TRUE)

## Why `remote_path` must match [`htc_upload()`](https://erwinlares.github.io/submitr/reference/htc_upload.md)

`htc_submit()` runs `cd remote_path && condor_submit submit_file` on the
submit node. HTCondor resolves all paths in the submit file relative to
the directory where `condor_submit` is called. If `remote_path` does not
match the directory where files were uploaded, HTCondor will not find
the executable, input files, or output destinations and the job will
fail.

## SSH connection reuse

Each call to `htc_submit()` opens a new SSH connection. If you have not
configured ControlMaster in your `~/.ssh/config`, this will trigger a
Duo MFA prompt. Run
[`htc_config()`](https://erwinlares.github.io/submitr/reference/htc_config.md)
for setup guidance.

## Examples

``` r
# \donttest{
# Preview the SSH command without connecting to CHTC
cfg <- list(username = "netid", server = "ap2002.chtc.wisc.edu")
htc_submit(submit_file = "job.sub", config = cfg, dry_run = TRUE)
#> ✔ Dry run -- command that would be executed:
#>   `ssh -q netid@ap2002.chtc.wisc.edu 'cd ~/ && condor_submit job.sub'`
# }

if (FALSE) { # \dontrun{
# All remaining examples require a live CHTC connection
cfg <- htc_config()

# Submit using default remote path
htc_submit(submit_file = "job.sub", config = cfg)

# Submit from a specific remote directory
htc_submit(
  submit_file = "analysis.sub",
  remote_path = "~/projects/penguins/",
  config      = cfg
)

# Submit with verbose output to see condor_submit response
htc_submit(
  submit_file = "job.sub",
  config      = cfg,
  verbose     = TRUE
)
} # }
```
