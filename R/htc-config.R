#' Configure a connection to an HTC submit server
#'
#' `htc_config()` creates or reads an `htc.cfg` file that stores the
#' connection details needed by `htc_stage()`, `htc_submit()`,
#' `htc_status()`, and `htc_fetch_results()`. On first use it prompts
#' interactively for your username and server address, writes `htc.cfg`
#' to `path`, and adds it to `.gitignore`. Subsequent calls read the
#' existing file.
#'
#' @param username A character string. Your HTC username (NetID), e.g.
#'   `"erwin.lares"`. If `NULL` and no `htc.cfg` exists, the function
#'   prompts interactively.
#' @param server A character string. The HTC submit server hostname.
#'   Defaults to `"ap2002.chtc.wisc.edu"`. If `NULL` and no `htc.cfg`
#'   exists, the function prompts interactively.
#' @param path A character string. Directory where `htc.cfg` will be
#'   read from or written to. Defaults to `"."` (current working
#'   directory).
#' @param overwrite Logical. If `TRUE`, recreates `htc.cfg` even if one
#'   already exists. Defaults to `FALSE`.
#'
#' @return A named list with elements `username` and `server`, returned
#'   invisibly.
#'
#' @section SSH connection reuse:
#' Each call to `htc_stage()`, `htc_submit()`, `htc_status()`, or
#' `htc_fetch_results()` opens a new SSH connection to the submit server,
#' which triggers a Duo MFA prompt each time. You can avoid this by
#' configuring SSH connection reuse (ControlMaster) in your
#' `~/.ssh/config` file. Add the following block:
#'
#' ```
#' Host *.chtc.wisc.edu
#'   ControlMaster auto
#'   ControlPersist 2h
#'   ControlPath ~/.ssh/connections/%r@%h:%p
#' ```
#'
#' Then create the connections directory:
#'
#' ```bash
#' mkdir -p ~/.ssh/connections
#' ```
#'
#' After this, only the first connection in a two-hour window will
#' require Duo authentication. Full documentation:
#' <https://chtc.cs.wisc.edu/uw-research-computing/configure-ssh>
#'
#' @section Security:
#' `htc.cfg` contains your username and server address. Neither is
#' sensitive on its own, but `htc_config()` adds `htc.cfg` to
#' `.gitignore` on creation to avoid accidentally committing
#' institutional account details to a public repository.
#'
#' @export
#'
#' @examples
#' \donttest{
#' # Preview what htc_config() would return without writing any files
#' cfg <- list(username = "netid", server = "ap2002.chtc.wisc.edu")
#' str(cfg)
#' }
#'
#' \dontrun{
#' # Interactive first-time setup
#' cfg <- htc_config()
#'
#' # Non-interactive setup (for scripts)
#' cfg <- htc_config(
#'   username = "erwin.lares",
#'   server   = "ap2002.chtc.wisc.edu"
#' )
#'
#' # Force recreation of htc.cfg
#' cfg <- htc_config(overwrite = TRUE)
#'
#' # Use in other functions
#' htc_upload(files = c("job.sub", "job.sh"), config = cfg)
#' }

