# Start an HTC session

`htc_start()` calls
[`htc_config()`](https://erwinlares.github.io/submitr/reference/htc_config.md)
to read or create the connection configuration, then stores the result
as a session-level option so that subsequent `htc_*()` functions can use
it without requiring an explicit `config` argument on every call.

## Usage

``` r
htc_start(...)
```

## Arguments

- ...:

  Arguments passed to
  [`htc_config()`](https://erwinlares.github.io/submitr/reference/htc_config.md).
  Common arguments include `username`, `server`, `path`, and
  `overwrite`.

## Value

Invisibly returns the config list (same as
[`htc_config()`](https://erwinlares.github.io/submitr/reference/htc_config.md)).

## Details

After calling `htc_start()`, functions like
[`htc_upload()`](https://erwinlares.github.io/submitr/reference/htc_upload.md),
[`htc_submit()`](https://erwinlares.github.io/submitr/reference/htc_submit.md),
[`htc_status()`](https://erwinlares.github.io/submitr/reference/htc_status.md),
and
[`htc_download()`](https://erwinlares.github.io/submitr/reference/htc_download.md)
will automatically use the stored configuration when `config = NULL`
(the default). You can still pass `config` explicitly to any function to
override the session config.

The session config is stored via `options(submitr.config = ...)` and is
cleared automatically when the R session ends. To clear it manually,
call `options(submitr.config = NULL)`.

## Examples

``` r
if (FALSE) { # \dontrun{
# Start a session -- all subsequent htc_*() calls use this config
htc_start()

# Now these work without config = cfg
htc_upload(files = c("job.sub", "job.sh"))
htc_submit(submit_file = "job.sub")
htc_status(cluster_id = 6351616)
htc_download(files = "*.tar.gz")

# You can still override for a specific call
other_cfg <- htc_config(path = "other-project/")
htc_upload(files = "job.sub", config = other_cfg)

# Clear the session config manually
options(submitr.config = NULL)
} # }
```
