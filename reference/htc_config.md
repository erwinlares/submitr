# Configure a connection to an HTC submit server

`htc_config()` creates or reads an `htc.cfg` file that stores the
connection details needed by `htc_stage()`,
[`htc_submit()`](https://erwinlares.github.io/submitr/reference/htc_submit.md),
[`htc_status()`](https://erwinlares.github.io/submitr/reference/htc_status.md),
and `htc_fetch_results()`. On first use it prompts interactively for
your username and server address, writes `htc.cfg` to `path`, and adds
it to `.gitignore`. Subsequent calls read the existing file.

## Usage

``` r
htc_config(username = NULL, server = NULL, path = ".", overwrite = FALSE)
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

## Value

A named list with elements `username` and `server`, returned invisibly.

## SSH connection reuse

Each call to `htc_stage()`,
[`htc_submit()`](https://erwinlares.github.io/submitr/reference/htc_submit.md),
[`htc_status()`](https://erwinlares.github.io/submitr/reference/htc_status.md),
or `htc_fetch_results()` opens a new SSH connection to the submit
server, which triggers a Duo MFA prompt each time. You can avoid this by
configuring SSH connection reuse (ControlMaster) in your `~/.ssh/config`
file. Add the following block:

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

# Use in other functions
htc_upload(files = c("job.sub", "job.sh"), config = cfg)
} # }
```
