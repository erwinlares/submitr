# submitr

## From the Notebook to the Cluster

You have an R analysis that runs on your laptop. Maybe it takes a while.
Maybe you need to run it many times — once per species, once per county,
once per simulation parameter, once per experimental condition. Maybe
both.

CHTC’s high-throughput computing infrastructure can run many independent
jobs across a large pool of compute resources. The barrier is rarely the
value of the computing. The barrier is the handoff: turning a local
analysis into something a scheduler can run somewhere else.

That handoff requires several pieces to line up at once. Your R code
needs to run without relying on the interactive session where you
developed it. Your software environment needs to be portable. Your files
need to move to a submit node. HTCondor needs a submit file. The execute
node needs a shell script. Your results need to come back.

`submitr` is designed to make that handoff easier. It generates the
HTCondor submit file, generates the executable script, wraps the SSH and
SCP commands that move files to and from the submit node, submits the
job, checks status, and downloads results — all from R.

If you are new to CHTC, `submitr` gives you a guided path to your first
successful submission. If you already use CHTC, `submitr` reduces
repetitive setup work and makes common submission patterns easier to
reproduce, review, and share.

------------------------------------------------------------------------

## When to use submitr

Use `submitr` when you are:

- sending a containerized R analysis to CHTC for the first time;
- teaching researchers the structure of an HTCondor job;
- moving from a single local analysis to many independent HTC jobs;
- standardizing a submit-file and executable-script pattern across
  projects;
- reducing repeated SSH, SCP, and `condor_submit` command-line work;
- making CHTC submissions easier to review, rerun, and share.

`submitr` is useful on its own if your project is already organized and
containerized. It also fits into a broader workflow for moving from a
literate analysis document to a portable, scalable computation.

------------------------------------------------------------------------

## The toolero family

`submitr` is the third step in the **From the Notebook to the Cluster**
package family:

``` text
toolero     organize, scaffold, split
  └─ containr   freeze the software environment in a container
       └─ submitr    send the analysis to CHTC and retrieve results
```

Each package is useful on its own. Together, they form a path from a
local R project to a completed high-throughput computing run.

- `toolero` helps you start with a maintainable project structure, use
  Quarto as a source of truth, and split data into job-sized pieces.
- `containr` helps you build a container image from your `renv.lock` so
  the software environment can travel with the analysis.
- `submitr` helps you send the containerized analysis to CHTC, monitor
  the job, and bring results back.

You can adopt these packages one at a time. `submitr` does not require
`toolero`, and `toolero` does not require `submitr`. The family exists
so that each step prepares cleanly for the next when your project is
ready to scale.

A typical path looks like this:

``` r

# toolero: organize the project and split the data
toolero::init_project("my-analysis")
toolero::write_by_group(
  data,
  group_col  = "species",
  output_dir = "data/jobs",
  manifest   = TRUE
)

# containr: containerize the software environment
containr::generate_dockerfile(r_version = "4.4.0", output = ".")
containr::build_image()
containr::push_image(
  image_id = "974123909a36",
  netid    = "your.netid",
  project  = "my-analysis",
  tag      = "1.0.0"
)

# submitr: submit to CHTC and retrieve results
cfg <- submitr::htc_config()

cluster_id <- submitr::htc_submit(
  submit_file = "analysis.sub",
  config      = cfg
)

submitr::htc_status(cluster_id = cluster_id, config = cfg)
submitr::htc_download(files = "*.tar.gz", config = cfg, local_path = "results/")
```

------------------------------------------------------------------------

## Installation

Install the development version from GitHub:

``` r

# install.packages("pak")
pak::pak("erwinlares/submitr")
```

------------------------------------------------------------------------

## Requirements

Before using `submitr`, you need:

- R (\>= 4.2.0);
- SSH access to a CHTC submit node, such as `ap2002.chtc.wisc.edu`;
- a container image pushed to a registry accessible from CHTC;
- an R script that can run with `Rscript`;
- input data that are appropriate to transfer to and process on CHTC.

