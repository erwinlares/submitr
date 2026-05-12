# From the Notebook to the Cluster: Your First CHTC Job with submitr

![submitr hex sticker](figures/logo.png)

## The promise of a first CHTC job

Many research coding projects begin in a notebook-style workflow: an
RStudio project, a Quarto document, a few scripts, a folder of input
files, and enough local experimentation to understand what the analysis
needs to do.

That is a good place to start. A laptop is often the right place to
explore data, write early code, make plots, and decide what question the
analysis is actually answering. But at some point, the same local
workflow can become the wrong place to keep pushing.

Maybe the analysis takes too long. Maybe you need to run the same model
across hundreds of parameter combinations. Maybe you need one job per
participant, county, simulation, image, genome, or bootstrap sample.
Maybe you simply want a workflow that will be easier to rerun six months
from now.

That is where high-throughput computing becomes useful.

The UW-Madison Center for High Throughput Computing (CHTC) gives
researchers access to large pools of computing capacity. Instead of
asking one computer to do everything in sequence, you can break work
into independent jobs and let the HTC system run those jobs when
resources are available.

`submitr` helps you take the final step in the **From the Notebook to
the Cluster** workflow: sending a prepared R project to CHTC. It is
designed for researchers who know R but may not yet be comfortable with
HTCondor submit files, executable shell scripts, `ssh`, `scp`, or the
rhythm of working on a remote submit node. It is also useful for regular
CHTC users who want to reduce repetitive setup work and make job
submission easier to reproduce, review, and share.

The goal is not to hide CHTC from you. The goal is to make the standard
path visible, repeatable, and less fragile.

------------------------------------------------------------------------

## Before you submit anything

A successful CHTC submission starts before `condor_submit`.

Before using `submitr`, confirm that:

- your R script runs with `Rscript analysis.R` outside RStudio;
- your container image is pushed to a registry CHTC can access;
- you have SSH access to a CHTC submit node such as
  `ap2002.chtc.wisc.edu`.

