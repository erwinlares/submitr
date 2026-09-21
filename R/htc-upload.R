#' Upload files to an HTC submit node
#'
#' `htc_upload()` copies one or more local files or directories to a
#' directory on an HTC submit node via `scp`. It is the first step in the
#' job submission workflow -- files must be present on the submit node before
#' `htc_submit()` can run `condor_submit`.
#'
#' @param files A character vector or `NULL`. One or more local file paths or
#'   directory paths to copy to the submit node. A single file, a vector of
#'   files, and a directory path are all accepted. Directories are copied
#'   recursively. When `NULL` (the default), the function resolves the files
#'   to upload from the job manifest built up by [htc_gen_submit()] and
#'   [htc_gen_executable()]: the submit file, the executable script, any
#'   shared input files, and -- in `"multiple"` mode -- the subdatasets
#'   manifest and the individual subset data files.
#' @param remote_path A character string. The destination directory on the
#'   submit node. Defaults to `"~/"` (the user's home directory). This should
#'   match the path used in the subsequent call to [htc_submit()].
#' @param config A named list as returned by [htc_config()]. Must contain
#'   `username` and `server`. If `NULL` (the default), uses the session
#'   config set by [htc_start()]. If no session config is set,
#'   the function errors with instructions.
#' @param dry_run Logical. If `TRUE`, prints the `scp` command that would be
#'   executed without running it. Useful for verifying the command before
#'   transferring files. Defaults to `FALSE`.
#' @param verbose Logical. If `TRUE`, prints progress messages. Defaults to
#'   `FALSE`.
#' @param path A character string. Directory holding the job manifest
#'   (`htc-manifest.yaml`), consulted only when `files` is `NULL`. Defaults
#'   to `"."`, which matches the generator functions' own default. If you
#'   passed a non-default `output` or `path` to [htc_gen_submit()] and
#'   [htc_gen_executable()], pass that same directory here.
#'
#' @return Called for its side effects. Returns `invisible(NULL)`.
#'
#' @section Workflow:
#' `htc_upload()` is the first system-facing step in the submitr workflow.
#' Call it after generating your submit file and executable script with
#' [htc_gen_submit()] and [htc_gen_executable()], and before calling
#' [htc_submit()].
#'
#' The typical sequence relies on automatic resolution from the job
#' manifest, so `files` can usually be omitted:
#'
#' ```r
#' cfg <- htc_config()
#'
#' htc_gen_submit(executable = "job.sh", input_files = "analysis.R")
#' htc_gen_executable(r_script = "analysis.R")
#'
#' htc_upload(config = cfg)
#'
#' htc_submit(submit_file = "job.sub", config = cfg)
#' ```
#'
#' Pass `files` explicitly to upload a specific set of files instead:
#'
#' ```r
#' htc_upload(
#'   files  = c("job.sub", "job.sh", "analysis.R", "data.csv"),
#'   config = cfg
#' )
#' ```
#'
#' @section SSH connection reuse:
#' Each call to `htc_upload()` opens a new SSH connection. If you have not
#' configured ControlMaster in your `~/.ssh/config`, this will trigger a
#' Duo MFA prompt. Run [htc_config()] for setup guidance.
#'
#' @export
#'
#' @examples
#' \donttest{
#' # Preview the scp command without connecting to CHTC
#' cfg <- list(username = "netid", server = "ap2002.chtc.wisc.edu")
#' tmp <- tempfile(fileext = ".sub")
#' writeLines("queue 1", tmp)
#' htc_upload(files = tmp, config = cfg, dry_run = TRUE)
#' }
#'
#' \dontrun{
#' # All remaining examples require a live CHTC connection
#' cfg <- htc_config()
#'
#' # Resolve files automatically from the job manifest
#' htc_gen_submit(executable = "job.sh", input_files = "analysis.R")
#' htc_gen_executable(r_script = "analysis.R")
#' htc_upload(config = cfg)
#'
#' # Upload a single file
#' htc_upload(files = "job.sub", config = cfg)
#'
#' # Upload multiple files
#' htc_upload(
#'   files  = c("job.sub", "job.sh", "analysis.R"),
#'   config = cfg
#' )
#'
#' # Upload a directory
#' htc_upload(files = "jobs/", config = cfg)
#'
#' # Upload to a specific remote directory
#' htc_upload(
#'   files       = c("job.sub", "job.sh"),
#'   remote_path = "~/projects/penguins/",
#'   config      = cfg
#' )
#' }
htc_upload <- function(files       = NULL,
                       remote_path = "~/",
                       config      = NULL,
                       dry_run     = FALSE,
                       verbose     = FALSE,
                       path        = ".") {

    # -- 1. Resolve config (explicit argument or session option) ----------------
    config <- .resolve_config(config)

    # -- 2. Resolve files from the job manifest if not supplied ----------------
    if (is.null(files)) {
        manifest <- .get_manifest(path = path)
        files <- .resolve_upload_files(manifest)

        if (length(files) > 0 && verbose) {
            cli::cli_inform(
                "Resolved {length(files)} file{?s} from the job manifest."
            )
        }
    }

    # -- 3. Validate files -------------------------------------------------------
    if (length(files) == 0) {
        cli::cli_abort(c(
            "{.arg files} must be supplied and cannot be empty.",
            "i" = "Pass {.arg files} directly, or run {.fn htc_gen_submit} and",
            " " = "  {.fn htc_gen_executable} first so the job manifest can",
            " " = "  resolve them automatically.",
            "i" = "Looked for a manifest in {.path {path}}."
        ))
    }

    missing_files <- files[!file.exists(files)]
    if (length(missing_files) > 0) {
        cli::cli_abort(c(
            "{length(missing_files)} file{?s} do not exist:",
            "x" = "{.path {missing_files}}"
        ))
    }

    # -- 4. Validate remote_path -----------------------------------------------
    if (!grepl("/$", remote_path)) {
        remote_path <- paste0(remote_path, "/")
    }

    # -- 5. Build scp command --------------------------------------------------
    # Directories are copied recursively via -r flag
    has_dirs <- any(file.info(files)$isdir)
    scp_flags <- if (has_dirs) c("-r") else character(0)

    destination <- paste0(config$username, "@", config$server, ":", remote_path)

    scp_args <- c(scp_flags, files, destination)

    # -- 6. dry_run or execute -------------------------------------------------
    if (dry_run) {
        cmd <- paste("scp", paste(scp_args, collapse = " "))
        cli::cli_inform(c(
            "v" = "Dry run -- command that would be executed:",
            " " = "  {.code {cmd}}"
        ))
        return(invisible(NULL))
    }

    if (verbose) {
        n <- length(files)
        cli::cli_inform(
            "Uploading {n} file{?s} to {.val {config$server}}:{remote_path}..."
        )
    }

    exit_code <- system2("scp", args = scp_args, stdout = FALSE, stderr = FALSE)

    if (exit_code != 0L) {
        cli::cli_abort(c(
            "scp failed with exit code {exit_code}.",
            "i" = "Check your network connection and ensure ControlMaster",
            " " = "  is active. Run {.fn htc_config} for setup guidance."
        ))
    }

    cli::cli_alert_success(
        "Uploaded {length(files)} file{?s} to {.val {config$server}}:{remote_path}"
    )

    invisible(NULL)
}


