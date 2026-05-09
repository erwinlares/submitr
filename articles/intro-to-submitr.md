# Intro to submitr

## Why submitr exists

High-throughput computing is powerful because it lets you turn one
analysis into many independent jobs. Instead of running a loop overnight
on your laptop, you can send the work to the UW–Madison Center for High
Throughput Computing (CHTC), where eligible researchers can use large
pools of computing capacity.

The difficulty is that a first CHTC submission requires several pieces
to line up at once:

- an R script that can run outside RStudio;
- a container image holding the R packages your analysis needs;
- an HTCondor submit file that describes the job;
- an executable shell script that HTCondor runs;
- a way to transfer the relevant file to the submit node;
- job submission, monitoring, and result retrieval from the command
  line.

For experienced CHTC users, those steps are familiar. For researchers
who mostly work in RStudio or Positron, the workflow can feel like a
sudden jump into shell scripting, SSH, SCP, and HTCondor syntax.

`submitr` is designed to make that first jump smaller.

It does not replace CHTC, HTCondor, containers, or good project
organization. Instead, it helps you generate the standard files, move
them to the submit node, submit the job, check its status, and copy
results back — from R.

## Who this vignette is for

This vignette is for researchers who already have an R analysis on their
local machine and want to run it on CHTC for the first time.

You do not need to be a command-line expert, but you do need a few
things in place before using `submitr`:

- an R project with a script that can be run using `Rscript`;
- SSH access to a CHTC submit node, such as `ap2002.chtc.wisc.edu`;
- a container image that includes the R packages required by your
  analysis;
- input data that are appropriate to move to and process on CHTC.

