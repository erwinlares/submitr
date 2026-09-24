# Cancel HTCondor jobs

`htc_cancel()` connects to an HTC submit node via SSH and runs
`condor_rm` to remove jobs from the queue – a mistaken submission (the
wrong resource request, the wrong image, 500 jobs instead of 5) can be
stopped from R rather than requiring a manual SSH session (S-G2).

## Usage

``` r
htc_cancel(
  cluster_id = NULL,
  reason = NULL,
  config = NULL,
  dry_run = FALSE,
  verbose = FALSE,
  path = "."
)
```

## Arguments

- cluster_id:

  An integer, character string, or `NULL`. The cluster ID to remove,
  e.g. `6302860`. When `NULL` (the default), resolves to the cluster ID
  recorded in the job manifest by the most recent
  [`htc_submit()`](https://erwinlares.github.io/submitr/reference/htc_submit.md)
  call. Unlike
  [`htc_status()`](https://erwinlares.github.io/submitr/reference/htc_status.md),
  `htc_cancel()` never falls back to "all of my jobs": a bare
  `condor_rm` with no arguments removes every job you have queued on the
  submit node, not just the ones from this project, so the function
  errors instead of guessing when no cluster ID is available anywhere.

- reason:

  A character string or `NULL`. An optional free-text reason recorded in
  the job's HTCondor log (via `condor_rm`'s own `-reason` flag), useful
  when revisiting a log later to remember why a cluster was removed.
  Defaults to `NULL`.

- config:

  A named list as returned by
  [`htc_config()`](https://erwinlares.github.io/submitr/reference/htc_config.md).
  Must contain `username` and `server`. If `NULL` (the default), uses
  the session config set by
  [`htc_start()`](https://erwinlares.github.io/submitr/reference/htc_start.md).
  If no session config is set, the function errors with instructions.

- dry_run:

  Logical. If `TRUE`, prints the SSH command that would be executed
  without running it. Defaults to `FALSE`.

- verbose:

  Logical. If `TRUE`, prints progress messages. Defaults to `FALSE`.

- path:

  A character string. Directory holding the job manifest
  (`htc-manifest.yaml`), consulted only when `cluster_id` is `NULL`.
  Defaults to `"."`, matching the default used elsewhere in the family.

## Value

The `condor_rm` output as a character vector, returned invisibly.

## Workflow

    cfg <- htc_config()
    job <- htc_submit(config = cfg)

    # Realized the resource request was wrong -- stop it before it runs
    htc_cancel(cluster_id = job, config = cfg, reason = "wrong request_memory")

## See also

[`htc_release()`](https://erwinlares.github.io/submitr/reference/htc_release.md)
to un-pause a held job instead of removing it, and
[`htc_status()`](https://erwinlares.github.io/submitr/reference/htc_status.md)
to see which jobs are running, idle, or held.

## Examples

``` r
# \donttest{
# Preview the SSH command without connecting to CHTC
cfg <- list(username = "netid", server = "ap2002.chtc.wisc.edu")
htc_cancel(cluster_id = 6302860, config = cfg, dry_run = TRUE)
#> ✔ Dry run -- command that would be executed:
#>   `ssh -q netid@ap2002.chtc.wisc.edu 'condor_rm 6302860'`
# }

if (FALSE) { # \dontrun{
cfg <- htc_config()
htc_cancel(cluster_id = 6302860, config = cfg)
htc_cancel(cluster_id = 6302860, config = cfg, reason = "submitted by mistake")
} # }
```
