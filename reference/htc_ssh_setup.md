# Configure SSH connection reuse (ControlMaster) for CHTC

`htc_ssh_setup()` writes the ControlMaster block described in
[`htc_config()`](https://erwinlares.github.io/submitr/reference/htc_config.md)'s
own setup guidance to `~/.ssh/config` and creates the connections
directory it references, so that reuse can be set up without leaving R
(S-G3). Every function in this package that opens an SSH connection –
[`htc_upload()`](https://erwinlares.github.io/submitr/reference/htc_upload.md),
[`htc_submit()`](https://erwinlares.github.io/submitr/reference/htc_submit.md),
[`htc_status()`](https://erwinlares.github.io/submitr/reference/htc_status.md),
[`htc_download()`](https://erwinlares.github.io/submitr/reference/htc_download.md),
[`htc_cancel()`](https://erwinlares.github.io/submitr/reference/htc_cancel.md),
and
[`htc_release()`](https://erwinlares.github.io/submitr/reference/htc_release.md)
– benefits, since each currently opens a fresh connection per call and
triggers a separate Duo MFA prompt without this.

## Usage

``` r
htc_ssh_setup(
  ssh_config_path = "~/.ssh/config",
  connections_dir = "~/.ssh/connections",
  host_pattern = "*.chtc.wisc.edu",
  dry_run = FALSE
)
```

## Arguments

- ssh_config_path:

  A character string. Path to the SSH client config file to append to.
  Defaults to `"~/.ssh/config"`.

- connections_dir:

  A character string. Path to the directory `ControlPath` will use for
  its control sockets. Defaults to `"~/.ssh/connections"`. Written into
  the config file exactly as given (so a leading `~` is expanded by
  `ssh` itself at connection time, not by R), and created on disk if it
  does not already exist.

- host_pattern:

  A character string. The `Host` pattern the block applies to. Defaults
  to `"*.chtc.wisc.edu"`, matching every CHTC submit node. Narrow this
  if you only want reuse for one specific host.

- dry_run:

  Logical. If `TRUE`, prints what would be added and created without
  writing anything. Defaults to `FALSE`.

## Value

Called for its side effects. Returns `invisible(NULL)`.

## What this does not do

If a `Host` block matching `host_pattern` already exists in
`ssh_config_path`, `htc_ssh_setup()` leaves the file untouched and says
so – it never edits or replaces an existing block, since the existing
one may have been customized deliberately. Remove or edit it by hand
first if you want `htc_ssh_setup()` to write a fresh one.

## Windows

`ControlPath` relies on Unix domain sockets, which native Windows
OpenSSH (as shipped with Windows 10/11) has historically supported
inconsistently across versions. `htc_ssh_setup()` still writes the block
on Windows – it may simply work, particularly on a current OpenSSH
release – but if `ssh` subsequently errors mentioning `ControlPath` or a
socket, connection reuse is not supported on this system: remove the
added block and expect a Duo MFA prompt on every call instead. OpenSSH
bundled with WSL or with Git Bash is more likely to support this than
the native Windows client.

## See also

[`htc_config()`](https://erwinlares.github.io/submitr/reference/htc_config.md),
whose own first-run message describes this same block for manual setup.

## Examples

``` r
# \donttest{
# Preview without touching any files
htc_ssh_setup(dry_run = TRUE)
#> ✔ Dry run -- would append the following to ~/.ssh/config:
#>   Host *.chtc.wisc.edu ControlMaster auto ControlPersist 2h ControlPath
#>   ~/.ssh/connections/%r@%h:%p
#> ℹ And create ~/.ssh/connections if it does not already exist.
# }

if (FALSE) { # \dontrun{
htc_ssh_setup()

# Apply only to one specific submit node
htc_ssh_setup(host_pattern = "ap2002.chtc.wisc.edu")
} # }
```
