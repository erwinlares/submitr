# Extract one job's tarball and describe what came out

Internal helper used by
[`htc_collect()`](https://erwinlares.github.io/submitr/reference/htc_collect.md).
Never errors on the job's own account: a tarball that is missing or will
not extract comes back as `extracted = FALSE` with a `problem` saying
which, so one failed job cannot stop the rest of a collection.

## Usage

``` r
.collect_one(tarball, dest, results_folder)
```

## Arguments

- tarball:

  Character. Local path to the tarball.

- dest:

  Character. Directory to extract into; must not exist yet.

- results_folder:

  Character. The folder the job tarred, normally `"output"`.

## Value

A list with elements `extracted`, `output_dir`, `files`, `n_files`,
`has_record`, and `problem` (`NA`, `"missing"`, `"unreadable"`, or
`"no_results_folder"`).
