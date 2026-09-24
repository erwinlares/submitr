#' Configure a connection to an HTC submit server
#'
#' `htc_config()` creates or reads an `htc.cfg` file that stores the
#' connection details needed by `htc_upload()`, `htc_submit()`,
#' `htc_status()`, and `htc_download()`. On first use it prompts
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
#' @param project_config A character string or `NULL` (the default). Path to
#'   a `_toolero.yml` file, the resolved project configuration
#'   `toolero::init_project()` writes to a project's root. When supplied,
#'   its `folders` and `conventions` sections are parsed once and folded
#'   into the returned list under `project`, so `config$project$folders`
#'   and `config$project$conventions` become available alongside the
#'   connection details. This is the same file, in the same schema, that
#'   `containr::generate_dockerfile()` reads through its own `config`
#'   argument. Never written into `htc.cfg`: project layout and SSH
#'   connection details are recorded separately, and `htc.cfg` on disk is
#'   unaffected by whether you pass `project_config`.
#' @param check_server Logical. If `TRUE`, opens a short SSH connection to
#'   `server` to report whether it is reachable before you rely on the
#'   config. Defaults to the `submitr.check_server` option, which is itself
#'   `TRUE` unless you set it otherwise. Set to `FALSE` in scripts, test
#'   suites, and anywhere else the probe has no audience -- reading a config
#'   file then costs nothing and touches no network.
#'
#' @return A named list with elements `username` and `server`, plus a
#'   `project` element when `project_config` is supplied, returned
#'   invisibly.
#'
#' @section Options:
#' Two options adjust how much `htc_config()` does on your behalf. Both
#' default to `TRUE`, and both are most useful set once for a whole session
#' or test suite rather than per call.
#'
#' `submitr.verbose` controls the progress messages ("Reading HTC config
#' from ...", "Checking connectivity to ..."). Setting it to `FALSE` leaves
#' warnings and errors intact.
#'
#' `submitr.check_server` controls the reachability probe described under
#' `check_server` above. The argument takes precedence when supplied, so the
#' option sets the default and a call can still override it.
#'
#' @section SSH connection reuse:
#' Each call to `htc_upload()`, `htc_submit()`, `htc_status()`, or
#' `htc_download()` opens a new SSH connection to the submit server,
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
#' @section Project configuration:
#' `project_config` is how `submitr` learns the layout a `toolero` project
#' already settled on, instead of retyping it. `toolero::init_project()`
#' writes `_toolero.yml` to a project's root once it has resolved the
#' folder set, and that file records two things: `folders`, the full list
#' of folders the project uses, and `conventions`, the names the family
#' resolves rather than assumes (`output_dir`, `script_dir`, `split_dir`).
#'
#' Passing `project_config = "_toolero.yml"` reads that file once and
#' returns it under `config$project`:
#'
#' ```r
#' cfg <- htc_config(project_config = "_toolero.yml")
#' cfg$project$conventions$output_dir
#' #> [1] "output"
#' ```
#'
#' As of this release (S-G5), passing the returned config's `project`
#' element on to [htc_gen_executable()] and [htc_gen_submit()] via their own
#' `config` argument lets `results_folder` and `queue_from` default from
#' `conventions$output_dir` and `conventions$split_dir`, the way
#' `containr::generate_dockerfile()` already reads the same file for its own
#' purposes:
#'
#' ```r
#' cfg <- htc_config(project_config = "_toolero.yml")
#' htc_gen_executable(r_script = "R/analysis.R", config = cfg)
#' htc_gen_submit(mode = "multiple", config = cfg)
#' ```
#'
#' `r_script` itself is not defaulted from `conventions$script_dir`: the
#' convention names a directory, not a file, and the script's own filename
#' is project-specific information `_toolero.yml` has no way to record.
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
#' # Read the config without probing the server, e.g. in a script or on CI
#' cfg <- htc_config(check_server = FALSE)
#'
#' # Or turn the probe off for a whole session
#' options(submitr.check_server = FALSE)
#'
#' # Fold in a toolero project's own folder layout and conventions
#' cfg <- htc_config(project_config = "_toolero.yml")
#' cfg$project$conventions$output_dir
#'
#' # Use in other functions
#' htc_upload(files = c("job.sub", "job.sh"), config = cfg)
#' }

htc_config <- function(username       = NULL,
                       server         = NULL,
                       path           = ".",
                       overwrite      = FALSE,
                       project_config = NULL,
                       check_server   = getOption("submitr.check_server",
                                                  default = TRUE)) {

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

        if (getOption("submitr.verbose", default = TRUE)) {
            cli::cli_inform(
                "Reading HTC config from {.file {cfg_path}}"
            )
        }

        cfg <- list(username = cfg$username, server = cfg$server)

        if (!is.null(project_config)) {
            cfg$project <- .read_project_config(project_config)
        }

        if (check_server) {
            .htc_check_server(cfg)
        }
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
        "i" = "Without it, each call to {.fn htc_upload}, {.fn htc_submit},",
        " " = "  {.fn htc_status}, or {.fn htc_download} will trigger a",
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

    # -- 5b. Fold in project config, if supplied --------------------------------
    # Read after htc.cfg is already written to disk, so a project's folder
    # layout never ends up inside the connection-details file. It lives only
    # in the list this call returns.
    if (!is.null(project_config)) {
        cfg$project <- .read_project_config(project_config)
    }

    # -- 6. Validate server reachability ---------------------------------------
    if (check_server) {
        .htc_check_server(cfg)
    }

    invisible(cfg)
}


# -- Internal: check server reachability --------------------------------------

#' @keywords internal
.htc_check_server <- function(cfg) {
    if (is.null(cfg$username) || is.null(cfg$server)) return(invisible(NULL))

    if (getOption("submitr.verbose", default = TRUE)) {
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
            " " = "  to authenticate before calling {.fn htc_upload} or",
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
