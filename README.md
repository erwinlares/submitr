# submitr <img src="man/figures/logo.png" align="right" height="139" alt="submitr package logo"/>

<!-- badges: start -->
[![R-CMD-check](https://github.com/erwinlares/submitr/actions/workflows/R-CMD-check.yaml/badge.svg)](https://github.com/erwinlares/submitr/actions/workflows/R-CMD-check.yaml)
[![Lifecycle: experimental](https://img.shields.io/badge/lifecycle-experimental-orange.svg)](https://lifecycle.r-lib.org/articles/stages.html#experimental)
<!-- badges: end -->

## From the Notebook to the Cluster

You have an R analysis that runs on your laptop. Maybe it takes a while.
Maybe you need to run it many times — once per species, once per county, once
per experimental condition. Maybe both.

CHTC's high-throughput computing infrastructure can run hundreds or thousands
of those jobs simultaneously, drawing on a pool of compute resources that no
individual laptop or lab server can match. The barrier is not the computing —
it is the setup. You need to package your software environment, write a submit
file, transfer files to a remote server, and learn enough HTCondor syntax to
get a job into the queue. That is a lot to ask of a researcher whose expertise
is in the science, not the infrastructure.

`submitr` is designed to lower that barrier. It generates the files HTCondor
needs, wraps the SSH and SCP commands that move files to and from the submit
node, and monitors job progress — all from R. You describe your job in R
function calls. `submitr` handles the rest.

If you are new to CHTC, `submitr` gives you a guided path to your first
successful submission. If you already use CHTC, `submitr` reduces repetitive
setup work and makes common submission patterns easier to reproduce, review,
and share.

---

## The toolero family

`submitr` is the third step in a three-package family for reproducible
research computing:

```
toolero     organize, scaffold, split
  └─ containr   freeze the software environment in a container
       └─ submitr    send the analysis to CHTC and retrieve results
```

A typical path looks like this:

```r
# toolero: organize the project and split the data
toolero::init_project("my-analysis")
toolero::write_by_group(data, group_col = "species",
                        output_dir = "data/jobs", manifest = TRUE)

# containr: containerize the software environment
containr::generate_dockerfile(r_version = "4.4.0", output = ".")
containr::build_image()
containr::push_image(image_id = "974123909a36", netid = "lares",
                     project = "my-analysis", tag = "1.0.0")

# submitr: submit to CHTC and retrieve results
cfg        <- submitr::htc_config()
cluster_id <- submitr::htc_submit(submit_file = "analysis.sub", config = cfg)
submitr::htc_status(cluster_id = cluster_id, config = cfg, watch = TRUE)
submitr::htc_download(files = "*.tar.gz", config = cfg, local_path = "results/")
```

Each package is useful on its own. Together they form a complete path from a
new R project to a completed HTC run.

---

## Installation

Install the development version from GitHub:

```r
# install.packages("pak")
pak::pak("erwinlares/submitr")
```

## Requirements

- R (>= 4.2.0)
- SSH access to a CHTC submit node (e.g. `ap2002.chtc.wisc.edu`)
- A container image pushed to a registry accessible from CHTC
  (see [containr](https://github.com/erwinlares/containr))

---

## What an HTCondor job needs

Before walking through the workflow, it helps to understand what HTCondor
actually requires to run a job. At minimum, you need:

- A **container image** that holds your R installation, packages, and system
  libraries — built and pushed with `containr`
- A **submit file** (`.sub`) that describes the job: which container to use,
  which script to run, what resources to request, and where to send output
- An **executable script** (`.sh`) that HTCondor runs inside the container —
  typically a short bash script that calls `Rscript`
- Your **analysis script** and any **input data** transferred to the submit node

`htc_gen_submit()` and `htc_gen_executable()` generate the first two.
`htc_upload()` transfers everything to the submit node. `htc_submit()` starts
the job.

---

## A first single-job submission

The simplest path is one job: one container, one script, one result.

### Step 1 — Configure your connection

On first use, `htc_config()` prompts for your NetID and server, writes
`htc.cfg` to your project directory, and displays instructions for setting
up SSH connection reuse (ControlMaster) to avoid repeated Duo MFA prompts:

```r
library(submitr)

cfg <- htc_config()
```

Subsequent calls read the existing `htc.cfg` and validate the connection:

```r
cfg <- htc_config()
#> Reading HTC config from ./htc.cfg
#> ✔ Connected to "ap2002.chtc.wisc.edu" as "erwin.lares".
```

### Step 2 — Generate the submit file

```r
htc_gen_submit(
  output_file     = "analysis.sub",
  container_image = "docker://registry.doit.wisc.edu/lares/my-analysis:1.0.0",
  executable      = "analysis.sh",
  input_files     = "analysis.R",
  output_files    = "results.tar.gz",
  resources       = "small",
  comments        = TRUE,
  output          = "."
)
```

The `comments = TRUE` argument annotates every section of the submit file
with an explanation of what it does and why. This is worth using on your
first submission — it makes the generated file readable and educational.

Three resource presets are available:

| preset | cpus | memory | disk  |
|--------|------|--------|-------|
| small  | 1    | 4 GB   | 4 GB  |
| medium | 4    | 16 GB  | 15 GB |
| large  | 8    | 64 GB  | 32 GB |

Start small. The HTCondor log file reports actual resource usage after each
run, which is the best guide for tuning on subsequent submissions.

### Step 3 — Generate the executable script

```r
htc_gen_executable(
  r_script       = "analysis.R",
  output_file    = "analysis.sh",
  results_folder = "results",
  comments       = TRUE
)
```

The generated script handles `mkdir`, `Rscript`, and `tar` in the correct
order. It also sets executable permissions automatically so the file is ready
to transfer without an extra `chmod` step.

### Step 4 — Upload files to CHTC

```r
htc_upload(
  files  = c("analysis.sub", "analysis.sh", "analysis.R"),
  config = cfg
)
```

Use `dry_run = TRUE` to preview the `scp` command before executing:

```r
htc_upload(
  files   = c("analysis.sub", "analysis.sh"),
  config  = cfg,
  dry_run = TRUE
)
#> ✔ Dry run -- command that would be executed:
#>   `scp analysis.sub analysis.sh erwin.lares@ap2002.chtc.wisc.edu:~/`
```

`dry_run = TRUE` is available on every system-facing function. Use it
liberally when learning the workflow.

### Step 5 — Submit the job

```r
cluster_id <- htc_submit(
  submit_file = "analysis.sub",
  config      = cfg,
  verbose     = TRUE
)
#> Submitting "analysis.sub" on "ap2002.chtc.wisc.edu"...
#> Submitting job(s)...
#> 1 job(s) submitted to cluster 6302860.
#> ✔ Job submitted from "~/analysis.sub" on "ap2002.chtc.wisc.edu".
```

`htc_submit()` returns the cluster ID invisibly so you can pass it directly
to `htc_status()`.

### Step 6 — Monitor progress

```r
# One-shot status check
htc_status(cluster_id = cluster_id, config = cfg)

# Watch until the job completes (polls every 60 seconds)
htc_status(cluster_id = cluster_id, config = cfg, watch = TRUE)
```

### Step 7 — Download results

```r
htc_download(
  files      = "results.tar.gz",
  config     = cfg,
  local_path = "results/"
)
```

---

## Scaling to many jobs

Once your single job works, scaling to hundreds of parallel jobs is a small
step. Use `toolero::write_by_group()` to split your dataset and produce a
manifest, then switch `htc_gen_submit()` to multiple-job mode:

```r
# Split the dataset (done with toolero earlier in the pipeline)
toolero::write_by_group(data, group_col = "species",
                        output_dir = "data/jobs", manifest = TRUE)

# Generate a submit file that queues one job per row in the manifest
htc_gen_submit(
  output_file     = "analysis.sub",
  container_image = "docker://registry.doit.wisc.edu/lares/my-analysis:1.0.0",
  executable      = "analysis.sh",
  input_files     = "analysis.R",
  mode            = "multiple",
  queue_from      = "data/jobs/manifest.csv",
  resources       = "medium"
)

# Generate the executable for multiple-job mode
htc_gen_executable(
  r_script       = "analysis.R",
  output_file    = "analysis.sh",
  results_folder = "results",
  mode           = "multiple"
)
```

In multiple-job mode, HTCondor passes each subset filename to your R script
as a positional argument. Use `toolero::detect_execution_context()` in your
analysis script to handle this correctly:

```r
context <- toolero::detect_execution_context()

input_file <- switch(context,
  interactive = "data/sample.csv",
  quarto      = params$input_file,
  rscript     = commandArgs(trailingOnly = TRUE)[1]
)
```

The same script runs correctly whether you call it interactively in RStudio,
render it as a Quarto document, or HTCondor calls it with `Rscript` on an
execute node.

---

## SSH connection reuse

Each `htc_upload()`, `htc_submit()`, `htc_status()`, and `htc_download()`
call opens a new SSH connection, which triggers a Duo MFA prompt. You can
reduce this to one prompt per two-hour window by configuring ControlMaster
in your `~/.ssh/config`:

```
Host *.chtc.wisc.edu
  ControlMaster auto
  ControlPersist 2h
  ControlPath ~/.ssh/connections/%r@%h:%p
```

Then create the connections directory:

```bash
mkdir -p ~/.ssh/connections
```

`htc_config()` displays these instructions automatically on first use. Full
documentation: <https://chtc.cs.wisc.edu/uw-research-computing/configure-ssh>

---

## What submitr does not do

`submitr` reduces friction. It does not replace understanding.

- It does not manage large input files (> 1 GB). Those belong in CHTC's
  staging area and require a different transfer pattern, planned for a future
  release.
- It does not validate that your container image is correct or that your
  analysis script will run successfully inside it. Test both locally before
  submitting to CHTC.
- It does not replace CHTC consultation for complex workloads, custom
  scheduling requirements, or non-standard resource requests.

The [CHTC facilitation team](https://chtc.cs.wisc.edu/uw-research-computing/get-help)
is the right resource for those questions.

---

## Function reference

**Connection management**

`htc_config()` creates or reads `htc.cfg`, validates server reachability, and
displays ControlMaster guidance on first use.

**Scaffolding**

`htc_gen_submit()` generates an HTCondor `.sub` submit file. Supports
single-job and multiple-job modes. Resource presets loaded from a YAML file
and customizable per project.

`htc_gen_executable()` generates the `.sh` script that HTCondor runs inside
the container.

**Job submission**

`htc_upload()` copies files to the CHTC submit node via `scp`. Accepts
single files, vectors of files, and directory paths.

`htc_submit()` runs `condor_submit` on the remote server via SSH. Returns the
cluster ID for use with `htc_status()`.

`htc_status()` runs `condor_q` on the remote server. When `watch = TRUE`,
polls repeatedly until all jobs in the cluster leave the queue.

`htc_download()` copies files back from the submit node via `scp`. Supports
glob patterns (`"*.tar.gz"`, `"job.*"`).

---

## Related packages

`submitr` is part of a family of packages for reproducible research computing
at CHTC:

- [toolero](https://github.com/erwinlares/toolero) — organize and scaffold
  the project, split datasets for parallel jobs
- [containr](https://github.com/erwinlares/containr) — containerize the
  software environment
- **submitr** — submit to CHTC and retrieve results (this package)

---

## License

MIT © Erwin Lares
