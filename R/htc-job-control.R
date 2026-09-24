#' Cancel HTCondor jobs
#'
#' `htc_cancel()` connects to an HTC submit node via SSH and runs
#' `condor_rm` to remove jobs from the queue -- a mistaken submission (the
#' wrong resource request, the wrong image, 500 jobs instead of 5) can be
#' stopped from R rather than requiring a manual SSH session (S-G2).
#'
#' @param cluster_id An integer, character string, or `NULL`. The cluster ID
#'   to remove, e.g. `6302860`. When `NULL` (the default), resolves to the
#'   cluster ID recorded in the job manifest by the most recent
#'   [htc_submit()] call. Unlike [htc_status()], `htc_cancel()` never falls
#'   back to "all of my jobs": a bare `condor_rm` with no arguments removes
#'   every job you have queued on the submit node, not just the ones from
#'   this project, so the function errors instead of guessing when no
#'   cluster ID is available anywhere.
#' @param reason A character string or `NULL`. An optional free-text reason
#'   recorded in the job's HTCondor log (via `condor_rm`'s own `-reason`
#'   flag), useful when revisiting a log later to remember why a cluster was
#'   removed. Defaults to `NULL`.
#' @param config A named list as returned by [htc_config()]. Must contain
#'   `username` and `server`. If `NULL` (the default), uses the session
#'   config set by [htc_start()]. If no session config is set, the function
#'   errors with instructions.
#' @param dry_run Logical. If `TRUE`, prints the SSH command that would be
#'   executed without running it. Defaults to `FALSE`.
#' @param verbose Logical. If `TRUE`, prints progress messages. Defaults to
#'   `FALSE`.
#' @param path A character string. Directory holding the job manifest
#'   (`htc-manifest.yaml`), consulted only when `cluster_id` is `NULL`.
#'   Defaults to `"."`, matching the default used elsewhere in the family.
#'
#' @return The `condor_rm` output as a character vector, returned invisibly.
#'
#' @section Workflow:
#' ```r
#' cfg <- htc_config()
#' job <- htc_submit(config = cfg)
#'
#' # Realized the resource request was wrong -- stop it before it runs
#' htc_cancel(cluster_id = job, config = cfg, reason = "wrong request_memory")
#' ```
#'
#' @seealso [htc_release()] to un-pause a held job instead of removing it,
#'   and [htc_status()] to see which jobs are running, idle, or held.
#'
#' @export
#'
#' @examples
#' \donttest{
#' # Preview the SSH command without connecting to CHTC
#' cfg <- list(username = "netid", server = "ap2002.chtc.wisc.edu")
#' htc_cancel(cluster_id = 6302860, config = cfg, dry_run = TRUE)
#' }
#'
#' \dontrun{
#' cfg <- htc_config()
#' htc_cancel(cluster_id = 6302860, config = cfg)
#' htc_cancel(cluster_id = 6302860, config = cfg, reason = "submitted by mistake")
#' }
htc_cancel <- function(cluster_id = NULL,
                       reason     = NULL,
                       config     = NULL,
                       dry_run    = FALSE,
                       verbose    = FALSE,
                       path       = ".") {

    # -- 1. Resolve config (explicit argument or session option) ----------------
    config <- .resolve_config(config)

    # -- 2. Resolve cluster_id from the job manifest if not supplied ------------
    # No "remove everything" fallback here, deliberately -- see @param docs.
    if (is.null(cluster_id)) {
        cluster_id <- .get_manifest(path = path)$cluster_id
    }

    if (is.null(cluster_id)) {
        cli::cli_abort(c(
            "{.arg cluster_id} must be supplied, directly or via the job manifest.",
            "i" = "Pass the cluster ID returned by {.fn htc_submit}.",
            "i" = "{.fn htc_cancel} will not run a bare {.code condor_rm} with no",
            " " = "  cluster ID -- that removes every job you have queued on the",
            " " = "  submit node, not just this project's."
        ))
    }

    # -- 3. Validate cluster_id --------------------------------------------------
    cluster_id <- as.character(cluster_id)
    if (!grepl("^[0-9]+$", cluster_id)) {
        cli::cli_abort(c(
            "{.arg cluster_id} must be a positive integer.",
            "i" = "Got {.val {cluster_id}}.",
            "i" = "The cluster ID is returned by {.fn htc_submit} after a",
            " " = "  successful submission."
        ))
    }

    if (!is.null(reason) && (!is.character(reason) || length(reason) != 1L)) {
        cli::cli_abort(
            "{.arg reason} must be a single character string or {.code NULL}."
        )
    }

    # -- 4. Build SSH command ----------------------------------------------------
    remote_cmd <- .sh_word(paste0(
        "condor_rm ", cluster_id,
        if (!is.null(reason)) paste0(" -reason ", .shell_quote(reason)) else ""
    ))

    ssh_args <- c(
        "-q",
        paste0(config$username, "@", config$server),
        remote_cmd
    )

    # -- 5. dry_run or execute ---------------------------------------------------
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
            "Removing cluster {.val {cluster_id}} on {.val {config$server}}..."
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
            "condor_rm failed with exit code {exit_code}.",
            "i" = "Check your connection to {.val {config$server}}.",
            "x" = .cli_escape(paste(result, collapse = " "))
        ))
    }

    if (length(result) > 0) cat(result, sep = "\n")

    cli::cli_alert_success(
        "Removed cluster {.val {cluster_id}} from the queue on {.val {config$server}}."
    )

    invisible(result)
}


