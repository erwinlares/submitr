# Stitch downloaded multi-job results back into one tibble

`htc_collect()` closes the gap
[`htc_download()`](https://erwinlares.github.io/submitr/reference/htc_download.md)
leaves open in `"multiple"` mode: after it fetches one tarball per
subset, nothing extracts them or brings their results back together the
way
[`toolero::run_by_group()`](https://erwinlares.github.io/toolero/reference/run_by_group.html)
does for a local run (S-G1). `htc_collect()` extracts every downloaded
tarball, reads each job's own `project-manifest.json` (written by
`toolero::generate_manifest()`) or, failing that, its raw
`accumulator.csv`, and row-binds them into one tibble describing every
artifact every job produced – with a `group_id` column identifying which
job each row came from and a `local_path` column pointing at the
extracted file on this machine.

## Usage

``` r
htc_collect(
  tarballs = NULL,
  local_path = ".",
  extract_dir = NULL,
  overwrite = FALSE,
  path = "."
)
```

## Arguments

- tarballs:

  A named character vector or `NULL`. Local tarball paths to collect,
  with names giving each one's group id. When `NULL` (the default),
  resolved automatically from the job manifest – the same subset names
  and script stem
  [`htc_download()`](https://erwinlares.github.io/submitr/reference/htc_download.md)
  itself used to name the files it fetched into `local_path`.

- local_path:

  A character string. The directory
  [`htc_download()`](https://erwinlares.github.io/submitr/reference/htc_download.md)
  saved tarballs into. Defaults to `"."`, matching
  [`htc_download()`](https://erwinlares.github.io/submitr/reference/htc_download.md)'s
  own default. Only consulted when `tarballs` is `NULL`.

- extract_dir:

  A character string or `NULL`. Directory to extract each tarball into,
  one subdirectory per group id. When `NULL` (the default), defaults to
  `local_path`.

- overwrite:

  Logical. If `TRUE`, deletes and re-extracts a group's subdirectory
  when it already exists. If `FALSE` (the default), an existing
  subdirectory is an error, so a second `htc_collect()` call never
  silently mixes stale and fresh results.

- path:

  A character string. Directory holding the job manifest
  (`htc-manifest.yaml`), consulted only when `tarballs` is `NULL`.
  Defaults to `"."`, matching the default used elsewhere in the family.

## Value

A tibble with one row per artifact, columns `group_id`, `file_path`,
`local_path`, `r_class`, `timestamp`, `function_used`, `status`,
`error_message`, `note`, `job_execution_context`, and
`job_generated_at`. In `"single"` mode this still has one `group_id`
(the script stem), for a schema that does not depend on which mode
produced it.

## Details

This does not attempt to load the artifacts themselves into R: their
types are whatever each job's own analysis chose to save (a model, a
plot, a data frame, a file), and no single loader is correct for all of
them. `local_path` is the join key back to the data – read it with
whatever `toolero::save_output()`'s `.f` originally wrote it with.

## Workflow

    htc_download(local_path = "downloads/")
    results <- htc_collect(local_path = "downloads/")

    # Load the actual saved objects, now that you know where they landed
    models <- lapply(
      results$local_path[results$r_class == "lm"],
      readRDS
    )

## Examples

``` r
# \donttest{
# Build a single-job tarball containing a project manifest, by hand, to
# show what htc_collect() does with one -- normally this tarball would
# have come from htc_download() after a real job finished.
job_dir <- withr::local_tempdir()
out_dir <- file.path(job_dir, "output")
dir.create(out_dir)
#> Warning: cannot create dir '/tmp/Rtmpye778X/file4a03515f02cd/output', reason 'No such file or directory'
saveRDS(mtcars, file.path(out_dir, "mtcars.rds"))
#> Warning: cannot open compressed file '/tmp/Rtmpye778X/file4a03515f02cd/output/mtcars.rds', probable reason 'No such file or directory'
#> Error in gzfile(file, mode): cannot open the connection
writeLines(
  jsonlite::toJSON(list(
    execution_context = "rscript",
    generated_at      = "2026-01-01T00:00:00.000Z",
    artifacts = list(list(
      file_path = "output/mtcars.rds", r_class = "data.frame",
      timestamp = "2026-01-01T00:00:00.000Z", function_used = "saveRDS",
      status = "success", error_message = NA, note = NA
    ))
  ), auto_unbox = TRUE),
  file.path(out_dir, "project-manifest.json")
)
#> Warning: cannot open file '/tmp/Rtmpye778X/file4a03515f02cd/output/project-manifest.json': No such file or directory
#> Error in file(con, "w"): cannot open the connection

local_path <- withr::local_tempdir()
withr::with_dir(job_dir, {
  utils::tar(file.path(local_path, "analysis-results.tar.gz"), "output",
             compression = "gzip", tar = "internal")
})
#> Error in setwd(dir = new): cannot change working directory

results <- htc_collect(
  tarballs   = c(analysis = file.path(local_path, "analysis-results.tar.gz")),
  extract_dir = withr::local_tempdir()
)
#> Error in htc_collect(tarballs = c(analysis = file.path(local_path, "analysis-results.tar.gz")),     extract_dir = withr::local_tempdir()): 1 tarball not found:
#> ✖ /tmp/Rtmpye778X/file4a036f1a6be/analysis-results.tar.gz
#> ℹ Run `htc_download()` first.
results
#> Error: object 'results' not found
# }
```
