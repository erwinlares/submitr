# tests/testthat/test-htc-gen-submit.R

# ---------------------------------------------------------------------------
# Fixture helpers
# ---------------------------------------------------------------------------

read_subfile <- function(dir, filename = "job.sub") {
    readLines(file.path(dir, filename))
}

# Writes a manifest.csv to dir in the format produced by
# toolero::write_by_group(manifest = TRUE) and returns the manifest path.
.write_manifest <- function(dir,
                            filenames = c("adelie.csv", "gentoo.csv")) {
    manifest_path <- file.path(dir, "manifest.csv")
    readr::write_csv(
        data.frame(
            group_value = tools::file_path_sans_ext(filenames),
            n_rows      = rep(100L, length(filenames)),
            file_path   = file.path(dir, filenames)
        ),
        manifest_path
    )
    manifest_path
}

# ---------------------------------------------------------------------------
# File creation
# ---------------------------------------------------------------------------

test_that("htc_gen_submit() writes a .sub file to the output directory", {
    tmp <- withr::local_tempdir()
    withr::local_dir(tmp)
    htc_gen_submit(output = tmp)
    expect_true(file.exists(file.path(tmp, "job.sub")))
})

test_that("htc_gen_submit() respects custom output_file name", {
    tmp <- withr::local_tempdir()
    withr::local_dir(tmp)
    htc_gen_submit(output_file = "analysis.sub", output = tmp)
    expect_true(file.exists(file.path(tmp, "analysis.sub")))
})

test_that("htc_gen_submit() returns invisible NULL", {
    tmp <- withr::local_tempdir()
    withr::local_dir(tmp)
    result <- htc_gen_submit(output = tmp)
    expect_null(result)
})

# ---------------------------------------------------------------------------
# Argument validation
# ---------------------------------------------------------------------------

test_that("htc_gen_submit() errors when output_file does not end in .sub", {
    tmp <- withr::local_tempdir()
    withr::local_dir(tmp)
    expect_error(
        htc_gen_submit(output_file = "job.txt", output = tmp),
        regexp = "\\.sub"
    )
})

test_that("htc_gen_submit() errors when output directory does not exist", {
    expect_error(
        htc_gen_submit(output = "/nonexistent/path"),
        regexp = "does not exist"
    )
})

test_that("htc_gen_submit() errors on invalid mode", {
    tmp <- withr::local_tempdir()
    withr::local_dir(tmp)
    expect_error(
        htc_gen_submit(mode = "batch", output = tmp),
        regexp = "should be one of"
    )
})

test_that("htc_gen_submit() errors on invalid resources preset", {
    tmp <- withr::local_tempdir()
    withr::local_dir(tmp)
    expect_error(
        htc_gen_submit(resources = "huge", output = tmp),
        regexp = "not a valid"
    )
})

test_that("htc_gen_submit() errors when mode = 'multiple' and queue_from is NULL", {
    tmp <- withr::local_tempdir()
    withr::local_dir(tmp)
    expect_error(
        htc_gen_submit(mode = "multiple", output = tmp),
        regexp = "queue_from"
    )
})

test_that("htc_gen_submit() errors when queue_from file does not exist", {
    tmp <- withr::local_tempdir()
    withr::local_dir(tmp)
    expect_error(
        htc_gen_submit(mode       = "multiple",
                       queue_from = file.path(tmp, "missing.csv"),
                       output     = tmp),
        regexp = "does not exist"
    )
})

test_that("htc_gen_submit() errors when queue_from lacks file_path column", {
    tmp      <- withr::local_tempdir()
    withr::local_dir(tmp)
    bad_path <- file.path(tmp, "bad.csv")
    readr::write_csv(data.frame(group_value = "a", n_rows = 1), bad_path)
    expect_error(
        htc_gen_submit(mode = "multiple", queue_from = bad_path, output = tmp),
        regexp = "file_path"
    )
})

