#' Generate an HTCondor executable shell script for an R job
#'
#' `htc_gen_executable()` writes a ready-to-use bash script (`.sh`) that
#' HTCondor runs inside the container for each job. The script changes to
#' HTCondor's writable scratch directory, creates an output folder, runs
#' the R script via `Rscript`, and compresses the results into a tarball
#' for transfer back to the submit node.
#'
#' @param output_file A character string or `NULL`. Name of the shell script
#'   to write. Must end in `".sh"`. When `NULL` (the default), resolves to
#'   the `executable_file` recorded in the job manifest by a previous
#'   [htc_gen_submit()] call (S-I3), so the name only has to be typed once
#'   regardless of which of the two generators runs first. Falls back to
#'   `"job.sh"` if neither an explicit value nor a manifest value is
#'   available. If the resolved value disagrees with an `executable_file`
#'   already in the manifest, warns rather than silently preferring one
#'   over the other.
#' @param r_script A character string. Name of the R script that HTCondor
#'   will run, e.g. `"analysis.R"`. Must be supplied explicitly -- there is
#'   no default. If you used `toolero::create_qmd(use_purl = TRUE)`, the
#'   script is the `.R` file produced by `purl.R` after rendering. The
#'   script itself is **not** baked into the container image -- it travels
#'   to the execute node as an uploaded job input file (see
#'   `transfer_input_files` in [htc_gen_submit()]), so editing it only
#'   requires re-uploading and resubmitting, never a container rebuild.
#'   Because HTCondor's file transfer does not preserve subdirectories,
#'   only the file's basename is used inside the script; if you pass
#'   `r_script = "R/analysis.R"`, make sure `"analysis.R"` (not the `R/`
#'   path) is what actually lands in `input_files` for [htc_gen_submit()].
#' @param data_files A character vector or `NULL`. Paths to data files
#'   baked into the container that should be passed to the R script as
#'   positional arguments. These are converted to absolute paths inside
#'   the container (e.g. `"data-raw/sample.csv"` becomes
#'   `"/home/data-raw/sample.csv"`). The R script receives them via
#'   `commandArgs(trailingOnly = TRUE)`. Defaults to `NULL`.
#' @param results_folder A character string or `NULL`. Name of the folder
#'   created in the scratch directory to hold job outputs before
#'   compression. When `NULL` (the default), resolves to
#'   `config$project$conventions$output_dir` when `config` is supplied
#'   (S-G5), falling back to `"output"`, the output folder used across the
#'   toolero family, when neither is available. Note that only this folder
#'   is created: if your analysis writes to `output/figures/`, the R script
#'   must create that subfolder itself, which `toolero::save_output()` does
#'   and a bare `ggsave()` does not.
#' @param home_dir A character string. The working directory inside the
#'   container where baked-in `data_files` live. Used to construct
#'   absolute paths for data file arguments only -- it has no effect on
#'   where `r_script` is read from, since the R script is not baked into
#'   the image. Must match the `home_dir` used in
#'   `containr::generate_dockerfile()` for `data_files`. Defaults to
#'   `"/home"`.
#' @param mode A character string. Execution mode. `"single"` (the default)
#'   runs the R script with only the data file arguments (if any),
#'   producing a tarball named after the script alone. `"multiple"` also
#'   passes the subset filename as the first positional argument via
#'   `${1}`, producing a per-job tarball that adds the subset's own stem,
#'   so `analysis.R` over `adelie.csv` gives
#'   `analysis-adelie-results.tar.gz`. Must match the `mode` used in
#'   [htc_gen_submit()], which has to declare the same name in
#'   `transfer_output_files`.
#' @param verbose Logical. If `TRUE`, prints progress messages as each
#'   section of the script is written. Defaults to `FALSE`.
#' @param comments Logical. If `TRUE`, annotates each section with an
#'   explanatory comment describing what the line does. Useful for
#'   researchers learning the HTCondor executable script conventions.
#'   Defaults to `FALSE`.
#' @param set_executable Logical. If `TRUE`, sets executable permissions on
#'   the generated script via `Sys.chmod()` so the file is ready to copy to
#'   the CHTC submit node without any additional steps. Defaults to `TRUE`.
#'   Set to `FALSE` if you prefer to manage permissions manually, in which
#'   case you must run `chmod +x` on the script before submitting your job.
#' @param output A character string. Directory where the shell script will
#'   be written. Defaults to `"."` (current working directory).
#' @param config A named list as returned by [htc_config()], or `NULL` (the
#'   default). When supplied with a `project` element (via
#'   `htc_config(project_config = )`), `config$project$conventions$output_dir`
#'   is used to default `results_folder` (S-G5). Not required -- everything
#'   here can still be passed explicitly.
#' @param path A character string. Directory where the job manifest
#'   (`htc-manifest.yaml`) is read from and written to. Defaults to `"."`
#'   (the current working directory), matching the default used by
#'   [htc_upload()], [htc_submit()], and [htc_download()]. This is
#'   independent of `output`: if you write generated files to a subfolder
#'   with `output`, pass the same `path` explicitly to every function in
#'   the pipeline so they all find the same manifest.
#'
#' @return Called for its side effects. Writes a bash script to
#'   `file.path(output, output_file)` and sets executable permissions when
#'   `set_executable = TRUE`. Returns `invisible(NULL)`.
#'
#' @section How file paths work inside the container:
#' The generated script draws on two different sources for its inputs,
#' and reads each one a different way:
#'
#' **The R script** -- `r_script` is not baked into the container image.
#' It travels to the execute node as an uploaded job input file, listed in
#' `transfer_input_files` by [htc_gen_submit()]. HTCondor's file transfer
#' does not preserve subdirectories, so whatever you pass as `r_script`
#' lands flat, by basename, in the scratch directory alongside the
#' executable script itself. The `Rscript` line therefore refers to it by
#' a bare relative name (e.g. `Rscript analysis.R`), not an absolute,
#' `home_dir`-prefixed path. This is deliberate: editing the analysis
#' script only requires re-uploading it and resubmitting the job, with no
#' container rebuild or registry push in between.
#'
#' **Data files** -- `data_files` are the opposite case: they are baked
#' into the container at build time by `containr::generate_dockerfile()`
#' and live under `home_dir` (default `"/home"`). The `Rscript` line
#' passes these as absolute paths (e.g. `/home/data-raw/sample.csv`) so
#' they are found regardless of the working directory. Baking data in
#' rather than uploading it keeps large or unchanging reference data out
#' of every job's file transfer.
#'
#' **Writing** -- the script changes to HTCondor's scratch directory
#' (`_CONDOR_SCRATCH_DIR`) before creating the output folder. This
#' directory is writable and is where HTCondor looks for
#' `transfer_output_files`. The R script writes outputs to `"output/"`
#' using a relative path, which resolves to the scratch directory.
#'
#' This separation means the R script stays portable -- `"output/"` works
#' in RStudio, in `quarto render`, and on HTCondor -- while the `.sh`
#' script handles the HTCondor-specific directory setup.
#'
#' @section Relationship to htc_gen_submit():
#' The executable script generated by `htc_gen_executable()` is the file
#' referenced by the `executable` argument in [htc_gen_submit()]. The two
#' functions should always use the same `mode`. In `"multiple"` mode,
#' HTCondor passes each subset filename to the script as `${1}`, which is
#' forwarded to the R script as a positional argument. The R script must
#' be written to accept this argument -- the recommended approach is
#' `toolero::detect_execution_context()`:
#'
#' ```r
#' context <- toolero::detect_execution_context()
#'
#' input_file <- switch(context,
#'   interactive = "data-raw/sample.csv",
#'   quarto      = params$input_file,
#'   rscript     = commandArgs(trailingOnly = TRUE)[1]
#' )
#' ```
#'
#' @export
#'
#' @examples
#' # output writes the generated .sh file; path is where the job manifest
#' # (htc-manifest.yaml) gets read from and written to. The two are
#' # independent arguments (see @param path), so both must point at the
#' # same scratch directory here to keep the manifest out of the current
#' # working directory.
#' tmp <- tempdir()
#'
#' # Single-job executable script with baked-in data
#' htc_gen_executable(
#'   r_script   = "R/analysis.R",
#'   data_files = "data-raw/sample.csv",
#'   output     = tmp,
#'   path       = tmp
#' )
#'
#' # Multiple-job executable script
#' htc_gen_executable(
#'   r_script = "R/analysis.R",
#'   mode     = "multiple",
#'   output   = tmp,
#'   path     = tmp
#' )
#'
#' # Custom names with annotations
#' htc_gen_executable(
#'   output_file = "run.sh",
#'   r_script    = "R/run-analysis.R",
#'   data_files  = c("data-raw/train.csv", "data-raw/test.csv"),
#'   comments    = TRUE,
#'   verbose     = TRUE,
#'   output      = tmp,
#'   path        = tmp
#' )
htc_gen_executable <- function(output_file    = NULL,
                               r_script       = NULL,
                               data_files     = NULL,
                               results_folder = NULL,
                               home_dir       = "/home",
                               mode           = "single",
                               set_executable = TRUE,
                               verbose        = FALSE,
                               comments       = FALSE,
                               output         = ".",
                               config         = NULL,
                               path           = ".") {

    # -- 1. Validate r_script --------------------------------------------------
    if (is.null(r_script)) {
        cli::cli_abort(c(
            "{.arg r_script} must be supplied.",
            "i" = "Pass the name of the R script that HTCondor will run,",
            " " = "  e.g. {.code r_script = \"analysis.R\"}.",
            "i" = "If you used {.fn toolero::create_qmd} with",
            " " = "  {.code use_purl = TRUE}, the script is the {.code .R}",
            " " = "  file produced by {.code purl.R} after rendering."
        ))
    }

    # -- 1b. Read the job manifest once, up front -------------------------------
    manifest <- .get_manifest(path = path)

    # -- 1c. Resolve output_file from the job manifest if not supplied (S-I3) --
    # Explicit argument > the executable_file a previous htc_gen_submit()
    # call recorded in the manifest > the hardcoded "job.sh" default.
    if (is.null(output_file)) {
        output_file <- manifest$executable_file
    } else if (!is.null(manifest$executable_file) &&
               !identical(output_file, manifest$executable_file)) {
        cli::cli_warn(c(
            "{.arg output_file} ({.val {output_file}}) does not match the",
            " " = "  executable script name already recorded in the job",
            " " = "  manifest ({.val {manifest$executable_file}}).",
            "i" = "That name came from an earlier {.fn htc_gen_submit} call.",
            "i" = "If this is deliberate, ignore this warning -- this script",
            " " = "  will be written as {.val {output_file}}. Otherwise, check",
            " " = "  that the two calls agree on the script's name."
        ))
    }
    if (is.null(output_file)) {
        output_file <- "job.sh"
    }

    # -- 1d. Resolve results_folder from project conventions if not supplied ---
    # (S-G5) Explicit argument > config$project$conventions$output_dir >
    # the hardcoded "output" default used across the toolero family.
    if (is.null(results_folder)) {
        results_folder <- config$project$conventions$output_dir
    }
    if (is.null(results_folder)) {
        results_folder <- "output"
    }

    # -- 2. Validate output_file -----------------------------------------------
    if (!grepl("\\.sh$", output_file)) {
        cli::cli_abort(c(
            "{.arg output_file} must end in {.val .sh}.",
            "i" = "Got {.val {output_file}}."
        ))
    }

    # -- 3. Validate output directory ------------------------------------------
    if (!dir.exists(output)) {
        cli::cli_abort(
            "Output directory {.path {output}} does not exist."
        )
    }

    # -- 4. Validate mode ------------------------------------------------------
    mode <- match.arg(mode, choices = c("single", "multiple"))

    # -- 5. Resolve the R script and data file paths ---------------------------
    # r_script is uploaded as a job input file, not baked into the image, and
    # HTCondor's file transfer does not preserve subdirectories -- it lands
    # flat, by basename, in the scratch directory. So the Rscript line refers
    # to it by a bare relative name, never an absolute, home_dir-prefixed
    # path. data_files, by contrast, are baked into the container under
    # home_dir at build time, so those keep their absolute paths.
    local_r_script <- basename(r_script)

    abs_data_files <- if (!is.null(data_files)) {
        file.path(home_dir, data_files)
    } else {
        NULL
    }

    # -- 5b. Resolve the results tarball name ----------------------------------
    # Built outside the section list because ${1%.*} contains braces, which
    # glue would try to interpolate. The submit file has to declare the same
    # name in transfer_output_files, and builds it from the same helper with
    # $Fn(file) in place of ${1%.*}.
    script_stem <- .script_stem(r_script)
    tarball     <- if (mode == "single") {
        .tarball_name(script_stem)
    } else {
        .tarball_name(script_stem, "${1%.*}")
    }

    # -- 6. Assemble script sections -------------------------------------------

    sections <- list(

        # The shebang carries no comment of its own, and that is deliberate
        # rather than an oversight. The write loop below emits a section's
        # comment before its lines, so any comment attached here would push
        # #!/bin/bash onto line two, where the kernel never looks for it --
        # the script would then run under whatever shell happened to invoke
        # it. Keeping the section comment-free is what guarantees the shebang
        # stays on line one under every combination of arguments.
        shebang = list(
            verbose_msg = "Writing shebang line",
            comment     = NULL,
            lines       = "#!/bin/bash"
        ),

        # The comment that used to sit on the shebang section belongs here
        # anyway: it describes set -euo pipefail, not #!/bin/bash.
        shell_options = list(
            verbose_msg = "Writing shell options",
            comment     = "# Exit immediately on errors, undefined variables, or pipe failures.",
            lines       = c("set -euo pipefail", "")
        ),

        permissions = list(
            verbose_msg = NULL,
            comment     = paste0(
                "# This script requires executable permissions before it can be submitted.\n",
                "# By default, htc_gen_executable() sets these permissions automatically\n",
                "# via Sys.chmod() -- so if you used set_executable = TRUE (the default),\n",
                "# you are already good to go and can copy this file directly to CHTC.\n",
                "# If you called the function with set_executable = FALSE, you must run\n",
                "#   chmod +x ", output_file, "\n",
                "# on the script before staging and submitting your job. Without this step,\n",
                "# HTCondor will fail to run the script with a 'permission denied' error."
            ),
            lines       = NULL
        ),

        workdir = list(
            verbose_msg = "Writing working directory change",
            comment     = paste0(
                "# Change to HTCondor's writable scratch directory. The R script\n",
                "# was transferred in and lands here directly; any data files baked\n",
                "# into the image are read from ", home_dir, " using absolute paths.\n",
                "# Outputs are written here using relative paths. This directory is\n",
                "# where HTCondor looks for transfer_output_files."
            ),
            lines       = c('cd "${_CONDOR_SCRATCH_DIR:-$PWD}"', "")
        ),

        results_dir = list(
            verbose_msg = "Writing results folder creation",
            comment     = paste0(
                "# Create a folder to collect all output files produced by the job.\n",
                "# The R script writes outputs to this folder using a relative path\n",
                "# (e.g. file.path(\"", results_folder, "\", \"results.csv\")).\n",
                "# The folder is compressed into a tarball after the script finishes."
            ),
            lines       = glue::glue("mkdir -p {results_folder}")
        ),

        execute = list(
            verbose_msg = glue::glue(
                "Writing Rscript execution line (mode: {mode})"
            ),
            comment     = if (mode == "single") {
                paste0(
                    "# Run the R script, transferred in flat alongside this executable,\n",
                    "# with absolute paths to any baked-in data files. The script's\n",
                    "# working directory is the scratch directory, so any outputs\n",
                    "# written to relative paths (e.g. \"", results_folder, "/\")\n",
                    "# land in the scratch directory where HTCondor can transfer them."
                )
            } else {
                paste0(
                    "# Run the R script, transferred in flat alongside this executable.\n",
                    "# ${1} is the first positional argument passed by HTCondor --\n",
                    "# the subset filename substituted from subdatasets.csv.\n",
                    "# The R script receives this as commandArgs(trailingOnly = TRUE)[1].\n",
                    "# Use toolero::detect_execution_context() in your R script to\n",
                    "# handle this argument correctly across all execution contexts."
                )
            },
            lines       = if (mode == "single") {
                rscript_parts <- local_r_script
                if (!is.null(abs_data_files)) {
                    rscript_parts <- c(rscript_parts, abs_data_files)
                }
                paste("Rscript", paste(rscript_parts, collapse = " "))
            } else {
                paste("Rscript", local_r_script, "${1}")
            }
        ),

        compress = list(
            verbose_msg = "Writing compression line",
            comment     = if (mode == "single") {
                paste0(
                    "# Compress the results folder into a single tarball.\n",
                    "# The tarball is created in the scratch directory where\n",
                    "# HTCondor looks for transfer_output_files."
                )
            } else {
                paste0(
                    "# Compress the results folder into a per-job tarball.\n",
                    "# ${1} is the subset filename and ${1%.*} strips its extension,\n",
                    "# so each job gets a unique archive named after the script and\n",
                    "# its subset (e.g. ", .tarball_name(script_stem, "adelie"), ")\n",
                    "# and results from different jobs do not overwrite each other\n",
                    "# on the submit node. The submit file must declare this same\n",
                    "# name in transfer_output_files."
                )
            },
            lines       = paste("tar -czf", tarball, results_folder)
        )
    )

    # -- 7. Write script -------------------------------------------------------
    script_path <- file.path(output, output_file)
    first <- TRUE
    for (section in sections) {
        if (is.null(section$lines) && is.null(section$comment)) next

        if (verbose && !is.null(section$verbose_msg)) {
            cli::cli_inform(section$verbose_msg)
        }
        if (comments && !is.null(section$comment)) {
            readr::write_lines(section$comment,
                               file   = script_path,
                               append = !first)
            first <- FALSE
        }
        if (!is.null(section$lines)) {
            readr::write_lines(section$lines,
                               file   = script_path,
                               append = !first)
            first <- FALSE
        }
    }

    # -- 8. Set executable permissions ----------------------------------------
    if (set_executable) {
        Sys.chmod(script_path, mode = "0755")
        if (verbose) {
            cli::cli_inform(
                "Set executable permissions on {.path {script_path}}"
            )
        }
    }

    if (verbose) {
        cli::cli_alert_success(
            "Executable script written to {.path {file.path(output, output_file)}}"
        )
    }
    # Record the script and results folder, plus both views of the executable
    # itself: the bare name HTCondor will see, and the local path
    # htc_upload() needs in order to find it on this machine.
    .update_manifest(
        r_script        = r_script,
        data_files      = data_files,
        results_folder  = results_folder,
        executable_file = output_file,
        executable_path = .join_output_path(output, output_file),
        path            = path
    )

    invisible(NULL)
}
