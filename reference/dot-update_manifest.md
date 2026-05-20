# Update the job manifest with new information

Internal helper that accumulates job metadata across the submitr
pipeline. Each function in the workflow calls `.update_manifest()` with
the information it knows.
[`htc_download()`](https://erwinlares.github.io/submitr/reference/htc_download.md)
reads the accumulated manifest to construct the list of files to
retrieve.

## Usage

``` r
.update_manifest(...)
```

## Arguments

- ...:

  Named key-value pairs to add or update in the manifest.

## Value

Called for its side effects. Returns `invisible(NULL)`.