test_that("htc_gen_submit() errors when custom_resources is NULL with resources = 'custom'", {
    tmp <- withr::local_tempdir()
    withr::local_dir(tmp)
    expect_error(
        htc_gen_submit(resources = "custom", output = tmp),
        regexp = "custom_resources"
    )
})

test_that("htc_gen_submit() errors when custom_resources is missing required keys", {
    tmp <- withr::local_tempdir()
    withr::local_dir(tmp)
    expect_error(
        htc_gen_submit(resources        = "custom",
                       custom_resources = list(cpus = 2),
                       output           = tmp),
        regexp = "missing"
    )
})

test_that("htc_gen_submit() warns when queue_from supplied with mode = 'single'", {
    tmp      <- withr::local_tempdir()
    withr::local_dir(tmp)
    manifest <- .write_manifest(tmp)
    expect_warning(
        htc_gen_submit(mode = "single", queue_from = manifest, output = tmp),
        regexp = "ignored"
    )
})

test_that("htc_gen_submit() warns when custom_resources supplied without resources = 'custom'", {
    tmp <- withr::local_tempdir()
    withr::local_dir(tmp)
    expect_warning(
        htc_gen_submit(resources        = "small",
                       custom_resources = list(cpus = 2, memory = "8GB",
                                               disk = "4GB"),
                       output           = tmp),
        regexp = "ignored"
    )
})

test_that("htc_gen_submit() warns when gpu_options supplied without gpu = TRUE", {
    tmp <- withr::local_tempdir()
    withr::local_dir(tmp)
    expect_warning(
        htc_gen_submit(gpu_options = list(request_gpus = 2), output = tmp),
        regexp = "ignored"
    )
})

# ---------------------------------------------------------------------------
# Submit file content -- single mode
# ---------------------------------------------------------------------------

test_that("submit file starts with HTC Submit File comment", {
    tmp <- withr::local_tempdir()
    withr::local_dir(tmp)
    htc_gen_submit(output = tmp)
    lines <- read_subfile(tmp)
    expect_true(any(grepl("^# HTC Submit File", lines)))
})

test_that("submit file contains universe = container", {
    tmp <- withr::local_tempdir()
    withr::local_dir(tmp)
    htc_gen_submit(output = tmp)
    lines <- read_subfile(tmp)
    expect_true(any(grepl("universe = container", lines, fixed = TRUE)))
})

test_that("submit file contains container_image when supplied", {
    tmp <- withr::local_tempdir()
    withr::local_dir(tmp)
    htc_gen_submit(
        container_image = "docker://registry.doit.wisc.edu/netid/myimage",
        output          = tmp
    )
    lines <- read_subfile(tmp)
    expect_true(any(grepl("container_image = docker://", lines, fixed = TRUE)))
})

test_that("submit file contains placeholder comment when container_image is NULL", {
    tmp <- withr::local_tempdir()
    withr::local_dir(tmp)
    htc_gen_submit(output = tmp)
    lines <- read_subfile(tmp)
    expect_true(any(grepl("# container_image", lines, fixed = TRUE)))
})

test_that("submit file prepends docker:// when container_image lacks prefix", {
    tmp <- withr::local_tempdir()
    withr::local_dir(tmp)
    htc_gen_submit(
        container_image = "registry.doit.wisc.edu/netid/myimage",
        output          = tmp
    )
    lines <- read_subfile(tmp)
    expect_true(any(grepl(
        "container_image = docker://registry.doit.wisc.edu/netid/myimage",
        lines, fixed = TRUE
    )))
})

test_that("submit file does not double-prepend docker:// when already present", {
    tmp <- withr::local_tempdir()
    withr::local_dir(tmp)
    htc_gen_submit(
        container_image = "docker://registry.doit.wisc.edu/netid/myimage",
        output          = tmp
    )
    lines <- read_subfile(tmp)
    expect_false(any(grepl("docker://docker://", lines, fixed = TRUE)))
})

