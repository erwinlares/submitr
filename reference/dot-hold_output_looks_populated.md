# Detect whether a condor_q -hold report actually shows a held job

Internal helper used by
[`htc_status()`](https://erwinlares.github.io/submitr/reference/htc_status.md)
to decide whether the follow-up `condor_q -hold` query (S-G2) found
anything worth printing. `condor_q` prints a schedd header (an address,
a port, a timestamp) whether or not any job is actually held, so an
empty-but-for-the-header report must not be mistaken for one describing
a held job.

## Usage

``` r
.hold_output_looks_populated(output, cluster_id)
```

## Arguments

- output:

  A character vector. The lines returned by `condor_q -hold`.

- cluster_id:

  A character string or `NULL`.

## Value

A logical scalar.

## Details

The check looks for something shaped like a job ID (`ClusterId.ProcId`,
e.g. `6302860.0`), anchored to `cluster_id` when one is known. This is
the same job-ID-pattern approach
[`.jobs_in_queue()`](https://erwinlares.github.io/submitr/reference/dot-jobs_in_queue.md)
falls back to, and for the same reason: it does not depend on
`condor_q`'s column layout, which is not a documented contract this
package can rely on.
