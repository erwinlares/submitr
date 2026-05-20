#' Resolve HTC config from argument or session option
#'
#' Internal helper used by `htc_upload()`, `htc_download()`, `htc_submit()`,
#' and `htc_status()` to resolve the config list. Checks the explicit
#' argument first, then falls back to the session option set by
#' `htc_start()`, then errors if neither is available.
#'
#' @param config A named list or `NULL`.
#'
#' @return A validated config list with `username` and `server`.
#'
#' @keywords internal
.resolve_config <- function(config) {

    # 1. Use explicit argument if provided
    if (is.null(config)) {
        # 2. Fall back to session option
        config <- getOption("submitr.config")
    }

    # 3. Error if still NULL
    if (is.null(config)) {
        cli::cli_abort(c(
            "No HTC config found.",
            "i" = "Call {.fn htc_start} to set up your connection,",
            " " = "  or pass a config list from {.fn htc_config} directly."
        ))
    }

    # 4. Validate required fields
    if (is.null(config$username) || is.null(config$server)) {
        cli::cli_abort(c(
            "Config is missing {.val username} or {.val server}.",
            "i" = "Call {.fn htc_start} or {.fn htc_config} to",
            " " = "  generate a valid config."
        ))
    }

    config
}


#' Update the job manifest with new information
#'
#' Internal helper that accumulates job metadata across the submitr
#' pipeline. Each function in the workflow calls `.update_manifest()`
#' with the information it knows. `htc_download()` reads the accumulated
#' manifest to construct the list of files to retrieve.
#'
#' @param ... Named key-value pairs to add or update in the manifest.
#'
#' @return Called for its side effects. Returns `invisible(NULL)`.
#'
#' @keywords internal
.update_manifest <- function(...) {
    current <- getOption("submitr.job_manifest", default = list())
    updates <- list(...)
    for (key in names(updates)) {
        current[[key]] <- updates[[key]]
    }
    options(submitr.job_manifest = current)
    invisible(NULL)
}


#' Retrieve the current job manifest
#'
#' Internal helper that reads the accumulated job manifest from session
#' options. Returns `NULL` if no manifest has been set.
#'
#' @return A named list or `NULL`.
#'
#' @keywords internal
.get_manifest <- function() {
    getOption("submitr.job_manifest", default = NULL)
}