test_that("submit file contains executable when supplied", {
    tmp <- withr::local_tempdir()
    withr::local_dir(tmp)
    htc_gen_submit(executable = "analysis.sh", output = tmp)
    lines <- read_subfile(tmp)
    expect_true(any(grepl("executable = analysis.sh", lines, fixed = TRUE)))
})

test_that("submit file contains $(ClusterID)-$(ProcID) in logging lines", {
    tmp <- withr::local_tempdir()
    withr::local_dir(tmp)
    htc_gen_submit(output = tmp)
    lines <- read_subfile(tmp)
    expect_true(any(grepl("$(ClusterID)-$(ProcID)", lines, fixed = TRUE)))
})

test_that("submit file contains log, error, and output logging lines", {
    tmp <- withr::local_tempdir()
    withr::local_dir(tmp)
    htc_gen_submit(output = tmp)
    lines <- read_subfile(tmp)
    expect_true(any(grepl("^log ", lines)))
    expect_true(any(grepl("^error ", lines)))
    expect_true(any(grepl("^output ", lines)))
})

test_that("submit file contains should_transfer_files = YES", {
    tmp <- withr::local_tempdir()
    withr::local_dir(tmp)
    htc_gen_submit(output = tmp)
    lines <- read_subfile(tmp)
    expect_true(any(grepl("should_transfer_files   = YES", lines, fixed = TRUE)))
})

test_that("submit file contains when_to_transfer_output = ON_EXIT", {
    tmp <- withr::local_tempdir()
    withr::local_dir(tmp)
    htc_gen_submit(output = tmp)
    lines <- read_subfile(tmp)
    expect_true(any(grepl("when_to_transfer_output = ON_EXIT", lines, fixed = TRUE)))
})

test_that("submit file contains queue 1 in single mode", {
    tmp <- withr::local_tempdir()
    withr::local_dir(tmp)
    htc_gen_submit(output = tmp)
    lines <- read_subfile(tmp)
    expect_true(any(grepl("^queue 1$", lines)))
})

test_that("submit file queue reflects custom queue value", {
    tmp <- withr::local_tempdir()
    withr::local_dir(tmp)
    htc_gen_submit(queue = 5, output = tmp)
    lines <- read_subfile(tmp)
    expect_true(any(grepl("^queue 5$", lines)))
})

# ---------------------------------------------------------------------------
# Resource presets
# ---------------------------------------------------------------------------

test_that("small preset writes correct resource values", {
    tmp     <- withr::local_tempdir()
    withr::local_dir(tmp)
    htc_gen_submit(resources = "small", output = tmp)
    content <- paste(read_subfile(tmp), collapse = "\n")
    expect_match(content, "request_cpus   = 1",   fixed = TRUE)
    expect_match(content, "request_memory = 4GB", fixed = TRUE)
    expect_match(content, "request_disk   = 4GB", fixed = TRUE)
})

test_that("medium preset writes correct resource values", {
    tmp     <- withr::local_tempdir()
    withr::local_dir(tmp)
    htc_gen_submit(resources = "medium", output = tmp)
    content <- paste(read_subfile(tmp), collapse = "\n")
    expect_match(content, "request_cpus   = 4",    fixed = TRUE)
    expect_match(content, "request_memory = 16GB", fixed = TRUE)
    expect_match(content, "request_disk   = 15GB",  fixed = TRUE)
})

test_that("large preset writes correct resource values", {
    tmp     <- withr::local_tempdir()
    withr::local_dir(tmp)
    htc_gen_submit(resources = "large", output = tmp)
    content <- paste(read_subfile(tmp), collapse = "\n")
    expect_match(content, "request_cpus   = 8",    fixed = TRUE)
    expect_match(content, "request_memory = 64GB", fixed = TRUE)
    expect_match(content, "request_disk   = 32GB", fixed = TRUE)
})

