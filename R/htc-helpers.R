#' Resolve HTC config from argument or session option
#'
#' Internal helper used by `htc_upload()`, `htc_download()`, `htc_submit()`,
#' and `htc_status()` to resolve the config list. Checks the explicit
#' argument first, then falls back to the session option set by
#' `htc_start_session()`, then errors if neither is available.
#'
#' @param config A named list or `NULL`.
#'
#' @return A validated config list with `username` and `server`.
#'
#' @keywords internal
#'
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
            "i" = "Call {.fn htc_start_session} to set up your connection,",
            " " = "  or pass a config list from {.fn htc_config} directly."
        ))
    }

    # 4. Validate required fields
    if (is.null(config$username) || is.null(config$server)) {
        cli::cli_abort(c(
            "Config is missing {.val username} or {.val server}.",
            "i" = "Call {.fn htc_start_session} or {.fn htc_config} to",
            " " = "  generate a valid config."
        ))
    }

    config
}
