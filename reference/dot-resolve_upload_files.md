# Resolve files to upload from the job manifest

Internal helper used by
[`htc_upload()`](https://erwinlares.github.io/submitr/reference/htc_upload.md)
when `files = NULL`. Builds the list of local files to copy to the
submit node from the job manifest accumulated by
[`htc_gen_submit()`](https://erwinlares.github.io/submitr/reference/htc_gen_submit.md)
and
[`htc_gen_executable()`](https://erwinlares.github.io/submitr/reference/htc_gen_executable.md):
the submit file, the executable script, any shared input files, and – in
`"multiple"` mode – the subdatasets manifest and the individual subset
data files.

## Usage

``` r
.resolve_upload_files(manifest)
```

## Arguments

- manifest:

  A named list from
  [`.get_manifest()`](https://erwinlares.github.io/submitr/reference/dot-get_manifest.md),
  or `NULL`.

## Value

A character vector of local file paths to upload, possibly empty.

## Details

Every field used here holds a path as seen from the machine running R,
not the bare name HTCondor sees on the submit node. That distinction
matters when the generators wrote into a non-default `output` directory:
`submit_file` is `"job.sub"` but `submit_path` is `"jobs/job.sub"`, and
only the latter will survive
[`file.exists()`](https://rdrr.io/r/base/files.html).
