#' Resolve the local tarballs htc_download() saved, keyed by group id
#'
#' Internal helper used by [htc_collect()] to rebuild, from the job
#' manifest, the same tarball names [htc_download()] would have fetched into
#' `local_path` -- reusing [.tarball_name()] so the naming stays in the one
#' place the rest of the family already shares it (see that function's own
#' docs for why three separate resolvers of this name would drift).
#'
#' @param manifest A named list from `.get_manifest()`, or `NULL`.
#' @param local_path A character string. Directory the tarballs were
#'   downloaded into.
#'
#' @return A tibble with columns `group_id` and `tarball` (a local path),
#'   possibly with zero rows.
#'
#' @keywords internal
.resolve_collected_tarballs <- function(manifest, local_path) {
    empty <- tibble::tibble(group_id = character(0), tarball = character(0))

    if (is.null(manifest)) {
        return(empty)
    }

    mode <- if (is.null(manifest$mode)) "single" else manifest$mode

    if (identical(mode, "multiple") && !is.null(manifest$subsets)) {
        group_ids <- tools::file_path_sans_ext(manifest$subsets)
        names     <- vapply(
            group_ids,
            function(g) .tarball_name(manifest$script_stem, g),
            character(1)
        )
        return(tibble::tibble(
            group_id = group_ids,
            tarball  = file.path(local_path, names)
        ))
    }

    if (!is.null(manifest$output_files)) {
        group_id <- if (!is.null(manifest$script_stem)) manifest$script_stem else "job"
        return(tibble::tibble(
            group_id = group_id,
            tarball  = file.path(local_path, manifest$output_files)
        ))
    }

    empty
}


#' An empty artifacts data frame matching toolero's accumulator schema
#'
#' Internal helper used by [htc_collect()] as the fallback when a job's
#' `project-manifest.json` records zero artifacts (an analysis that ran and
#' produced nothing -- `toolero::generate_manifest()` warns but still writes
#' a manifest in that case). Column names mirror
#' `toolero:::.accumulator_columns()`; submitr keeps its own copy rather
#' than importing an internal function from a `Suggests`-only dependency.
#'
#' @return A zero-row data frame.
#'
#' @keywords internal
.empty_artifacts_df <- function() {
    data.frame(
        file_path      = character(0),
        r_class        = character(0),
        timestamp      = character(0),
        function_used  = character(0),
        status         = character(0),
        error_message  = character(0),
        note           = character(0),
        stringsAsFactors = FALSE
    )
}


