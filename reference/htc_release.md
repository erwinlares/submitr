# Release held HTCondor jobs

`htc_release()` connects to an HTC submit node via SSH and runs
`condor_release` to un-pause jobs that HTCondor has held (S-G2) –
typically after fixing whatever caused the hold, such as raising a
resource request reported by
[`htc_status()`](https://erwinlares.github.io/submitr/reference/htc_status.md)'s
hold-reason output.

## Usage

``` r
htc_release(
  cluster_id = NULL,
  config = NULL,
  dry_run = FALSE,
  verbose = FALSE,
  path = "."
)
```

## Arguments

- cluster_id:

  An integer, character string, or `NULL`. The cluster ID to release,
  e.g. `6302860`. When `NULL` (the default), resolves to the cluster ID
  recorded in the job manifest by the most recent
  [`htc_submit()`](https://erwinlares.github.io/submitr/reference/htc_submit.md)
  call. Unlike
  [`htc_status()`](https://erwinlares.github.io/submitr/reference/htc_status.md),
  `htc_release()` never falls back to "all of my jobs": a bare
  `condor_release` with no arguments releases every held job you have on
  the submit node, not just the ones from this project, so the function
  errors instead of guessing when no cluster ID is available anywhere.

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

The `condor_release` output as a character vector, returned invisibly.

## Workflow

    cfg <- htc_config()
    htc_status(cluster_id = 6302860, config = cfg)
    # ... shows job 6302860.0 held; hold reason printed below the table ...
    # ... fix the resource request that caused the hold, then:
    htc_release(cluster_id = 6302860, config = cfg)

## See also

[`htc_cancel()`](https://erwinlares.github.io/submitr/reference/htc_cancel.md)
to remove a job instead of releasing it, and
[`htc_status()`](https://erwinlares.github.io/submitr/reference/htc_status.md)
to see hold reasons.

## Examples

``` r
# \donttest{
# Preview the SSH command without connecting to CHTC
cfg <- list(username = "netid", server = "ap2002.chtc.wisc.edu")
htc_release(cluster_id = 6302860, config = cfg, dry_run = TRUE)
#> ✔ Dry run -- command that would be executed:
#>   `ssh -q netid@ap2002.chtc.wisc.edu 'condor_release 6302860'`
# }

if (FALSE) { # \dontrun{
cfg <- htc_config()
htc_release(cluster_id = 6302860, config = cfg)
} # }
```
