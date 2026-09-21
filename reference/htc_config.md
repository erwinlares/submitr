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

- check_server:

  Logical. If `TRUE`, opens a short SSH connection to `server` to report
  whether it is reachable before you rely on the config. Defaults to the
  `submitr.check_server` option, which is itself `TRUE` unless you set
  it otherwise. Set to `FALSE` in scripts, test suites, and anywhere
  else the probe has no audience – reading a config file then costs
  nothing and touches no network.

## Value

A named list with elements `username` and `server`, returned invisibly.

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

# Use in other functions
htc_upload(files = c("job.sub", "job.sh"), config = cfg)
} # }
```
