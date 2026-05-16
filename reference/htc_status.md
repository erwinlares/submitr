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
  verbose = FALSE
)
```

## Arguments

- cluster_id:

  An integer or character string. The cluster ID returned by
  [`htc_submit()`](https://erwinlares.github.io/submitr/reference/htc_submit.md),
  e.g. `6302860`. If `NULL` (the default), shows all of your jobs
  currently in the queue. Required when `watch = TRUE`.

- config:

  A named list as returned by
  [`htc_config()`](https://erwinlares.github.io/submitr/reference/htc_config.md).
  Must contain `username` and `server`. If `NULL` (the default), uses
  the session config set by `htc_start_session()`. If no session config
  is set, the function errors with instructions.

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

## Value

Called for its side effects. Prints the `condor_q` output to the
console. Returns the most recent output invisibly as a character vector.

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