test_that("custom preset writes supplied resource values", {
    tmp <- withr::local_tempdir()
    withr::local_dir(tmp)
    htc_gen_submit(
        resources        = "custom",
        custom_resources = list(cpus = 3, memory = "12GB", disk = "6GB"),
        output           = tmp
    )
    content <- paste(read_subfile(tmp), collapse = "\n")
    expect_match(content, "request_cpus   = 3",    fixed = TRUE)
    expect_match(content, "request_memory = 12GB", fixed = TRUE)
    expect_match(content, "request_disk   = 6GB",  fixed = TRUE)
})

# ---------------------------------------------------------------------------
# GPU section
# ---------------------------------------------------------------------------

test_that("GPU section absent when gpu = FALSE", {
    tmp <- withr::local_tempdir()
    withr::local_dir(tmp)
    htc_gen_submit(output = tmp)
    lines <- read_subfile(tmp)
    expect_false(any(grepl("request_gpus", lines, fixed = TRUE)))
})

test_that("GPU section present when gpu = TRUE", {
    tmp <- withr::local_tempdir()
    withr::local_dir(tmp)
    htc_gen_submit(gpu = TRUE, output = tmp)
    lines <- read_subfile(tmp)
    expect_true(any(grepl("request_gpus = 1",    lines, fixed = TRUE)))
    expect_true(any(grepl("+WantGPULab = true",  lines, fixed = TRUE)))
})

test_that("GPU section reflects custom gpu_options", {
    tmp <- withr::local_tempdir()
    withr::local_dir(tmp)
    htc_gen_submit(
        gpu         = TRUE,
        gpu_options = list(
            request_gpus   = 2,
            want_gpu_lab   = FALSE,
            min_capability = 8.0
        ),
        output = tmp
    )
    content <- paste(read_subfile(tmp), collapse = "\n")
    expect_match(content, "request_gpus = 2",              fixed = TRUE)
    expect_false(grepl("+WantGPULab",                      content, fixed = TRUE))
    expect_match(content, "gpus_minimum_capability = 8",   fixed = TRUE)
})

# ---------------------------------------------------------------------------
# Multiple mode
# ---------------------------------------------------------------------------

test_that("multiple mode writes queue file from subdatasets.csv", {
    tmp      <- withr::local_tempdir()
    withr::local_dir(tmp)
    manifest <- .write_manifest(tmp)
    htc_gen_submit(mode = "multiple", queue_from = manifest,
                   r_script = "analysis.R", input_files = "analysis.R",
                   output = tmp)
    lines <- read_subfile(tmp)
    expect_true(any(grepl("queue file from subdatasets.csv", lines,
                          fixed = TRUE)))
})

test_that("multiple mode writes subdatasets.csv with bare filenames", {
    tmp      <- withr::local_tempdir()
    withr::local_dir(tmp)
    manifest <- .write_manifest(tmp, filenames = c("adelie.csv", "gentoo.csv"))
    htc_gen_submit(mode = "multiple", queue_from = manifest,
                   r_script = "analysis.R", input_files = "analysis.R",
                   output = tmp)
    expect_true(file.exists(file.path(tmp, "subdatasets.csv")))
    sub_df <- readr::read_csv(file.path(tmp, "subdatasets.csv"),
                              col_names      = FALSE,
                              show_col_types = FALSE)
    expect_equal(sub_df[[1]], c("adelie.csv", "gentoo.csv"))
})

test_that("multiple mode includes arguments = $(file)", {
    tmp      <- withr::local_tempdir()
    withr::local_dir(tmp)
    manifest <- .write_manifest(tmp, filenames = "adelie.csv")
    htc_gen_submit(mode = "multiple", queue_from = manifest,
                   r_script = "analysis.R", input_files = "analysis.R",
                   output = tmp)
    lines <- read_subfile(tmp)
    expect_true(any(grepl("arguments = $(file)", lines, fixed = TRUE)))
})

