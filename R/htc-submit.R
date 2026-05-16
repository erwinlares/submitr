#' Submit an HTCondor job from a remote submit node
#'
#' `htc_submit()` connects to an HTC submit node via SSH and runs
#' `condor_submit` on a submit file that has already been uploaded with
#' [htc_upload()]. It changes into the remote directory before submitting
#' so that relative paths in the submit file resolve correctly.
#'
#' @param submit_file A character string. Name of the submit file on the
#'   remote node, e.g. `"job.sub"`. Must end in `".sub"`. Defaults to
#'   `"job.sub"`.
#' @param remote_path A character string. The directory on the submit node
#'   where the submit file was uploaded. Defaults to `"~/"`. Must match the
#'   `remote_path` used in the preceding call to [htc_upload()].
#' @param config A named list as returned by [htc_config()]. Must contain
#'   `username` and `server`. If `NULL` (the default), uses the session
#'   config set by [htc_start()]. If no session config is set,
#'   the function errors with instructions.
#' @param dry_run Logical. If `TRUE`, prints the SSH command that would be
#'   executed without running it. Useful for verifying the command before
#'   submitting. Defaults to `FALSE`.
#' @param verbose Logical. If `TRUE`, prints progress messages and the
#'   `condor_submit` output. Defaults to `FALSE`.
#'
#' @return The cluster ID assigned by HTCondor as a character string,
#'   returned invisibly. Pass it directly to [htc_status()] to monitor
#'   job progress. Returns `invisible(NULL)` if the cluster ID cannot be
#'   parsed from the `condor_submit` output.
#'
#' @section Workflow:
#' `htc_submit()` is the second system-facing step in the submitr workflow.
#' Call it after uploading your files with [htc_upload()]. The returned
#' cluster ID can be passed directly to [htc_status()].
#'
#' ```r
#' cfg <- htc_config()
#'
#' htc_upload(
#'   files  = c("job.sub", "job.sh", "analysis.R"),
#'   config = cfg
#' )
#'
#' cluster_id <- htc_submit(submit_file = "job.sub", config = cfg)
#' htc_status(cluster_id = cluster_id, config = cfg, watch = TRUE)
#' ```
#'
#' @section Why `remote_path` must match `htc_upload()`:
#' `htc_submit()` runs `cd remote_path && condor_submit submit_file` on the
#' submit node. HTCondor resolves all paths in the submit file relative to
#' the directory where `condor_submit` is called. If `remote_path` does not
#' match the directory where files were uploaded, HTCondor will not find the
#' executable, input files, or output destinations and the job will fail.
#'
#' @section SSH connection reuse:
#' Each call to `htc_submit()` opens a new SSH connection. If you have not
#' configured ControlMaster in your `~/.ssh/config`, this will trigger a
#' Duo MFA prompt. Run [htc_config()] for setup guidance.
#'
#' @export
#'
#' @examples
#' \donttest{
#' # Preview the SSH command without connecting to CHTC
#' cfg <- list(username = "netid", server = "ap2002.chtc.wisc.edu")
#' htc_submit(submit_file = "job.sub", config = cfg, dry_run = TRUE)
#' }
#'
#' \dontrun{
#' # All remaining examples require a live CHTC connection
#' cfg <- htc_config()
#'
#' # Submit using default remote path
#' htc_submit(submit_file = "job.sub", config = cfg)
#'
#' # Submit from a specific remote directory
#' htc_submit(
#'   submit_file = "analysis.sub",
#'   remote_path = "~/projects/penguins/",
#'   config      = cfg
#' )
#'
#' # Submit with verbose output to see condor_submit response
#' htc_submit(
#'   submit_file = "job.sub",
#'   config      = cfg,
#'   verbose     = TRUE
#' )
#' }
htc_submit <- function(submit_file = "job.sub",
                       remote_path = "~/",
                       config      = NULL,
                       dry_run     = FALSE,
                       verbose     = FALSE) {

    # -- 1. Resolve config (explicit argument or session option) ----------------
    config <- .resolve_config(config)

    # -- 2. Validate submit_file -----------------------------------------------
    if (!grepl("\\.sub$", submit_file)) {
        cli::cli_abort(c(
            "{.arg submit_file} must end in {.val .sub}.",
            "i" = "Got {.val {submit_file}}."
        ))
    }

    # -- 3. Validate remote_path -----------------------------------------------
    if (!grepl("/$", remote_path)) {
        remote_path <- paste0(remote_path, "/")
    }

    # -- 4. Build SSH command --------------------------------------------------
    # cd into remote_path first so condor_submit resolves relative paths
    # in the submit file correctly.
    # The remote command is single-quoted to prevent the local shell from
    # expanding ~ before the command reaches the remote server.
    remote_cmd <- paste0("'cd ", remote_path, " && condor_submit ", submit_file, "'")

    ssh_args <- c(
        "-q",
        paste0(config$username, "@", config$server),
        remote_cmd
    )

    # -- 5. dry_run or execute -------------------------------------------------
    if (dry_run) {
        cmd <- paste("ssh", paste(ssh_args, collapse = " "))
        cli::cli_inform(c(
            "v" = "Dry run -- command that would be executed:",
            " " = "  {.code {cmd}}"
        ))
        return(invisible(NULL))
    }

    if (verbose) {
        cli::cli_inform(
            "Submitting {.val {submit_file}} on {.val {config$server}}..."
        )
    }

    result <- system2(
        "ssh",
        args   = ssh_args,
        stdout = TRUE,
        stderr = TRUE
    )

    exit_code <- attr(result, "status")
    exit_code <- if (is.null(exit_code)) 0L else exit_code

    if (exit_code != 0L) {
        cli::cli_abort(c(
            "condor_submit failed with exit code {exit_code}.",
            "i" = "Check that all files were uploaded with {.fn htc_upload}",
            " " = "  and that {.val {submit_file}} exists in {.val {remote_path}}.",
            "x" = "{result}"
        ))
    }

    if (verbose && length(result) > 0) {
        cli::cli_inform(result)
    }

    # -- 6. Parse and return cluster ID ----------------------------------------
    cluster_line <- result[grepl("submitted to cluster", result, fixed = TRUE)]
    cluster_id <- if (length(cluster_line) > 0) {
        sub(".*cluster ([0-9]+).*", "\\1", cluster_line)
    } else {
        NULL
    }

    cli::cli_alert_success(
        "Job submitted from {.val {remote_path}{submit_file}} on {.val {config$server}}."
    )

    invisible(cluster_id)
}
