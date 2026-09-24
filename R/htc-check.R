#' Parse a request_memory/request_disk-style size string into gigabytes
#'
#' Internal helper used by [htc_check()] to compare `resources` values like
#' `"16GB"`, `"512MB"`, or a bare `"4"` (HTCondor treats an amount with no
#' unit suffix as megabytes for `request_memory`/`request_disk`) on a common
#' scale. Never authoritative -- it exists to catch an obviously implausible
#' request (a stray extra zero, GB where MB was meant), not to validate
#' HTCondor's own resource-request syntax exhaustively.
#'
#' @param x A character string, or `NULL`/`NA`.
#'
#' @return A numeric scalar in gigabytes, or `NA_real_` if `x` cannot be
#'   parsed.
#'
#' @keywords internal
.parse_size_gb <- function(x) {
    if (is.null(x) || length(x) != 1L || is.na(x)) {
        return(NA_real_)
    }

    m <- regmatches(
        trimws(x),
        regexec("^([0-9.]+)\\s*(GB|MB|TB)?$", trimws(x), ignore.case = TRUE)
    )[[1]]

    if (length(m) == 0L) {
        return(NA_real_)
    }

    value <- suppressWarnings(as.numeric(m[2]))
    if (is.na(value)) {
        return(NA_real_)
    }

    unit <- toupper(m[3])
    factor <- switch(unit, "TB" = 1024, "GB" = 1, "MB" = 1 / 1024, 1 / 1024)
    value * factor
}