test_that("multiple mode includes $(file) in transfer_input_files", {
    tmp      <- withr::local_tempdir()
    withr::local_dir(tmp)
    manifest <- .write_manifest(tmp, filenames = "adelie.csv")
    htc_gen_submit(mode        = "multiple",
                   queue_from  = manifest,
                   input_files = "analysis.R",
                   r_script    = "analysis.R",
                   output      = tmp)
    lines <- read_subfile(tmp)
    expect_true(any(grepl("$(file)", lines, fixed = TRUE)))
})

# ---------------------------------------------------------------------------
# transfer_output_files derivation from r_script
#
# htc_gen_submit() never reads the executable script or the Dockerfile, so
# the script's name cannot be inferred and has to be supplied. The name it
# derives must match the tarball htc_gen_executable() tells the job to build.
# ---------------------------------------------------------------------------

test_that("single mode derives transfer_output_files from r_script", {
    tmp <- withr::local_tempdir()
    withr::local_dir(tmp)
    htc_gen_submit(r_script = "analysis.R", input_files = "analysis.R", output = tmp)
    lines <- read_subfile(tmp)
    expect_true(any(grepl("transfer_output_files = analysis-results.tar.gz",
                          lines, fixed = TRUE)))
})

test_that("the script stem drops a leading directory", {
    tmp <- withr::local_tempdir()
    withr::local_dir(tmp)
    htc_gen_submit(r_script = "R/analysis.R", input_files = "R/analysis.R", output = tmp)
    lines <- read_subfile(tmp)
    expect_true(any(grepl("transfer_output_files = analysis-results.tar.gz",
                          lines, fixed = TRUE)))
    expect_false(any(grepl("R/analysis-results", lines, fixed = TRUE)))
})

test_that("explicit output_files overrides the derivation", {
    tmp <- withr::local_tempdir()
    withr::local_dir(tmp)
    htc_gen_submit(
        r_script     = "analysis.R",
        input_files  = "analysis.R",
        output_files = "custom.tar.gz",
        output       = tmp
    )
    lines <- read_subfile(tmp)
    expect_true(any(grepl("transfer_output_files = custom.tar.gz",
                          lines, fixed = TRUE)))
    expect_false(any(grepl("analysis-results.tar.gz", lines, fixed = TRUE)))
})

test_that("single mode without r_script writes the placeholder, as before", {
    tmp <- withr::local_tempdir()
    withr::local_dir(tmp)
    htc_gen_submit(output = tmp)
    lines <- read_subfile(tmp)
    expect_true(any(grepl("# transfer_output_files", lines, fixed = TRUE)))
})

test_that("multiple mode without r_script warns that the names will disagree", {
    tmp      <- withr::local_tempdir()
    withr::local_dir(tmp)
    manifest <- .write_manifest(tmp)
    expect_warning(
        htc_gen_submit(mode = "multiple", queue_from = manifest, output = tmp),
        regexp = "r_script"
    )
})

# ---------------------------------------------------------------------------
# r_script not listed in input_files (S-I4)
#
# r_script is uploaded as a job input file, not baked into the container
# image, so if its basename never shows up in input_files, HTCondor never
# transfers it and the job fails looking for a file that was never sent.
# ---------------------------------------------------------------------------

test_that("htc_gen_submit() warns when r_script is missing from input_files", {
    tmp <- withr::local_tempdir()
    withr::local_dir(tmp)
    expect_warning(
        htc_gen_submit(r_script = "analysis.R", output = tmp),
        regexp = "input_files"
    )
})

test_that("htc_gen_submit() does not warn when r_script's basename is in input_files", {
    tmp <- withr::local_tempdir()
    withr::local_dir(tmp)
    expect_no_warning(
        htc_gen_submit(
            r_script    = "R/analysis.R",
            input_files = "R/analysis.R",
            output      = tmp
        )
    )
})

