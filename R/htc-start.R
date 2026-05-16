#' Start an HTC session
#'
#' `htc_start()` calls [htc_config()] to read or create the connection
#' configuration, then stores the result as a session-level option so
#' that subsequent `htc_*()` functions can use it without requiring an
#' explicit `config` argument on every call.
#'
#' After calling `htc_start()`, functions like [htc_upload()],
#' [htc_submit()], [htc_status()], and [htc_download()] will
#' automatically use the stored configuration when `config = NULL`
#' (the default). You can still pass `config` explicitly to any
#' function to override the session config.
#'
#' The session config is stored via `options(submitr.config = ...)` and
#' is cleared automatically when the R session ends. To clear it
#' manually, call `options(submitr.config = NULL)`.
#'
#' @param ... Arguments passed to [htc_config()]. Common arguments
#'   include `username`, `server`, `path`, and `overwrite`.
#'
#' @return Invisibly returns the config list (same as [htc_config()]).
#'
#' @export
#'
#' @examples
#' \dontrun{
#' # Start a session -- all subsequent htc_*() calls use this config
#' htc_start()
#'
#' # Now these work without config = cfg
#' htc_upload(files = c("job.sub", "job.sh"))
#' htc_submit(submit_file = "job.sub")
#' htc_status(cluster_id = 6351616)
#' htc_download(files = "*.tar.gz")
#'
#' # You can still override for a specific call
#' other_cfg <- htc_config(path = "other-project/")
#' htc_upload(files = "job.sub", config = other_cfg)
#'
#' # Clear the session config manually
#' options(submitr.config = NULL)
#' }
htc_start <- function(...) {

    cfg <- htc_config(...)
    options(submitr.config = cfg)

    cli::cli_alert_success(
        "Session started: {.val {cfg$username}}@{.val {cfg$server}}"
    )

    invisible(cfg)
}
