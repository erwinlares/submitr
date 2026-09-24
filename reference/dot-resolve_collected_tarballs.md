# Resolve the local tarballs htc_download() saved, keyed by group id

Internal helper used by
[`htc_collect()`](https://erwinlares.github.io/submitr/reference/htc_collect.md)
to rebuild, from the job manifest, the same tarball names
[`htc_download()`](https://erwinlares.github.io/submitr/reference/htc_download.md)
would have fetched into `local_path` – reusing
[`.tarball_name()`](https://erwinlares.github.io/submitr/reference/dot-tarball_name.md)
so the naming stays in the one place the rest of the family already
shares it (see that function's own docs for why three separate resolvers
of this name would drift).

## Usage

``` r
.resolve_collected_tarballs(manifest, local_path)
```

## Arguments

- manifest:

  A named list from
  [`.get_manifest()`](https://erwinlares.github.io/submitr/reference/dot-get_manifest.md),
  or `NULL`.

- local_path:

  A character string. Directory the tarballs were downloaded into.

## Value

A tibble with columns `group_id` and `tarball` (a local path), possibly
with zero rows.