If your project is not yet containerized, start with the companion
package [`containr`](https://github.com/erwinlares/containr), which
helps generate, build, and push a container image from an `renv.lock`
file.

## The mental model

A CHTC job has two main instructions:

1.  **The submit file** tells HTCondor what resources the job needs,
    what files to transfer, what container to use, and how many jobs to
    queue.
2.  **The executable script** tells the job what to do once it starts
    running inside the container.

`submitr` helps you create both.

A minimal single-job workflow looks like this:

``` r

library(submitr)

cfg <- htc_config()

htc_gen_submit(
  output_file     = "analysis.sub",
  container_image = "docker://registry.doit.wisc.edu/netid/my-image",
  executable      = "analysis.sh",
  input_files     = c("analysis.R", "data.csv"),
  output_files    = "results.tar.gz",
  resources       = "medium"
)

htc_gen_executable(
  r_script       = "analysis.R",
  output_file    = "analysis.sh",
  results_folder = "results"
)

htc_upload(
  files  = c("analysis.sub", "analysis.sh", "analysis.R", "data.csv"),
  config = cfg
)

cluster_id <- htc_submit(
  submit_file = "analysis.sub",
  config      = cfg
)

htc_status(cluster_id = cluster_id, config = cfg)

htc_download(
  files      = "*.tar.gz",
  config     = cfg,
  local_path = "results/"
)
```

The rest of this vignette walks through each step.

## Start with an R script that can run on its own

Before submitting anything to CHTC, make sure your analysis can run
outside the interactive R session where you developed it.

For example, suppose you have a script called `analysis.R`:

``` r

library(readr)
library(dplyr)

input <- read_csv("data.csv")

summary <- input |>
  group_by(group) |>
  summarise(
    mean_value = mean(value, na.rm = TRUE),
    .groups = "drop"
  )

if (!dir.exists("results")) {
  dir.create("results")
}

write_csv(summary, "results/summary.csv")
```

Test it locally from the Terminal, not only from the R console:

``` bash
Rscript analysis.R
```

This matters because CHTC will not open RStudio, restore your workspace,
or use objects you created interactively. The job will run your script
in a clean session inside the container.

## Configure your CHTC connection

Start by loading `submitr` and creating a connection configuration:

``` r

library(submitr)

cfg <- htc_config()
```

On first use,
[`htc_config()`](https://erwinlares.github.io/submitr/reference/htc_config.md)
prompts for your NetID and submit node, then writes an `htc.cfg` file in
your project directory. On later runs, it reads the existing
configuration and checks that the connection works.

A successful configuration looks like this:

``` r

cfg <- htc_config()
#> Reading HTC config from ./htc.cfg
#> ✔ Connected to "ap2002.chtc.wisc.edu" as "netid".
```

The configuration file keeps the project-specific connection information
in one place so you do not need to repeatedly type your username and
server.

## Reduce repeated Duo prompts with SSH connection reuse

Each upload, submit, status, or download command opens an SSH
connection. Without additional SSH configuration, each connection can
trigger a Duo MFA prompt.

CHTC recommends SSH connection reuse through `ControlMaster`. Add this
block to your `~/.ssh/config` file:

``` bash
Host *.chtc.wisc.edu
  ControlMaster auto
  ControlPersist 2h
  ControlPath ~/.ssh/connections/%r@%h:%p
```

Then create the directory used by `ControlPath`:

``` bash
mkdir -p ~/.ssh/connections
```

With this setup, you can usually authenticate once and reuse that
connection for later `submitr` calls during the persistence window.

[`htc_config()`](https://erwinlares.github.io/submitr/reference/htc_config.md)
displays this guidance automatically the first time it creates a
configuration file.

## Generate the HTCondor submit file

The submit file describes the job to HTCondor. It names the container
image, the executable script, the files to transfer, the files to bring
back, and the resources the job requests.

``` r

htc_gen_submit(
  output_file     = "analysis.sub",
  container_image = "docker://registry.doit.wisc.edu/netid/my-image",
  executable      = "analysis.sh",
  input_files     = c("analysis.R", "data.csv"),
  output_files    = "results.tar.gz",
  resources       = "medium",
  comments        = TRUE,
  output          = "."
)
```

For a first submission, use `comments = TRUE`. The generated file will
include explanatory comments that make the submit file easier to inspect
and share.

The `resources` argument accepts named presets:

| preset | cpus | memory | disk  |
|--------|------|--------|-------|
| small  | 1    | 4 GB   | 4 GB  |
| medium | 4    | 16 GB  | 15 GB |
| large  | 8    | 64 GB  | 32 GB |

Start conservatively. Request enough resources for the job to run, but
avoid asking for much more than you need. Oversized requests can make
jobs harder to match to available slots.

For project-specific resource settings, copy `htc-resources.yaml` from
the package into your project directory and edit the values. When a
local resource file is present,
[`htc_gen_submit()`](https://erwinlares.github.io/submitr/reference/htc_gen_submit.md)
uses it instead of the package defaults.

## Generate the executable script

The executable script is the command HTCondor runs after the job starts.
It is responsible for preparing the output directory, running your R
script, and packaging results.

``` r

htc_gen_executable(
  r_script       = "analysis.R",
  output_file    = "analysis.sh",
  results_folder = "results",
  comments       = TRUE
)
```

The generated script handles the common ordering details:

1.  create the results directory;
2.  run the R script with `Rscript`;
3.  archive the results folder as `results.tar.gz`.

That order is easy to write by hand, but it is also easy to get slightly
wrong when you are learning the workflow. `submitr` generates a standard
version so you can focus on the analysis logic.

## Preview the upload before sending files

Before copying files to the submit node, preview the transfer command:

``` r

htc_upload(
  files   = c("analysis.sub", "analysis.sh", "analysis.R", "data.csv"),
  config  = cfg,
  dry_run = TRUE
)
#> ✔ Dry run -- command that would be executed:
#>   `scp analysis.sub analysis.sh analysis.R data.csv netid@ap2002.chtc.wisc.edu:~/`
```

A dry run is especially useful the first time you submit a project
because it lets you check which files will be transferred before
anything changes on the submit node.

Once the command looks right, run the upload:

``` r

htc_upload(
  files  = c("analysis.sub", "analysis.sh", "analysis.R", "data.csv"),
  config = cfg
)
```

## Submit the job

After the files are on the submit node, submit the job:

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
reuse it when checking job status.

## Check job status

To check the job once:

``` r

htc_status(cluster_id = cluster_id, config = cfg)
```

To keep checking until all jobs complete:

``` r

htc_status(
  cluster_id = cluster_id,
  config     = cfg,
  watch      = TRUE
)
```

Watching is useful for small test jobs. For larger real workloads, you
may prefer occasional one-shot checks instead of keeping an R session
occupied.

## Download the results

When the job finishes, copy the results back to your local machine:

``` r

htc_download(
  files      = "*.tar.gz",
  config     = cfg,
  local_path = "results/"
)
```

You can also download specific files, such as log and error files:

``` r

htc_download(
  files      = c("job.log", "job.err"),
  config     = cfg,
  local_path = "logs/"
)
```

The result archive can then be unpacked locally and inspected in R.

## Scaling from one job to many jobs

The real value of high-throughput computing appears when you split one
large task into many independent tasks.

For example, you might split a dataset by county, simulation parameter,
participant, image tile, model specification, or bootstrap replicate.
Each subset can run as its own job.

In the broader workflow,
[`toolero::write_by_group()`](https://github.com/erwinlares/toolero) can
split a dataset and write a manifest file. `submitr` can then use that
manifest to queue one job per row.

``` r

htc_gen_submit(
  output_file     = "analysis.sub",
  container_image = "docker://registry.doit.wisc.edu/netid/my-image",
  executable      = "analysis.sh",
  input_files     = "analysis.R",
  mode            = "multiple",
  queue_from      = "data/manifest.csv",
  resources       = "medium",
  comments        = TRUE
)
```

Then generate an executable script in multiple-job mode:

``` r

htc_gen_executable(
  r_script       = "analysis.R",
  output_file    = "analysis.sh",
  results_folder = "results",
  mode           = "multiple",
  comments       = TRUE
)
```

In multiple-job mode, the generated executable passes the per-job input
filename to your R script as the first positional argument.

Your R script should read that argument:

``` r

args <- commandArgs(trailingOnly = TRUE)
input_file <- args[[1]]

input <- readr::read_csv(input_file)
```

This pattern is important because it separates the job logic from the
specific input file. HTCondor decides which subset belongs to each job,
and the same R script runs repeatedly with different inputs.

## Where submitr fits in the larger workflow

`submitr` is one step in a larger reproducible-computing pipeline:

``` r

toolero::init_project()         # initialize a project with sensible defaults
toolero::create_qmd()           # scaffold a Quarto document and extracted R script
toolero::write_by_group()       # split data into job-sized pieces
containr::generate_dockerfile() # generate a Dockerfile from renv.lock
containr::build_image()         # build the container image locally
containr::push_image()          # push the image to a registry
submitr::htc_config()           # configure the CHTC connection
submitr::htc_gen_submit()       # generate the HTCondor submit file
submitr::htc_gen_executable()   # generate the executable shell script
submitr::htc_upload()           # copy files to the submit node
submitr::htc_submit()           # submit the job
submitr::htc_status()           # monitor progress
submitr::htc_download()         # retrieve results
```

You can use `submitr` by itself if your project is already organized and
containerized. The companion packages are there to help with earlier
steps in the workflow.

## A first-submission checklist

Before submitting your first job, check the following:

- The analysis runs locally with `Rscript analysis.R`.
- Required input files are listed in `input_files`.
- The container image exists and is accessible from CHTC.
- The submit file and executable script were generated successfully.
- `htc_upload(..., dry_run = TRUE)` shows the files you expect.
- [`htc_config()`](https://erwinlares.github.io/submitr/reference/htc_config.md)
  can connect to your submit node.
- Your job requests a reasonable amount of CPU, memory, and disk.
- Your script writes outputs into the expected results folder.

## What submitr does not do

`submitr` reduces workflow friction, but it does not remove the need to
understand the basic structure of an HTC job.

In particular, it does not:

- decide whether your analysis is appropriate for CHTC;
- guarantee that your container image works;
- automatically rewrite interactive R code into batch-safe code;
- manage sensitive or restricted data for you;
- replace CHTC documentation or consultation for complex workflows.

For first submissions, start with a small test job. Once that works,
scale up to the larger workload.

## Summary

The first CHTC submission is often the hardest because it requires
researchers to coordinate R, containers, SSH, file transfer, shell
scripts, and HTCondor submit syntax all at once.

`submitr` provides a guided R interface for the parts of that workflow
that are easy to standardize:

- configure the submit-node connection;
- generate the submit file;
- generate the executable script;
- upload files;
- submit the job;
- monitor progress;
- download results.

For researchers new to the command line, this makes the first successful
job more approachable. For experienced CHTC users, it removes repetitive
steps and makes common job submissions easier to reproduce.
