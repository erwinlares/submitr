# Preflight check for a submitr job before upload or submission

`htc_check()` verifies, locally and in seconds, several things that
would otherwise only surface an hour later as a held or failed job on
the cluster (S-G4): that every file the job depends on actually exists
on this machine, that a `"multiple"`-mode job's subset files still match
what `subdatasets.csv` expects, that the resource request looks
plausible, and – best effort, when a container tool is available locally
– that the container image looks reachable.

## Usage

``` r
htc_check(
  container_image = NULL,
  input_files = NULL,
  data_files = NULL,
  resources = NULL,
  verbose = TRUE,
  path = "."
)
```

## Arguments

- container_image:

  A character string or `NULL`. The container image reference to check,
  e.g. `"registry.doit.wisc.edu/netid/myimage:1.0.0"`. When `NULL` (the
  default), resolves to the `container_image` recorded in the job
  manifest by
  [`htc_gen_submit()`](https://erwinlares.github.io/submitr/reference/htc_gen_submit.md).
  When still `NULL`, image checks are skipped.

- input_files:

  A character vector or `NULL`. Local paths that are expected to exist
  before upload – normally the same value passed to
  [`htc_gen_submit()`](https://erwinlares.github.io/submitr/reference/htc_gen_submit.md).
  When `NULL` (the default), resolves to `input_files` recorded in the
  manifest.

- data_files:

  A character vector or `NULL`. Local paths to data files expected to
  exist before a container image bakes them in – normally the same value
  passed to
  [`htc_gen_executable()`](https://erwinlares.github.io/submitr/reference/htc_gen_executable.md).
  When `NULL` (the default), resolves to `data_files` recorded in the
  manifest.

- resources:

  A named list with `cpus`, `memory`, and `disk`, or `NULL`. When `NULL`
  (the default), resolves to the resolved resource values
  [`htc_gen_submit()`](https://erwinlares.github.io/submitr/reference/htc_gen_submit.md)
  recorded in the manifest (whichever preset, or `custom_resources`, was
  actually used).

- verbose:

  Logical. If `TRUE` (the default), prints a line for every check
  performed, not just the ones that found something. Set `FALSE` to only
  see problems.

- path:

  A character string. Directory holding the job manifest
  (`htc-manifest.yaml`). Defaults to `"."`, matching the default used
  elsewhere in the family.

## Value

A tibble with one row per issue found, columns `check`, `severity`
(`"error"` or `"warning"`), and `message`. Zero rows means nothing was
found. Returned invisibly; call
[`print()`](https://rdrr.io/r/base/print.html) explicitly or assign it
to inspect the detail behind the printed summary.

## Details

Every argument can be resolved from the job manifest, so the common case
is `htc_check()` with no arguments at all, run right after
[`htc_gen_submit()`](https://erwinlares.github.io/submitr/reference/htc_gen_submit.md)
and
[`htc_gen_executable()`](https://erwinlares.github.io/submitr/reference/htc_gen_executable.md)
and before
[`htc_upload()`](https://erwinlares.github.io/submitr/reference/htc_upload.md).

## What counts as an error versus a warning

A missing input, data, or subset file is an `"error"`: the job will not
run without it, full stop. A resource request outside typical bounds, a
`container_image` tagged `latest`, or an image that could not be
confirmed pullable are `"warning"`s – each might be exactly what you
intend, and none of them is something `htc_check()` can be certain about
from the local machine alone.
[`htc_upload()`](https://erwinlares.github.io/submitr/reference/htc_upload.md)'s
own `check` argument only blocks the upload on `"error"`s.

## The image check is best effort

`htc_check()` only attempts to confirm `container_image` is pullable
when `podman` or `docker` is found on the local `PATH`, via
`<tool> manifest inspect`. A failure there is reported as a warning, not
an error, and is not conclusive either way: it may mean the image
genuinely does not exist, or simply that you are not logged in to the
registry from this machine, or that the tool timed out. When neither
tool is found, the image check is skipped entirely and reported as such.

## See also

[`htc_upload()`](https://erwinlares.github.io/submitr/reference/htc_upload.md)'s
`check` argument, which runs this automatically and aborts before
uploading if an `"error"`-level issue is found.

## Examples

``` r
# \donttest{
tmp <- withr::local_tempdir()
htc_gen_submit(
  container_image = "registry.doit.wisc.edu/netid/myimage:latest",
  resources       = "small",
  output          = tmp,
  path            = tmp
)
#> Error in htc_gen_submit(container_image = "registry.doit.wisc.edu/netid/myimage:latest",     resources = "small", output = tmp, path = tmp): Output directory /tmp/Rtmpye778X/file4a032142e2f9 does not exist.
htc_check(path = tmp)
#> ℹ No `input_files` to check (none supplied or recorded).
#> ℹ No `data_files` to check (none supplied or recorded).
#> ℹ Mode is "single" (or unset) -- no subset files to check.
#> ℹ No `resources` to check (none supplied or recorded).
#> ℹ No `container_image` to check (none supplied or recorded).
#> ✔ Preflight check passed -- no issues found.
# }
```