**Set up SSH connection reuse now, before anything else.** Every
`submitr` function that touches CHTC opens an SSH connection, which can
trigger a Duo MFA prompt. ControlMaster caches your authenticated
session so all subsequent calls – uploads, submits, status checks,
downloads – reuse the same connection without prompting again. The setup
takes two minutes and is worth doing before your first
[`htc_config()`](https://erwinlares.github.io/submitr/reference/htc_config.md)
call. Full instructions appear right after Step 1.

For a first submission, choose something small and intentionally boring.
The goal is not to prove that your full analysis can scale yet. The goal
is to prove that the pathway works.

------------------------------------------------------------------------

## A small example analysis

Suppose your project has this shape:

``` text
my-analysis/
├── analysis.R
├── data.csv
├── renv.lock
└── results/
```

Your `analysis.R` script might look like this:

``` r

library(readr)
library(dplyr)

input <- read_csv("data.csv")

summary <- input |>
  group_by(group) |>
  summarise(
    mean_value = mean(value, na.rm = TRUE),
    n          = dplyr::n(),
    .groups    = "drop"
  )

if (!dir.exists("results")) dir.create("results")

write_csv(summary, "results/summary.csv")
```

This script is deliberately modest. A first CHTC job should be easy to
inspect. Once the small version works, you can scale the pattern with
more confidence.

------------------------------------------------------------------------

## Step 1: configure your CHTC connection

Load `submitr` and create a project-level configuration:

``` r

library(submitr)

cfg <- htc_config()
```

On first use,
[`htc_config()`](https://erwinlares.github.io/submitr/reference/htc_config.md)
prompts for your NetID and submit node. It writes an `htc.cfg` file to
the project directory so later calls can reuse the same connection
information, and it displays ControlMaster setup instructions.

A later call should look something like this:

``` r

cfg <- htc_config()
#> Reading HTC config from ./htc.cfg
#> ✔ Connected to "ap2002.chtc.wisc.edu" as "your.netid".
```

------------------------------------------------------------------------

## Setting up SSH connection reuse

Before continuing, take two minutes to configure ControlMaster. Add this
block to `~/.ssh/config`:

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

With ControlMaster in place, all subsequent SSH connections reuse the
same authenticated session. You authenticate once when the connection is
first established; everything that follows – file uploads, job
submission, status checks, result downloads – happens without prompting
for Duo MFA again. Full documentation is at
<https://chtc.cs.wisc.edu/uw-research-computing/configure-ssh>.

The rest of this vignette assumes ControlMaster is in place.

------------------------------------------------------------------------

## Step 2: generate the submit file

The submit file is the main HTCondor instruction file. It answers the
question: what should the HTC system run, and what does it need?

``` r

htc_gen_submit(
  output_file     = "analysis.sub",
  container_image = "docker://registry.doit.wisc.edu/your.netid/my-analysis:1.0.0",
  executable      = "analysis.sh",
  input_files     = c("analysis.R", "data.csv"),
  output_files    = "results.tar.gz",
  resources       = "small",
  comments        = TRUE,
  output          = "."
)
```

For a first submission, keep `comments = TRUE`. The generated file
includes explanations of the main sections, making it easier to inspect,
learn from, and share with a collaborator or consultant.

The `resources` argument uses presets. For a first test, always start
with `"small"` regardless of what your eventual job will need:

| preset | cpus | memory | disk  | when to use                           |
|--------|------|--------|-------|---------------------------------------|
| small  | 1    | 4 GB   | 4 GB  | first test jobs, lightweight scripts  |
| medium | 4    | 16 GB  | 15 GB | moderate analyses, model fitting      |
| large  | 8    | 64 GB  | 32 GB | memory-intensive work, large datasets |

The HTCondor log file reports actual resource usage after each run. That
log is the ground truth for tuning future submissions – not guesswork.
Requesting too little causes jobs to fail; requesting much more than you
need makes jobs harder to match with available resources.

------------------------------------------------------------------------

## Step 3: generate the executable script

The executable script answers a different question: once the job starts,
what commands should run?

``` r

htc_gen_executable(
  r_script       = "analysis.R",
  output_file    = "analysis.sh",
  results_folder = "results",
  comments       = TRUE
)
```

The generated script handles a standard sequence: create the results
folder, run the R script with `Rscript`, and archive the results as
`results.tar.gz`. That sequence is not complicated, but it is exactly
the kind of glue code that can become a barrier for researchers who are
new to shell scripts. `submitr` writes the standard version so you can
focus on the analysis.

------------------------------------------------------------------------

## Step 4: preview and upload files

Before copying files to the submit node, do a dry run:

``` r

htc_upload(
  files   = c("analysis.sub", "analysis.sh", "analysis.R", "data.csv"),
  config  = cfg,
  dry_run = TRUE
)
#> ✔ Dry run -- command that would be executed:
#>   `scp analysis.sub analysis.sh analysis.R data.csv your.netid@ap2002.chtc.wisc.edu:~/`
```

A dry run is a safety habit. It lets you see the command before it
changes anything on the remote system. Once the command looks right,
upload the files:

``` r

htc_upload(
  files  = c("analysis.sub", "analysis.sh", "analysis.R", "data.csv"),
  config = cfg
)
```

------------------------------------------------------------------------

## Step 5: submit the job

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

The cluster ID is the handle for this submission. Store it in an object
so you can check the job later without having to look it up.

------------------------------------------------------------------------

## Step 6: check progress

``` r

# One-shot status check
htc_status(cluster_id = cluster_id, config = cfg)

# Watch until the job completes
htc_status(cluster_id = cluster_id, config = cfg, watch = TRUE)
```

For a small test job, `watch = TRUE` is useful. For larger workloads,
occasional one-shot checks are usually a better fit than keeping an R
session occupied.

------------------------------------------------------------------------

## Step 7: download results

When the job is complete, download the result archive and logs:

``` r

# Results
htc_download(
  files      = "*.tar.gz",
  config     = cfg,
  local_path = "results/"
)

# Logs
htc_download(
  files      = c("job.log", "job.err"),
  config     = cfg,
  local_path = "logs/"
)
```

The logs are not just for failures. They record what happened when the
job ran – including actual resource usage, which informs future resource
requests.

------------------------------------------------------------------------

## From one test job to many HTC jobs

A first job proves that the path works. The next step is to think like
an HTC user: how can the analysis be divided into many independent
pieces?

Common patterns include one job per simulation replicate, model
specification, input file, county, participant, sample, or parameter
set. This is where
[`toolero::write_by_group()`](https://erwinlares.github.io/toolero/reference/write_by_group.html)
helps upstream. It splits a data frame into separate CSV files and
writes a manifest describing those files. Then `submitr` queues one job
per row of the manifest:

``` r

htc_gen_submit(
  output_file     = "analysis.sub",
  container_image = "docker://registry.doit.wisc.edu/your.netid/my-analysis:1.0.0",
  executable      = "analysis.sh",
  input_files     = "analysis.R",
  mode            = "multiple",
  queue_from      = "data/manifest.csv",
  resources       = "medium",
  comments        = TRUE
)

htc_gen_executable(
  r_script       = "analysis.R",
  output_file    = "analysis.sh",
  results_folder = "results",
  mode           = "multiple",
  comments       = TRUE
)
```

In multiple-job mode, the generated executable passes the per-job input
file to your R script as the first command-line argument. Your script
should read that argument explicitly:

``` r

args       <- commandArgs(trailingOnly = TRUE)
input_file <- args[[1]]

data <- readr::read_csv(input_file)
```

This is a key pattern. The script stays the same; each job receives a
different input.

------------------------------------------------------------------------

## Where containr fits

CHTC needs to know what software environment your job should use. A
container image solves that problem by packaging the R version,
packages, and system libraries needed to run the analysis. `containr`
handles that step:

``` r

containr::generate_dockerfile(r_version = "4.4.0", output = ".")
containr::build_image(verbose = TRUE)
imgs <- containr::list_images()
containr::push_image(
  image_id = imgs$image_id[1],
  netid    = "your.netid",
  project  = "my-analysis",
  tag      = "1.0.0"
)
```

Use explicit image tags such as `"1.0.0"` rather than `"latest"`. A
versioned tag makes it unambiguous which software environment was used
for a particular analysis.

------------------------------------------------------------------------

## A practical first-submission checklist

Before scaling up, confirm that the small job works end to end:

- The script runs locally with `Rscript analysis.R`.
- ControlMaster is configured and the session is authenticated.
- The container image is pushed to a registry CHTC can access.
- The image tag is explicit, not `"latest"`.
- The submit file lists the correct executable and input files.
- The executable script points to the correct R script and results
  folder.
- The dry-run upload shows the expected files.
- [`htc_config()`](https://erwinlares.github.io/submitr/reference/htc_config.md)
  connects to the submit node without error.
- The resource request is reasonable for a test job.
- The job produces logs and a result archive.

Once this works, you have something valuable: a known-good pathway from
local R project to CHTC.

------------------------------------------------------------------------

## What submitr does not do

`submitr` reduces friction, but it does not remove the need to make
sound research-computing decisions.

It does not:

- decide whether your workload is a good fit for CHTC;
- make interactive R code safe for batch execution;
- guarantee that your container image contains every system dependency;
- manage restricted or sensitive data;
- replace CHTC documentation or consultation for complex workflows.

That boundary is intentional. Good tools should make the common path
easier while still leaving the important decisions visible.

The [CHTC facilitation
team](https://chtc.cs.wisc.edu/uw-research-computing/get-help) is the
right resource for complex workflow questions.

------------------------------------------------------------------------

## A good first goal

Do not make your first submission your largest analysis.

Make your first goal smaller: send one boring job to CHTC, watch it run,
and download one result file.

After that, the cluster becomes less mysterious. You can inspect the
generated files, adjust resources, split work into many jobs, and grow
the workflow with more confidence. That is the role of `submitr`: to
help you take the first successful step from local R code to
high-throughput research computing. lysis is actually answering. But at
some point, the same local workflow can become the wrong place to keep
pushing.

Maybe the analysis takes too long. Maybe you need to run the same model
across hundreds of parameter combinations. Maybe you need one job per
participant, county, simulation, image, genome, or bootstrap sample.
Maybe you simply want a workflow that will be easier to rerun six months
from now.

That is where high-throughput computing becomes useful.

The UW-Madison Center for High Throughput Computing (CHTC) gives
researchers access to large pools of computing capacity. Instead of
asking one computer to do everything in sequence, you can break work
into independent jobs and let the HTC system run those jobs when
resources are available.

`submitr` helps you take the final step in the **From the Notebook to
the Cluster** workflow: sending a prepared R project to CHTC.

It is designed for researchers who know R but may not yet be comfortable
with HTCondor submit files, executable shell scripts, `ssh`, `scp`, or
the rhythm of working on a remote submit node. It is also useful for
regular CHTC users who want to reduce repetitive setup work and make job
submission easier to reproduce, review, and share.

The goal is not to hide CHTC from you. The goal is to make the standard
path visible, repeatable, and less fragile.

## The larger idea: make the right choice easy

`submitr` is part of a small family of R packages for research computing
workflows:

``` text
local R project
  └─ toolero: organize the project and prepare job-sized inputs
      └─ containr: capture the R software environment in a container image
          └─ submitr: send the containerized job to CHTC
```

You can use each package on its own.

Use `toolero` if you want a better project skeleton, cleaner
data-loading habits, Quarto scaffolding, or a simple way to split a
dataset into many job-sized files.

Use `containr` if you already have a project with an `renv.lock` file
and want to build a container image that can run somewhere other than
your laptop.

Use `submitr` if your project is already organized and containerized,
and you are ready to submit it to CHTC.

Used together, the packages support a practical arc: start with a
project that is easier to understand, make its software environment
portable, then send it to CHTC with fewer command-line hurdles.

## What submitr does

A CHTC job needs a few pieces of information:

- what code to run;
- what input files to transfer;
- what container image to use;
- how much CPU, memory, and disk to request;
- what output files to retrieve;
- how many jobs to queue.

In HTCondor, that information is split across two main files.

The **submit file** tells HTCondor how to run the job. It describes the
executable script, container image, input files, output files, log
files, resource requests, and queue instructions.

The **executable script** tells the job what to do after it starts. For
an R analysis, that usually means creating an output folder, running
`Rscript`, and packaging results.

`submitr` helps you generate those files and then use them:

``` r

submitr::htc_config()         # configure your submit-node connection
submitr::htc_gen_submit()     # generate the HTCondor submit file
submitr::htc_gen_executable() # generate the executable shell script
submitr::htc_upload()         # copy files to the submit node
submitr::htc_submit()         # submit the job
submitr::htc_status()         # check progress
submitr::htc_download()       # copy results back
```

## Before you submit anything

A successful CHTC submission starts before `condor_submit`.

Before using `submitr`, make sure you have:

- an R script that can run with `Rscript`;
- the input files needed by that script;
- an `renv.lock` file or another clear record of package dependencies;
- a container image available from a registry CHTC can access;
- SSH access to a CHTC submit node, such as `ap2002.chtc.wisc.edu`.

The most important check is simple: your analysis should run outside
RStudio.

``` bash
Rscript analysis.R
```

If that command fails locally, the same analysis is likely to fail on
CHTC. Fix that first. CHTC will not know about objects in your Global
Environment, local RStudio settings, manually clicked files, or packages
that happen to be installed on your laptop.

For a first submission, choose something small and intentionally boring.
The goal is not to prove that your full analysis can scale yet. The goal
is to prove that the pathway works.

## A small example analysis

Suppose your project has this shape:

``` text
my-analysis/
├── analysis.R
├── data.csv
├── renv.lock
└── results/
```

Your `analysis.R` script might look like this:

``` r

library(readr)
library(dplyr)

input <- read_csv("data.csv")

summary <- input |>
  group_by(group) |>
  summarise(
    mean_value = mean(value, na.rm = TRUE),
    n = dplyr::n(),
    .groups = "drop"
  )

if (!dir.exists("results")) {
  dir.create("results")
}

write_csv(summary, "results/summary.csv")
```

This script is deliberately modest. A first CHTC job should be easy to
inspect. Once the small version works, you can scale the pattern with
more confidence.

## Step 1: configure your CHTC connection

Load `submitr` and create a project-level configuration:

``` r

library(submitr)

cfg <- htc_config()
```

On first use,
[`htc_config()`](https://erwinlares.github.io/submitr/reference/htc_config.md)
prompts for your NetID and submit node. It writes an `htc.cfg` file to
the project directory so later calls can reuse the same connection
information.

A later call should look something like this:

``` r

cfg <- htc_config()
#> Reading HTC config from ./htc.cfg
#> ✔ Connected to "ap2002.chtc.wisc.edu" as "netid".
```

This configuration file is deliberately project-local. Different
projects may need different submit nodes, paths, or connection settings.

## Step 2: generate the submit file

The submit file is the main HTCondor instruction file. It answers the
question: “What should the HTC system run, and what does it need?”

``` r

htc_gen_submit(
  output_file     = "analysis.sub",
  container_image = "docker://registry.doit.wisc.edu/netid/my-image:1.0.0",
  executable      = "analysis.sh",
  input_files     = c("analysis.R", "data.csv"),
  output_files    = "results.tar.gz",
  resources       = "small",
  comments        = TRUE,
  output          = "."
)
```

For a first submission, keep `comments = TRUE`. The generated file will
include explanations of the main sections. That makes it easier to
inspect the file, learn from it, and share it with a collaborator or
consultant.

The `resources` argument uses presets:

| preset | cpus | memory | disk  |
|--------|------|--------|-------|
| small  | 1    | 4 GB   | 4 GB  |
| medium | 4    | 16 GB  | 15 GB |
| large  | 8    | 64 GB  | 32 GB |

For a first test, choose the smallest preset that is plausible for your
job. Requesting too little can make a job fail. Requesting much more
than you need can make the job harder to match with available resources.

## Step 3: generate the executable script

The executable script answers a different question: “Once the job
starts, what commands should run?”

``` r

htc_gen_executable(
  r_script       = "analysis.R",
  output_file    = "analysis.sh",
  results_folder = "results",
  comments       = TRUE
)
```

The generated script handles a standard sequence:

1.  create the results folder;
2.  run the R script with `Rscript`;
3.  archive the results as `results.tar.gz`.

That sequence is not complicated, but it is exactly the kind of glue
code that can become a barrier for researchers who are new to shell
scripts. `submitr` writes the standard version so you can focus on the
analysis.

## Step 4: preview the upload

Before copying files to the submit node, do a dry run:

``` r

htc_upload(
  files   = c("analysis.sub", "analysis.sh", "analysis.R", "data.csv"),
  config  = cfg,
  dry_run = TRUE
)
#> ✔ Dry run -- command that would be executed:
#>   `scp analysis.sub analysis.sh analysis.R data.csv netid@ap2002.chtc.wisc.edu:~/`
```

A dry run is a safety habit. It lets you see the command before it
changes anything on the remote system.

If the command looks right, upload the files:

``` r

htc_upload(
  files  = c("analysis.sub", "analysis.sh", "analysis.R", "data.csv"),
  config = cfg
)
```

## Step 5: submit the job

Submit the job from R:

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

The cluster ID is the handle for this submission. Store it in an object
so you can check the job later.

## Step 6: check progress

For a one-time status check:

``` r

htc_status(cluster_id = cluster_id, config = cfg)
```

For a small test job, you can watch until the job completes:

``` r

htc_status(
  cluster_id = cluster_id,
  config     = cfg,
  watch      = TRUE
)
```

For larger workloads, occasional status checks are usually better than
keeping an R session occupied.

## Step 7: download results

When the job is complete, download the result archive:

``` r

htc_download(
  files      = "*.tar.gz",
  config     = cfg,
  local_path = "results/"
)
```

You can also retrieve logs and error files:

``` r

htc_download(
  files      = c("job.log", "job.err"),
  config     = cfg,
  local_path = "logs/"
)
```

The logs are not just for failures. They are part of the record of what
happened when the job ran.

## Making repeated SSH prompts less painful

Each upload, submit, status, and download call uses SSH. Without
connection reuse, that can mean repeated Duo MFA prompts.

CHTC recommends using SSH `ControlMaster` settings so multiple SSH calls
can reuse one authenticated connection. Add this block to
`~/.ssh/config`:

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

[`htc_config()`](https://erwinlares.github.io/submitr/reference/htc_config.md)
displays this guidance when it creates a new configuration file. This is
a small setup step, but it can make the day-to-day workflow much
smoother.

## From one test job to many HTC jobs

A first job proves that the path works. The next step is to think like
an HTC user.

HTC works best when a large task can be divided into many independent
pieces. Common examples include:

- one job per simulation replicate;
- one job per model specification;
- one job per input file;
- one job per county, participant, sample, or parameter set;
- one job per bootstrap iteration.

This is where `toolero` can help upstream. For example,
[`toolero::write_by_group()`](https://erwinlares.github.io/toolero/reference/write_by_group.html)
can split a data frame into separate CSV files and write a manifest
describing those files.

Then `submitr` can queue one job per row of the manifest:

``` r

htc_gen_submit(
  output_file     = "analysis.sub",
  container_image = "docker://registry.doit.wisc.edu/netid/my-image:1.0.0",
  executable      = "analysis.sh",
  input_files     = "analysis.R",
  mode            = "multiple",
  queue_from      = "data/manifest.csv",
  resources       = "medium",
  comments        = TRUE
)
```

Generate the executable in multiple-job mode:

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
file to your R script as the first command-line argument. Your script
should read that argument explicitly:

``` r

args <- commandArgs(trailingOnly = TRUE)
input_file <- args[[1]]

input <- readr::read_csv(input_file)
```

This is a key pattern. The script stays the same, but each job receives
a different input.

## Where containr fits

CHTC needs to know what software environment your job should use. Your
laptop may have the right R packages installed, but the execute node
will not automatically have the same setup.

A container image solves that problem by packaging the software
environment needed to run the analysis.

`containr` helps with that step:

``` r

containr::generate_dockerfile(r_version = "4.4.0", output = ".")
containr::build_image(verbose = TRUE)
imgs <- containr::list_images()
containr::push_image(
  image_id = imgs$image_id[1],
  netid    = "netid",
  project  = "container-registry",
  tag      = "1.0.0"
)
```

After the image is pushed to a registry CHTC can access, `submitr` can
refer to it in `container_image`.

Use explicit image tags such as `"1.0.0"` rather than relying on
`"latest"`. A versioned tag makes it easier to know which software
environment was used for a particular analysis.

## A practical first-submission checklist

Before scaling up, confirm that the small job works:

- The script runs locally with `Rscript analysis.R`.
- The project has the input files listed in `input_files`.
- The container image has been pushed to a registry CHTC can access.
- The image tag is explicit, not just `latest`.
- The submit file was generated with the expected executable and inputs.
- The executable script points to the correct R script and results
  folder.
- The dry-run upload shows the files you expect.
- [`htc_config()`](https://erwinlares.github.io/submitr/reference/htc_config.md)
  can connect to the submit node.
- The resource request is reasonable for a test job.
- The job produces logs and a result archive.

Once this works, you have something valuable: a known-good pathway from
local project to CHTC.

## What submitr does not try to do

`submitr` reduces friction, but it does not remove the need to make
sound research-computing decisions.

It does not:

- decide whether your workload is a good fit for CHTC;
- make interactive R code safe for batch execution;
- guarantee that your container image contains every system dependency;
- manage restricted or sensitive data;
- replace CHTC documentation or consultation for complex workflows.

That boundary is intentional. Good tools should make the common path
easier while still leaving the important decisions visible.

## A good first goal

Do not make your first submission your largest analysis.

Make your first goal smaller:

> Send one boring job to CHTC, watch it run, and download one result
> file.

After that, the cluster becomes less mysterious. You can inspect the
generated files, adjust resources, split work into many jobs, and grow
the workflow with more confidence.

That is the role of `submitr`: to help you take the first successful
step from local R code to high-throughput research computing.