test_that("htc_gen_submit() matches r_script to input_files by basename, ignoring directories", {
    # r_script and input_files can point at the same file via different
    # local paths (e.g. a relative path vs. one already stripped of R/); only
    # the basename has to agree, since that's what HTCondor transfers by.
    tmp <- withr::local_tempdir()
    withr::local_dir(tmp)
    expect_no_warning(
        htc_gen_submit(
            r_script    = "R/analysis.R",
            input_files = "analysis.R",
            output      = tmp
        )
    )
})

test_that("htc_gen_submit() does not warn when r_script is NULL", {
    tmp <- withr::local_tempdir()
    withr::local_dir(tmp)
    expect_no_warning(htc_gen_submit(output = tmp))
})

test_that("htc_gen_submit() falls back to the r_script in the job manifest", {
    tmp <- withr::local_tempdir()
    withr::local_dir(tmp)
    # As htc_gen_executable() would have recorded it on an earlier call.
    .update_manifest(r_script = "R/analysis.R", path = tmp)

    htc_gen_submit(input_files = "R/analysis.R", output = tmp)
    lines <- read_subfile(tmp)
    expect_true(any(grepl("transfer_output_files = analysis-results.tar.gz",
                          lines, fixed = TRUE)))
})

test_that("htc_gen_submit() records the script stem in the manifest", {
    tmp <- withr::local_tempdir()
    withr::local_dir(tmp)
    htc_gen_submit(r_script = "R/run-model.R", input_files = "R/run-model.R", output = tmp)
    expect_equal(.get_manifest(path = tmp)$script_stem, "run-model")
})

test_that("multiple mode derives transfer_output_files from r_script", {
    tmp      <- withr::local_tempdir()
    withr::local_dir(tmp)
    manifest <- .write_manifest(tmp, filenames = "adelie.csv")
    htc_gen_submit(mode = "multiple", queue_from = manifest,
                   r_script = "analysis.R", input_files = "analysis.R",
                   output = tmp)
    lines <- read_subfile(tmp)
    expect_true(any(grepl("analysis-$Fn(file)-results.tar.gz", lines, fixed = TRUE)))
})

# ---------------------------------------------------------------------------
# comments and verbose
# ---------------------------------------------------------------------------

test_that("comments = TRUE writes comment lines to the submit file", {
    tmp <- withr::local_tempdir()
    withr::local_dir(tmp)
    htc_gen_submit(comments = TRUE, output = tmp)
    lines <- read_subfile(tmp)
    expect_true(sum(grepl("^#", lines)) > 2)
})

test_that("verbose = TRUE produces messages", {
    tmp <- withr::local_tempdir()
    withr::local_dir(tmp)
    expect_message(htc_gen_submit(verbose = TRUE, output = tmp))
})

test_that("verbose = FALSE produces no messages", {
    tmp <- withr::local_tempdir()
    withr::local_dir(tmp)
    expect_no_message(htc_gen_submit(verbose = FALSE, output = tmp))
})

# ---------------------------------------------------------------------------
# Job manifest recording
# ---------------------------------------------------------------------------

test_that("htc_gen_submit() writes the job manifest to the output directory", {
    tmp <- withr::local_tempdir()
    withr::local_dir(tmp)
    htc_gen_submit(output = tmp)
    expect_true(file.exists(file.path(tmp, "htc-manifest.yaml")))
})

test_that("htc_gen_submit() records the submit file and input files in the manifest", {
    tmp <- withr::local_tempdir()
    withr::local_dir(tmp)
    htc_gen_submit(
        output_file = "analysis.sub",
        input_files = "analysis.R",
        output      = tmp
    )
    m <- .get_manifest(path = tmp)
    expect_equal(m$submit_file, "analysis.sub")
    expect_equal(m$input_files, "analysis.R")
})

