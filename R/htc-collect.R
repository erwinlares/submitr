#' Resolve the local tarballs htc_download() saved, keyed by group id
#'
#' Internal helper used by [htc_collect()] to rebuild, from the submission
#' state, the same tarball names [htc_download()] would have fetched into
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


#' Match group ids to HTCondor process numbers
#'
#' Internal helper used by [htc_collect()]. HTCondor numbers the jobs of a
#' cluster from 0 in the order it reads `subdatasets.csv`, which is the
#' order of `subsets` in the submission state, so a group's `ProcId` is its
#' position in that list minus one. A single-mode job is always process 0.
#' A group id that cannot be matched (a `tarballs` name that is not in the
#' submission state, or no submission state at all) gets `NA`.
#'
#' @param group_ids Character vector of group ids.
#' @param manifest A named list from `.get_manifest()`, or `NULL`.
#'
#' @return An integer vector the same length as `group_ids`.
#'
#' @keywords internal
.collect_proc_ids <- function(group_ids, manifest) {
    proc_ids <- rep(NA_integer_, length(group_ids))

    if (is.null(manifest)) {
        return(proc_ids)
    }

    mode <- if (is.null(manifest$mode)) "single" else manifest$mode

    if (identical(mode, "multiple") && !is.null(manifest$subsets)) {
        subset_ids <- tools::file_path_sans_ext(manifest$subsets)
        return(match(group_ids, subset_ids) - 1L)
    }

    single_id <- if (!is.null(manifest$script_stem)) manifest$script_stem else "job"
    proc_ids[group_ids == single_id] <- 0L
    proc_ids
}


#' Local paths to one job's HTCondor log files, when present
#'
#' Internal helper used by [htc_collect()]. [htc_gen_submit()] names the
#' three files `<cluster>-<proc>-job.log`, `.err`, and `.out`, and
#' [htc_download()] saves them beside the tarballs, so they are looked for
#' in the tarball's own directory. A file that is not there, or cannot be
#' named because the cluster or process number is unknown, is `NA`.
#'
#' @param dir Character. Directory to look in.
#' @param cluster_id Character or `NA`.
#' @param proc_id Integer or `NA`.
#'
#' @return A named character vector with elements `log`, `err`, and `out`.
#'
#' @keywords internal
.collect_log_paths <- function(dir, cluster_id, proc_id) {
    paths <- c(log = NA_character_, err = NA_character_, out = NA_character_)

    if (is.na(cluster_id) || is.na(proc_id)) {
        return(paths)
    }

    for (ext in names(paths)) {
        candidate <- file.path(dir, paste0(cluster_id, "-", proc_id, "-job.", ext))
        if (file.exists(candidate)) {
            paths[[ext]] <- candidate
        }
    }

    paths
}


