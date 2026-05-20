# Retrieve the current job manifest

Internal helper that reads the accumulated job manifest from session
options. Returns `NULL` if no manifest has been set.

## Usage

``` r
.get_manifest()
```

## Value

A named list or `NULL`.
