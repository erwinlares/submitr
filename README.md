# submitr <img src="man/figures/logo.png" align="right" height="139" alt="submitr package logo"/>

<!-- badges: start -->
[![R-CMD-check](https://github.com/erwinlares/submitr/actions/workflows/R-CMD-check.yaml/badge.svg)](https://github.com/erwinlares/submitr/actions/workflows/R-CMD-check.yaml)
[![Lifecycle: experimental](https://img.shields.io/badge/lifecycle-experimental-orange.svg)](https://lifecycle.r-lib.org/articles/stages.html#experimental)
<!-- badges: end -->

`submitr` helps researchers prepare and submit containerized R analyses to
high-throughput computing (HTC) schedulers. It generates the files HTCondor
needs to run a job, wraps the SSH and SCP commands that move files to and
from the submit node, and monitors job progress — all from R.

The package is designed for researchers at the University of Wisconsin–Madison
using [CHTC](https://chtc.cs.wisc.edu), but the core workflow applies to any
HTCondor-based HTC system.

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

## The full workflow

submitr is one step in a larger pipeline. The complete sequence from data
to results looks like this:

```
toolero::init_project()         initializes coding project with sensible defaults + git and renv
toolero::create_qmd()           scaffolds a qmd and extracts R code automatically to prevent code drift
toolero::write_by_group()       split dataset into subsets based on an existing variable
containr::generate_dockerfile() generate Dockerfile from renv.lock
containr::build_image()         build container image locally
containr::push_image()          push image to registry
submitr::htc_config()           configure CHTC connection
submitr::htc_gen_submit()       generate HTCondor submit file (.sub)
submitr::htc_gen_executable()   generate job executable script (.sh)
submitr::htc_upload()           copy files to CHTC submit node
submitr::htc_submit()           submit job to HTCondor
submitr::htc_status()           monitor job progress
submitr::htc_download()         retrieve results
```

---

## Getting started

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
  container_image = "docker://registry.doit.wisc.edu/erwin.lares/my-image",
  executable      = "analysis.sh",
  input_files     = c("analysis.R", "data.csv"),
  output_files    = "results.tar.gz",
  resources       = "medium",
  comments        = TRUE,
  output          = "."
)
```

The `comments = TRUE` argument annotates each section of the submit file
with an explanation of what it does — useful when you are learning HTCondor
or sharing your setup with collaborators.

Three resource presets are available out of the box:

| preset | cpus | memory | disk  |
|--------|------|--------|-------|
| small  | 1    | 4 GB   | 4 GB  |
| medium | 4    | 16 GB  | 15 GB |
| large  | 8    | 64 GB  | 32 GB |

To customize presets for a project, copy `htc-resources.yaml` from the
package to your project directory and edit the values. `htc_gen_submit()`
uses the local file when present.

For multiple-job submissions driven by a manifest from
`toolero::write_by_group()`:

```r
htc_gen_submit(
  output_file     = "analysis.sub",
  container_image = "docker://registry.doit.wisc.edu/erwin.lares/my-image",
  executable      = "analysis.sh",
  input_files     = "analysis.R",
  mode            = "multiple",
  queue_from      = "data/manifest.csv",
  resources       = "medium"
)
```

### Step 3 — Generate the executable script

```r
htc_gen_executable(
  r_script       = "analysis.R",
  output_file    = "analysis.sh",
  results_folder = "results",
  mode           = "multiple",
  comments       = TRUE
)
```

The generated script handles `mkdir`, `Rscript`, and `tar` in the correct
order. In multiple-job mode, it passes `${1}` (the per-job subset filename)
as a positional argument to your R script.

### Step 4 — Upload files to CHTC

```r
htc_upload(
  files  = c("analysis.sub", "analysis.sh", "analysis.R", "data.csv"),
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

### Step 5 — Submit the job

```r
cluster_id <- htc_submit(
  submit_file = "analysis.sub",
  config      = cfg,
  verbose     = TRUE
)
#> Submitting "analysis.sub" on "ap2002.chtc.wisc.edu"...
#> Submitting job(s)...
#> 10 job(s) submitted to cluster 6302860.
#> ✔ Job submitted from "~/analysis.sub" on "ap2002.chtc.wisc.edu".
```

`htc_submit()` returns the cluster ID invisibly so you can pass it directly
to `htc_status()`.

### Step 6 — Monitor progress

```r
# One-shot status check
htc_status(cluster_id = cluster_id, config = cfg)

# Watch until all jobs complete (polls every 60 seconds)
htc_status(cluster_id = cluster_id, config = cfg, watch = TRUE)
```

### Step 7 — Download results

```r
# Download all result tarballs
htc_download(
  files      = "*.tar.gz",
  config     = cfg,
  local_path = "results/"
)

# Download specific files
htc_download(
  files      = c("job.log", "job.err"),
  config     = cfg,
  local_path = "logs/"
)
```

---

## SSH connection reuse

Each `htc_upload()`, `htc_submit()`, `htc_status()`, and `htc_download()`
call opens a new SSH connection to the submit node, which triggers a Duo MFA
prompt. You can reduce this to one prompt per two-hour window by configuring
ControlMaster in your `~/.ssh/config`:

```
Host *.chtc.wisc.edu
  ControlMaster auto
  ControlPersist 2h
  ControlPath ~/.ssh/connections/%r@%h:%p
```

Then:

```bash
mkdir -p ~/.ssh/connections
```

`htc_config()` displays these instructions automatically on first use. Full
documentation: <https://chtc.cs.wisc.edu/uw-research-computing/configure-ssh>

---

## Functions

### Scaffolding

`htc_gen_submit()` generates an HTCondor `.sub` submit file. Supports
single-job and multiple-job modes. Resource presets are loaded from a YAML
file and can be customized per project.

`htc_gen_executable()` generates the `.sh` script that HTCondor runs inside
the container. Handles `mkdir`, `Rscript`, and `tar` in the correct order.

### Connection management

`htc_config()` creates or reads `htc.cfg` in the project directory. Validates
server reachability and displays ControlMaster setup guidance on first use.

### Job submission

`htc_upload()` copies files to the CHTC submit node via `scp`. Accepts
single files, vectors of files, and directory paths.

`htc_submit()` runs `condor_submit` on the remote server via SSH. Returns
the cluster ID invisibly for use with `htc_status()`.

`htc_status()` runs `condor_q` on the remote server. Optionally polls
repeatedly until all jobs complete (`watch = TRUE`).

`htc_download()` copies files back from the submit node via `scp`. Supports
glob patterns (`"*.tar.gz"`, `"job.*"`).

---

## Related packages

submitr is one of four sibling packages:

- [toolero](https://github.com/erwinlares/toolero) — research workflow toolkit
- [containr](https://github.com/erwinlares/containr) — container image management
- [curriculr](https://github.com/erwinlares/curriculr) — data-driven CV generation
- **submitr** — HTC job submission

---

## License

MIT © Erwin Lares