#' Preflight check for a submitr job before upload or submission
#'
#' `htc_check()` verifies, locally and in seconds, several things that would
#' otherwise only surface an hour later as a held or failed job on the
#' cluster (S-G4): that every file the job depends on actually exists on
#' this machine, that a `"multiple"`-mode job's subset files still match
#' what `subdatasets.csv` expects, that the resource request looks
#' plausible, and -- best effort, when a container tool is available
#' locally -- that the container image looks reachable.
#'
#' Every argument can be resolved from the job manifest, so the common case
#' is `htc_check()` with no arguments at all, run right after
#' [htc_gen_submit()] and [htc_gen_executable()] and before [htc_upload()].
#'
#' @param container_image A character string or `NULL`. The container image
#'   reference to check, e.g. `"registry.doit.wisc.edu/netid/myimage:1.0.0"`.
#'   When `NULL` (the default), resolves to the `container_image` recorded
#'   in the job manifest by [htc_gen_submit()]. When still `NULL`, image
#'   checks are skipped.
#' @param input_files A character vector or `NULL`. Local paths that are
#'   expected to exist before upload -- normally the same value passed to
#'   [htc_gen_submit()]. When `NULL` (the default), resolves to
#'   `input_files` recorded in the manifest.
#' @param data_files A character vector or `NULL`. Local paths to data files
#'   expected to exist before a container image bakes them in -- normally
#'   the same value passed to [htc_gen_executable()]. When `NULL` (the
#'   default), resolves to `data_files` recorded in the manifest.
#' @param resources A named list with `cpus`, `memory`, and `disk`, or
#'   `NULL`. When `NULL` (the default), resolves to the resolved resource
#'   values [htc_gen_submit()] recorded in the manifest (whichever preset,
#'   or `custom_resources`, was actually used).
#' @param verbose Logical. If `TRUE` (the default), prints a line for every
#'   check performed, not just the ones that found something. Set `FALSE`
#'   to only see problems.
#' @param path A character string. Directory holding the job manifest
#'   (`htc-manifest.yaml`). Defaults to `"."`, matching the default used
#'   elsewhere in the family.
#'
#' @return A tibble with one row per issue found, columns `check`,
#'   `severity` (`"error"` or `"warning"`), and `message`. Zero rows means
#'   nothing was found. Returned invisibly; call `print()` explicitly or
#'   assign it to inspect the detail behind the printed summary.
#'
#' @section What counts as an error versus a warning:
#' A missing input, data, or subset file is an `"error"`: the job will not
#' run without it, full stop. A resource request outside typical bounds, a
#' `container_image` tagged `latest`, or an image that could not be
#' confirmed pullable are `"warning"`s -- each might be exactly what you
#' intend, and none of them is something `htc_check()` can be certain about
#' from the local machine alone. [htc_upload()]'s own `check` argument only
#' blocks the upload on `"error"`s.
#'
#' @section The image check is best effort:
#' `htc_check()` only attempts to confirm `container_image` is pullable when
#' `podman` or `docker` is found on the local `PATH`, via
#' `<tool> manifest inspect`. A failure there is reported as a warning, not
#' an error, and is not conclusive either way: it may mean the image
#' genuinely does not exist, or simply that you are not logged in to the
#' registry from this machine, or that the tool timed out. When neither
#' tool is found, the image check is skipped entirely and reported as such.
#'
#' @seealso [htc_upload()]'s `check` argument, which runs this
#'   automatically and aborts before uploading if an `"error"`-level issue
#'   is found.
#'
#' @importFrom stats setNames
#' @export
#'
#' @examples
#' \donttest{
#' tmp <- withr::local_tempdir()
#' htc_gen_submit(
#'   container_image = "registry.doit.wisc.edu/netid/myimage:latest",
#'   resources       = "small",
#'   output          = tmp,
#'   path            = tmp
#' )
#' htc_check(path = tmp)
#' }
htc_check <- function(container_image = NULL,
                      input_files     = NULL,
                      data_files      = NULL,
                      resources       = NULL,
                      verbose         = TRUE,
                      path            = ".") {

    manifest <- .get_manifest(path = path)

    if (is.null(container_image)) {
        container_image <- manifest$container_image
    }
    if (is.null(input_files)) {
        input_files <- manifest$input_files
    }
    if (is.null(data_files)) {
        data_files <- manifest$data_files
    }
    if (is.null(resources)) {
        resources <- manifest$resources
    }

    issues <- list()
    .add_issue <- function(check, severity, message) {
        issues[[length(issues) + 1L]] <<- tibble::tibble(
            check = check, severity = severity, message = message
        )
    }
    # c(...) collects the named "v"/"i"/" " arguments into the single named
    # character vector cli_inform() expects as its message argument. Passing
    # ... straight through left each name (v, i, ...) unmatched against
    # cli_inform()'s own formals, so it fell into cli_inform()'s own ...
    # and message was left unfilled -- "argument \"message\" is missing".
    .say <- function(...) if (verbose) cli::cli_inform(c(...))

    # -- 1. Input files exist locally -------------------------------------------
    if (length(input_files) > 0L) {
        missing <- input_files[!file.exists(input_files)]
        if (length(missing) > 0L) {
            .add_issue(
                "input_files", "error",
                paste0(
                    length(missing), " input file(s) not found: ",
                    paste(missing, collapse = ", ")
                )
            )
        } else {
            .say("v" = "All {length(input_files)} input file{?s} found.")
        }
    } else {
        .say("i" = "No {.arg input_files} to check (none supplied or recorded).")
    }

    # -- 2. Data files exist locally ---------------------------------------------
    if (length(data_files) > 0L) {
        missing <- data_files[!file.exists(data_files)]
        if (length(missing) > 0L) {
            .add_issue(
                "data_files", "error",
                paste0(
                    length(missing), " data file(s) not found: ",
                    paste(missing, collapse = ", ")
                )
            )
        } else {
            .say("v" = "All {length(data_files)} data file{?s} found.")
        }
    } else {
        .say("i" = "No {.arg data_files} to check (none supplied or recorded).")
    }

    # -- 3. Multiple-mode subset files match subdatasets.csv ---------------------
    if (identical(manifest$mode, "multiple")) {
        subdatasets_path <- manifest$subdatasets_path
        subset_files      <- manifest$subset_files

        if (is.null(subdatasets_path) || !file.exists(subdatasets_path)) {
            .add_issue(
                "subdatasets", "error",
                paste0(
                    "subdatasets.csv not found at ",
                    if (is.null(subdatasets_path)) "(not recorded in the manifest)"
                    else subdatasets_path
                )
            )
        } else {
            listed <- readr::read_csv(
                subdatasets_path, col_names = "file", show_col_types = FALSE
            )[["file"]]

            missing_on_disk <- subset_files[!file.exists(subset_files)]
            if (length(missing_on_disk) > 0L) {
                .add_issue(
                    "subdatasets", "error",
                    paste0(
                        length(missing_on_disk), " subset file(s) listed in the",
                        " job manifest no longer exist: ",
                        paste(missing_on_disk, collapse = ", ")
                    )
                )
            }

            recorded_basenames <- basename(subset_files)
            if (!setequal(listed, recorded_basenames)) {
                .add_issue(
                    "subdatasets", "error",
                    paste0(
                        "subdatasets.csv (", length(listed), " file(s)) and the",
                        " job manifest's subset list (", length(recorded_basenames),
                        " file(s)) disagree. Re-run htc_gen_submit() if the",
                        " split data has changed since."
                    )
                )
            }

            if (length(missing_on_disk) == 0L && setequal(listed, recorded_basenames)) {
                .say(
                    "v" = "All {length(subset_files)} subset file{?s} found and",
                    " " = "  match subdatasets.csv."
                )
            }
        }
    } else {
        .say("i" = "Mode is {.val single} (or unset) -- no subset files to check.")
    }

    # -- 4. Resource request plausibility ----------------------------------------
    if (!is.null(resources)) {
        cpus   <- suppressWarnings(as.integer(resources[["cpus"]]))
        memory <- .parse_size_gb(resources[["memory"]])
        disk   <- .parse_size_gb(resources[["disk"]])

        if (is.na(cpus) || cpus < 1L) {
            .add_issue("resources", "error", "request_cpus could not be parsed, or is less than 1.")
        } else if (cpus > 32L) {
            .add_issue(
                "resources", "warning",
                paste0(
                    "request_cpus = ", cpus, " is unusually high for a single",
                    " job -- most CHTC execute slots top out well below this;",
                    " confirm this is intentional."
                )
            )
        }

        if (is.na(memory)) {
            .add_issue("resources", "warning", "request_memory could not be parsed as a size.")
        } else if (memory > 128) {
            .add_issue(
                "resources", "warning",
                paste0(
                    "request_memory (~", round(memory, 1), " GB) is large enough",
                    " that it may take a while to match a slot, or may not fit",
                    " the general HTC pool at all; confirm this is intentional."
                )
            )
        }

        if (is.na(disk)) {
            .add_issue("resources", "warning", "request_disk could not be parsed as a size.")
        } else if (disk > 256) {
            .add_issue(
                "resources", "warning",
                paste0(
                    "request_disk (~", round(disk, 1), " GB) is unusually large;",
                    " confirm this is intentional."
                )
            )
        }

        if (length(issues) == 0L || !any(vapply(issues, function(i) i$check[[1]] == "resources", logical(1)))) {
            .say("v" = "Resource request looks plausible.")
        }
    } else {
        .say("i" = "No {.arg resources} to check (none supplied or recorded).")
    }

    # -- 5. Container image ------------------------------------------------------
    if (!is.null(container_image)) {
        bare_image <- sub("^docker://", "", container_image)

        if (grepl(":latest$", bare_image) || !grepl(":", bare_image)) {
            .add_issue(
                "container_image", "warning",
                paste0(
                    "container_image resolves to the \"latest\" tag (",
                    bare_image, "). \"latest\" is overwritten on every push,",
                    " which works against reproducibility -- an explicit",
                    " version tag is recommended."
                )
            )
        }

        tool <- if (nzchar(Sys.which("podman"))) {
            "podman"
        } else if (nzchar(Sys.which("docker"))) {
            "docker"
        } else {
            NULL
        }

        if (is.null(tool)) {
            .say(c(
                "i" = "Skipping image reachability check: neither {.val podman}",
                " " = "  nor {.val docker} was found on the local PATH."
            ))
        } else {
            inspect_exit <- tryCatch(
                system2(
                    tool, c("manifest", "inspect", bare_image),
                    stdout = FALSE, stderr = FALSE, timeout = 15
                ),
                warning = function(w) 1L,
                error   = function(e) 1L
            )

            if (!identical(inspect_exit, 0L)) {
                .add_issue(
                    "container_image", "warning",
                    paste0(
                        "Could not confirm ", bare_image, " is pullable via ",
                        "`", tool, " manifest inspect`. This is not conclusive --",
                        " it may just mean you are not logged in to the",
                        " registry from this machine."
                    )
                )
            } else {
                .say("v" = "{tool} confirms {.val {bare_image}} is reachable.")
            }
        }
    } else {
        .say("i" = "No {.arg container_image} to check (none supplied or recorded).")
    }

    # -- 6. Summarize -------------------------------------------------------------
    result <- if (length(issues) > 0L) {
        do.call(rbind, issues)
    } else {
        tibble::tibble(
            check = character(0), severity = character(0), message = character(0)
        )
    }

    n_errors   <- sum(result$severity == "error")
    n_warnings <- sum(result$severity == "warning")

    if (n_errors == 0L && n_warnings == 0L) {
        cli::cli_alert_success("Preflight check passed -- no issues found.")
    } else {
        cli::cli_warn(c(
            "!" = "Preflight check found {n_errors} error{?s} and {n_warnings} warning{?s}.",
            setNames(
                paste0(toupper(result$severity), " [", result$check, "]: ", result$message),
                ifelse(result$severity == "error", "x", "!")
            )
        ))
    }

    invisible(result)
}