If your project is not yet containerized, start with
[`containr`](https://github.com/erwinlares/containr). If your project is
not yet organized for reproducible analysis, start with
[`toolero`](https://github.com/erwinlares/toolero).

------------------------------------------------------------------------

## What an HTCondor job needs

Before walking through the workflow, it helps to understand what
HTCondor needs to run your analysis.

At minimum, you need:

- a **container image** that holds your R version, packages, and system
  libraries;
- a **submit file** (`.sub`) that tells HTCondor what to run, what
  resources to request, what files to transfer, and where to write logs;
- an **executable script** (`.sh`) that runs inside the container,
  usually by calling `Rscript`;
- your **analysis script** and any **input files** the job needs;
- a way to **retrieve results** after the job finishes.

`submitr` helps with the parts that are easy to standardize:

- [`htc_gen_submit()`](https://erwinlares.github.io/submitr/reference/htc_gen_submit.md)
  generates the submit file;
- [`htc_gen_executable()`](https://erwinlares.github.io/submitr/reference/htc_gen_executable.md)
  generates the executable script;
- [`htc_upload()`](https://erwinlares.github.io/submitr/reference/htc_upload.md)
  transfers files to the submit node;
- [`htc_submit()`](https://erwinlares.github.io/submitr/reference/htc_submit.md)
  submits the job;
- [`htc_status()`](https://erwinlares.github.io/submitr/reference/htc_status.md)
  checks progress;
- [`htc_download()`](https://erwinlares.github.io/submitr/reference/htc_download.md)
  retrieves results.

------------------------------------------------------------------------

## A first single-job submission

The simplest path is one job: one container, one script, one result
archive. Start here before scaling to many jobs.

### Step 1 — Configure your connection

On first use,
[`htc_config()`](https://erwinlares.github.io/submitr/reference/htc_config.md)
prompts for your NetID and server, writes `htc.cfg` to your project
directory, and displays instructions for setting up SSH connection reuse
to avoid repeated Duo MFA prompts.

``` r

library(submitr)

cfg <- htc_config()
```

Subsequent calls read the existing `htc.cfg` and validate the
connection:

``` r

cfg <- htc_config()
#> Reading HTC config from ./htc.cfg
#> ✔ Connected to "ap2002.chtc.wisc.edu" as "your.netid".
```

The configuration file keeps project-specific connection information in
one place so you do not need to repeatedly type your username and
server.

### Step 2 — Generate the submit file

``` r

htc_gen_submit(
  output_file     = "analysis.sub",
  container_image = "docker://registry.doit.wisc.edu/your.netid/my-analysis:1.0.0",
  executable      = "analysis.sh",
  input_files     = "analysis.R",
  output_files    = "results.tar.gz",
  resources       = "small",
  comments        = TRUE,
  output          = "."
)
```

The submit file is the job description. It tells HTCondor which
container to use, which executable to run, which files to transfer, what
resources to request, and what output files to expect.

For a first submission, use `comments = TRUE`. The generated file will
include explanations for each section, making it useful as both a
working submit file and a learning document.

Three resource presets are available:

| preset | cpus | memory | disk  |
|--------|------|--------|-------|
| small  | 1    | 4 GB   | 4 GB  |
| medium | 4    | 16 GB  | 15 GB |
| large  | 8    | 64 GB  | 32 GB |

Start small. The HTCondor log file reports actual resource usage after
each run, which is the best guide for tuning future submissions. Request
enough for the job to run, but avoid asking for much more than you need.

### Step 3 — Generate the executable script

``` r

htc_gen_executable(
  r_script       = "analysis.R",
  output_file    = "analysis.sh",
  results_folder = "results",
  comments       = TRUE
)
```

The executable script is what HTCondor runs inside the container. The
generated script handles the common ordering details:

1.  create the results directory;
2.  run your R script with `Rscript`;
3.  archive the results folder as `results.tar.gz`.

It also sets executable permissions automatically, so the file is ready
to transfer without an extra `chmod` step.

### Step 4 — Preview and upload files

Before copying files to the submit node, preview the transfer command:

``` r

htc_upload(
  files   = c("analysis.sub", "analysis.sh", "analysis.R"),
  config  = cfg,
  dry_run = TRUE
)
#> ✔ Dry run -- command that would be executed:
#>   `scp analysis.sub analysis.sh analysis.R your.netid@ap2002.chtc.wisc.edu:~/`
```

`dry_run = TRUE` is available on the system-facing functions. Use it
liberally while learning the workflow.

Once the command looks right, upload the files:

``` r

htc_upload(
  files  = c("analysis.sub", "analysis.sh", "analysis.R"),
  config = cfg
)
```

### Step 5 — Submit the job

``` r

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

[`htc_submit()`](https://erwinlares.github.io/submitr/reference/htc_submit.md)
returns the cluster ID invisibly. Assigning it to `cluster_id` lets you
reuse it when checking status.

### Step 6 — Monitor progress

``` r

# One-shot status check
htc_status(cluster_id = cluster_id, config = cfg)

# Watch until the job completes
htc_status(cluster_id = cluster_id, config = cfg, watch = TRUE)
```

Watching is useful for small test jobs. For larger workloads, occasional
one-shot checks are usually a better fit.

### Step 7 — Download results

``` r

htc_download(
  files      = "results.tar.gz",
  config     = cfg,
  local_path = "results/"
)
```

You can also download logs or other files by name or glob pattern:

``` r

htc_download(
  files      = c("job.log", "job.err", "job.out"),
  config     = cfg,
  local_path = "logs/"
)
```

------------------------------------------------------------------------

## Scaling to many jobs

High-throughput computing becomes powerful when one analysis can become
many independent jobs. That might mean one job per species, county,
participant, image tile, simulation parameter, bootstrap replicate,
model specification, or experimental condition.

Once your single job works, scaling up is mostly a matter of changing
the queue. Use
[`toolero::write_by_group()`](https://erwinlares.github.io/toolero/reference/write_by_group.html)
to split your dataset and produce a manifest, then switch
[`htc_gen_submit()`](https://erwinlares.github.io/submitr/reference/htc_gen_submit.md)
and
[`htc_gen_executable()`](https://erwinlares.github.io/submitr/reference/htc_gen_executable.md)
to multiple-job mode.

``` r

# Split the dataset earlier in the workflow
toolero::write_by_group(
  data,
  group_col  = "species",
  output_dir = "data/jobs",
  manifest   = TRUE
)

# Queue one job per row in the manifest
htc_gen_submit(
  output_file     = "analysis.sub",
  container_image = "docker://registry.doit.wisc.edu/your.netid/my-analysis:1.0.0",
  executable      = "analysis.sh",
  input_files     = "analysis.R",
  mode            = "multiple",
  queue_from      = "data/jobs/manifest.csv",
  resources       = "medium",
  comments        = TRUE
)

# Generate the executable for multiple-job mode
htc_gen_executable(
  r_script       = "analysis.R",
  output_file    = "analysis.sh",
  results_folder = "results",
  mode           = "multiple",
  comments       = TRUE
)
```

In multiple-job mode, HTCondor passes each subset filename to your R
script as a positional argument. Your script should read that argument
when it is called through `Rscript`.

One useful pattern is to combine this with
[`toolero::detect_execution_context()`](https://erwinlares.github.io/toolero/reference/detect_execution_context.html):

``` r

context <- toolero::detect_execution_context()

input_file <- switch(context,
  interactive = "data/sample.csv",
  quarto      = params$input_file,
  rscript     = commandArgs(trailingOnly = TRUE)[1]
)
```

This helps the same analysis behave correctly whether you run it
interactively, render it as a Quarto document, or submit it to HTCondor.
It is a small guard against code drift: you do not need one script for
local development, another for the report, and a third for the cluster.

------------------------------------------------------------------------

## SSH connection reuse

Each
[`htc_upload()`](https://erwinlares.github.io/submitr/reference/htc_upload.md),
[`htc_submit()`](https://erwinlares.github.io/submitr/reference/htc_submit.md),
[`htc_status()`](https://erwinlares.github.io/submitr/reference/htc_status.md),
and
[`htc_download()`](https://erwinlares.github.io/submitr/reference/htc_download.md)
call opens a new SSH connection, which can trigger a Duo MFA prompt. You
can reduce repeated prompts by configuring ControlMaster in your
`~/.ssh/config`:

``` text
Host *.chtc.wisc.edu
  ControlMaster auto
  ControlPersist 2h
  ControlPath ~/.ssh/connections/%r@%h:%p
```

Then create the connections directory:

``` bash
mkdir -p ~/.ssh/connections
```

[`htc_config()`](https://erwinlares.github.io/submitr/reference/htc_config.md)
displays these instructions automatically on first use. Full
documentation:
<https://chtc.cs.wisc.edu/uw-research-computing/configure-ssh>

------------------------------------------------------------------------

## What submitr does not do

`submitr` reduces friction. It does not replace understanding.

- It does not decide whether your workload is appropriate for CHTC.
- It does not manage large input files greater than 1 GB. Those belong
  in CHTC’s staging area and require a different transfer pattern.
- It does not validate that your container image is correct or that your
  analysis script will run successfully inside it. Test both locally
  before submitting to CHTC.
- It does not replace CHTC consultation for complex workloads, custom
  scheduling requirements, or non-standard resource requests.

The [CHTC facilitation
team](https://chtc.cs.wisc.edu/uw-research-computing/get-help) is the
right resource for complex workflow questions.

------------------------------------------------------------------------

## Function reference

### Connection management

[`htc_config()`](https://erwinlares.github.io/submitr/reference/htc_config.md)
creates or reads `htc.cfg`, validates server reachability, and displays
ControlMaster guidance on first use.

### Scaffolding

[`htc_gen_submit()`](https://erwinlares.github.io/submitr/reference/htc_gen_submit.md)
generates an HTCondor `.sub` submit file. Supports single-job and
multiple-job modes. Resource presets are loaded from a YAML file and can
be customized per project.

[`htc_gen_executable()`](https://erwinlares.github.io/submitr/reference/htc_gen_executable.md)
generates the `.sh` script that HTCondor runs inside the container. It
can be generated for single-job or multiple-job submissions.

### Job submission

[`htc_upload()`](https://erwinlares.github.io/submitr/reference/htc_upload.md)
copies files to the CHTC submit node via `scp`. Accepts single files,
vectors of files, and directory paths.

[`htc_submit()`](https://erwinlares.github.io/submitr/reference/htc_submit.md)
runs `condor_submit` on the remote server via SSH. Returns the cluster
ID for use with
[`htc_status()`](https://erwinlares.github.io/submitr/reference/htc_status.md).

[`htc_status()`](https://erwinlares.github.io/submitr/reference/htc_status.md)
runs `condor_q` on the remote server. When `watch = TRUE`, it polls
repeatedly until all jobs in the cluster leave the queue.

[`htc_download()`](https://erwinlares.github.io/submitr/reference/htc_download.md)
copies files back from the submit node via `scp`. Supports glob patterns
such as `"*.tar.gz"` and `"job.*"`.

------------------------------------------------------------------------

## Related packages

`submitr` is part of the **From the Notebook to the Cluster** package
family:

- [toolero](https://github.com/erwinlares/toolero) — organize and
  scaffold the project, use Quarto as the source of truth, and split
  datasets for parallel jobs
- [containr](https://github.com/erwinlares/containr) — containerize the
  software environment
- **submitr** — submit to CHTC and retrieve results

------------------------------------------------------------------------

## License

MIT © Erwin Lares
