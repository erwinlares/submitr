# Retrieve the current job manifest

Internal helper that reads the accumulated job manifest from
`htc-manifest.yaml` in `path`. Returns `NULL` if no manifest file exists
yet.

## Usage

``` r
.get_manifest(path = ".")
```

## Arguments

- path:

  A character string. Directory to look for `htc-manifest.yaml` in.
  Defaults to `"."` (current working directory).

## Value

A named list or `NULL`.

## Details

YAML represents a sequence (e.g. a character vector recorded via
[`.update_manifest()`](https://erwinlares.github.io/submitr/reference/dot-update_manifest.md))
as a list on read-back. Each top-level element that is a list of
length-1 atomic values is simplified back into an ordinary vector here,
so callers see the same shape they originally passed to
[`.update_manifest()`](https://erwinlares.github.io/submitr/reference/dot-update_manifest.md).
