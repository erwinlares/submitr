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
#' with the information it knows. `htc_download()` and `htc_upload()`
#' read the accumulated manifest to resolve files automatically.
#'
#' The manifest is persisted to `htc-manifest.yaml` in `path`, not to
#' session options. Persisting it to disk means the manifest survives
#' across R sessions: restarting a session with [htc_start()] no longer
#' discards job metadata recorded by an earlier call to
#' [htc_gen_submit()], [htc_gen_executable()], or [htc_submit()].
#'
#' Passing `NULL` for a key removes it, which is what makes a single-mode
#' run clear the `subsets` and `subdatasets_path` left behind by an earlier
#' multiple-mode run in the same directory.
#'
#' @param ... Named key-value pairs to add or update in the manifest. Because
#'   `path` below sits after the dots, it is matched exactly by name and can
#'   never be stored as a manifest field. Nothing in the package needs a
#'   field called `path`, but any future one would have to be named
#'   differently.
#' @param path A character string. Directory where `htc-manifest.yaml`
#'   is read from and written to. Defaults to `"."` (current working
#'   directory). Functions that write to a caller-supplied `output`
#'   directory (e.g. [htc_gen_submit()], [htc_gen_executable()]) pass
#'   that directory through so the manifest travels with the generated
#'   files, and so package examples never write outside `tempdir()`.
#'
#' @return Called for its side effects. Returns `invisible(NULL)`.
#'
#' @keywords internal
.update_manifest <- function(..., path = ".") {

    if (!dir.exists(path)) {
        cli::cli_abort(c(
            "Cannot write the job manifest: {.path {path}} does not exist.",
            "i" = "{.arg path} must name an existing directory."
        ))
    }

    manifest_file <- file.path(path, "htc-manifest.yaml")

    current <- if (file.exists(manifest_file)) {
        yaml::read_yaml(manifest_file)
    } else {
        list()
    }
    if (!is.list(current)) {
        current <- list()
    }

    updates <- list(...)
    for (key in names(updates)) {
        current[[key]] <- updates[[key]]
    }

    yaml::write_yaml(current, manifest_file)
    invisible(NULL)
}


#' Retrieve the current job manifest
#'
#' Internal helper that reads the accumulated job manifest from
#' `htc-manifest.yaml` in `path`. Returns `NULL` if no manifest file
#' exists yet.
#'
#' YAML represents a sequence (e.g. a character vector recorded via
#' `.update_manifest()`) as a list on read-back. Each top-level element
#' that is a list of length-1 atomic values is simplified back into an
#' ordinary vector here, so callers see the same shape they originally
#' passed to `.update_manifest()`.
#'
#' @param path A character string. Directory to look for
#'   `htc-manifest.yaml` in. Defaults to `"."` (current working
#'   directory).
#'
#' @return A named list or `NULL`.
#'
#' @keywords internal
.get_manifest <- function(path = ".") {
    manifest_file <- file.path(path, "htc-manifest.yaml")
    if (!file.exists(manifest_file)) {
        return(NULL)
    }

    manifest <- yaml::read_yaml(manifest_file)

    # An empty or unreadable manifest file is treated the same as no manifest
    # at all, so callers only ever have to test for NULL.
    if (!is.list(manifest) || length(manifest) == 0L) {
        return(NULL)
    }

    lapply(manifest, function(x) {
        if (is.list(x) &&
            length(x) > 0L &&
            all(vapply(x, function(e) is.atomic(e) && length(e) == 1L, logical(1)))) {
            unlist(x)
        } else {
            x
        }
    })
}


#' Join a generated file to the directory it was written to
#'
#' Internal helper. The generator functions record two things about each file
#' they write: the bare name, which is what HTCondor sees on the submit node
#' after `scp` flattens the transfer, and the local path, which is what
#' `htc_upload()` needs in order to find the file on this machine. This
#' helper builds the second from the first, leaving the name untouched when
#' `output` is the working directory so that dry-run output reads
#' `job.sub` rather than `./job.sub`.
#'
#' @param output A character string. The directory the file was written to.
#' @param file A character string. The bare filename.
#'
#' @return A character string.
#'
#' @keywords internal
.join_output_path <- function(output, file) {
    if (is.null(output) || identical(output, ".") || identical(output, "./")) {
        file
    } else {
        file.path(output, file)
    }
}
