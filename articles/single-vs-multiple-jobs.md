# Single Jobs vs Multiple Jobs on HTCondor

## Why two modes?

Not every analysis scales the same way. Sometimes you have one dataset
and one script and you want to run it once on hardware you don’t have
locally. Other times you have the same analysis but need to run it
independently across many subsets of the data: once per species, once
per site, once per simulation parameter, once per experimental
condition.

HTCondor handles both cases, but the job setup is different. The
container image, the submit file, the executable script, and the file
transfer strategy all change depending on whether you are submitting one
job or many. Getting the setup wrong is the most common source of job
failures, and the errors are not always obvious.

This vignette walks through both modes side by side using the same
analysis, a summary and visualization of the Palmer Penguins dataset. In
single mode, the analysis runs once over the full dataset. In multiple
mode, it runs once per species, producing independent results for
Adelie, Chinstrap, and Gentoo penguins.

The R script is identical in both cases. What changes is how the data
gets to the script and how the surrounding infrastructure is configured.

## The analysis

The analysis is simple by design so the focus stays on the
infrastructure. The R script loads a CSV file, computes a grouped
summary of body mass and flipper length, produces a scatterplot, and
writes both outputs to an `output/` folder.

The script uses
[`toolero::detect_execution_context()`](https://erwinlares.github.io/toolero/reference/detect_execution_context.html)
to resolve the input file path. In an interactive RStudio session, the
path is hardcoded for convenience. When rendered via Quarto, it comes
from the YAML `params` block. When run via `Rscript` on HTCondor, it
comes from the first command-line argument:

``` r

context <- toolero::detect_execution_context()

input_file <- switch(context,
  interactive = "data-raw/sample.csv",
  quarto      = params$input_file,
  rscript     = commandArgs(trailingOnly = TRUE)[1]
)

penguins <- toolero::read_clean_csv(input_file)
```

The output section writes results to a relative path:

``` r

output_dir <- "output"
dir.create(output_dir, showWarnings = FALSE, recursive = TRUE)

toolero::write_clean_csv(p_stats, file.path(output_dir, "results.csv"),
                         overwrite = TRUE)
ggplot2::ggsave(filename = file.path(output_dir, "plot.png"), plot = p_plot)
```

This is portable. `"output/"` resolves correctly in RStudio, in
`quarto render`, and on HTCondor, because the executable script sets the
working directory to HTCondor’s writable scratch space before calling
`Rscript`. `output/` is the folder name all three packages in the family
use, which is what lets the same line of R work in all three places.

## Two kinds of manifest

The word “manifest” appears in two different contexts in the submitr
workflow. They serve different purposes and should not be confused.

The **data manifest** is a CSV file produced by
`toolero::write_by_group(manifest = TRUE)`. It lists the subset data
files created when splitting a dataset by a grouping column.
[`htc_gen_submit()`](https://erwinlares.github.io/submitr/reference/htc_gen_submit.md)
reads it via the `queue_from` argument to produce the `subdatasets.csv`
that HTCondor uses to dispatch one job per subset. The data manifest is
only relevant in multiple mode.

The **job manifest** is `htc-manifest.yaml`, written by `submitr` into
your project beside `htc.cfg`. It accumulates metadata as you work
through the pipeline. Each function contributes a piece:
[`htc_gen_submit()`](https://erwinlares.github.io/submitr/reference/htc_gen_submit.md)
records the submit file, the mode, the results name, and in multiple
mode the subset names;
[`htc_gen_executable()`](https://erwinlares.github.io/submitr/reference/htc_gen_executable.md)
records the analysis script and the executable;
[`htc_submit()`](https://erwinlares.github.io/submitr/reference/htc_submit.md)
records the cluster ID HTCondor assigned and the remote directory it
submitted from. At the end,
[`htc_upload()`](https://erwinlares.github.io/submitr/reference/htc_upload.md)
and
[`htc_download()`](https://erwinlares.github.io/submitr/reference/htc_download.md)
read it to work out which files to move, with no glob patterns or manual
file lists required.

Because the job manifest is a file rather than something held in the R
session, it survives restarting R. That matters more than it may sound.
A job worth sending to CHTC usually takes a while, so you submit it in
one sitting and collect it in another, and in between you close RStudio
or your laptop sleeps. Calling
[`htc_start()`](https://erwinlares.github.io/submitr/reference/htc_start.md)
again does not disturb it.

|  | Data manifest | Job manifest |
|----|----|----|
| What is it | A CSV file (`manifest.csv`) | A YAML file (`htc-manifest.yaml`) |
| Created by | [`toolero::write_by_group()`](https://erwinlares.github.io/toolero/reference/write_by_group.html) | [`htc_gen_submit()`](https://erwinlares.github.io/submitr/reference/htc_gen_submit.md), [`htc_gen_executable()`](https://erwinlares.github.io/submitr/reference/htc_gen_executable.md), [`htc_submit()`](https://erwinlares.github.io/submitr/reference/htc_submit.md) |
| Contains | Subset filenames and row counts | Mode, script stem, results name, subset names, cluster ID, remote path |
| Used by | `htc_gen_submit(queue_from = ...)` | [`htc_upload()`](https://erwinlares.github.io/submitr/reference/htc_upload.md) and [`htc_download()`](https://erwinlares.github.io/submitr/reference/htc_download.md) |
| Lives | On disk in the project directory | On disk beside `htc.cfg` |
| Survives a restart | Yes | Yes |
| Relevant in | Multiple mode only | Both modes |

## Single mode: one dataset, one job

In single mode, the full dataset and the R script are baked into the
container image at build time. Nothing is transferred at runtime,
because the container has everything it needs. HTCondor runs the job,
the script writes results to `output/`, the executable script tars them
up, and HTCondor transfers the tarball back to the submit node.

### Building the container

The Dockerfile includes the R script and the data file via the
`code_file` and `data_file` arguments:

``` r

containr::generate_dockerfile(
  r_version = "4.5.0",
  code_file = "R/analysis.R",
  data_file = "data-raw/sample.csv",
  comments  = TRUE,
  verbose   = TRUE
)
```

This produces `COPY` instructions that preserve the local directory
structure inside the container:

``` dockerfile
COPY R/analysis.R /home/R/analysis.R
COPY data-raw/sample.csv /home/data-raw/sample.csv
```

Build and push the image:

``` r

containr::build_image(
  tag             = "registry.doit.wisc.edu/your.netid/penguins-analysis:1.0.0",
  tool_preference = "docker"
)
containr::push_image(
  image_id        = "abc123",
  netid           = "your.netid",
  project         = "penguins-analysis",
  tag             = "1.0.0",
  tool_preference = "docker",
  check_login     = FALSE
)
```

### Generating the submit file and executable

``` r

submitr::htc_gen_submit(
  output_file     = "analysis.sub",
  container_image = "registry.doit.wisc.edu/your.netid/penguins-analysis:1.0.0",
  executable      = "analysis.sh",
  r_script        = "R/analysis.R"
)

submitr::htc_gen_executable(
  r_script    = "R/analysis.R",
  output_file = "analysis.sh",
  data_files  = "data-raw/sample.csv"
)
```

`r_script` appears in both calls and has a different job in each.
[`htc_gen_executable()`](https://erwinlares.github.io/submitr/reference/htc_gen_executable.md)
uses it to write the `Rscript` line.
[`htc_gen_submit()`](https://erwinlares.github.io/submitr/reference/htc_gen_submit.md)
uses it only to derive the results tarball name, since it never opens
the executable script and so cannot infer what the job will produce.
Passing the same value to both is what guarantees the name the job
builds is the name the submit file asks for.

The generated `.sh` file:

``` bash
#!/bin/bash
set -euo pipefail

cd "${_CONDOR_SCRATCH_DIR:-$PWD}"

mkdir -p output
Rscript /home/R/analysis.R /home/data-raw/sample.csv
tar -czf analysis-results.tar.gz output
```

The script changes to the scratch directory, which is writable, creates
the output folder, runs the R script using absolute paths to the
baked-in files, and tars the results. The tarball lands in the scratch
directory where HTCondor expects to find it. Its name comes from
`r_script` with the directory and extension stripped, so `R/analysis.R`
gives `analysis-results.tar.gz`.

The generated `.sub` file:

    container_image = docker://registry.doit.wisc.edu/your.netid/penguins-analysis:1.0.0
    universe = container

    executable = analysis.sh

    should_transfer_files   = YES
    when_to_transfer_output = ON_EXIT
    transfer_output_files = analysis-results.tar.gz

    request_cpus   = 1
    request_memory = 4GB
    request_disk   = 4GB

    queue 1

No `transfer_input_files`, because everything is inside the container.

### Submitting and downloading

``` r

submitr::htc_start()
submitr::htc_upload()
job <- submitr::htc_submit("analysis.sub")
submitr::htc_status(cluster_id = job, watch = TRUE)
submitr::htc_download()
```

Neither
[`htc_upload()`](https://erwinlares.github.io/submitr/reference/htc_upload.md)
nor
[`htc_download()`](https://erwinlares.github.io/submitr/reference/htc_download.md)
takes arguments here, because the job manifest has everything they need.
[`htc_gen_submit()`](https://erwinlares.github.io/submitr/reference/htc_gen_submit.md)
recorded that this is a single-mode job with `analysis-results.tar.gz`
as its output, and which files were generated.
[`htc_submit()`](https://erwinlares.github.io/submitr/reference/htc_submit.md)
recorded the cluster ID and the remote directory. From those,
[`htc_download()`](https://erwinlares.github.io/submitr/reference/htc_download.md)
constructs the file list: one tarball plus three log files,
`{cluster_id}-0-job.log`, `.err` and `.out`.

You can also be explicit if you prefer:

``` r

submitr::htc_download(cluster_id = job)
submitr::htc_download(files = "*.tar.gz", local_path = "downloads/")
```

## Multiple mode: one analysis, three species

In multiple mode, the same R script runs independently on each subset of
the data. The container holds the R script and the software environment,
but not the data, since each subset file is transferred at runtime by
HTCondor.

The motivation is straightforward: rather than analyzing all three
penguin species together, you want to analyze each one independently.
Maybe the analysis is computationally expensive, or maybe the subsets
come from different sources and should be processed in isolation.
HTCondor runs one job per subset, in parallel, across available compute
resources.

### Splitting the data

Use
[`toolero::write_by_group()`](https://erwinlares.github.io/toolero/reference/write_by_group.html)
to split the dataset by species and produce a data manifest:

``` r

penguins <- toolero::read_clean_csv("data-raw/sample.csv")

toolero::write_by_group(
  penguins,
  group_col  = "species",
  output_dir = "data/jobs",
  manifest   = TRUE
)
```

This produces three CSV files (`adelie.csv`, `chinstrap.csv`,
`gentoo.csv`) and a data manifest (`manifest.csv`) listing them.

If a project splits more than one dataset, pass `prefix` as well.
Uploaded files land in a single flat directory on the access point, so
two datasets split on the same grouping column would produce the same
subset filenames and the second set would overwrite the first.

### Building the container

The container needs the R script but not the data. The data files are
transferred at runtime:

``` r

containr::generate_dockerfile(
  r_version = "4.5.0",
  code_file = "R/analysis.R",
  comments  = TRUE,
  verbose   = TRUE
)
```

No `data_file` argument. The Dockerfile copies only the script:

``` dockerfile
COPY R/analysis.R /home/R/analysis.R
```

Build and push as before.

### Generating the submit file and executable

``` r

submitr::htc_gen_submit(
  output_file     = "analysis.sub",
  container_image = "registry.doit.wisc.edu/your.netid/penguins-analysis:2.0.0",
  executable      = "analysis.sh",
  r_script        = "R/analysis.R",
  mode            = "multiple",
  queue_from      = "data/jobs/manifest.csv"
)

submitr::htc_gen_executable(
  r_script    = "R/analysis.R",
  output_file = "analysis.sh",
  mode        = "multiple"
)
```

[`htc_gen_submit()`](https://erwinlares.github.io/submitr/reference/htc_gen_submit.md)
reads the data manifest via `queue_from`, extracts the subset filenames,
and writes `subdatasets.csv` alongside the submit file. It also records
the mode, subset names, script stem, and the full local paths of the
subsets in the job manifest, which is how
[`htc_upload()`](https://erwinlares.github.io/submitr/reference/htc_upload.md)
later knows to send them and
[`htc_download()`](https://erwinlares.github.io/submitr/reference/htc_download.md)
knows what to bring back.

The generated `.sh` file:

``` bash
#!/bin/bash
set -euo pipefail

cd "${_CONDOR_SCRATCH_DIR:-$PWD}"

mkdir -p output
Rscript /home/R/analysis.R ${1}
tar -czf analysis-${1%.*}-results.tar.gz output
```

`${1}` is the subset filename passed by HTCondor, for example
`adelie.csv`. The R script receives it as
`commandArgs(trailingOnly = TRUE)[1]`. The tarball name combines the
script stem with the subset stem, so the Adelie job produces
`analysis-adelie-results.tar.gz`. `${1%.*}` is the shell’s way of
stripping the extension: without it the name would contain `.csv`,
describing a file that is not a CSV.

The generated `.sub` file:

    container_image = docker://registry.doit.wisc.edu/your.netid/penguins-analysis:2.0.0
    universe = container

    executable = analysis.sh
    arguments = $(file)

    should_transfer_files   = YES
    when_to_transfer_output = ON_EXIT
    transfer_input_files = $(file)
    transfer_output_files = analysis-$Fn(file)-results.tar.gz

    request_cpus   = 1
    request_memory = 4GB
    request_disk   = 4GB

    queue file from subdatasets.csv

Key differences from single mode: `arguments = $(file)` passes the
subset filename to the executable, `transfer_input_files = $(file)`
sends each subset to the execute node at runtime, and
`queue file from subdatasets.csv` submits one job per line in the file.

`$Fn(file)` is worth pausing on. It is an HTCondor submit macro that
expands a variable to its file name with the directory and extension
removed, so `adelie.csv` becomes `adelie`. It is the submit language’s
counterpart to the shell’s `${1%.*}`, and both are here for the same
reason: the shell script has to *create* the tarball under a name, and
the submit file has to *declare* the same name, or HTCondor looks for a
file that was never produced.

### Submitting and downloading

``` r

submitr::htc_start()
submitr::htc_upload()
job <- submitr::htc_submit("analysis.sub")
submitr::htc_status(cluster_id = job, watch = TRUE)
submitr::htc_download()
```

This is where the job manifest pays off.
[`htc_upload()`](https://erwinlares.github.io/submitr/reference/htc_upload.md)
sends the submit file, the executable, `subdatasets.csv`, and all three
subset files without being told, because
[`htc_gen_submit()`](https://erwinlares.github.io/submitr/reference/htc_gen_submit.md)
recorded where they are. On the way back, there are 12 files to retrieve
across three species and three log types per job, and
[`htc_download()`](https://erwinlares.github.io/submitr/reference/htc_download.md)
constructs the full list automatically: it reads the subset names and
script stem from the job manifest, composes
`analysis-adelie-results.tar.gz`, `analysis-chinstrap-results.tar.gz`
and `analysis-gentoo-results.tar.gz`, and generates the nine log file
names from the cluster ID and process count.

One call, no globs, no guessing:

``` r

# These are all equivalent
submitr::htc_download()
submitr::htc_download(cluster_id = job)
```

## Side-by-side comparison

### What lives in the container

|                            | Single mode | Multiple mode |
|----------------------------|-------------|---------------|
| R + packages + system libs | Yes         | Yes           |
| R script                   | Yes         | Yes           |
| Data files                 | Yes         | No            |

### The `.sub` file

| Directive | Single mode | Multiple mode |
|----|----|----|
| `container_image` | `docker://...` | `docker://...` |
| `universe` | `container` | `container` |
| `executable` | `analysis.sh` | `analysis.sh` |
| `arguments` | *(absent)* | `$(file)` |
| `transfer_input_files` | *(absent)* | `$(file)` |
| `transfer_output_files` | `analysis-results.tar.gz` | `analysis-$Fn(file)-results.tar.gz` |
| `queue` | `queue 1` | `queue file from subdatasets.csv` |

### The `.sh` file

| Line | Single mode | Multiple mode |
|----|----|----|
| Working directory | `cd "${_CONDOR_SCRATCH_DIR:-$PWD}"` | `cd "${_CONDOR_SCRATCH_DIR:-$PWD}"` |
| Output folder | `mkdir -p output` | `mkdir -p output` |
| Run script | `Rscript /home/R/analysis.R /home/data-raw/sample.csv` | `Rscript /home/R/analysis.R ${1}` |
| Package results | `tar -czf analysis-results.tar.gz output` | `tar -czf analysis-${1%.*}-results.tar.gz output` |

### The R script

The R script is identical in both modes. The only difference is where
the input file path comes from:

| Context               | Single mode              | Multiple mode        |
|-----------------------|--------------------------|----------------------|
| Interactive (RStudio) | Hardcoded path           | Hardcoded path       |
| Quarto render         | `params$input_file`      | `params$input_file`  |
| Rscript (HTCondor)    | Absolute path from `.sh` | `${1}` from HTCondor |

In both cases, `detect_execution_context()` resolves the right source
and `commandArgs(trailingOnly = TRUE)[1]` picks up whatever the `.sh`
script passes. The R script doesn’t know whether it’s running in single
or multiple mode.

### Files uploaded to the submit node

|                   | Single mode | Multiple mode |
|-------------------|-------------|---------------|
| `.sub` file       | Yes         | Yes           |
| `.sh` file        | Yes         | Yes           |
| `subdatasets.csv` | No          | Yes           |
| Subset data files | No          | Yes           |
| R script          | No          | No            |
| Full dataset      | No          | No            |

In both modes
[`htc_upload()`](https://erwinlares.github.io/submitr/reference/htc_upload.md)
works this out from the job manifest, so the column above describes what
it sends rather than what you have to type.

### Files downloaded after the job

|                 | Single mode                         | Multiple mode          |
|-----------------|-------------------------------------|------------------------|
| Result tarballs | 1 (`analysis-results.tar.gz`)       | 1 per subset (3 total) |
| Log files       | 3 (`{cluster}-0-job.{log,err,out}`) | 3 per subset (9 total) |
| Total files     | 4                                   | 12                     |

### How `htc_download()` resolves files

In both modes,
[`htc_download()`](https://erwinlares.github.io/submitr/reference/htc_download.md)
reads the job manifest that was built automatically during the workflow.
No file lists or glob patterns are needed.

|  | Single mode | Multiple mode |
|----|----|----|
| Job manifest knows | Tarball name, cluster ID, remote path | Script stem, subset names, cluster ID, remote path |
| Files resolved | 1 tarball + 3 logs = 4 files | 3 tarballs + 9 logs = 12 files |
| Researcher types | [`htc_download()`](https://erwinlares.github.io/submitr/reference/htc_download.md) | [`htc_download()`](https://erwinlares.github.io/submitr/reference/htc_download.md) |

The same zero-argument call works for both modes because the job
manifest captures the difference.

### How the two manifests relate

The data manifest and the job manifest are connected but distinct. The
data manifest feeds into the job manifest: when
[`htc_gen_submit()`](https://erwinlares.github.io/submitr/reference/htc_gen_submit.md)
reads the data manifest via `queue_from`, it extracts the subset
filenames and stores them in the job manifest. From that point on, the
job manifest carries the subset names forward so that
[`htc_upload()`](https://erwinlares.github.io/submitr/reference/htc_upload.md)
can send the right files and
[`htc_download()`](https://erwinlares.github.io/submitr/reference/htc_download.md)
can reconstruct the tarball names without re-reading anything.

    toolero::write_by_group()
      |
      v
    manifest.csv  (data manifest, a CSV on disk)
      |
      v
    htc_gen_submit(queue_from = "manifest.csv")
      |
      +---> subdatasets.csv    (sent to HTCondor)
      +---> htc-manifest.yaml  (job manifest: subsets, script stem, mode)
              |
              v
            htc_gen_executable()
              +---> htc-manifest.yaml  (executable and script recorded)
                      |
                      v
                    htc_submit()
                      +---> htc-manifest.yaml  (cluster ID, remote path added)
                              |
                              v
                            htc_download()  (resolves all files automatically)

## A note on the results naming change

If you followed an earlier version of this vignette, the tarball names
have changed. A multiple-mode job over `adelie.csv` now produces
`analysis-adelie-results.tar.gz` where it used to produce
`adelie.csv-results.tar.gz`, and the output folder is `output/` rather
than `results/`. Single-job names are unchanged.

This is a clean break rather than a compatibility layer. If you have
results sitting on the access point from a job submitted with an earlier
version, download them before upgrading, because
[`htc_download()`](https://erwinlares.github.io/submitr/reference/htc_download.md)
will look for names those jobs never created. The README has the full
rationale.

## When to use which mode

Use **single mode** when your analysis processes one dataset as a unit.
The container has everything baked in. Nothing is transferred at
runtime. This is the simplest path and the right starting point for a
first CHTC job.

Use **multiple mode** when you need to run the same analysis
independently across subsets of the data. The data files are transferred
at runtime, one per job. This scales naturally: adding more subsets
means more jobs, not more configuration.

Start with single mode to confirm the analysis runs correctly on CHTC.
Switch to multiple mode when you are confident the container, script,
and results pipeline are working.
