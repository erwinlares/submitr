# Update the job manifest with new information

Internal helper that accumulates job metadata across the submitr
pipeline. Each function in the workflow calls `.update_manifest()` with
the information it knows.
[`htc_download()`](https://erwinlares.github.io/submitr/reference/htc_download.md)
and
[`htc_upload()`](https://erwinlares.github.io/submitr/reference/htc_upload.md)
read the accumulated manifest to resolve files automatically.

## Usage

``` r
.update_manifest(..., path = ".")
```

## Arguments

- ...:

  Named key-value pairs to add or update in the manifest. Because `path`
  below sits after the dots, it is matched exactly by name and can never
  be stored as a manifest field. Nothing in the package needs a field
  called `path`, but any future one would have to be named differently.

- path:

  A character string. Directory where `htc-manifest.yaml` is read from
  and written to. Defaults to `"."` (current working directory).
  Functions that write to a caller-supplied `output` directory (e.g.
  [`htc_gen_submit()`](https://erwinlares.github.io/submitr/reference/htc_gen_submit.md),
  [`htc_gen_executable()`](https://erwinlares.github.io/submitr/reference/htc_gen_executable.md))
  pass that directory through so the manifest travels with the generated
  files, and so package examples never write outside
  [`tempdir()`](https://rdrr.io/r/base/tempfile.html).

## Value

Called for its side effects. Returns `invisible(NULL)`.

## Details

The manifest is persisted to `htc-manifest.yaml` in `path`, not to
session options. Persisting it to disk means the manifest survives
across R sessions: restarting a session with
[`htc_start()`](https://erwinlares.github.io/submitr/reference/htc_start.md)
no longer discards job metadata recorded by an earlier call to
[`htc_gen_submit()`](https://erwinlares.github.io/submitr/reference/htc_gen_submit.md),
[`htc_gen_executable()`](https://erwinlares.github.io/submitr/reference/htc_gen_executable.md),
or
[`htc_submit()`](https://erwinlares.github.io/submitr/reference/htc_submit.md).

Passing `NULL` for a key removes it, which is what makes a single-mode
run clear the `subsets` and `subdatasets_path` left behind by an earlier
multiple-mode run in the same directory.
