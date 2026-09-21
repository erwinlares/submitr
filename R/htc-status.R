#' Check the status of submitted HTCondor jobs
#'
#' `htc_status()` connects to an HTC submit node via SSH and runs
#' `condor_q` to report the status of jobs in the queue. By default it
#' shows all of your jobs. Optionally filter by cluster ID to monitor a
#' specific submission.
#'
#' When `watch = TRUE`, `htc_status()` polls the queue repeatedly at a
#' fixed interval until all jobs in the cluster have completed, printing
#' a timestamped snapshot after each poll.
#'
#' @param cluster_id An integer or character string. The cluster ID returned
#'   by [htc_submit()], e.g. `6302860`. If `NULL` (the default), shows all
#'   of your jobs currently in the queue. Required when `watch = TRUE`.
#' @param config A named list as returned by [htc_config()]. Must contain
#'   `username` and `server`. If `NULL` (the default), uses the session
#'   config set by [htc_start()]. If no session config is set,
#'   the function errors with instructions.
#' @param watch Logical. If `TRUE`, polls the queue repeatedly at `interval`
#'   seconds until all jobs in `cluster_id` have completed. Requires
#'   `cluster_id` to be supplied. Defaults to `FALSE`.
#' @param interval A positive integer. Number of seconds to wait between
#'   polls when `watch = TRUE`. Defaults to `60`.
#' @param dry_run Logical. If `TRUE`, prints the SSH command that would be
#'   executed without running it. Defaults to `FALSE`.
#' @param verbose Logical. If `TRUE`, prints progress messages. Defaults to
#'   `FALSE`.
#'
#' @return Called for its side effects. Prints the `condor_q` output to the
#'   console. Returns the most recent output invisibly as a character vector.
#'
#' @section Job status codes:
#' HTCondor reports each job's status with a single letter:
#'
#' | Code | Meaning |
#' |------|---------|
#' | I | Idle -- waiting for a matching execute node |
#' | R | Running -- currently executing |
#' | H | Held -- paused, usually due to an error |
#' | C | Completed -- finished successfully |
#' | X | Removed -- cancelled |
#' | S | Suspended |
#'
#' Jobs disappear from `condor_q` once they complete and their output has
#' been transferred back to the submit node. Use [htc_download()] to retrieve
#' completed job output.
#'
#' @section Workflow:
#' ```r
#' cfg <- htc_config()
#'
#' # One-shot status check
#' htc_status(config = cfg)
#'
#' # Monitor a specific cluster until completion
#' htc_status(cluster_id = 6302860, config = cfg, watch = TRUE)
#' ```
#'
#' @section SSH connection reuse:
#' Each poll in watch mode opens a new SSH connection. Configuring
#' ControlMaster in your `~/.ssh/config` (see [htc_config()]) is strongly
#' recommended when using `watch = TRUE` to avoid repeated Duo MFA prompts.
#'
#' @export
#'
#' @examples
#' \donttest{
#' # Preview the SSH command without connecting to CHTC
#' cfg <- list(username = "netid", server = "ap2002.chtc.wisc.edu")
#' htc_status(config = cfg, dry_run = TRUE)
#'
#' # Preview with a specific cluster ID
#' htc_status(cluster_id = 6302860, config = cfg, dry_run = TRUE)
#' }
#'
#' \dontrun{
#' # All remaining examples require a live CHTC connection
#' cfg <- htc_config()
#'
#' # Check all your jobs
#' htc_status(config = cfg)
#'
#' # Check a specific cluster
#' htc_status(cluster_id = 6302860, config = cfg)
#'
#' # Watch a cluster until all jobs complete (polls every 60 seconds)
#' htc_status(cluster_id = 6302860, config = cfg, watch = TRUE)
#'
#' # Watch with a shorter polling interval
#' htc_status(cluster_id = 6302860, config = cfg, watch = TRUE, interval = 30)
#' }
htc_status <- function(cluster_id = NULL,
                       config     = NULL,
                       watch      = FALSE,
                       interval   = 60L,
                       dry_run    = FALSE,
                       verbose    = FALSE) {

    # -- 1. Resolve config (explicit argument or session option) ----------------
    config <- .resolve_config(config)

    # -- 2. Validate cluster_id ------------------------------------------------
    if (!is.null(cluster_id)) {
        cluster_id <- as.character(cluster_id)
        if (!grepl("^[0-9]+$", cluster_id)) {
            cli::cli_abort(c(
                "{.arg cluster_id} must be a positive integer.",
                "i" = "Got {.val {cluster_id}}.",
                "i" = "The cluster ID is returned by {.fn htc_submit} after a",
                " " = "  successful submission."
            ))
        }
    }

    # -- 3. Validate watch requirements ----------------------------------------
    if (watch && is.null(cluster_id)) {
        cli::cli_abort(c(
            "{.arg cluster_id} must be supplied when {.arg watch} is {.val TRUE}.",
            "i" = "Watching the queue without a cluster ID cannot reliably",
            " " = "  detect when your specific jobs have completed.",
            "i" = "Pass the cluster ID returned by {.fn htc_submit}."
        ))
    }

    if (watch && (!is.numeric(interval) || interval < 1)) {
        cli::cli_abort(
            "{.arg interval} must be a positive integer. Got {.val {interval}}."
        )
    }

    # -- 4. Build SSH command --------------------------------------------------
    # cluster_id is already validated as digits only, so nothing here can
    # need quoting; the command is wrapped anyway so that both remote-command
    # sites in the package are built the same way.
    remote_cmd <- if (!is.null(cluster_id)) {
        .sh_word(paste0("condor_q ", cluster_id))
    } else {
        .sh_word("condor_q")
    }

    ssh_args <- c(
        "-q",
        paste0(config$username, "@", config$server),
        remote_cmd
    )

    # -- 5. dry_run ------------------------------------------------------------
    if (dry_run) {
        cmd <- paste("ssh", paste(ssh_args, collapse = " "))
        cli::cli_inform(c(
            "v" = "Dry run -- command that would be executed:",
            " " = "  {.code {cmd}}"
        ))
        return(invisible(NULL))
    }

    # -- 6. Internal poll function ---------------------------------------------
    .poll <- function() {
        if (verbose) {
            if (!is.null(cluster_id)) {
                cli::cli_inform(
                    "Checking status of cluster {.val {cluster_id}} on {.val {config$server}}..."
                )
            } else {
                cli::cli_inform(
                    "Checking job queue on {.val {config$server}}..."
                )
            }
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
                "condor_q failed with exit code {exit_code}.",
                "i" = "Check your connection to {.val {config$server}}.",
                "x" = .cli_escape(paste(result, collapse = " "))
            ))
        }

        cat(result, sep = "\n")
        invisible(result)
    }

    # -- 7. Single poll or watch loop ------------------------------------------
    if (!watch) {
        return(.poll())
    }

    # watch = TRUE - poll repeatedly until cluster_id no longer appears
    cli::cli_inform(
        "Watching cluster {.val {cluster_id}} - polling every {interval}s. Press Ctrl+C to stop."
    )

    repeat {
        cat(format(Sys.time(), "\n[%Y-%m-%d %H:%M:%S]\n"))
        output <- .poll()

        if (.jobs_in_queue(output, cluster_id) == 0L) {
            cli::cli_alert_success(
                "All jobs in cluster {.val {cluster_id}} have left the queue."
            )
            return(invisible(output))
        }

        Sys.sleep(interval)
    }
}


