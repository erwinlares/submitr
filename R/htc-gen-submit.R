#' Generate an HTCondor submit file for a containerized R job
#'
#' `htc_gen_submit()` writes a ready-to-use HTCondor submit file (`.sub`)
#' for running a containerized R job on an HTC cluster such as CHTC. It
#' supports both single-job and multiple-job submission modes.
#' @param output_file A character string. Name of the submit file to write.
#'   Must end in `".sub"`. Defaults to `"job.sub"`.
#' @param container_image A character string. The container image to use,
#' @param container_image A character string. The container image to use,
#'   e.g. `"registry.doit.wisc.edu/netid/myimage"`. The `docker://` prefix
#'   is added automatically if not already present. Defaults to `NULL`,
#'   which writes a placeholder comment in the submit file.
#' @param executable A character string. The shell script that HTCondor will
#'   run inside the container, e.g. `"analysis.sh"`. Defaults to `NULL`,
#'   which writes a placeholder comment in the submit file.
#' @param input_files A character vector. Files to transfer to the job's
#'   working directory before execution, e.g. `c("analysis.R", "data.csv")`.
#'   In `"multiple"` mode, the per-job subset file is added automatically
#'   from the manifest; use this argument for files shared across all jobs
#'   (e.g. the analysis script). Defaults to `NULL`.
#' @param output_files A character vector. Files to transfer back from the
#'   job's working directory after execution. In `"multiple"` mode, this
#'   defaults to `"$(file)-results.tar.gz"` if not supplied. Defaults to
#'   `NULL`.
#' @param mode A character string. Submission mode. `"single"` (the default)
#'   submits one job. `"multiple"` submits one job per row in the manifest
#'   supplied to `queue_from`, passing each subset file as a positional
#'   argument to the executable via `arguments = $(file)`.
#' @param queue A positive integer. Number of identical jobs to submit.
#'   Only used when `mode = "single"`. Defaults to `1`.
#' @param queue_from A character string. Path to the manifest file produced
#'   by `toolero::write_by_group(manifest = TRUE)`. Required when
#'   `mode = "multiple"`. The `file_path` column is extracted and written
#'   alongside the submit file as `subdatasets.csv`, which HTCondor reads
#'   to generate one job per subset file.
#' @param resources A character string. Compute resource preset. One of
#'   `"small"`, `"medium"`, `"large"`, or `"custom"` (requires
#'   `custom_resources`). Default preset values reflect CHTC recommendations
#'   and are loaded from `inst/extdata/htc-resources.yaml`. A local
#'   `htc-resources.yaml` in the working directory takes precedence over the
#'   package default, allowing per-project customization. Defaults to
#'   `"small"`.
#' @param custom_resources A named list. Required when `resources = "custom"`.
#'   Must contain `cpus` (integer), `memory` (character, e.g. `"8GB"`), and
#'   `disk` (character, e.g. `"4GB"`). Ignored when `resources` is not
#'   `"custom"`.
#' @param gpu Logical. If `TRUE`, adds GPU resource requests to the submit
#'   file. Defaults to `FALSE`.
#' @param gpu_options A named list or `NULL`. Fine-grained GPU options applied
#'   when `gpu = TRUE`. Supported keys: `request_gpus` (integer, default
#'   `1`), `want_gpu_lab` (logical, default `TRUE`), `min_capability`
#'   (numeric, e.g. `8.0` for A100; `NULL` to omit), `min_memory_mb`
#'   (integer in MB, e.g. `40000`; `NULL` to omit). When `gpu = TRUE` and
#'   `gpu_options = NULL`, CHTC defaults are used.
#' @param verbose Logical. If `TRUE`, prints progress messages as each
#'   section of the submit file is written. Defaults to `FALSE`.
#' @param comments Logical. If `TRUE`, annotates each section with an
#'   explanatory comment describing what the section does and how to use it.
#'   Defaults to `FALSE`.
#' @param output A character string. Directory where the submit file (and,
#'   in `"multiple"` mode, `subdatasets.csv`) will be written. Defaults to
#'   `"."` (current working directory).
#'
#' @return Called for its side effects. Writes an HTCondor submit file to
#'   `file.path(output, output_file)`. In `"multiple"` mode also writes
#'   `subdatasets.csv` to `output`. Returns `invisible(NULL)`.
#'
#' @section Multiple-job mode and positional arguments:
#' When `mode = "multiple"`, HTCondor passes each subset filename to the
#' executable as a positional argument via `arguments = $(file)`. Your R
#' script must be written to accept and use this argument. The recommended
#' approach is to use `toolero::detect_execution_context()` in your analysis
#' script, which resolves the input file path correctly across interactive,
#' Quarto, and Rscript execution contexts:
#'
#' ```r
#' context <- toolero::detect_execution_context()
#'
#' input_file <- switch(context,
#'   interactive = "data/penguins.csv",
#'   quarto      = params$input_file,
#'   rscript     = commandArgs(trailingOnly = TRUE)[1]
#' )
#'
#' data <- readr::read_csv(input_file)
#' ```
#'
#' The typical workflow is:
#' 1. Write and develop your analysis in `analysis.qmd` using
#'    `toolero::detect_execution_context()` for data loading.
#' 2. Split your dataset with `toolero::write_by_group(manifest = TRUE)` to
#'    produce subset CSV files and a `manifest.csv`.
#' 3. Strip `analysis.qmd` to `analysis.R` with `knitr::purl()`.
#' 4. Call `htc_gen_submit(mode = "multiple", queue_from = "manifest.csv")`
#'    to produce the submit file and `subdatasets.csv`.
#' 5. Copy `analysis.R`, the subset data files, `analysis.sub`,
#'    `analysis.sh`, and `subdatasets.csv` to CHTC and submit.
#'
#' @section Resource presets:
#' Resource presets are loaded at runtime from `inst/extdata/htc-resources.yaml`.
#' To customize presets for a specific project, copy that file to your project
#' directory as `htc-resources.yaml` and edit the values. `htc_gen_submit()`
#' checks for a local `htc-resources.yaml` in the working directory first,
#' falling back to the package default if none is found.
#'
#' @export
#'
#' @examples
#' # Single-job submit file with default resource preset
#' htc_gen_submit(output = tempdir())
#'
#' # Single-job submit file with medium resources and file transfer
#' htc_gen_submit(
#'   output_file     = "analysis.sub",
#'   container_image = "docker://registry.doit.wisc.edu/netid/myimage",
#'   executable      = "analysis.sh",
#'   input_files     = "analysis.R",
#'   output_files    = "results.tar.gz",
#'   resources       = "medium",
#'   output          = tempdir()
#' )
#'
#' # Annotated submit file useful for learning HTCondor syntax
#' htc_gen_submit(
#'   output_file = "annotated.sub",
#'   comments    = TRUE,
#'   verbose     = TRUE,
#'   output      = tempdir()
#' )
#'
#' # Custom resource request
#' htc_gen_submit(
#'   resources        = "custom",
#'   custom_resources = list(cpus = 2, memory = "8GB", disk = "4GB"),
#'   output           = tempdir()
#' )
#'
#' \dontrun{
#' # Multiple-job submit file driven by a write_by_group() manifest
#' htc_gen_submit(
#'   output_file     = "analysis.sub",
#'   container_image = "docker://registry.doit.wisc.edu/netid/myimage",
#'   executable      = "analysis.sh",
#'   input_files     = "analysis.R",
#'   mode            = "multiple",
#'   queue_from      = "data/manifest.csv",
#'   resources       = "medium",
#'   output          = "."
#' )
#' }
htc_gen_submit <- function(output_file      = "job.sub",
                           container_image  = NULL,
                           executable       = NULL,
                           input_files      = NULL,
                           output_files     = NULL,
                           mode             = "single",
                           queue            = 1L,
                           queue_from       = NULL,
                           resources        = "small",
                           custom_resources = NULL,
                           gpu              = FALSE,
                           gpu_options      = NULL,
                           verbose          = FALSE,
                           comments         = FALSE,
                           output           = ".") {

    # -- 1. Validate output_file -----------------------------------------------
    if (!grepl("\\.sub$", output_file)) {
        cli::cli_abort(c(
            "{.arg output_file} must end in {.val .sub}.",
            "i" = "Got {.val {output_file}}."
        ))
    }

    # -- 2. Validate output directory ------------------------------------------
    if (!dir.exists(output)) {
        cli::cli_abort(
            "Output directory {.path {output}} does not exist."
        )
    }

    # -- 2b. Prepend docker:// to container_image if missing -------------------
    if (!is.null(container_image) && !grepl("^docker://", container_image)) {
        container_image <- paste0("docker://", container_image)
    }

    # -- 3. Validate mode ------------------------------------------------------
    mode <- match.arg(mode, choices = c("single", "multiple"))

    if (mode == "multiple" && is.null(queue_from)) {
        cli::cli_abort(c(
            "{.arg queue_from} must be supplied when {.arg mode} is {.val multiple}.",
            "i" = "Pass the path to a manifest file produced by {.fn toolero::write_by_group}."
        ))
    }

    if (mode == "single" && !is.null(queue_from)) {
        cli::cli_warn(c(
            "{.arg queue_from} is ignored when {.arg mode} is {.val single}.",
            "i" = "Set {.code mode = \"multiple\"} to submit one job per row in the manifest."
        ))
        queue_from <- NULL
    }

    # -- 4. Validate and process queue_from ------------------------------------
    subset_filenames <- NULL

    if (!is.null(queue_from)) {
        if (!file.exists(queue_from)) {
            cli::cli_abort(
                "Manifest file {.path {queue_from}} does not exist."
            )
        }
        manifest <- readr::read_csv(queue_from, show_col_types = FALSE)
        if (!"file_path" %in% names(manifest)) {
            cli::cli_abort(c(
                "Manifest file {.path {queue_from}} must contain a {.val file_path} column.",
                "i" = "Use {.fn toolero::write_by_group} with {.code manifest = TRUE} to produce a compatible manifest."
            ))
        }
        # Extract bare filenames from full paths
        subset_filenames <- basename(manifest[["file_path"]])

        # Write subdatasets.csv alongside the submit file
        subdatasets_path <- file.path(output, "subdatasets.csv")
        readr::write_csv(
            data.frame(file = subset_filenames),
            subdatasets_path,
            col_names = FALSE
        )
        if (verbose) {
            cli::cli_inform(
                "Wrote {length(subset_filenames)} subset filename{?s} to {.path {subdatasets_path}}"
            )
        }
    }

    # -- 5. Validate queue (single mode only) ----------------------------------
    if (mode == "single") {
        if (!is.numeric(queue) || length(queue) != 1 || queue < 1) {
            cli::cli_abort(
                "{.arg queue} must be a positive integer. Got {.val {queue}}."
            )
        }
        queue <- as.integer(queue)
    }

    # -- 6. Validate custom_resources ------------------------------------------
    if (resources == "custom") {
        if (is.null(custom_resources)) {
            cli::cli_abort(c(
                "{.arg custom_resources} must be supplied when {.arg resources} is {.val custom}.",
                "i" = "Provide a named list with {.val cpus}, {.val memory}, and {.val disk}."
            ))
        }
        missing_keys <- setdiff(c("cpus", "memory", "disk"), names(custom_resources))
        if (length(missing_keys) > 0) {
            cli::cli_abort(c(
                "{.arg custom_resources} is missing required key{?s}: {.val {missing_keys}}.",
                "i" = "Supply a named list with {.val cpus}, {.val memory}, and {.val disk}."
            ))
        }
    }

    if (resources != "custom" && !is.null(custom_resources)) {
        cli::cli_warn(c(
            "{.arg custom_resources} is ignored when {.arg resources} is not {.val custom}.",
            "i" = "Set {.code resources = \"custom\"} to use custom resource values."
        ))
    }

    # -- 7. Validate gpu_options -----------------------------------------------
    if (!is.null(gpu_options) && !gpu) {
        cli::cli_warn(c(
            "{.arg gpu_options} is ignored when {.arg gpu} is {.val FALSE}.",
            "i" = "Set {.code gpu = TRUE} to enable GPU resource requests."
        ))
    }

    # -- 8. Resolve resource values --------------------------------------------
    # Check for a local htc-resources.yaml in the working directory first,
    # falling back to the package default in inst/extdata/.
    local_resources_file <- file.path(getwd(), "htc-resources.yaml")
    package_resources_file <- system.file(
        "extdata", "htc-resources.yaml",
        package  = "submitr",
        mustWork = TRUE
    )
    resources_file <- if (file.exists(local_resources_file)) {
        local_resources_file
    } else {
        package_resources_file
    }

    resource_map <- yaml::read_yaml(resources_file)

    resolved_resources <- if (resources == "custom") {
        custom_resources
    } else {
        if (!resources %in% names(resource_map)) {
            cli::cli_abort(c(
                "{.val {resources}} is not a valid resource preset.",
                "i" = "Available presets: {.val {names(resource_map)}}.",
                "i" = "Use {.arg resources = 'custom'} and supply",
                " " = "  {.arg custom_resources} for non-standard values."
            ))
        }
        r <- resource_map[[resources]]
        list(
            cpus   = as.integer(r$cpus),
            memory = r$memory,
            disk   = r$disk
        )
    }

    # -- 9. Resolve GPU options ------------------------------------------------
    resolved_gpu <- if (gpu) {
        defaults <- list(
            request_gpus   = 1L,
            want_gpu_lab   = TRUE,
            min_capability = NULL,
            min_memory_mb  = NULL
        )
        if (!is.null(gpu_options)) {
            for (key in names(gpu_options)) {
                defaults[[key]] <- gpu_options[[key]]
            }
        }
        defaults
    } else {
        NULL
    }

    # -- 10. Resolve transfer lines based on mode ------------------------------
    # In multiple mode, $(file) is the per-job variable HTCondor substitutes
    # from subdatasets.csv. Shared input files (e.g. analysis.R) are listed
    # alongside the per-job file.
    resolved_input_files <- if (mode == "multiple") {
        shared <- if (!is.null(input_files)) {
            paste(input_files, collapse = ", ")
        } else {
            NULL
        }
        if (!is.null(shared)) {
            paste0(shared, ", $(file)")
        } else {
            "$(file)"
        }
    } else {
        if (!is.null(input_files)) paste(input_files, collapse = ", ") else NULL
    }

    resolved_output_files <- if (mode == "multiple") {
        if (!is.null(output_files)) {
            paste(output_files, collapse = ", ")
        } else {
            "$(file)-results.tar.gz"
        }
    } else {
        if (!is.null(output_files)) paste(output_files, collapse = ", ") else NULL
    }

    # -- 11. Assemble submit file sections -------------------------------------
    sections <- list(

        title = list(
            verbose_msg = "Writing submit file header",
            comment     = NULL,
            lines       = c(
                "# HTC Submit File",
                glue::glue("# Generated by submitr on {Sys.Date()}"),
                glue::glue("# Mode: {mode}"),
                ""
            )
        ),

        container = list(
            verbose_msg = "Writing container section",
            comment     = paste0(
                "# The container section tells HTCondor which Docker image to use.\n",
                "# The image must be accessible from the execute node. For CHTC,\n",
                "# use the registry prefix docker:// followed by the full image path.\n",
                "# Example: docker://registry.doit.wisc.edu/your-netid/your-image\n",
                "# universe = container tells HTCondor this is a container job."
            ),
            lines       = c(
                "# Container section",
                if (!is.null(container_image)) {
                    glue::glue("container_image = {container_image}")
                } else {
                    "# container_image = docker://registry.doit.wisc.edu/netid/myimage"
                },
                "universe = container",
                ""
            )
        ),

        executable = list(
            verbose_msg = "Writing executable section",
            comment     = paste0(
                "# The executable section tells HTCondor which script to run inside\n",
                "# the container. This is typically a bash script (.sh) that calls\n",
                "# your R script. The script must be present in the job's working\n",
                "# directory at runtime."
            ),
            lines       = c(
                "# Executable section",
                if (!is.null(executable)) {
                    glue::glue("executable = {executable}")
                } else {
                    "# executable = myjob.sh"
                },
                ""
            )
        ),

        arguments = list(
            verbose_msg = "Writing arguments section",
            comment     = if (mode == "multiple") {
                paste0(
                    "# The arguments section passes each subset filename to the executable\n",
                    "# as a positional argument. HTCondor substitutes $(file) with each\n",
                    "# value from subdatasets.csv, one per job.\n",
                    "# Your R script must read this argument. The recommended approach is\n",
                    "# toolero::detect_execution_context(), which resolves the input file\n",
                    "# correctly whether the script runs interactively, via Quarto, or via\n",
                    "# Rscript on the execute node:\n",
                    "#\n",
                    "#   context <- toolero::detect_execution_context()\n",
                    "#   input_file <- switch(context,\n",
                    "#     interactive = \"data/penguins.csv\",\n",
                    "#     quarto      = params$input_file,\n",
                    "#     rscript     = commandArgs(trailingOnly = TRUE)[1]\n",
                    "#   )"
                )
            } else {
                NULL
            },
            lines       = if (mode == "multiple") {
                c("# Arguments section", "arguments = $(file)", "")
            } else {
                NULL
            }
        ),

        transfer = list(
            verbose_msg = "Writing file transfer section",
            comment     = paste0(
                "# The transfer section tells HTCondor which files to move between\n",
                "# the submit node and the execute node.\n",
                "# transfer_input_files: files to send TO the job before it runs.\n",
                if (mode == "multiple") {
                    paste0(
                        "#   $(file) is substituted per job from subdatasets.csv.\n",
                        "#   List any shared files (e.g. analysis.R) before $(file).\n"
                    )
                } else {
                    "#   Include your R script, data files, and any other inputs.\n"
                },
                "# transfer_output_files: files to retrieve AFTER the job finishes.\n",
                "#   Packaging outputs as a .tar.gz before job completion is recommended."
            ),
            lines       = c(
                "# Transfer section",
                "should_transfer_files   = YES",
                "when_to_transfer_output = ON_EXIT",
                "",
                if (!is.null(resolved_input_files)) {
                    glue::glue("transfer_input_files = {resolved_input_files}")
                } else {
                    "# transfer_input_files = file1, file2"
                },
                if (!is.null(resolved_output_files)) {
                    glue::glue("transfer_output_files = {resolved_output_files}")
                } else {
                    "# transfer_output_files = results.tar.gz"
                },
                ""
            )
        ),

        logging = list(
            verbose_msg = "Writing logging section",
            comment     = paste0(
                "# The logging section tells HTCondor where to write job information.\n",
                "# $(ClusterID) and $(ProcID) are HTCondor macros that uniquely identify\n",
                "# each job submission and job instance. Using them in filenames prevents\n",
                "# log files from being overwritten across resubmissions.\n",
                "# log    -- job lifecycle events, timing, and resource usage summary.\n",
                "#           This is your primary debugging tool.\n",
                "# error  -- standard error (stderr) from your executable, including\n",
                "#           R warnings and error messages.\n",
                "# output -- standard output (stdout) from your executable, including\n",
                "#           print() statements from your R script."
            ),
            lines       = c(
                "# Logging section",
                "log    = $(ClusterID)-$(ProcID)-job.log",
                "error  = $(ClusterID)-$(ProcID)-job.err",
                "output = $(ClusterID)-$(ProcID)-job.out",
                ""
            )
        ),

        resources = list(
            verbose_msg = glue::glue(
                "Writing resources section ({resources} preset: ",
                "{resolved_resources$cpus} CPU / ",
                "{resolved_resources$memory} RAM / ",
                "{resolved_resources$disk} disk)"
            ),
            comment     = paste0(
                "# The resources section tells HTCondor how much compute to allocate.\n",
                "# Request only what your job actually needs -- over-requesting wastes\n",
                "# shared resources and may increase your wait time in the queue.\n",
                "# The log file reports actual usage after each run, which is the best\n",
                "# way to tune these values over time.\n",
                "# request_cpus   -- number of CPU cores\n",
                "# request_memory -- RAM (use GB or MB, e.g. 4GB or 512MB)\n",
                "# request_disk   -- scratch disk space for all files during the job,\n",
                "#                   including executable, inputs, outputs, and temp files"
            ),
            lines       = c(
                glue::glue("# Resources section ({resources} preset)"),
                glue::glue("request_cpus   = {resolved_resources$cpus}"),
                glue::glue("request_memory = {resolved_resources$memory}"),
                glue::glue("request_disk   = {resolved_resources$disk}"),
                ""
            )
        ),

        gpu = list(
            verbose_msg = "Writing GPU section",
            comment     = paste0(
                "# The GPU section requests GPU hardware for your job.\n",
                "# request_gpus           -- number of GPUs to allocate (typically 1)\n",
                "# +WantGPULab            -- opt in to CHTC's shared GPU Lab pool\n",
                "# gpus_minimum_capability -- minimum CUDA compute capability\n",
                "#   (e.g. 8.0 targets A100-class GPUs and newer)\n",
                "# gpus_minimum_memory    -- minimum GPU VRAM in MB\n",
                "#   (e.g. 40000 requests at least 40 GB VRAM)\n",
                "# Note: GPU jobs require a CUDA-enabled container image."
            ),
            lines       = if (!is.null(resolved_gpu)) {
                gpu_lines <- c(
                    "# GPU section",
                    glue::glue("request_gpus = {resolved_gpu$request_gpus}")
                )
                if (isTRUE(resolved_gpu$want_gpu_lab)) {
                    gpu_lines <- c(gpu_lines, "+WantGPULab = true")
                }
                if (!is.null(resolved_gpu$min_capability)) {
                    gpu_lines <- c(
                        gpu_lines,
                        glue::glue("gpus_minimum_capability = {resolved_gpu$min_capability}")
                    )
                }
                if (!is.null(resolved_gpu$min_memory_mb)) {
                    gpu_lines <- c(
                        gpu_lines,
                        glue::glue("gpus_minimum_memory = {resolved_gpu$min_memory_mb}")
                    )
                }
                c(gpu_lines, "")
            } else {
                NULL
            }
        ),

        queue = list(
            verbose_msg = if (mode == "single") {
                glue::glue("Writing queue section ({queue} job{ifelse(queue == 1, '', 's')})")
            } else {
                glue::glue(
                    "Writing queue section ({length(subset_filenames)} job{ifelse(length(subset_filenames) == 1, '', 's')} from manifest)"
                )
            },
            comment     = if (mode == "single") {
                paste0(
                    "# The queue section tells HTCondor how many jobs to submit.\n",
                    "# queue 1 submits a single job. Increase this number to submit\n",
                    "# multiple identical jobs using the $(Process) macro to differentiate\n",
                    "# output files (e.g. output = job.$(Process).out)."
                )
            } else {
                paste0(
                    "# The queue section submits one job per line in subdatasets.csv.\n",
                    "# HTCondor reads each filename into the $(file) variable and\n",
                    "# substitutes it throughout the submit file -- in arguments,\n",
                    "# transfer_input_files, and transfer_output_files.\n",
                    "# subdatasets.csv was generated from the manifest produced by\n",
                    "# toolero::write_by_group(manifest = TRUE)."
                )
            },
            lines       = if (mode == "single") {
                c(
                    "# Queue section",
                    glue::glue("queue {queue}"),
                    ""
                )
            } else {
                c(
                    "# Queue section",
                    "queue file from subdatasets.csv",
                    ""
                )
            }
        )
    )

    # -- 12. Write submit file -------------------------------------------------
    subfile_path <- file.path(output, output_file)
    first <- TRUE

    for (section in sections) {
        if (is.null(section$lines)) next

        if (verbose && !is.null(section$verbose_msg)) {
            cli::cli_inform(section$verbose_msg)
        }

        if (comments && !is.null(section$comment)) {
            readr::write_lines(section$comment,
                               file   = subfile_path,
                               append = !first)
            first <- FALSE
        }

        readr::write_lines(section$lines,
                           file   = subfile_path,
                           append = !first)
        first <- FALSE
    }

    if (verbose) {
        cli::cli_alert_success(
            "Submit file written to {.path {file.path(output, output_file)}}"
        )
    }

    invisible(NULL)
}