#' Stitch downloaded multi-job results back into one tibble
#'
#' `htc_collect()` closes the gap [htc_download()] leaves open in
#' `"multiple"` mode: after it fetches one tarball per subset, nothing
#' extracts them or brings their results back together the way
#' `toolero::run_by_group()` does for a local run (S-G1). `htc_collect()`
#' extracts every downloaded tarball, reads each job's own
#' `project-manifest.json` (written by `toolero::generate_manifest()`) or,
#' failing that, its raw `accumulator.csv`, and row-binds them into one
#' tibble describing every artifact every job produced -- with a `group_id`
#' column identifying which job each row came from and a `local_path`
#' column pointing at the extracted file on this machine.
#'
#' This does not attempt to load the artifacts themselves into R: their
#' types are whatever each job's own analysis chose to save (a model, a
#' plot, a data frame, a file), and no single loader is correct for all of
#' them. `local_path` is the join key back to the data -- read it with
#' whatever `toolero::save_output()`'s `.f` originally wrote it with.
#'
#' @param tarballs A named character vector or `NULL`. Local tarball paths
#'   to collect, with names giving each one's group id. When `NULL` (the
#'   default), resolved automatically from the job manifest -- the same
#'   subset names and script stem [htc_download()] itself used to name the
#'   files it fetched into `local_path`.
#' @param local_path A character string. The directory [htc_download()]
#'   saved tarballs into. Defaults to `"."`, matching [htc_download()]'s own
#'   default. Only consulted when `tarballs` is `NULL`.
#' @param extract_dir A character string or `NULL`. Directory to extract
#'   each tarball into, one subdirectory per group id. When `NULL` (the
#'   default), defaults to `local_path`.
#' @param overwrite Logical. If `TRUE`, deletes and re-extracts a group's
#'   subdirectory when it already exists. If `FALSE` (the default), an
#'   existing subdirectory is an error, so a second `htc_collect()` call
#'   never silently mixes stale and fresh results.
#' @param path A character string. Directory holding the job manifest
#'   (`htc-manifest.yaml`), consulted only when `tarballs` is `NULL`.
#'   Defaults to `"."`, matching the default used elsewhere in the family.
#'
#' @return A tibble with one row per artifact, columns `group_id`,
#'   `file_path`, `local_path`, `r_class`, `timestamp`, `function_used`,
#'   `status`, `error_message`, `note`, `job_execution_context`, and
#'   `job_generated_at`. In `"single"` mode this still has one `group_id`
#'   (the script stem), for a schema that does not depend on which mode
#'   produced it.
#'
#' @section Workflow:
#' ```r
#' htc_download(local_path = "downloads/")
#' results <- htc_collect(local_path = "downloads/")
#'
#' # Load the actual saved objects, now that you know where they landed
#' models <- lapply(
#'   results$local_path[results$r_class == "lm"],
#'   readRDS
#' )
#' ```
#'
#' @export
#'
#' @examples
#' \donttest{
#' # Build a single-job tarball containing a project manifest, by hand, to
#' # show what htc_collect() does with one -- normally this tarball would
#' # have come from htc_download() after a real job finished.
#' job_dir <- withr::local_tempdir()
#' out_dir <- file.path(job_dir, "output")
#' dir.create(out_dir)
#' saveRDS(mtcars, file.path(out_dir, "mtcars.rds"))
#' writeLines(
#'   jsonlite::toJSON(list(
#'     execution_context = "rscript",
#'     generated_at      = "2026-01-01T00:00:00.000Z",
#'     artifacts = list(list(
#'       file_path = "output/mtcars.rds", r_class = "data.frame",
#'       timestamp = "2026-01-01T00:00:00.000Z", function_used = "saveRDS",
#'       status = "success", error_message = NA, note = NA
#'     ))
#'   ), auto_unbox = TRUE),
#'   file.path(out_dir, "project-manifest.json")
#' )
#'
#' local_path <- withr::local_tempdir()
#' withr::with_dir(job_dir, {
#'   utils::tar(file.path(local_path, "analysis-results.tar.gz"), "output",
#'              compression = "gzip", tar = "internal")
#' })
#'
#' results <- htc_collect(
#'   tarballs   = c(analysis = file.path(local_path, "analysis-results.tar.gz")),
#'   extract_dir = withr::local_tempdir()
#' )
#' results
#' }
htc_collect <- function(tarballs    = NULL,
                        local_path  = ".",
                        extract_dir = NULL,
                        overwrite   = FALSE,
                        path        = ".") {

    manifest <- .get_manifest(path = path)

    # -- 1. Resolve tarballs, keyed by group id ----------------------------------
    if (is.null(tarballs)) {
        resolved <- .resolve_collected_tarballs(manifest, local_path)

        if (nrow(resolved) == 0L) {
            cli::cli_abort(c(
                "No tarballs to collect.",
                "i" = "Pass {.arg tarballs} directly (a named character vector,",
                " " = "  names giving each one's group id), or run the full",
                " " = "  workflow first ({.fn htc_gen_submit}, {.fn htc_gen_executable},",
                " " = "  {.fn htc_submit}, {.fn htc_download}) so the job manifest",
                " " = "  can resolve them automatically.",
                "i" = "Looked for a manifest in {.path {path}}."
            ))
        }

        tarball_paths <- setNames(resolved$tarball, resolved$group_id)
    } else {
        if (is.null(names(tarballs)) || any(!nzchar(names(tarballs)))) {
            cli::cli_abort(c(
                "{.arg tarballs} must be a named character vector when",
                " " = "  supplied directly, with names giving each tarball's",
                " " = "  group id.",
                "i" = "Leave {.arg tarballs} as {.code NULL} to resolve it",
                " " = "  automatically from the job manifest instead."
            ))
        }
        if (anyDuplicated(names(tarballs)) > 0L) {
            cli::cli_abort(
                "{.arg tarballs} has duplicate group ids; each name must be unique."
            )
        }
        tarball_paths <- tarballs
    }

    missing <- tarball_paths[!file.exists(tarball_paths)]
    if (length(missing) > 0L) {
        cli::cli_abort(c(
            "{length(missing)} tarball{?s} not found:",
            "x" = "{.path {missing}}",
            "i" = "Run {.fn htc_download} first."
        ))
    }

    # -- 2. Resolve and prepare extract_dir ---------------------------------------
    if (is.null(extract_dir)) {
        extract_dir <- local_path
    }
    if (!dir.exists(extract_dir)) {
        dir.create(extract_dir, recursive = TRUE)
    }

    results_folder <- if (!is.null(manifest$results_folder)) manifest$results_folder else "output"

    # -- 3. Extract each tarball and read its per-job artifact manifest ----------
    rows <- list()

    for (group_id in names(tarball_paths)) {
        dest <- file.path(extract_dir, group_id)

        if (dir.exists(dest)) {
            if (!overwrite) {
                cli::cli_abort(c(
                    "{.path {dest}} already exists.",
                    "i" = "Pass {.code overwrite = TRUE} to re-extract, or remove",
                    " " = "  the directory first."
                ))
            }
            unlink(dest, recursive = TRUE)
        }
        dir.create(dest, recursive = TRUE)

        untar_status <- utils::untar(tarball_paths[[group_id]], exdir = dest)
        if (!identical(untar_status, 0L)) {
            cli::cli_abort(
                "Failed to extract {.path {tarball_paths[[group_id]]}} (untar returned {untar_status})."
            )
        }

        job_manifest_path <- file.path(dest, results_folder, "project-manifest.json")
        accumulator_path  <- file.path(dest, results_folder, "accumulator.csv")

        if (file.exists(job_manifest_path)) {
            job_manifest <- jsonlite::fromJSON(job_manifest_path)

            artifacts <- if (is.null(job_manifest$artifacts) ||
                             NROW(job_manifest$artifacts) == 0L) {
                .empty_artifacts_df()
            } else {
                as.data.frame(job_manifest$artifacts, stringsAsFactors = FALSE)
            }

            execution_context <- if (!is.null(job_manifest$execution_context)) {
                job_manifest$execution_context
            } else {
                NA_character_
            }
            generated_at <- if (!is.null(job_manifest$generated_at)) {
                job_manifest$generated_at
            } else {
                NA_character_
            }
        } else if (file.exists(accumulator_path)) {
            cli::cli_warn(c(
                "!" = "No project-manifest.json found for {.val {group_id}};",
                " " = "  falling back to accumulator.csv (raw, not deduplicated).",
                "i" = "Call {.fn toolero::generate_manifest} at the end of the",
                " " = "  analysis script to get a deduplicated",
                " " = "  project-manifest.json instead."
            ))
            artifacts <- utils::read.csv(
                accumulator_path,
                colClasses = "character",
                na.strings = "",
                check.names = FALSE,
                stringsAsFactors = FALSE
            )
            execution_context <- NA_character_
            generated_at       <- NA_character_
        } else {
            cli::cli_warn(c(
                "!" = "No project-manifest.json or accumulator.csv found for",
                " " = "  {.val {group_id}} under {.path {file.path(dest, results_folder)}}."
            ))
            next
        }

        artifacts$local_path             <- file.path(dest, artifacts$file_path)
        artifacts$group_id               <- group_id
        artifacts$job_execution_context  <- execution_context
        artifacts$job_generated_at       <- generated_at

        rows[[group_id]] <- artifacts
    }

    # -- 4. Assemble the combined tibble ------------------------------------------
    if (length(rows) == 0L) {
        cli::cli_warn("No artifacts were found in any collected tarball.")
        return(invisible(tibble::tibble()))
    }

    out <- do.call(rbind, rows)
    out <- out[, c(
        "group_id", "file_path", "local_path", "r_class", "timestamp",
        "function_used", "status", "error_message", "note",
        "job_execution_context", "job_generated_at"
    ), drop = FALSE]
    rownames(out) <- NULL

    cli::cli_alert_success(
        "Collected {nrow(out)} artifact{?s} from {length(rows)} job{?s}."
    )

    tibble::as_tibble(out)
}