#' Release held HTCondor jobs
#'
#' `htc_release()` connects to an HTC submit node via SSH and runs
#' `condor_release` to un-pause jobs that HTCondor has held (S-G2) --
#' typically after fixing whatever caused the hold, such as raising a
#' resource request reported by [htc_status()]'s hold-reason output.
#'
#' @param cluster_id An integer, character string, or `NULL`. The cluster ID
#'   to release, e.g. `6302860`. When `NULL` (the default), resolves to the
#'   cluster ID recorded in the job manifest by the most recent
#'   [htc_submit()] call. Unlike [htc_status()], `htc_release()` never falls
#'   back to "all of my jobs": a bare `condor_release` with no arguments
#'   releases every held job you have on the submit node, not just the ones
#'   from this project, so the function errors instead of guessing when no
#'   cluster ID is available anywhere.
#' @param config A named list as returned by [htc_config()]. Must contain
#'   `username` and `server`. If `NULL` (the default), uses the session
#'   config set by [htc_start()]. If no session config is set, the function
#'   errors with instructions.
#' @param dry_run Logical. If `TRUE`, prints the SSH command that would be
#'   executed without running it. Defaults to `FALSE`.
#' @param verbose Logical. If `TRUE`, prints progress messages. Defaults to
#'   `FALSE`.
#' @param path A character string. Directory holding the job manifest
#'   (`htc-manifest.yaml`), consulted only when `cluster_id` is `NULL`.
#'   Defaults to `"."`, matching the default used elsewhere in the family.
#'
#' @return The `condor_release` output as a character vector, returned
#'   invisibly.
#'
#' @section Workflow:
#' ```r
#' cfg <- htc_config()
#' htc_status(cluster_id = 6302860, config = cfg)
#' # ... shows job 6302860.0 held; hold reason printed below the table ...
#' # ... fix the resource request that caused the hold, then:
#' htc_release(cluster_id = 6302860, config = cfg)
#' ```
#'
#' @seealso [htc_cancel()] to remove a job instead of releasing it, and
#'   [htc_status()] to see hold reasons.
#'
#' @export
#'
#' @examples
#' \donttest{
#' # Preview the SSH command without connecting to CHTC
#' cfg <- list(username = "netid", server = "ap2002.chtc.wisc.edu")
#' htc_release(cluster_id = 6302860, config = cfg, dry_run = TRUE)
#' }
#'
#' \dontrun{
#' cfg <- htc_config()
#' htc_release(cluster_id = 6302860, config = cfg)
#' }
htc_release <- function(cluster_id = NULL,
                        config     = NULL,
                        dry_run    = FALSE,
                        verbose    = FALSE,
                        path       = ".") {

    # -- 1. Resolve config (explicit argument or session option) ----------------
    config <- .resolve_config(config)

    # -- 2. Resolve cluster_id from the job manifest if not supplied ------------
    # No "release everything" fallback here, deliberately -- see @param docs.
    if (is.null(cluster_id)) {
        cluster_id <- .get_manifest(path = path)$cluster_id
    }

    if (is.null(cluster_id)) {
        cli::cli_abort(c(
            "{.arg cluster_id} must be supplied, directly or via the job manifest.",
            "i" = "Pass the cluster ID returned by {.fn htc_submit}.",
            "i" = "{.fn htc_release} will not run a bare {.code condor_release} with",
            " " = "  no cluster ID -- that releases every held job you have on the",
            " " = "  submit node, not just this project's."
        ))
    }

    # -- 3. Validate cluster_id --------------------------------------------------
    cluster_id <- as.character(cluster_id)
    if (!grepl("^[0-9]+$", cluster_id)) {
        cli::cli_abort(c(
            "{.arg cluster_id} must be a positive integer.",
            "i" = "Got {.val {cluster_id}}.",
            "i" = "The cluster ID is returned by {.fn htc_submit} after a",
            " " = "  successful submission."
        ))
    }

    # -- 4. Build SSH command ----------------------------------------------------
    remote_cmd <- .sh_word(paste0("condor_release ", cluster_id))

    ssh_args <- c(
        "-q",
        paste0(config$username, "@", config$server),
        remote_cmd
    )

    # -- 5. dry_run or execute ---------------------------------------------------
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
            "Releasing cluster {.val {cluster_id}} on {.val {config$server}}..."
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
            "condor_release failed with exit code {exit_code}.",
            "i" = "Check your connection to {.val {config$server}}.",
            "x" = .cli_escape(paste(result, collapse = " "))
        ))
    }

    if (length(result) > 0) cat(result, sep = "\n")

    cli::cli_alert_success(
        "Released cluster {.val {cluster_id}} on {.val {config$server}}."
    )

    invisible(result)
}
