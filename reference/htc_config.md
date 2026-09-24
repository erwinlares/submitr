# Configure a connection to an HTC submit server

`htc_config()` creates or reads an `htc.cfg` file that stores the
connection details needed by
[`htc_upload()`](https://erwinlares.github.io/submitr/reference/htc_upload.md),
[`htc_submit()`](https://erwinlares.github.io/submitr/reference/htc_submit.md),
[`htc_status()`](https://erwinlares.github.io/submitr/reference/htc_status.md),
and
[`htc_download()`](https://erwinlares.github.io/submitr/reference/htc_download.md).
On first use it prompts interactively for your username and server
address, writes `htc.cfg` to `path`, and adds it to `.gitignore`.
Subsequent calls read the existing file.

## Usage

``` r
htc_config(
  username = NULL,
  server = NULL,
  path = ".",
  overwrite = FALSE,
  project_config = NULL,
  check_server = getOption("submitr.check_server", default = TRUE)
)
```

## Arguments

- username:

  A character string. Your HTC username (NetID), e.g. `"erwin.lares"`.
  If `NULL` and no `htc.cfg` exists, the function prompts interactively.

- server:

  A character string. The HTC submit server hostname. Defaults to
  `"ap2002.chtc.wisc.edu"`. If `NULL` and no `htc.cfg` exists, the
  function prompts interactively.

- path:

  A character string. Directory where `htc.cfg` will be read from or
  written to. Defaults to `"."` (current working directory).

- overwrite:

  Logical. If `TRUE`, recreates `htc.cfg` even if one already exists.
  Defaults to `FALSE`.

- project_config:

  A character string or `NULL` (the default). Path to a `_toolero.yml`
  file, the resolved project configuration
  [`toolero::init_project()`](https://erwinlares.github.io/toolero/reference/init_project.html)
  writes to a project's root. When supplied, its `folders` and
  `conventions` sections are parsed once and folded into the returned
  list under `project`, so `config$project$folders` and
  `config$project$conventions` become available alongside the connection
  details. This is the same file, in the same schema, that
  [`containr::generate_dockerfile()`](https://erwinlares.github.io/containr/reference/generate_dockerfile.html)
  reads through its own `config` argument. Never written into `htc.cfg`:
  project layout and SSH connection details are recorded separately, and
  `htc.cfg` on disk is unaffected by whether you pass `project_config`.

- check_server:

  Logical. If `TRUE`, opens a short SSH connection to `server` to report
  whether it is reachable before you rely on the config. Defaults to the
  `submitr.check_server` option, which is itself `TRUE` unless you set
  it otherwise. Set to `FALSE` in scripts, test suites, and anywhere
  else the probe has no audience – reading a config file then costs
  nothing and touches no network.

## Value

A named list with elements `username` and `server`, plus a `project`
element when `project_config` is supplied, returned invisibly.

## Options

Two options adjust how much `htc_config()` does on your behalf. Both
default to `TRUE`, and both are most useful set once for a whole session
or test suite rather than per call.

`submitr.verbose` controls the progress messages ("Reading HTC config
from ...", "Checking connectivity to ..."). Setting it to `FALSE` leaves
warnings and errors intact.

`submitr.check_server` controls the reachability probe described under
`check_server` above. The argument takes precedence when supplied, so
the option sets the default and a call can still override it.

## SSH connection reuse

Each call to
[`htc_upload()`](https://erwinlares.github.io/submitr/reference/htc_upload.md),
[`htc_submit()`](https://erwinlares.github.io/submitr/reference/htc_submit.md),
[`htc_status()`](https://erwinlares.github.io/submitr/reference/htc_status.md),
or
[`htc_download()`](https://erwinlares.github.io/submitr/reference/htc_download.md)
opens a new SSH connection to the submit server, which triggers a Duo
MFA prompt each time. You can avoid this by configuring SSH connection
reuse (ControlMaster) in your `~/.ssh/config` file. Add the following
block:

    Host *.chtc.wisc.edu
      ControlMaster auto
      ControlPersist 2h
      ControlPath ~/.ssh/connections/%r@%h:%p

Then create the connections directory:

    mkdir -p ~/.ssh/connections

After this, only the first connection in a two-hour window will require
Duo authentication. Full documentation:
<https://chtc.cs.wisc.edu/uw-research-computing/configure-ssh>

## Project configuration

`project_config` is how `submitr` learns the layout a `toolero` project
already settled on, instead of retyping it.
[`toolero::init_project()`](https://erwinlares.github.io/toolero/reference/init_project.html)
writes `_toolero.yml` to a project's root once it has resolved the
folder set, and that file records two things: `folders`, the full list
of folders the project uses, and `conventions`, the names the family
resolves rather than assumes (`output_dir`, `script_dir`, `split_dir`).

Passing `project_config = "_toolero.yml"` reads that file once and
returns it under `config$project`:

    cfg <- htc_config(project_config = "_toolero.yml")
    cfg$project$conventions$output_dir
    #> [1] "output"

As of this release (S-G5), passing the returned config's `project`
element on to
[`htc_gen_executable()`](https://erwinlares.github.io/submitr/reference/htc_gen_executable.md)
and
[`htc_gen_submit()`](https://erwinlares.github.io/submitr/reference/htc_gen_submit.md)
via their own `config` argument lets `results_folder` and `queue_from`
default from `conventions$output_dir` and `conventions$split_dir`, the
way
[`containr::generate_dockerfile()`](https://erwinlares.github.io/containr/reference/generate_dockerfile.html)
already reads the same file for its own purposes:

    cfg <- htc_config(project_config = "_toolero.yml")
    htc_gen_executable(r_script = "R/analysis.R", config = cfg)
    htc_gen_submit(mode = "multiple", config = cfg)

`r_script` itself is not defaulted from `conventions$script_dir`: the
convention names a directory, not a file, and the script's own filename
is project-specific information `_toolero.yml` has no way to record.

## Security

`htc.cfg` contains your username and server address. Neither is
sensitive on its own, but `htc_config()` adds `htc.cfg` to `.gitignore`
on creation to avoid accidentally committing institutional account
details to a public repository.

## Examples

``` r
# \donttest{
# Preview what htc_config() would return without writing any files
cfg <- list(username = "netid", server = "ap2002.chtc.wisc.edu")
str(cfg)
#> List of 2
#>  $ username: chr "netid"
#>  $ server  : chr "ap2002.chtc.wisc.edu"
# }

if (FALSE) { # \dontrun{
# Interactive first-time setup
cfg <- htc_config()

# Non-interactive setup (for scripts)
cfg <- htc_config(
  username = "erwin.lares",
  server   = "ap2002.chtc.wisc.edu"
)

# Force recreation of htc.cfg
cfg <- htc_config(overwrite = TRUE)

# Read the config without probing the server, e.g. in a script or on CI
cfg <- htc_config(check_server = FALSE)

# Or turn the probe off for a whole session
options(submitr.check_server = FALSE)

# Fold in a toolero project's own folder layout and conventions
cfg <- htc_config(project_config = "_toolero.yml")
cfg$project$conventions$output_dir

# Use in other functions
htc_upload(files = c("job.sub", "job.sh"), config = cfg)
} # }
```