#' Count the jobs a condor_q report still shows for a cluster
#'
#' Internal helper used by `htc_status(watch = TRUE)` to decide when to stop
#' polling.
#'
#' The obvious test, searching the report for the cluster ID as a substring,
#' is not safe. `condor_q` always prints a schedd header carrying an address,
#' a port and a timestamp, and closes with summary lines such as
#' `Total for all users: 3402 jobs; ...`. Digits from any of those can
#' coincide with the cluster ID, and because the test drives the loop's exit,
#' a false match does not produce a wrong answer -- it produces a watch loop
#' that never returns.
#'
#' The report's own `Total for query:` line is a direct answer instead. The
#' remote command is `condor_q <cluster_id>`, so the query is this cluster,
#' and the count is the number of its jobs still in the queue. If that line
#' is missing, the fallback matches the cluster ID anchored to the `.` that
#' separates it from the process number, which restricts it to the `JOB_IDS`
#' column (`6302860.0`) rather than the report at large.
#'
#' @param output A character vector. The lines returned by `condor_q`.
#' @param cluster_id A character string. The cluster being watched.
#'
#' @return An integer count of jobs still in the queue.
#'
#' @keywords internal
.jobs_in_queue <- function(output, cluster_id) {

    if (length(output) == 0L) {
        return(0L)
    }

    total_line <- grep("Total for query:", output, value = TRUE, fixed = TRUE)

    if (length(total_line) > 0L) {
        n <- sub(
            ".*Total for query:[[:space:]]*([0-9]+)[[:space:]]+job.*",
            "\\1",
            total_line[[1]]
        )
        if (grepl("^[0-9]+$", n)) {
            return(as.integer(n))
        }
    }

    sum(grepl(
        paste0("(^|[[:space:]])", cluster_id, "\\."),
        output
    ))
}
