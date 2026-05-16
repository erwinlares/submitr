# Resolve HTC config from argument or session option

Internal helper used by
[`htc_upload()`](https://erwinlares.github.io/submitr/reference/htc_upload.md),
[`htc_download()`](https://erwinlares.github.io/submitr/reference/htc_download.md),
[`htc_submit()`](https://erwinlares.github.io/submitr/reference/htc_submit.md),
and
[`htc_status()`](https://erwinlares.github.io/submitr/reference/htc_status.md)
to resolve the config list. Checks the explicit argument first, then
falls back to the session option set by `htc_start_session()`, then
errors if neither is available.

## Usage

``` r
.resolve_config(config)
```

## Arguments

- config:

  A named list or `NULL`.

## Value

A validated config list with `username` and `server`.