test_that("htc_gen_submit() records submit_path pointing at the written file", {
    tmp <- withr::local_tempdir()
    withr::local_dir(tmp)
    htc_gen_submit(output_file = "analysis.sub", output = tmp)
    m <- .get_manifest(path = tmp)
    # submit_file is the bare name HTCondor sees; submit_path is where the
    # file actually is on this machine, which is what htc_upload() needs.
    expect_equal(m$submit_path, file.path(tmp, "analysis.sub"))
    expect_true(file.exists(m$submit_path))
})

test_that("htc_gen_submit() writes the manifest to path when it differs from output", {
    out  <- withr::local_tempdir()
    proj <- withr::local_tempdir()
    htc_gen_submit(output = out, path = proj)
    expect_true(file.exists(file.path(proj, "htc-manifest.yaml")))
    expect_false(file.exists(file.path(out, "htc-manifest.yaml")))
    expect_equal(.get_manifest(path = proj)$submit_path,
                 file.path(out, "job.sub"))
})

test_that("htc_gen_submit() records subdatasets_path and subset_files in multiple mode", {
    tmp      <- withr::local_tempdir()
    withr::local_dir(tmp)
    manifest <- .write_manifest(tmp, filenames = c("adelie.csv", "gentoo.csv"))
    htc_gen_submit(mode = "multiple", queue_from = manifest,
                   r_script = "analysis.R", input_files = "analysis.R",
                   output = tmp)
    m <- .get_manifest(path = tmp)
    expect_equal(m$subdatasets_path, file.path(tmp, "subdatasets.csv"))
    expect_equal(m$subset_files, file.path(tmp, c("adelie.csv", "gentoo.csv")))
})

test_that("htc_gen_submit() does not record subdatasets_path or subset_files in single mode", {
    tmp <- withr::local_tempdir()
    withr::local_dir(tmp)
    htc_gen_submit(output = tmp)
    m <- .get_manifest(path = tmp)
    expect_null(m$subdatasets_path)
    expect_null(m$subset_files)
})

test_that("htc_gen_submit() records container_image and resources in the manifest", {
    tmp <- withr::local_tempdir()
    withr::local_dir(tmp)
    htc_gen_submit(
        container_image = "registry.doit.wisc.edu/netid/myimage",
        resources       = "medium",
        output          = tmp
    )
    m <- .get_manifest(path = tmp)
    expect_equal(m$container_image, "docker://registry.doit.wisc.edu/netid/myimage")
    # .get_manifest() normalizes a length-1-per-element list into a flat
    # named vector on read-back, so access by [[ ]] rather than $.
    expect_equal(as.integer(m$resources[["cpus"]]), 4L)
    expect_equal(m$resources[["memory"]], "16GB")
    expect_equal(m$resources[["disk"]], "15GB")
})

# ---------------------------------------------------------------------------
# executable cross-defaulting from the job manifest (S-I3)
#
# Same coordination problem as r_script/output_files above: htc_gen_submit()
# and htc_gen_executable() both need to agree on the executable script's
# name, and the documented workflow calls htc_gen_submit() first -- so this
# direction (submit reading a value htc_gen_executable() wrote earlier) only
# applies when the two calls happen in the other order.
# ---------------------------------------------------------------------------

test_that("htc_gen_submit() defaults executable from a prior htc_gen_executable() call", {
    tmp <- withr::local_tempdir()
    withr::local_dir(tmp)
    writeLines("# analysis", "analysis.R")

    htc_gen_executable(
        output_file = "analysis.sh",
        r_script    = "analysis.R",
        output      = tmp,
        path        = tmp
    )

    # input_files names the script htc_gen_executable() already recorded as
    # r_script, so this exercises S-I3's executable defaulting without
    # tripping S-I4's separate "r_script isn't listed in input_files"
    # warning, which is a different concern than the one under test here.
    expect_no_warning(
        htc_gen_submit(input_files = "analysis.R", output = tmp, path = tmp)
    )
    lines <- read_subfile(tmp)
    expect_true(any(grepl("executable = analysis.sh", lines, fixed = TRUE)))
})

