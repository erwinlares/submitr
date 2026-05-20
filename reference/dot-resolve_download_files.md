# Resolve file list from job manifest and cluster ID

Internal helper that constructs the list of files to download based on
the job mode, output file pattern, subset names, and cluster ID.

## Usage

``` r
.resolve_download_files(cluster_id, manifest)
```

## Arguments

- cluster_id:

  A character string. The HTCondor cluster ID.

- manifest:

  A named list from
  [`.get_manifest()`](https://erwinlares.github.io/submitr/reference/dot-get_manifest.md).

## Value

A character vector of filenames to download.
