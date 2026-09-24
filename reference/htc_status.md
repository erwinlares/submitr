# Check the status of submitted HTCondor jobs

`htc_status()` connects to an HTC submit node via SSH and runs
`condor_q` to report the status of jobs in the queue. By default it
shows all of your jobs. Optionally filter by cluster ID to monitor a
specific submission.

## Usage

``` r
htc_status(
  cluster_id = NULL,
  config = NULL,
  watch = FALSE,
  interval = 60L,
  dry_run = FALSE,
  verbose = FALSE,
  path = ".",
  show_hold_reason = TRUE
)
```

## Arguments

- cluster_id:

  An integer, character string, or `NULL`. The cluster ID returned by
  [`htc_submit()`](https://erwinlares.github.io/submitr/reference/htc_submit.md),
  e.g. `6302860`. When `NULL` (the default), resolves to the cluster ID
  recorded in the job manifest by the most recent
  [`htc_submit()`](https://erwinlares.github.io/submitr/reference/htc_submit.md)
  call; if no manifest value is available either, shows all of your jobs
  currently in the queue instead. Required (directly or via the
  manifest) when `watch = TRUE`.

- config:

  A named list as returned by
  [`htc_config()`](https://erwinlares.github.io/submitr/reference/htc_config.md).
  Must contain `username` and `server`. If `NULL` (the default), uses
  the session config set by
  [`htc_start()`](https://erwinlares.github.io/submitr/reference/htc_start.md).
  If no session config is set, the function errors with instructions.

- watch:

  Logical. If `TRUE`, polls the queue repeatedly at `interval` seconds
  until all jobs in `cluster_id` have completed. Requires `cluster_id`
  to be supplied. Defaults to `FALSE`.

- interval:

  A positive integer. Number of seconds to wait between polls when
  `watch = TRUE`. Defaults to `60`.

- dry_run:

  Logical. If `TRUE`, prints the SSH command that would be executed
  without running it. Defaults to `FALSE`.

- verbose:

  Logical. If `TRUE`, prints progress messages. Defaults to `FALSE`.

- path:

  A character string. Directory holding the job manifest
  (`htc-manifest.yaml`), consulted only when `cluster_id` is `NULL`.
  Defaults to `"."`, matching the default used by
  [`htc_upload()`](https://erwinlares.github.io/submitr/reference/htc_upload.md),
  [`htc_submit()`](https://erwinlares.github.io/submitr/reference/htc_submit.md),
  and
  [`htc_download()`](https://erwinlares.github.io/submitr/reference/htc_download.md).
  If you passed a non-default `path` to
  [`htc_submit()`](https://erwinlares.github.io/submitr/reference/htc_submit.md),
  pass that same directory here.

- show_hold_reason:

  Logical. If `TRUE` (the default), every poll automatically follows up
  with `condor_q -hold` and prints the result whenever it shows an
  actual held job – nothing is printed when nothing is held (S-G2). This
  is the single most common cause of newcomer confusion – a job held for
  exceeding its memory or disk request otherwise gives no clue why
  without a separate manual query. Set to `FALSE` to skip the follow-up
  query entirely (for example, in a tight `watch = TRUE` polling loop
  where the extra round trip is unwelcome).

## Value

Called for its side effects. Prints the `condor_q` output (and, when
applicable, hold reasons) to the console. Returns the most recent
`condor_q` output invisibly as a character vector.

## Details

When `watch = TRUE`, `htc_status()` polls the queue repeatedly at a
fixed interval until all jobs in the cluster have completed, printing a
timestamped snapshot after each poll.

## Job status codes

HTCondor reports each job's status with a single letter:

|      |                                            |
|------|--------------------------------------------|
| Code | Meaning                                    |
| I    | Idle – waiting for a matching execute node |
| R    | Running – currently executing              |
| H    | Held – paused, usually due to an error     |
| C    | Completed – finished successfully          |
| X    | Removed – cancelled                        |
| S    | Suspended                                  |

Jobs disappear from `condor_q` once they complete and their output has
been transferred back to the submit node. Use
[`htc_download()`](https://erwinlares.github.io/submitr/reference/htc_download.md)
to retrieve completed job output.

A held (`H`) job is not a lost cause: `htc_status()` surfaces the hold
reason automatically (see `show_hold_reason`), and once the underlying
problem is fixed – most often the resource request –
[`htc_release()`](https://erwinlares.github.io/submitr/reference/htc_release.md)
resumes it without resubmitting. To abandon a job entirely instead, use
[`htc_cancel()`](https://erwinlares.github.io/submitr/reference/htc_cancel.md).

## Workflow

    cfg <- htc_config()

    # One-shot status check
    htc_status(config = cfg)

    # Monitor a specific cluster until completion
    htc_status(cluster_id = 6302860, config = cfg, watch = TRUE)

## SSH connection reuse

Each poll in watch mode opens a new SSH connection. Configuring
ControlMaster in your `~/.ssh/config` (see
[`htc_config()`](https://erwinlares.github.io/submitr/reference/htc_config.md))
is strongly recommended when using `watch = TRUE` to avoid repeated Duo
MFA prompts.

## See also

[`htc_cancel()`](https://erwinlares.github.io/submitr/reference/htc_cancel.md)
to remove a job, and
[`htc_release()`](https://erwinlares.github.io/submitr/reference/htc_release.md)
to resume a held one after fixing what caused the hold.

## Examples

``` r
# \donttest{
# Preview the SSH command without connecting to CHTC
cfg <- list(username = "netid", server = "ap2002.chtc.wisc.edu")
htc_status(config = cfg, dry_run = TRUE)
#> ✔ Dry run -- command that would be executed:
#>   `ssh -q netid@ap2002.chtc.wisc.edu 'condor_q'`

# Preview with a specific cluster ID
htc_status(cluster_id = 6302860, config = cfg, dry_run = TRUE)
#> ✔ Dry run -- command that would be executed:
#>   `ssh -q netid@ap2002.chtc.wisc.edu 'condor_q 6302860'`
# }

if (FALSE) { # \dontrun{
# All remaining examples require a live CHTC connection
cfg <- htc_config()

# Check all your jobs
htc_status(config = cfg)

# Check a specific cluster
htc_status(cluster_id = 6302860, config = cfg)

# Watch a cluster until all jobs complete (polls every 60 seconds)
htc_status(cluster_id = 6302860, config = cfg, watch = TRUE)

# Watch with a shorter polling interval
htc_status(cluster_id = 6302860, config = cfg, watch = TRUE, interval = 30)
} # }
```
