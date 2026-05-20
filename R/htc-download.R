#' Download files from an HTC submit node
#'
#' `htc_download()` copies one or more files from a directory on an HTC
#' submit node to a local directory via `scp`. It is the final step in the
#' job submission workflow -- called after [htc_status()] confirms all jobs
#' have completed.
#'
#' When `cluster_id` is supplied without `files`, the function uses the
#' job manifest built up by [htc_gen_submit()], [htc_gen_executable()],
#' and [htc_submit()] to determine which files to download. For single-mode
#' jobs, this includes the results tarball and the log, error, and output
#' files. For multiple-mode jobs, the function reads the subset names from
#' the manifest and constructs per-job tarball names and per-process log
#' file patterns.
#'
#' Glob patterns such as `"*.tar.gz"` are supported when using the `files`
#' argument and are evaluated on the remote server, not locally.
#'
#' @param files A character vector or `NULL`. One or more filenames or glob
#'   patterns to download from `remote_path` on the submit node. Examples:
#'   `"results.tar.gz"`, `c("job.log", "job.err")`, `"*.tar.gz"`. When
#'   `NULL`, the function uses `cluster_id` and the job manifest to
#'   determine which files to download. Defaults to `NULL`.
#' @param cluster_id A character string or `NULL`. The cluster ID returned
#'   by [htc_submit()]. When supplied without `files`, the function
#'   constructs the file list from the job manifest. When `NULL`, falls
#'   back to the most recently submitted cluster ID stored in the manifest.
#'   Defaults to `NULL`.
#' @param remote_path A character string. The directory on the submit node
#'   where the files are located. Defaults to `"~/"`. Should match the
#'   `remote_path` used in [htc_upload()] and [htc_submit()].
#' @param local_path A character string. The local directory where downloaded
#'   files will be saved. Defaults to `"."` (current working directory).
#' @param config A named list as returned by [htc_config()]. Must contain
#'   `username` and `server`. If `NULL` (the default), uses the session
#'   config set by [htc_start()]. If no session config is set,
#'   the function errors with instructions.
#' @param dry_run Logical. If `TRUE`, prints the `scp` command that would be
#'   executed without running it. Defaults to `FALSE`.
#' @param verbose Logical. If `TRUE`, prints progress messages. Defaults to
#'   `FALSE`.
#'
#' @return Called for its side effects. Returns `invisible(NULL)`.
#'
#' @section Automatic file resolution:
#' When `files` is `NULL`, the function resolves the file list from the
#' job manifest. The manifest is built automatically as you call
#' [htc_gen_submit()], [htc_gen_executable()], and [htc_submit()] during
#' the normal workflow. No extra steps are needed.
#'
#' For a single-mode job:
#' - The results tarball (e.g. `"analysis-results.tar.gz"`)
#' - Log files: `"{cluster_id}-0-job.log"`, `".err"`, `".out"`
#'
#' For a multiple-mode job:
#' - Per-subset tarballs (e.g. `"adelie.csv-results.tar.gz"`)
#' - Log files for each process: `"{cluster_id}-{0,1,...}-job.log"`, etc.
#'
#' @section Workflow:
#' `htc_download()` is the final system-facing step in the submitr workflow.
#' Call it after [htc_status()] confirms all jobs have completed.
#'
#' ```r
#' # Automatic: uses the job manifest to determine what to download
#' htc_start()
#' htc_gen_submit(...)
#' htc_gen_executable(...)
#' htc_upload(...)
#' job <- htc_submit("analysis.sub")
#' htc_status(cluster_id = job, watch = TRUE)
#' htc_download()
#' ```
#'
#' @section Glob patterns:
#' When using `files` directly, glob patterns are passed to the remote
#' shell for evaluation so they match files on the submit node, not on
#' your local machine. The pattern is single-quoted in the `scp` command
#' to prevent local shell expansion.
#'
#' @section SSH connection reuse:
#' Each call to `htc_download()` opens a new SSH connection. If you have
#' not configured ControlMaster in your `~/.ssh/config`, this will trigger
#' a Duo MFA prompt. Run [htc_config()] for setup guidance.
#'
#' @export
#'
#' @examples
#' \donttest{
#' # Preview the scp command without connecting to CHTC
#' cfg <- list(username = "netid", server = "ap2002.chtc.wisc.edu")
#' htc_download(files = "*.tar.gz", config = cfg, dry_run = TRUE)
#' }
#'
#' \dontrun{
#' # All remaining examples require a live CHTC connection
#'
#' # Automatic download after a workflow
#' htc_start()
#' htc_gen_submit(...)
#' htc_gen_executable(...)
#' htc_upload(...)
#' job <- htc_submit("job.sub")
#' htc_status(cluster_id = job, watch = TRUE)
#' htc_download()
#'
#' # Download by cluster ID
#' htc_download(cluster_id = "6590895")
#'
#' # Download specific files using globs
#' htc_download(files = "*.tar.gz", local_path = "results/")
#'
#' # Download logs only
#' htc_download(files = c("*.log", "*.err", "*.out"), local_path = "logs/")
#' }
htc_download <- function(files       = NULL,
                         cluster_id  = NULL,
                         remote_path = "~/",
                         local_path  = ".",
                         config      = NULL,
                         dry_run     = FALSE,
                         verbose     = FALSE) {

    # -- 1. Resolve config (explicit argument or session option) ----------------
    config <- .resolve_config(config)

    # -- 2. Resolve files from manifest if not supplied -------------------------
    if (is.null(files)) {
        manifest <- .get_manifest()

        # Resolve cluster_id: explicit > manifest > error
        if (is.null(cluster_id)) {
            cluster_id <- manifest$cluster_id
        }

        if (is.null(cluster_id) && is.null(manifest)) {
            cli::cli_abort(c(
                "No files specified and no job manifest found.",
                "i" = "Either supply {.arg files} directly, or run the full",
                " " = "  workflow ({.fn htc_gen_submit}, {.fn htc_gen_executable},",
                " " = "  {.fn htc_submit}) so the manifest is available."
            ))
        }

        if (is.null(cluster_id)) {
            cli::cli_abort(c(
                "No {.arg cluster_id} supplied and none found in the job manifest.",
                "i" = "Pass the cluster ID returned by {.fn htc_submit}, or",
                " " = "  re-run the workflow so the manifest is populated."
            ))
        }

        files <- .resolve_download_files(cluster_id, manifest)

        if (verbose) {
            cli::cli_inform(
                "Resolved {length(files)} file{?s} from job manifest for cluster {.val {cluster_id}}."
            )
        }
    }

    # -- 3. Validate files -----------------------------------------------------
    if (length(files) == 0) {
        cli::cli_abort(
            "{.arg files} must be supplied and cannot be empty."
        )
    }

    # -- 4. Validate local_path ------------------------------------------------
    if (!dir.exists(local_path)) {
        cli::cli_abort(c(
            "Local directory {.path {local_path}} does not exist.",
            "i" = "Create it first with {.code dir.create({deparse(local_path)})}."
        ))
    }

    # -- 5. Validate remote_path -----------------------------------------------
    if (!grepl("/$", remote_path)) {
        remote_path <- paste0(remote_path, "/")
    }

    # -- 6. Build scp arguments ------------------------------------------------
    remote_sources <- vapply(files, \(f) {
        has_glob <- grepl("[*?\\[]", f)
        remote   <- paste0(config$username, "@", config$server, ":", remote_path, f)
        if (has_glob) paste0("'", remote, "'") else remote
    }, character(1L), USE.NAMES = FALSE)

    scp_args <- c(remote_sources, local_path)

    # -- 7. dry_run or execute -------------------------------------------------
    if (dry_run) {
        cmd <- paste("scp", paste(scp_args, collapse = " "))
        cli::cli_inform(c(
            "v" = "Dry run -- command that would be executed:",
            " " = "  {.code {cmd}}"
        ))
        return(invisible(NULL))
    }

    if (verbose) {
        cli::cli_inform(
            "Downloading {length(files)} file{?s} from {.val {config$server}}:{remote_path} to {.path {local_path}}..."
        )
    }

    exit_code <- system2("scp", args = scp_args, stdout = FALSE, stderr = FALSE)

    if (exit_code != 0L) {
        cli::cli_abort(c(
            "scp failed with exit code {exit_code}.",
            "i" = "Check that the files exist on the submit node and that",
            " " = "  your connection to {.val {config$server}} is active.",
            "i" = "Run {.fn htc_status} to verify job completion before",
            " " = "  downloading results."
        ))
    }

    cli::cli_alert_success(
        "Downloaded {length(files)} file{?s} from {.val {config$server}}:{remote_path} to {.path {local_path}}"
    )

    invisible(NULL)
}