test_that("explicit executable overrides the manifest silently when they agree", {
    tmp <- withr::local_tempdir()
    withr::local_dir(tmp)
    writeLines("# analysis", "analysis.R")

    htc_gen_executable(
        output_file = "analysis.sh",
        r_script    = "analysis.R",
        output      = tmp,
        path        = tmp
    )

    # Same S-I4 caveat as the test above: input_files has to name the
    # recorded r_script, or that unrelated warning fires alongside this one.
    expect_no_warning(
        htc_gen_submit(executable = "analysis.sh", input_files = "analysis.R",
                       output = tmp, path = tmp)
    )
})

test_that("htc_gen_submit() warns when executable disagrees with the manifest", {
    tmp <- withr::local_tempdir()
    withr::local_dir(tmp)
    writeLines("# analysis", "analysis.R")

    htc_gen_executable(
        output_file = "analysis.sh",
        r_script    = "analysis.R",
        output      = tmp,
        path        = tmp
    )

    # Same S-I4 caveat as above: without input_files naming the recorded
    # r_script, a second, unrelated warning fires alongside this one.
    expect_warning(
        htc_gen_submit(executable = "run.sh", input_files = "analysis.R",
                       output = tmp, path = tmp),
        regexp = "does not match"
    )
    # The explicit value still wins despite the warning.
    lines <- read_subfile(tmp)
    expect_true(any(grepl("executable = run.sh", lines, fixed = TRUE)))
})

test_that("htc_gen_submit() falls back to the placeholder when executable resolves to NULL", {
    tmp <- withr::local_tempdir()
    withr::local_dir(tmp)
    htc_gen_submit(output = tmp, path = tmp)
    lines <- read_subfile(tmp)
    expect_true(any(grepl("# executable", lines, fixed = TRUE)))
})

# ---------------------------------------------------------------------------
# queue_from defaulting from project conventions (S-G5)
# ---------------------------------------------------------------------------

test_that("htc_gen_submit() defaults queue_from from config$project$conventions$split_dir", {
    tmp <- withr::local_tempdir()
    withr::local_dir(tmp)
    split_dir <- file.path(tmp, "split")
    dir.create(split_dir)
    .write_manifest(split_dir)

    config <- list(project = list(conventions = list(split_dir = split_dir)))

    htc_gen_submit(
        mode        = "multiple",
        config      = config,
        r_script    = "analysis.R",
        input_files = "analysis.R",
        output      = tmp
    )
    expect_true(file.exists(file.path(tmp, "subdatasets.csv")))
})

test_that("explicit queue_from overrides config$project$conventions$split_dir", {
    tmp <- withr::local_tempdir()
    withr::local_dir(tmp)
    split_dir <- file.path(tmp, "split")
    dir.create(split_dir)
    .write_manifest(split_dir, filenames = "unused.csv")

    explicit_dir <- file.path(tmp, "explicit")
    dir.create(explicit_dir)
    manifest <- .write_manifest(explicit_dir, filenames = "adelie.csv")

    config <- list(project = list(conventions = list(split_dir = split_dir)))

    htc_gen_submit(
        mode        = "multiple",
        queue_from  = manifest,
        config      = config,
        r_script    = "analysis.R",
        input_files = "analysis.R",
        output      = tmp
    )
    sub_df <- readr::read_csv(file.path(tmp, "subdatasets.csv"),
                              col_names      = FALSE,
                              show_col_types = FALSE)
    expect_equal(sub_df[[1]], "adelie.csv")
})

test_that("htc_gen_submit() still errors when mode = 'multiple' and neither queue_from nor config resolves it", {
    tmp <- withr::local_tempdir()
    withr::local_dir(tmp)
    config <- list(project = list(conventions = list()))
    expect_error(
        htc_gen_submit(mode = "multiple", config = config, output = tmp),
        regexp = "queue_from"
    )
})
