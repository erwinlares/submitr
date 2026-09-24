# Generate an HTCondor executable shell script for an R job

`htc_gen_executable()` writes a ready-to-use bash script (`.sh`) that
HTCondor runs inside the container for each job. The script changes to
HTCondor's writable scratch directory, creates an output folder, runs
the R script via `Rscript`, and compresses the results into a tarball
for transfer back to the submit node.

## Usage

``` r
htc_gen_executable(
  output_file = NULL,
  r_script = NULL,
  data_files = NULL,
  results_folder = NULL,
  home_dir = "/home",
  mode = "single",
  set_executable = TRUE,
  verbose = FALSE,
  comments = FALSE,
  output = ".",
  config = NULL,
  path = "."
)
```

## Arguments

- output_file:

  A character string or `NULL`. Name of the shell script to write. Must
  end in `".sh"`. When `NULL` (the default), resolves to the
  `executable_file` recorded in the job manifest by a previous
  [`htc_gen_submit()`](https://erwinlares.github.io/submitr/reference/htc_gen_submit.md)
  call (S-I3), so the name only has to be typed once regardless of which
  of the two generators runs first. Falls back to `"job.sh"` if neither
  an explicit value nor a manifest value is available. If the resolved
  value disagrees with an `executable_file` already in the manifest,
  warns rather than silently preferring one over the other.

- r_script:

  A character string. Name of the R script that HTCondor will run, e.g.
  `"analysis.R"`. Must be supplied explicitly – there is no default. If
  you used `toolero::create_qmd(use_purl = TRUE)`, the script is the
  `.R` file produced by `purl.R` after rendering. The script itself is
  **not** baked into the container image – it travels to the execute
  node as an uploaded job input file (see `transfer_input_files` in
  [`htc_gen_submit()`](https://erwinlares.github.io/submitr/reference/htc_gen_submit.md)),
  so editing it only requires re-uploading and resubmitting, never a
  container rebuild. Because HTCondor's file transfer does not preserve
  subdirectories, only the file's basename is used inside the script; if
  you pass `r_script = "R/analysis.R"`, make sure `"analysis.R"` (not
  the `R/` path) is what actually lands in `input_files` for
  [`htc_gen_submit()`](https://erwinlares.github.io/submitr/reference/htc_gen_submit.md).

- data_files:

  A character vector or `NULL`. Paths to data files baked into the
  container that should be passed to the R script as positional
  arguments. These are converted to absolute paths inside the container
  (e.g. `"data-raw/sample.csv"` becomes `"/home/data-raw/sample.csv"`).
  The R script receives them via `commandArgs(trailingOnly = TRUE)`.
  Defaults to `NULL`.

- results_folder:

  A character string or `NULL`. Name of the folder created in the
  scratch directory to hold job outputs before compression. When `NULL`
  (the default), resolves to `config$project$conventions$output_dir`
  when `config` is supplied (S-G5), falling back to `"output"`, the
  output folder used across the toolero family, when neither is
  available. Note that only this folder is created: if your analysis
  writes to `output/figures/`, the R script must create that subfolder
  itself, which `toolero::save_output()` does and a bare `ggsave()` does
  not.

- home_dir:

  A character string. The working directory inside the container where
  baked-in `data_files` live. Used to construct absolute paths for data
  file arguments only – it has no effect on where `r_script` is read
  from, since the R script is not baked into the image. Must match the
  `home_dir` used in
  [`containr::generate_dockerfile()`](https://erwinlares.github.io/containr/reference/generate_dockerfile.html)
  for `data_files`. Defaults to `"/home"`.

- mode:

  A character string. Execution mode. `"single"` (the default) runs the
  R script with only the data file arguments (if any), producing a
  tarball named after the script alone. `"multiple"` also passes the
  subset filename as the first positional argument via `${1}`, producing
  a per-job tarball that adds the subset's own stem, so `analysis.R`
  over `adelie.csv` gives `analysis-adelie-results.tar.gz`. Must match
  the `mode` used in
  [`htc_gen_submit()`](https://erwinlares.github.io/submitr/reference/htc_gen_submit.md),
  which has to declare the same name in `transfer_output_files`.

- set_executable:

  Logical. If `TRUE`, sets executable permissions on the generated
  script via [`Sys.chmod()`](https://rdrr.io/r/base/files2.html) so the
  file is ready to copy to the CHTC submit node without any additional
  steps. Defaults to `TRUE`. Set to `FALSE` if you prefer to manage
  permissions manually, in which case you must run `chmod +x` on the
  script before submitting your job.

- verbose:

  Logical. If `TRUE`, prints progress messages as each section of the
  script is written. Defaults to `FALSE`.

- comments:

  Logical. If `TRUE`, annotates each section with an explanatory comment
  describing what the line does. Useful for researchers learning the
  HTCondor executable script conventions. Defaults to `FALSE`.

- output:

  A character string. Directory where the shell script will be written.
  Defaults to `"."` (current working directory).

- config:

  A named list as returned by
  [`htc_config()`](https://erwinlares.github.io/submitr/reference/htc_config.md),
  or `NULL` (the default). When supplied with a `project` element (via
  `htc_config(project_config = )`),
  `config$project$conventions$output_dir` is used to default
  `results_folder` (S-G5). Not required – everything here can still be
  passed explicitly.

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

Called for its side effects. Writes a bash script to
`file.path(output, output_file)` and sets executable permissions when
`set_executable = TRUE`. Returns `invisible(NULL)`.

## How file paths work inside the container

The generated script draws on two different sources for its inputs, and
reads each one a different way:

**The R script** – `r_script` is not baked into the container image. It
travels to the execute node as an uploaded job input file, listed in
`transfer_input_files` by
[`htc_gen_submit()`](https://erwinlares.github.io/submitr/reference/htc_gen_submit.md).
HTCondor's file transfer does not preserve subdirectories, so whatever
you pass as `r_script` lands flat, by basename, in the scratch directory
alongside the executable script itself. The `Rscript` line therefore
refers to it by a bare relative name (e.g. `Rscript analysis.R`), not an
absolute, `home_dir`-prefixed path. This is deliberate: editing the
analysis script only requires re-uploading it and resubmitting the job,
with no container rebuild or registry push in between.

**Data files** – `data_files` are the opposite case: they are baked into
the container at build time by
[`containr::generate_dockerfile()`](https://erwinlares.github.io/containr/reference/generate_dockerfile.html)
and live under `home_dir` (default `"/home"`). The `Rscript` line passes
these as absolute paths (e.g. `/home/data-raw/sample.csv`) so they are
found regardless of the working directory. Baking data in rather than
uploading it keeps large or unchanging reference data out of every job's
file transfer.

**Writing** – the script changes to HTCondor's scratch directory
(`_CONDOR_SCRATCH_DIR`) before creating the output folder. This
directory is writable and is where HTCondor looks for
`transfer_output_files`. The R script writes outputs to `"output/"`
using a relative path, which resolves to the scratch directory.

This separation means the R script stays portable – `"output/"` works in
RStudio, in `quarto render`, and on HTCondor – while the `.sh` script
handles the HTCondor-specific directory setup.

## Relationship to htc_gen_submit()

The executable script generated by `htc_gen_executable()` is the file
referenced by the `executable` argument in
[`htc_gen_submit()`](https://erwinlares.github.io/submitr/reference/htc_gen_submit.md).
The two functions should always use the same `mode`. In `"multiple"`
mode, HTCondor passes each subset filename to the script as `${1}`,
which is forwarded to the R script as a positional argument. The R
script must be written to accept this argument – the recommended
approach is
[`toolero::detect_execution_context()`](https://erwinlares.github.io/toolero/reference/detect_execution_context.html):

    context <- toolero::detect_execution_context()

    input_file <- switch(context,
      interactive = "data-raw/sample.csv",
      quarto      = params$input_file,
      rscript     = commandArgs(trailingOnly = TRUE)[1]
    )

## Examples

``` r
# output writes the generated .sh file; path is where the job manifest
# (htc-manifest.yaml) gets read from and written to. The two are
# independent arguments (see @param path), so both must point at the
# same scratch directory here to keep the manifest out of the current
# working directory.
tmp <- tempdir()

# Single-job executable script with baked-in data
htc_gen_executable(
  r_script   = "R/analysis.R",
  data_files = "data-raw/sample.csv",
  output     = tmp,
  path       = tmp
)

# Multiple-job executable script
htc_gen_executable(
  r_script = "R/analysis.R",
  mode     = "multiple",
  output   = tmp,
  path     = tmp
)

# Custom names with annotations
htc_gen_executable(
  output_file = "run.sh",
  r_script    = "R/run-analysis.R",
  data_files  = c("data-raw/train.csv", "data-raw/test.csv"),
  comments    = TRUE,
  verbose     = TRUE,
  output      = tmp,
  path        = tmp
)
#> Warning: `output_file` ("run.sh") does not match the
#>   executable script name already recorded in the job
#>   manifest ("job.sh").
#> ℹ That name came from an earlier `htc_gen_submit()` call.
#> ℹ If this is deliberate, ignore this warning -- this script
#>   will be written as "run.sh". Otherwise, check
#>   that the two calls agree on the script's name.
#> Writing shebang line
#> Writing shell options
#> Writing working directory change
#> Writing results folder creation
#> Writing Rscript execution line (mode: single)
#> Writing compression line
#> Set executable permissions on /tmp/Rtmpye778X/run.sh
#> ✔ Executable script written to /tmp/Rtmpye778X/run.sh
```
