# Count the jobs a condor_q report still shows for a cluster

Internal helper used by `htc_status(watch = TRUE)` to decide when to
stop polling.

## Usage

``` r
.jobs_in_queue(output, cluster_id)
```

## Arguments

- output:

  A character vector. The lines returned by `condor_q`.

- cluster_id:

  A character string. The cluster being watched.

## Value

An integer count of jobs still in the queue.

## Details

The obvious test, searching the report for the cluster ID as a
substring, is not safe. `condor_q` always prints a schedd header
carrying an address, a port and a timestamp, and closes with summary
lines such as `Total for all users: 3402 jobs; ...`. Digits from any of
those can coincide with the cluster ID, and because the test drives the
loop's exit, a false match does not produce a wrong answer – it produces
a watch loop that never returns.

The report's own `Total for query:` line is a direct answer instead. The
remote command is `condor_q <cluster_id>`, so the query is this cluster,
and the count is the number of its jobs still in the queue. If that line
is missing, the fallback matches the cluster ID anchored to the `.` that
separates it from the process number, which restricts it to the
`JOB_IDS` column (`6302860.0`) rather than the report at large.