#' Extract one job's tarball and describe what came out
#'
#' Internal helper used by [htc_collect()]. Never errors on the job's own
#' account: a tarball that is missing or will not extract comes back as
#' `extracted = FALSE` with a `problem` saying which, so one failed job
#' cannot stop the rest of a collection.
#'
#' @param tarball Character. Local path to the tarball.
#' @param dest Character. Directory to extract into; must not exist yet.
#' @param results_folder Character. The folder the job tarred, normally
#'   `"output"`.
#'
#' @return A list with elements `extracted`, `output_dir`, `files`,
#'   `n_files`, `has_record`, and `problem` (`NA`, `"missing"`,
#'   `"unreadable"`, or `"no_results_folder"`).
#'
#' @keywords internal
.collect_one <- function(tarball, dest, results_folder) {
    failed <- function(problem) {
        list(
            extracted  = FALSE,
            output_dir = NA_character_,
            files      = character(0),
            n_files    = NA_integer_,
            has_record = NA,
            problem    = problem
        )
    }

    if (!file.exists(tarball)) {
        return(failed("missing"))
    }

    dir.create(dest, recursive = TRUE)

    # A tarball that is truncated or not a tarball at all makes untar()
    # either error or return a non-zero status, depending on which tar it
    # uses; both count as unreadable. Warnings (such as uid/gid notes from
    # R's internal tar) do not, on their own, mean the extraction failed.
    status <- tryCatch(
        suppressWarnings(utils::untar(tarball, exdir = dest)),
        error = function(cnd) 1L
    )
    if (!identical(as.integer(status), 0L)) {
        unlink(dest, recursive = TRUE)
        return(failed("unreadable"))
    }

    output_dir <- file.path(dest, results_folder)

    # A job whose results folder was empty can come back as a tarball with
    # no entries at all: some tar implementations, R's own included, record
    # a directory only through the files inside it. An archive that
    # extracted to nothing is that case, so it is indexed as an empty
    # results folder rather than as a missing one.
    extracted_nothing <- length(list.files(
        dest, recursive = TRUE, all.files = TRUE, include.dirs = TRUE,
        no.. = TRUE
    )) == 0L
    if (!dir.exists(output_dir) && extracted_nothing) {
        dir.create(output_dir, recursive = TRUE)
    }

    if (!dir.exists(output_dir)) {
        return(list(
            extracted  = TRUE,
            output_dir = NA_character_,
            files      = character(0),
            n_files    = 0L,
            has_record = FALSE,
            problem    = "no_results_folder"
        ))
    }

    files <- sort(list.files(output_dir, recursive = TRUE, all.files = TRUE))

    list(
        extracted  = TRUE,
        output_dir = output_dir,
        files      = files,
        n_files    = length(files),
        has_record = file.exists(file.path(output_dir, "project-manifest.json")),
        problem    = NA_character_
    )
}


