# Unpack downloaded results and index them, one row per job

`htc_collect()` is the step after
[`htc_download()`](https://erwinlares.github.io/submitr/reference/htc_download.md).
It extracts every job's results tarball into its own folder and returns
the *job index*: a tibble with one row per job saying whether its
results came back, where they landed, what files they hold, and where
that job's HTCondor log files are. In `"multiple"` mode that is one row
per subset, the HTC-side counterpart to the tibble
[`toolero::run_by_group()`](https://erwinlares.github.io/toolero/reference/run_by_group.html)
returns for a local run.

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
  resolved from the submission state: the same subset names and script
  stem
  [`htc_download()`](https://erwinlares.github.io/submitr/reference/htc_download.md)
  used to name the files it fetched into `local_path`.

- local_path:

  A character string. The directory
  [`htc_download()`](https://erwinlares.github.io/submitr/reference/htc_download.md)
  saved tarballs into. Defaults to `"."`, matching
  [`htc_download()`](https://erwinlares.github.io/submitr/reference/htc_download.md)'s
  own default. Only consulted when `tarballs` is `NULL`.

- extract_dir:

  A character string or `NULL`. Directory to extract into, one
  subdirectory per group id. When `NULL` (the default), defaults to
  `local_path`.

- overwrite:

  Logical. If `TRUE`, deletes and re-extracts a group's subdirectory
  when it already exists. If `FALSE` (the default), any existing
  subdirectory is an error, raised before anything is extracted, so a
  second `htc_collect()` call never silently mixes stale and fresh
  results.

- path:

  A character string. Directory holding the submission state
  (`htc-manifest.yml`). Defaults to `"."`, matching the default used
  elsewhere in the family. Consulted for the tarball names when
  `tarballs` is `NULL`, and in every case for the cluster ID, process
  numbers, container image, and results folder.

## Value

The job index: a tibble with one row per job and these columns.

- `group_id` – the subset stem in `"multiple"` mode (`"adelie"` for
  `adelie.csv`), the script stem in `"single"` mode, or the name given
  in `tarballs`.

- `proc_id` – the job's HTCondor process number, from its position in
  the submission state; `NA` when it cannot be matched.

- `cluster_id` – from the submission state; `NA` when absent.

- `extracted` – whether the tarball was found and extracted.

- `n_files` – how many files the results folder holds; `NA` when not
  extracted.

- `has_record` – whether the results folder holds an output record
  (`project-manifest.json`, written by `toolero::generate_manifest()`).
  The file is only checked for, never read. `NA` when not extracted.

- `output_dir` – where the job's results folder landed; `NA` when not
  extracted.

- `files` – a list column of paths relative to `output_dir`.

- `log`, `err`, `out` – local paths to the job's three HTCondor files,
  found beside its tarball; `NA` when not there.

- `container_image` – from the submission state; `NA` when absent.

## Details

It works for any analysis, whatever the script wrote into its results
folder, and never opens the files themselves: their types are whatever
each job chose to save, and no single reader is right for all of them.
Read them with whatever wrote them, using `output_dir` and `files` (see
the Workflow section).

A job whose tarball is missing, or will not extract, still gets a row,
with `extracted = FALSE`, and the collection carries on with the other
jobs. A job whose R script fails still sends its tarball back (see
[`htc_gen_executable()`](https://erwinlares.github.io/submitr/reference/htc_gen_executable.md)),
so a missing tarball means the job stopped before it got that far: the
container did not start, a file it needed was not transferred, or the
job was removed. Its `.err` and `.log` files, in the `err` and `log`
columns when they were downloaded, are the place to look.

## Workflow

    htc_download(local_path = "downloads/")
    index <- htc_collect(local_path = "downloads/")

    # Which jobs came back?
    index[, c("group_id", "extracted", "n_files")]

    # Why did a job fail? Its .err file usually says.
    readLines(index$err[!index$extracted][1])

    # Full paths to every file each job produced
    paths <- Map(file.path, index$output_dir, index$files)
    models <- lapply(unlist(paths[index$extracted]), readRDS)

## Examples

``` r
# \donttest{
# Build a single-job tarball by hand to show what htc_collect() does with
# one -- normally this tarball would have come from htc_download() after
# a real job finished.
job_dir <- tempfile("job")
dir.create(file.path(job_dir, "output"), recursive = TRUE)
saveRDS(mtcars, file.path(job_dir, "output", "mtcars.rds"))

local_path <- tempfile("downloads")
dir.create(local_path)
tarball <- file.path(local_path, "analysis-results.tar.gz")
old <- setwd(job_dir)
utils::tar(tarball, "output", compression = "gzip", tar = "internal")
setwd(old)

index <- htc_collect(
  tarballs    = c(analysis = tarball),
  extract_dir = tempfile("collected")
)
#> ✔ Collected 1 of 1 job into /tmp/Rtmpl7h864/collected4ac8186aa071.
index
#> # A tibble: 1 × 12
#>   group_id proc_id cluster_id extracted n_files has_record output_dir      files
#>   <chr>      <int> <chr>      <lgl>       <int> <lgl>      <chr>           <lis>
#> 1 analysis      NA NA         TRUE            1 FALSE      /tmp/Rtmpl7h86… <chr>
#> # ℹ 4 more variables: log <chr>, err <chr>, out <chr>, container_image <chr>
index$files[[1]]
#> [1] "mtcars.rds"
# }
```
