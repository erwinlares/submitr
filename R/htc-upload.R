#' Upload files to an HTC submit node
#'
#' `htc_upload()` copies one or more local files or directories to a
#' directory on an HTC submit node via `scp`. It is the first step in the
#' job submission workflow -- files must be present on the submit node before
#' `htc_submit()` can run `condor_submit`.
#'
#' @param files A character vector. One or more local file paths or directory
#'   paths to copy to the submit node. A single file, a vector of files, and
#'   a directory path are all accepted. Directories are copied recursively.
#' @param remote_path A character string. The destination directory on the
#'   submit node. Defaults to `"~/"` (the user's home directory). This should
#'   match the path used in the subsequent call to [htc_submit()].
#' @param config A named list as returned by [htc_config()]. Must contain
#'   `username` and `server`. If `NULL` (the default), uses the session
#'   config set by [htc_start()]. If no session config is set,
#'   the function errors with instructions.
#' @param dry_run Logical. If `TRUE`, prints the `scp` command that would be
#'   executed without running it. Useful for verifying the command before
#'   transferring files. Defaults to `FALSE`.
#' @param verbose Logical. If `TRUE`, prints progress messages. Defaults to
#'   `FALSE`.
#'
#' @return Called for its side effects. Returns `invisible(NULL)`.
#'
#' @section Workflow:
#' `htc_upload()` is the first system-facing step in the submitr workflow.
#' Call it after generating your submit file and executable script with
#' [htc_gen_submit()] and [htc_gen_executable()], and before calling
#' [htc_submit()].
#'
#' The typical sequence is:
#'
#' ```r
#' cfg <- htc_config()
#'
#' htc_upload(
#'   files  = c("job.sub", "job.sh", "analysis.R", "data.csv"),
#'   config = cfg
#' )
#'
#' htc_submit(submit_file = "job.sub", config = cfg)
#' ```
#'
#' @section SSH connection reuse:
#' Each call to `htc_upload()` opens a new SSH connection. If you have not
#' configured ControlMaster in your `~/.ssh/config`, this will trigger a
#' Duo MFA prompt. Run [htc_config()] for setup guidance.
#'
#' @export
#'
#' @examples
#' \donttest{
#' # Preview the scp command without connecting to CHTC
#' cfg <- list(username = "netid", server = "ap2002.chtc.wisc.edu")
#' tmp <- tempfile(fileext = ".sub")
#' writeLines("queue 1", tmp)
#' htc_upload(files = tmp, config = cfg, dry_run = TRUE)
#' }
#'
#' \dontrun{
#' # All remaining examples require a live CHTC connection
#' cfg <- htc_config()
#'
#' # Upload a single file
#' htc_upload(files = "job.sub", config = cfg)
#'
#' # Upload multiple files
#' htc_upload(
#'   files  = c("job.sub", "job.sh", "analysis.R"),
#'   config = cfg
#' )
#'
#' # Upload a directory
#' htc_upload(files = "jobs/", config = cfg)
#'
#' # Upload to a specific remote directory
#' htc_upload(
#'   files       = c("job.sub", "job.sh"),
#'   remote_path = "~/projects/penguins/",
#'   config      = cfg
#' )
#' }
htc_upload <- function(files,
                       remote_path = "~/",
                       config      = NULL,
                       dry_run     = FALSE,
                       verbose     = FALSE) {

    # -- 1. Resolve config (explicit argument or session option) ----------------
    config <- .resolve_config(config)

    # -- 2. Validate files -----------------------------------------------------
    if (missing(files) || length(files) == 0) {
        cli::cli_abort(
            "{.arg files} must be supplied and cannot be empty."
        )
    }

    missing_files <- files[!file.exists(files)]
    if (length(missing_files) > 0) {
        cli::cli_abort(c(
            "{length(missing_files)} file{?s} do not exist:",
            "x" = "{.path {missing_files}}"
        ))
    }

    # -- 3. Validate remote_path -----------------------------------------------
    if (!grepl("/$", remote_path)) {
        remote_path <- paste0(remote_path, "/")
    }

    # -- 4. Build scp command --------------------------------------------------
    # Directories are copied recursively via -r flag
    has_dirs <- any(file.info(files)$isdir)
    scp_flags <- if (has_dirs) c("-r") else character(0)

    destination <- paste0(config$username, "@", config$server, ":", remote_path)

    scp_args <- c(scp_flags, files, destination)

    # -- 5. dry_run or execute -------------------------------------------------
    if (dry_run) {
        cmd <- paste("scp", paste(scp_args, collapse = " "))
        cli::cli_inform(c(
            "v" = "Dry run -- command that would be executed:",
            " " = "  {.code {cmd}}"
        ))
        return(invisible(NULL))
    }

    if (verbose) {
        n <- length(files)
        cli::cli_inform(
            "Uploading {n} file{?s} to {.val {config$server}}:{remote_path}..."
        )
    }

    exit_code <- system2("scp", args = scp_args, stdout = FALSE, stderr = FALSE)

    if (exit_code != 0L) {
        cli::cli_abort(c(
            "scp failed with exit code {exit_code}.",
            "i" = "Check your network connection and ensure ControlMaster",
            " " = "  is active. Run {.fn htc_config} for setup guidance."
        ))
    }

    cli::cli_alert_success(
        "Uploaded {length(files)} file{?s} to {.val {config$server}}:{remote_path}"
    )

    invisible(NULL)
}