#' Resolve files to upload from the job manifest
#'
#' Internal helper used by `htc_upload()` when `files = NULL`. Builds the
#' list of local files to copy to the submit node from the job manifest
#' accumulated by [htc_gen_submit()] and [htc_gen_executable()]: the submit
#' file, the executable script, any shared input files, and -- in
#' `"multiple"` mode -- the subdatasets manifest and the individual subset
#' data files.
#'
#' Every field used here holds a path as seen from the machine running R,
#' not the bare name HTCondor sees on the submit node. That distinction
#' matters when the generators wrote into a non-default `output` directory:
#' `submit_file` is `"job.sub"` but `submit_path` is `"jobs/job.sub"`, and
#' only the latter will survive `file.exists()`.
#'
#' @param manifest A named list from `.get_manifest()`, or `NULL`.
#'
#' @return A character vector of local file paths to upload, possibly empty.
#'
#' @keywords internal
.resolve_upload_files <- function(manifest) {
    if (is.null(manifest)) {
        return(character(0))
    }

    files <- c(
        manifest$submit_path,
        manifest$executable_path,
        manifest$input_files
    )

    if (identical(manifest$mode, "multiple")) {
        files <- c(files, manifest$subdatasets_path, manifest$subset_files)
    }

    if (length(files) == 0L) {
        return(character(0))
    }

    unique(as.character(files))
}
