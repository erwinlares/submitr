#' Download files from an HTC submit node
#'
#' `htc_download()` copies one or more files from a directory on an HTC
#' submit node to a local directory via `scp`. It is the final step in the
#' job submission workflow -- called after [htc_status()] confirms all jobs
#' have completed.
#'
#' Glob patterns such as `"*.tar.gz"` are supported and are evaluated on the
#' remote server, not locally, so they match files that exist on the submit
#' node regardless of what is present on your local machine.
#'
#' @param files A character vector. One or more filenames or glob patterns
#'   to download from `remote_path` on the submit node. Examples:
#'   `"results.tar.gz"`, `c("job.log", "job.err")`, `"*.tar.gz"`. Required.
#' @param remote_path A character string. The directory on the submit node
#'   where the files are located. Defaults to `"~/"`. Should match the
#'   `remote_path` used in [htc_upload()] and [htc_submit()].
#' @param local_path A character string. The local directory where downloaded
#'   files will be saved. Defaults to `"."` (current working directory).
#' @param config A named list as returned by [htc_config()]. Must contain
#'   `username` and `server`. If `NULL`, the function errors with instructions
#'   to call [htc_config()] first.
#' @param dry_run Logical. If `TRUE`, prints the `scp` command that would be
#'   executed without running it. Defaults to `FALSE`.
#' @param verbose Logical. If `TRUE`, prints progress messages. Defaults to
#'   `FALSE`.
#'
#' @return Called for its side effects. Returns `invisible(NULL)`.
#'
#' @section Workflow:
#' `htc_download()` is the final system-facing step in the submitr workflow.
#' Call it after [htc_status()] confirms all jobs have completed.
#'
#' ```r
#' cfg <- htc_config()
#'
#' htc_status(cluster_id = 6302877, config = cfg, watch = TRUE)
#'
#' # Download all result tarballs
#' htc_download(
#'   files      = "*.tar.gz",
#'   config     = cfg,
#'   local_path = "results/"
#' )
#' ```
#'
#' @section Glob patterns:
#' Glob patterns are passed to the remote shell for evaluation so they
#' match files on the submit node, not on your local machine. The pattern
#' is single-quoted in the `scp` command to prevent local shell expansion.
#'
#' Common patterns:
#' - `"*.tar.gz"` -- all result tarballs
#' - `"*.log"` -- all log files
#' - `"*.out"` -- all output files
#' - `"*.err"` -- all error files
#'
#' @section SSH connection reuse:
#' Each call to `htc_download()` opens a new SSH connection. If you have
#' not configured ControlMaster in your `~/.ssh/config`, this will trigger
#' a Duo MFA prompt. Run [htc_config()] for setup guidance.
#'
#' @export
#'
#' @examples
#' \donttest{
#' # Preview the scp command without connecting to CHTC
#' cfg <- list(username = "netid", server = "ap2002.chtc.wisc.edu")
#' htc_download(files = "*.tar.gz", config = cfg, dry_run = TRUE)
#' }
#'
#' \dontrun{
#' # All remaining examples require a live CHTC connection
#' cfg <- htc_config()
#'
#' # Download a single file
#' htc_download(files = "r <- esults.tar.gz", config = cfg)
#'
#' # Download multiple specific files
#' htc_download(
#'   files  = c("job.log", "job.err", "results.tar.gz"),
#'   config = cfg
#' )
#'
#' # Download all result tarballs using a glob pattern
#' htc_download(
#'   files      = "*.tar.gz",
#'   config     = cfg,
#'   local_path = "results/"
#' )
#'
#' # Download all log files from a specific remote directory
#' htc_download(
#'   files       = "*.log",
#'   remote_path = "~/projects/penguins/",
#'   local_path  = "logs/",
#'   config      = cfg
#' )
#' }
htc_download <- function(files,
                         remote_path = "~/",
                         local_path  = ".",
                         config      = NULL,
                         dry_run     = FALSE,
                         verbose     = FALSE) {

    # -- 1. Validate config ----------------------------------------------------
    if (is.null(config)) {
        cli::cli_abort(c(
            "{.arg config} must be supplied.",
            "i" = "Call {.fn htc_config} first to create or read your HTC",
            " " = "  connection config, then pass the result to {.arg config}."
        ))
    }

    if (is.null(config$username) || is.null(config$server)) {
        cli::cli_abort(c(
            "{.arg config} is missing {.val username} or {.val server}.",
            "i" = "Call {.fn htc_config} to generate a valid config list."
        ))
    }

    # -- 2. Validate files -----------------------------------------------------
    if (missing(files) || length(files) == 0) {
        cli::cli_abort(
            "{.arg files} must be supplied and cannot be empty."
        )
    }

    # -- 3. Validate local_path ------------------------------------------------
    if (!dir.exists(local_path)) {
        cli::cli_abort(c(
            "Local directory {.path {local_path}} does not exist.",
            "i" = "Create it first with {.code dir.create({deparse(local_path)})}."
        ))
    }

    # -- 4. Validate remote_path -----------------------------------------------
    if (!grepl("/$", remote_path)) {
        remote_path <- paste0(remote_path, "/")
    }

    # -- 5. Build scp arguments ------------------------------------------------
    # Each file or glob pattern is prefixed with the remote host and path.
    # Glob patterns are single-quoted to prevent local shell expansion --
    # the remote shell evaluates them against files on the submit node.
    remote_sources <- vapply(files, function(f) {
        # If the file contains a glob character, single-quote the full
        # remote path so the local shell passes it verbatim to scp,
        # which then lets the remote shell expand the glob.
        has_glob <- grepl("[*?\\[]", f)
        remote   <- paste0(config$username, "@", config$server, ":", remote_path, f)
        if (has_glob) paste0("'", remote, "'") else remote
    }, character(1L), USE.NAMES = FALSE)

    scp_args <- c(remote_sources, local_path)

    # -- 6. dry_run or execute -------------------------------------------------
    if (dry_run) {
        cmd <- paste("scp", paste(scp_args, collapse = " "))
        cli::cli_inform(c(
            "v" = "Dry run -- command that would be executed:",
            " " = "  {.code {cmd}}"
        ))
        return(invisible(NULL))
    }

    if (verbose) {
        cli::cli_inform(
            "Downloading {.val {files}} from {.val {config$server}}:{remote_path} to {.path {local_path}}..."
        )
    }

    exit_code <- system2("scp", args = scp_args, stdout = FALSE, stderr = FALSE)

    if (exit_code != 0L) {
        cli::cli_abort(c(
            "scp failed with exit code {exit_code}.",
            "i" = "Check that the files exist on the submit node and that",
            " " = "  your connection to {.val {config$server}} is active.",
            "i" = "Run {.fn htc_status} to verify job completion before",
            " " = "  downloading results."
        ))
    }

    cli::cli_alert_success(
            "Downloaded files from {.val {config$server}}:{remote_path} to {.path {local_path}}"
    )

    invisible(NULL)
}
