# Match group ids to HTCondor process numbers

Internal helper used by
[`htc_collect()`](https://erwinlares.github.io/submitr/reference/htc_collect.md).
HTCondor numbers the jobs of a cluster from 0 in the order it reads
`subdatasets.csv`, which is the order of `subsets` in the submission
state, so a group's `ProcId` is its position in that list minus one. A
single-mode job is always process 0. A group id that cannot be matched
(a `tarballs` name that is not in the submission state, or no submission
state at all) gets `NA`.

## Usage

``` r
.collect_proc_ids(group_ids, manifest)
```

## Arguments

- group_ids:

  Character vector of group ids.

- manifest:

  A named list from
  [`.get_manifest()`](https://erwinlares.github.io/submitr/reference/dot-get_manifest.md),
  or `NULL`.

## Value

An integer vector the same length as `group_ids`.