#' Resolve file list from job manifest and cluster ID
#'
#' Internal helper that constructs the list of files to download based on
#' the job mode, output file pattern, subset names, and cluster ID.
#'
#' @param cluster_id A character string. The HTCondor cluster ID.
#' @param manifest A named list from `.get_manifest()`.
#'
#' @return A character vector of filenames to download.
#'
#' @keywords internal
.resolve_download_files <- function(cluster_id, manifest) {

    files <- character(0)
    mode <- if (is.null(manifest$mode)) "single" else manifest$mode

    # -- Result tarballs -------------------------------------------------------
    if (mode == "multiple" && !is.null(manifest$subsets)) {
        # Per-subset tarballs: adelie.csv-results.tar.gz, etc.
        tarball_pattern <- if (is.null(manifest$output_files))
                                "$(file)-results.tar.gz"
                            else
                                manifest$output_files
        for (subset in manifest$subsets) {
            tarball <- gsub("$(file)", subset, tarball_pattern, fixed = TRUE)
            files <- c(files, tarball)
        }
    } else if (!is.null(manifest$output_files)) {
        # Single mode: use the output_files directly
        files <- c(files, manifest$output_files)
    }

    # -- Log files -------------------------------------------------------------
    if (mode == "multiple" && !is.null(manifest$subsets)) {
        n_jobs <- length(manifest$subsets)
        for (i in seq_len(n_jobs) - 1L) {
            files <- c(
                files,
                paste0(cluster_id, "-", i, "-job.log"),
                paste0(cluster_id, "-", i, "-job.err"),
                paste0(cluster_id, "-", i, "-job.out")
            )
        }
    } else {
        # Single mode: one set of logs
        files <- c(
            files,
            paste0(cluster_id, "-0-job.log"),
            paste0(cluster_id, "-0-job.err"),
            paste0(cluster_id, "-0-job.out")
        )
    }

    files
}
