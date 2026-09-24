#' Configure SSH connection reuse (ControlMaster) for CHTC
#'
#' `htc_ssh_setup()` writes the ControlMaster block described in
#' [htc_config()]'s own setup guidance to `~/.ssh/config` and creates the
#' connections directory it references, so that reuse can be set up without
#' leaving R (S-G3). Every function in this package that opens an SSH
#' connection -- [htc_upload()], [htc_submit()], [htc_status()],
#' [htc_download()], [htc_cancel()], and [htc_release()] -- benefits, since
#' each currently opens a fresh connection per call and triggers a separate
#' Duo MFA prompt without this.
#'
#' @param ssh_config_path A character string. Path to the SSH client config
#'   file to append to. Defaults to `"~/.ssh/config"`.
#' @param connections_dir A character string. Path to the directory
#'   `ControlPath` will use for its control sockets. Defaults to
#'   `"~/.ssh/connections"`. Written into the config file exactly as given
#'   (so a leading `~` is expanded by `ssh` itself at connection time, not by
#'   R), and created on disk if it does not already exist.
#' @param host_pattern A character string. The `Host` pattern the block
#'   applies to. Defaults to `"*.chtc.wisc.edu"`, matching every CHTC submit
#'   node. Narrow this if you only want reuse for one specific host.
#' @param dry_run Logical. If `TRUE`, prints what would be added and created
#'   without writing anything. Defaults to `FALSE`.
#'
#' @return Called for its side effects. Returns `invisible(NULL)`.
#'
#' @section What this does not do:
#' If a `Host` block matching `host_pattern` already exists in
#' `ssh_config_path`, `htc_ssh_setup()` leaves the file untouched and says
#' so -- it never edits or replaces an existing block, since the existing
#' one may have been customized deliberately. Remove or edit it by hand
#' first if you want `htc_ssh_setup()` to write a fresh one.
#'
#' @section Windows:
#' `ControlPath` relies on Unix domain sockets, which native Windows OpenSSH
#' (as shipped with Windows 10/11) has historically supported inconsistently
#' across versions. `htc_ssh_setup()` still writes the block on Windows --
#' it may simply work, particularly on a current OpenSSH release -- but if
#' `ssh` subsequently errors mentioning `ControlPath` or a socket, connection
#' reuse is not supported on this system: remove the added block and expect
#' a Duo MFA prompt on every call instead. OpenSSH bundled with WSL or with
#' Git Bash is more likely to support this than the native Windows client.
#'
#' @seealso [htc_config()], whose own first-run message describes this same
#'   block for manual setup.
#'
#' @export
#'
#' @examples
#' \donttest{
#' # Preview without touching any files
#' htc_ssh_setup(dry_run = TRUE)
#' }
#'
#' \dontrun{
#' htc_ssh_setup()
#'
#' # Apply only to one specific submit node
#' htc_ssh_setup(host_pattern = "ap2002.chtc.wisc.edu")
#' }
htc_ssh_setup <- function(ssh_config_path = "~/.ssh/config",
                          connections_dir = "~/.ssh/connections",
                          host_pattern    = "*.chtc.wisc.edu",
                          dry_run         = FALSE) {

    if (identical(.Platform$OS.type, "windows")) {
        cli::cli_warn(c(
            "!" = "ControlMaster relies on Unix domain sockets for ControlPath,",
            " " = "  which native Windows OpenSSH has historically supported",
            " " = "  inconsistently across versions.",
            "i" = "Proceeding anyway -- it may simply work on your version. If",
            " " = "  {.code ssh} later errors mentioning ControlPath or a socket,",
            " " = "  remove the block this adds and expect a Duo MFA prompt on",
            " " = "  every call instead.",
            "i" = "OpenSSH bundled with WSL or with Git Bash is more likely to",
            " " = "  support this than the native Windows client."
        ))
    }

    ssh_config_expanded  <- path.expand(ssh_config_path)
    connections_expanded <- path.expand(connections_dir)

    existing <- if (file.exists(ssh_config_expanded)) {
        readLines(ssh_config_expanded, warn = FALSE)
    } else {
        character(0)
    }

    host_line       <- paste0("Host ", host_pattern)
    already_present <- any(grepl(host_line, existing, fixed = TRUE))

    if (already_present) {
        cli::cli_inform(c(
            "i" = "{.file {ssh_config_path}} already has a {.val {host_line}} block.",
            "i" = "Leaving it as-is -- edit it by hand if it needs updating."
        ))
        return(invisible(NULL))
    }

    block <- c(
        "",
        host_line,
        "  ControlMaster auto",
        "  ControlPersist 2h",
        paste0("  ControlPath ", file.path(connections_dir, "%r@%h:%p"))
    )

    if (dry_run) {
        cli::cli_inform(c(
            "v" = "Dry run -- would append the following to {.file {ssh_config_path}}:",
            " " = paste(block, collapse = "\n"),
            "i" = "And create {.path {connections_dir}} if it does not already exist."
        ))
        return(invisible(NULL))
    }

    if (!dir.exists(connections_expanded)) {
        dir.create(connections_expanded, recursive = TRUE)
        cli::cli_alert_success("Created {.path {connections_dir}}")
    }

    config_dir <- dirname(ssh_config_expanded)
    if (!dir.exists(config_dir)) {
        dir.create(config_dir, recursive = TRUE)
    }

    writeLines(c(existing, block), ssh_config_expanded)

    cli::cli_alert_success(
        "Added a ControlMaster block for {.val {host_pattern}} to {.file {ssh_config_path}}"
    )
    cli::cli_inform(c(
        "i" = "The first connection in a session window will still prompt for",
        " " = "  Duo authentication; subsequent ones within the window will not."
    ))

    invisible(NULL)
}
