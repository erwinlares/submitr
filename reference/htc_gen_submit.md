# Generate an HTCondor submit file for a containerized R job

`htc_gen_submit()` writes a ready-to-use HTCondor submit file (`.sub`)
for running a containerized R job on an HTC cluster such as CHTC. It
supports both single-job and multiple-job submission modes.

## Usage

``` r
htc_gen_submit(
  output_file = "job.sub",
  container_image = NULL,
  executable = NULL,
  r_script = NULL,
  input_files = NULL,
  output_files = NULL,
  mode = "single",
  queue = 1L,
  queue_from = NULL,
  resources = "small",
  custom_resources = NULL,
  gpu = FALSE,
  gpu_options = NULL,
  verbose = FALSE,
  comments = FALSE,
  output = ".",
  config = NULL,
  path = "."
)
```

## Arguments

- output_file:

  A character string. Name of the submit file to write. Must end in
  `".sub"`. Defaults to `"job.sub"`.

- container_image:

  A character string. The container image to use, e.g.
  `"registry.doit.wisc.edu/netid/myimage"`. The `docker://` prefix is
  added automatically if not already present. Defaults to `NULL`, which
  writes a placeholder comment in the submit file.

- executable:

  A character string or `NULL`. The shell script that HTCondor will run
  inside the container, e.g. `"analysis.sh"`. When `NULL` (the default),
  resolves to the `executable_file` recorded in the job manifest by a
  previous
  [`htc_gen_executable()`](https://erwinlares.github.io/submitr/reference/htc_gen_executable.md)
  call (S-I3), so the name only has to be typed once regardless of which
  of the two generators runs first. If neither an explicit value nor a
  manifest value is available, writes a placeholder comment in the
  submit file instead. If the resolved value here disagrees with an
  `executable_file` already in the manifest, warns rather than silently
  preferring one over the other.

- r_script:

  A character string. The R script the job runs, e.g. `"R/analysis.R"`.
  Used only to derive the default `output_files` name, which must match
  the tarball
  [`htc_gen_executable()`](https://erwinlares.github.io/submitr/reference/htc_gen_executable.md)
  tells the job to build. This function never reads the executable
  script or the Dockerfile, so the script's name cannot be inferred and
  has to be given here. If omitted, the value recorded in the job
  manifest by a previous
  [`htc_gen_executable()`](https://erwinlares.github.io/submitr/reference/htc_gen_executable.md)
  call is used; note that the documented workflow calls this function
  first, in which case there is nothing recorded yet. Ignored when
  `output_files` is supplied. Note that supplying `r_script` here does
  not transfer it – the script is not baked into the container image
  (see
  [`htc_gen_executable()`](https://erwinlares.github.io/submitr/reference/htc_gen_executable.md)),
  so its basename must also appear in `input_files` or HTCondor will not
  send it to the execute node; this function warns when it does not.
  Defaults to `NULL`.

- input_files:

  A character vector. Files to transfer to the job's working directory
  before execution, e.g. `c("analysis.R", "data.csv")`. This must
  include the R script named by `r_script` (by basename) – the script
  travels to the execute node as an uploaded input file, not as part of
  the container image. In `"multiple"` mode, the per-job subset file is
  added automatically from the manifest; use this argument for files
  shared across all jobs (e.g. the analysis script). Defaults to `NULL`.

- output_files:

  A character vector. Files to transfer back from the job's working
  directory after execution. When not supplied, it is derived from
  `r_script` following the family convention
  `<script stem>[-<subset stem>]-results.tar.gz`, giving for example
  `analysis-results.tar.gz` in `"single"` mode and
  `analysis-$Fn(file)-results.tar.gz` in `"multiple"` mode. `$Fn()` is
  an HTCondor submit macro that strips a value's directory and
  extension, so a subset named `adelie.csv` yields
  `analysis-adelie-results.tar.gz`. Supplying this argument overrides
  the derivation entirely. Defaults to `NULL`.

- mode:

  A character string. Submission mode. `"single"` (the default) submits
  one job. `"multiple"` submits one job per row in the manifest supplied
  to `queue_from`, passing each subset file as a positional argument to
  the executable via `arguments = $(file)`.

- queue:

  A positive integer. Number of identical jobs to submit. Only used when
  `mode = "single"`. Defaults to `1`.

- queue_from:

  A character string or `NULL`. Path to the manifest file produced by
  `toolero::write_by_group(manifest = TRUE)`. Required when
  `mode = "multiple"`, unless it can be resolved from `config` (S-G5):
  when `NULL` and `config$project$conventions$split_dir` is set,
  defaults to `file.path(split_dir, "manifest.csv")` –
  `write_by_group()` always names its manifest `manifest.csv`, so the
  convention's directory is enough to reconstruct the full path. The
  `file_path` column is extracted and written alongside the submit file
  as `subdatasets.csv`, which HTCondor reads to generate one job per
  subset file.

- resources:

  A character string. Compute resource preset. One of `"small"`,
  `"medium"`, `"large"`, or `"custom"` (requires `custom_resources`).
  Default preset values reflect CHTC recommendations and are loaded from
  `inst/extdata/htc-resources.yaml`. A local `htc-resources.yaml` in the
  working directory takes precedence over the package default, allowing
  per-project customization. Defaults to `"small"`.

- custom_resources:

  A named list. Required when `resources = "custom"`. Must contain
  `cpus` (integer), `memory` (character, e.g. `"8GB"`), and `disk`
  (character, e.g. `"4GB"`). Ignored when `resources` is not `"custom"`.

- gpu:

  Logical. If `TRUE`, adds GPU resource requests to the submit file.
  Defaults to `FALSE`.

- gpu_options:

  A named list or `NULL`. Fine-grained GPU options applied when
  `gpu = TRUE`. Supported keys: `request_gpus` (integer, default `1`),
  `want_gpu_lab` (logical, default `TRUE`), `min_capability` (numeric,
  e.g. `8.0` for A100; `NULL` to omit), `min_memory_mb` (integer in MB,
  e.g. `40000`; `NULL` to omit). When `gpu = TRUE` and
  `gpu_options = NULL`, CHTC defaults are used.

- verbose:

  Logical. If `TRUE`, prints progress messages as each section of the
  submit file is written. Defaults to `FALSE`.

- comments:

  Logical. If `TRUE`, annotates each section with an explanatory comment
  describing what the section does and how to use it. Defaults to
  `FALSE`.

- output:

  A character string. Directory where the submit file (and, in
  `"multiple"` mode, `subdatasets.csv`) will be written. Defaults to
  `"."` (current working directory).

- config:

  A named list as returned by
  [`htc_config()`](https://erwinlares.github.io/submitr/reference/htc_config.md),
  or `NULL` (the default). When supplied with a `project` element (via
  `htc_config(project_config = )`),
  `config$project$conventions$split_dir` is used to default `queue_from`
  (S-G5). Not required – everything here can still be passed explicitly.

- path:

  A character string. Directory where the job manifest
  (`htc-manifest.yaml`) is read from and written to. Defaults to `"."`
  (the current working directory), matching the default used by
  [`htc_upload()`](https://erwinlares.github.io/submitr/reference/htc_upload.md),
  [`htc_submit()`](https://erwinlares.github.io/submitr/reference/htc_submit.md),
  and
  [`htc_download()`](https://erwinlares.github.io/submitr/reference/htc_download.md).
  This is independent of `output`: if you write generated files to a
  subfolder with `output`, pass the same `path` explicitly to every
  function in the pipeline so they all find the same manifest.

## Value

Called for its side effects. Writes an HTCondor submit file to
`file.path(output, output_file)`. In `"multiple"` mode also writes
`subdatasets.csv` to `output`. Returns `invisible(NULL)`.

## Multiple-job mode and positional arguments

When `mode = "multiple"`, HTCondor passes each subset filename to the
executable as a positional argument via `arguments = $(file)`. Your R
script must be written to accept and use this argument. The recommended
approach is to use
[`toolero::detect_execution_context()`](https://erwinlares.github.io/toolero/reference/detect_execution_context.html)
in your analysis script, which resolves the input file path correctly
across interactive, Quarto, and Rscript execution contexts:

    context <- toolero::detect_execution_context()

    input_file <- switch(context,
      interactive = "data/penguins.csv",
      quarto      = params$input_file,
      rscript     = commandArgs(trailingOnly = TRUE)[1]
    )

    data <- readr::read_csv(input_file)

The typical workflow is:

1.  Write and develop your analysis in `analysis.qmd` using
    [`toolero::detect_execution_context()`](https://erwinlares.github.io/toolero/reference/detect_execution_context.html)
    for data loading.

2.  Split your dataset with `toolero::write_by_group(manifest = TRUE)`
    to produce subset CSV files and a `manifest.csv`.

3.  Strip `analysis.qmd` to `R/analysis.R` with
    [`knitr::purl()`](https://rdrr.io/pkg/knitr/man/knit.html).

4.  Call
    `htc_gen_submit(mode = "multiple", queue_from = "manifest.csv")` to
    produce the submit file and `subdatasets.csv`.

5.  Copy `R/analysis.R`, the subset data files, `analysis.sub`,
    `analysis.sh`, and `subdatasets.csv` to CHTC and submit.

## Resource presets

Resource presets are loaded at runtime from
`inst/extdata/htc-resources.yaml`. To customize presets for a specific
project, copy that file to your project directory as
`htc-resources.yaml` and edit the values. `htc_gen_submit()` checks for
a local `htc-resources.yaml` in the working directory first, falling
back to the package default if none is found.

## Examples

``` r
# Single-job submit file with default resource preset
htc_gen_submit(output = tempdir())

# Single-job submit file with medium resources and file transfer
htc_gen_submit(
  output_file     = "analysis.sub",
  container_image = "docker://registry.doit.wisc.edu/netid/myimage",
  executable      = "analysis.sh",
  r_script        = "R/analysis.R",
  input_files     = "R/analysis.R",
  resources       = "medium",
  output          = tempdir()
)

# Annotated submit file useful for learning HTCondor syntax
htc_gen_submit(
  output_file = "annotated.sub",
  comments    = TRUE,
  verbose     = TRUE,
  output      = tempdir()
)
#> Writing submit file header
#> Writing container section
#> Writing executable section
#> Writing file transfer section
#> Writing logging section
#> Writing resources section (small preset: 1 CPU / 4GB RAM / 4GB disk)
#> Writing queue section (1 job)
#> ✔ Submit file written to /tmp/Rtmpye778X/annotated.sub

# Custom resource request
htc_gen_submit(
  resources        = "custom",
  custom_resources = list(cpus = 2, memory = "8GB", disk = "4GB"),
  output           = tempdir()
)

if (FALSE) { # \dontrun{
# Multiple-job submit file driven by a write_by_group() manifest
htc_gen_submit(
  output_file     = "analysis.sub",
  container_image = "docker://registry.doit.wisc.edu/netid/myimage",
  executable      = "analysis.sh",
  input_files     = "analysis.R",
  mode            = "multiple",
  queue_from      = "data/manifest.csv",
  resources       = "medium",
  output          = "."
)
} # }
```
