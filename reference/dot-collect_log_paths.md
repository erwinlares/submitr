# Local paths to one job's HTCondor log files, when present

Internal helper used by
[`htc_collect()`](https://erwinlares.github.io/submitr/reference/htc_collect.md).
[`htc_gen_submit()`](https://erwinlares.github.io/submitr/reference/htc_gen_submit.md)
names the three files `<cluster>-<proc>-job.log`, `.err`, and `.out`,
and
[`htc_download()`](https://erwinlares.github.io/submitr/reference/htc_download.md)
saves them beside the tarballs, so they are looked for in the tarball's
own directory. A file that is not there, or cannot be named because the
cluster or process number is unknown, is `NA`.

## Usage

``` r
.collect_log_paths(dir, cluster_id, proc_id)
```

## Arguments

- dir:

  Character. Directory to look in.

- cluster_id:

  Character or `NA`.

- proc_id:

  Integer or `NA`.

## Value

A named character vector with elements `log`, `err`, and `out`.