htc_config <- function(username  = NULL,
                       server    = NULL,
                       path      = ".",
                       overwrite = FALSE) {

    cfg_path <- file.path(path, "htc.cfg")

    # -- 1. Read existing config if present ------------------------------------
    if (file.exists(cfg_path) && !overwrite) {
        cfg <- yaml::read_yaml(cfg_path)

        if (is.null(cfg$username) || is.null(cfg$server)) {
            cli::cli_abort(c(
                "{.file {cfg_path}} is missing required fields.",
                "i" = "Expected {.val username} and {.val server}.",
                "i" = "Run {.code htc_config(overwrite = TRUE)} to recreate it."
            ))
        }

        if (verbose <- getOption("htc_config_verbose", default = TRUE)) {
            cli::cli_inform(
                "Reading HTC config from {.file {cfg_path}}"
            )
        }

        cfg <- list(username = cfg$username, server = cfg$server)
        .htc_check_server(cfg)
        return(invisible(cfg))
    }

    # -- 2. Prompt interactively if arguments not supplied --------------------
    if (is.null(username)) {
        if (!interactive()) {
            cli::cli_abort(c(
                "{.arg username} must be supplied in non-interactive sessions.",
                "i" = "Call {.code htc_config(username = 'yournetid', server = '...')}",
                " " = "  or create {.file {cfg_path}} manually."
            ))
        }
        username <- readline("Enter your HTC username (NetID): ")
        username <- trimws(username)
        if (nchar(username) == 0L) {
            cli::cli_abort("Username cannot be empty.")
        }
    }

    if (is.null(server)) {
        if (!interactive()) {
            cli::cli_abort(c(
                "{.arg server} must be supplied in non-interactive sessions.",
                "i" = "Call {.code htc_config(username = '...', server = '...')}",
                " " = "  or create {.file {cfg_path}} manually."
            ))
        }
        server_input <- readline(
            "Enter the HTC submit server [ap2002.chtc.wisc.edu]: "
        )
        server_input <- trimws(server_input)
        server <- if (nchar(server_input) == 0L) "ap2002.chtc.wisc.edu" else server_input
    }

    # Validate supplied values
    if (nchar(trimws(username)) == 0L) {
        cli::cli_abort("{.arg username} cannot be empty.")
    }
    if (nchar(trimws(server)) == 0L) {
        cli::cli_abort("{.arg server} cannot be empty.")
    }

    cfg <- list(username = username, server = server)

    # -- 3. ControlMaster notice on first creation ----------------------------
    cli::cli_inform(c(
        "",
        "!" = "SSH connection reuse (ControlMaster) is strongly recommended.",
        "i" = "Without it, each call to {.fn htc_stage}, {.fn htc_submit},",
        " " = "  {.fn htc_status}, or {.fn htc_fetch_results} will trigger a",
        " " = "  separate Duo MFA prompt.",
        "i" = "Add the following to {.file ~/.ssh/config}:",
        " " = "",
        " " = "  Host *.chtc.wisc.edu",
        " " = "    ControlMaster auto",
        " " = "    ControlPersist 2h",
        " " = "    ControlPath ~/.ssh/connections/%r@%h:%p",
        " " = "",
        " " = "  Then run: mkdir -p ~/.ssh/connections",
        " " = "",
        "i" = "Full guide: {.url https://chtc.cs.wisc.edu/uw-research-computing/configure-ssh}",
        ""
    ))

    # -- 4. Write htc.cfg ------------------------------------------------------
    yaml::write_yaml(cfg, cfg_path)
    cli::cli_alert_success("Created {.file {cfg_path}}")

    # -- 5. Add to .gitignore --------------------------------------------------
    gitignore_path <- file.path(path, ".gitignore")
    .htc_add_to_gitignore("htc.cfg", gitignore_path)

    # -- 6. Validate server reachability ---------------------------------------
    .htc_check_server(cfg)

    invisible(cfg)
}


# -- Internal: check server reachability --------------------------------------

#' @keywords internal
.htc_check_server <- function(cfg) {
    if (is.null(cfg$username) || is.null(cfg$server)) return(invisible(NULL))

    if (verbose <- getOption("htc_config_verbose", default = TRUE)) {
        cli::cli_inform("Checking connectivity to {.val {cfg$server}}...")
    }

    exit_code <- system2(
        "ssh",
        args   = c(
            "-q",
            "-o", "BatchMode=yes",
            "-o", "ConnectTimeout=5",
            paste0(cfg$username, "@", cfg$server),
            "exit"
        ),
        stdout = FALSE,
        stderr = FALSE
    )

    if (exit_code == 255L) {
        cli::cli_warn(c(
            "Could not reach {.val {cfg$server}}.",
            "i" = "Check your network connection and VPN status.",
            "i" = "Functions using this config will fail unless",
            " " = "  {.arg dry_run = TRUE} is used."
        ))
    } else if (exit_code != 0L) {
        cli::cli_inform(c(
            "i" = "Connected to {.val {cfg$server}} but authentication",
            " " = "  may be required.",
            "i" = "Run {.code ssh {cfg$username}@{cfg$server}} in your terminal",
            " " = "  to authenticate before calling {.fn htc_stage} or",
            " " = "  {.fn htc_submit}."
        ))
    } else {
        cli::cli_alert_success(
            "Connected to {.val {cfg$server}} as {.val {cfg$username}}."
        )
    }

    invisible(NULL)
}


# -- Internal: add entry to .gitignore ----------------------------------------

#' @keywords internal
.htc_add_to_gitignore <- function(entry, gitignore_path) {
    existing <- if (file.exists(gitignore_path)) {
        readLines(gitignore_path, warn = FALSE)
    } else {
        character(0)
    }

    if (!entry %in% existing) {
        writeLines(c(existing, entry), gitignore_path)
        cli::cli_inform("Added {.val {entry}} to {.file {gitignore_path}}")
    }

    invisible(NULL)
}