#' Unpack downloaded results and index them, one row per job
#'
#' `htc_collect()` is the step after [htc_download()]. It extracts every
#' job's results tarball into its own folder and returns the *job index*: a
#' tibble with one row per job saying whether its results came back, where
#' they landed, what files they hold, and where that job's HTCondor log
#' files are. In `"multiple"` mode that is one row per subset, the HTC-side
#' counterpart to the tibble `toolero::run_by_group()` returns for a local
#' run.
#'
#' It works for any analysis, whatever the script wrote into its results
#' folder, and never opens the files themselves: their types are whatever
#' each job chose to save, and no single reader is right for all of them.
#' Read them with whatever wrote them, using `output_dir` and `files` (see
#' the Workflow section).
#'
#' A job whose tarball is missing, or will not extract, still gets a row,
#' with `extracted = FALSE`, and the collection carries on with the other
#' jobs. A job whose R script fails still sends its tarball back (see
#' [htc_gen_executable()]), so a missing tarball means the job stopped
#' before it got that far: the container did not start, a file it needed
#' was not transferred, or the job was removed. Its `.err` and `.log`
#' files, in the `err` and `log` columns when they were downloaded, are the
#' place to look.
#'
#' @param tarballs A named character vector or `NULL`. Local tarball paths
#'   to collect, with names giving each one's group id. When `NULL` (the
#'   default), resolved from the submission state: the same subset names
#'   and script stem [htc_download()] used to name the files it fetched into
#'   `local_path`.
#' @param local_path A character string. The directory [htc_download()]
#'   saved tarballs into. Defaults to `"."`, matching [htc_download()]'s own
#'   default. Only consulted when `tarballs` is `NULL`.
#' @param extract_dir A character string or `NULL`. Directory to extract
#'   into, one subdirectory per group id. When `NULL` (the default),
#'   defaults to `local_path`.
#' @param overwrite Logical. If `TRUE`, deletes and re-extracts a group's
#'   subdirectory when it already exists. If `FALSE` (the default), any
#'   existing subdirectory is an error, raised before anything is
#'   extracted, so a second `htc_collect()` call never silently mixes stale
#'   and fresh results.
#' @param path A character string. Directory holding the submission state
#'   (`htc-manifest.yml`). Defaults to `"."`, matching the default used
#'   elsewhere in the family. Consulted for the tarball names when
#'   `tarballs` is `NULL`, and in every case for the cluster ID, process
#'   numbers, container image, and results folder.
#'
#' @return The job index: a tibble with one row per job and these columns.
#'
#'   * `group_id` -- the subset stem in `"multiple"` mode (`"adelie"` for
#'     `adelie.csv`), the script stem in `"single"` mode, or the name given
#'     in `tarballs`.
#'   * `proc_id` -- the job's HTCondor process number, from its position in
#'     the submission state; `NA` when it cannot be matched.
#'   * `cluster_id` -- from the submission state; `NA` when absent.
#'   * `extracted` -- whether the tarball was found and extracted.
#'   * `n_files` -- how many files the results folder holds; `NA` when not
#'     extracted.
#'   * `has_record` -- whether the results folder holds an output record
#'     (`project-manifest.json`, written by `toolero::generate_manifest()`).
#'     The file is only checked for, never read. `NA` when not extracted.
#'   * `output_dir` -- where the job's results folder landed; `NA` when not
#'     extracted.
#'   * `files` -- a list column of paths relative to `output_dir`.
#'   * `log`, `err`, `out` -- local paths to the job's three HTCondor files,
#'     found beside its tarball; `NA` when not there.
#'   * `container_image` -- from the submission state; `NA` when absent.
#'
#' @section Workflow:
#' ```r
#' htc_download(local_path = "downloads/")
#' index <- htc_collect(local_path = "downloads/")
#'
#' # Which jobs came back?
#' index[, c("group_id", "extracted", "n_files")]
#'
#' # Why did a job fail? Its .err file usually says.
#' readLines(index$err[!index$extracted][1])
#'
#' # Full paths to every file each job produced
#' paths <- Map(file.path, index$output_dir, index$files)
#' models <- lapply(unlist(paths[index$extracted]), readRDS)
#' ```
#'
#' @export
#'
#' @examples
#' \donttest{
#' # Build a single-job tarball by hand to show what htc_collect() does with
#' # one -- normally this tarball would have come from htc_download() after
#' # a real job finished.
#' job_dir <- tempfile("job")
#' dir.create(file.path(job_dir, "output"), recursive = TRUE)
#' saveRDS(mtcars, file.path(job_dir, "output", "mtcars.rds"))
#'
#' local_path <- tempfile("downloads")
#' dir.create(local_path)
#' tarball <- file.path(local_path, "analysis-results.tar.gz")
#' old <- setwd(job_dir)
#' utils::tar(tarball, "output", compression = "gzip", tar = "internal")
#' setwd(old)
#'
#' index <- htc_collect(
#'   tarballs    = c(analysis = tarball),
#'   extract_dir = tempfile("collected")
#' )
#' index
#' index$files[[1]]
#' }
htc_collect <- function(tarballs    = NULL,
                        local_path  = ".",
                        extract_dir = NULL,
                        overwrite   = FALSE,
                        path        = ".") {

    manifest <- .get_manifest(path = path)

    # -- 1. Resolve tarballs, keyed by group id --------------------------------
    if (is.null(tarballs)) {
        resolved <- .resolve_collected_tarballs(manifest, local_path)

        if (nrow(resolved) == 0L) {
            cli::cli_abort(c(
                "No tarballs to collect.",
                "i" = "Pass {.arg tarballs} directly (a named character vector,",
                " " = "  names giving each one's group id), or run the full",
                " " = "  workflow first ({.fn htc_gen_submit}, {.fn htc_gen_executable},",
                " " = "  {.fn htc_submit}, {.fn htc_download}) so the submission state",
                " " = "  can resolve them automatically.",
                "i" = "Looked for the submission state ({.file htc-manifest.yml}) in {.path {path}}."
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
                " " = "  automatically from the submission state instead."
            ))
        }
        if (anyDuplicated(names(tarballs)) > 0L) {
            cli::cli_abort(
                "{.arg tarballs} has duplicate group ids; each name must be unique."
            )
        }
        tarball_paths <- tarballs
    }

    group_ids <- names(tarball_paths)

    # -- 2. Resolve extract_dir and refuse to clobber, before extracting -------
    # Checked for every group up front, so an existing folder stops the
    # collection before any tarball is extracted rather than halfway through.
    if (is.null(extract_dir)) {
        extract_dir <- local_path
    }
    if (!dir.exists(extract_dir)) {
        dir.create(extract_dir, recursive = TRUE)
    }

    dests    <- file.path(extract_dir, group_ids)
    existing <- dests[dir.exists(dests)]

    if (length(existing) > 0L) {
        if (!overwrite) {
            cli::cli_abort(c(
                "{.path {existing}} already exist{?s/}.",
                "i" = "Pass {.code overwrite = TRUE} to re-extract, or remove",
                " " = "  what is there first."
            ))
        }
        unlink(existing, recursive = TRUE)
    }

    # -- 3. Facts from the submission state ------------------------------------
    results_folder <- if (!is.null(manifest$results_folder)) manifest$results_folder else "output"
    cluster_id     <- if (!is.null(manifest$cluster_id)) as.character(manifest$cluster_id) else NA_character_
    image          <- if (!is.null(manifest$container_image)) manifest$container_image else NA_character_
    proc_ids       <- .collect_proc_ids(group_ids, manifest)

    # -- 4. Extract each job and index it --------------------------------------
    jobs <- lapply(seq_along(group_ids), function(i) {
        job  <- .collect_one(tarball_paths[[i]], dests[[i]], results_folder)
        logs <- .collect_log_paths(
            dirname(tarball_paths[[i]]), cluster_id, proc_ids[[i]]
        )
        c(job, as.list(logs))
    })

    pick <- function(field, type) vapply(jobs, function(j) j[[field]], type)

    index <- tibble::tibble(
        group_id        = group_ids,
        proc_id         = proc_ids,
        cluster_id      = rep(cluster_id, length(group_ids)),
        extracted       = pick("extracted", logical(1)),
        n_files         = pick("n_files", integer(1)),
        has_record      = pick("has_record", logical(1)),
        output_dir      = pick("output_dir", character(1)),
        files           = lapply(jobs, function(j) j$files),
        log             = pick("log", character(1)),
        err             = pick("err", character(1)),
        out             = pick("out", character(1)),
        container_image = rep(image, length(group_ids))
    )

    # -- 5. Report --------------------------------------------------------------
    problems   <- pick("problem", character(1))
    n_jobs     <- length(group_ids)
    missing    <- basename(tarball_paths[problems %in% "missing"])
    unreadable <- basename(tarball_paths[problems %in% "unreadable"])
    no_folder  <- group_ids[problems %in% "no_results_folder"]

    if (length(missing) > 0L || length(unreadable) > 0L) {
        n_failed <- length(missing) + length(unreadable)
        cli::cli_warn(c(
            "!" = "{n_failed} of {n_jobs} tarball{?s} could not be collected.",
            if (length(missing) > 0L) c("x" = "Not found: {.file {missing}}"),
            if (length(unreadable) > 0L) c("x" = "Could not be extracted: {.file {unreadable}}"),
            "i" = "Those rows have {.code extracted = FALSE}. A job that stops before",
            " " = "  packing its results sends back no tarball; its {.file .err} and",
            " " = "  {.file .log} files (the {.field err} and {.field log} columns, once",
            " " = "  downloaded) usually say why.",
            "i" = "If the jobs have not finished downloading, run {.fn htc_download} first."
        ))
    }

    if (length(no_folder) > 0L) {
        cli::cli_warn(c(
            "!" = "Extracted, but no {.file {results_folder}/} folder inside for: {.val {no_folder}}.",
            "i" = "{.fn htc_gen_executable} tars {.file {results_folder}/}; a tarball built",
            " " = "  some other way may use a different folder name."
        ))
    }

    n_extracted <- sum(index$extracted)
    cli::cli_alert_success(
        "Collected {n_extracted} of {n_jobs} job{?s} into {.path {extract_dir}}."
    )

    index
}
