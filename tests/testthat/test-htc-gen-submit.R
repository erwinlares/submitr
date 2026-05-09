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
    htc_gen_submit(output = tmp)
    expect_true(file.exists(file.path(tmp, "job.sub")))
})

test_that("htc_gen_submit() respects custom output_file name", {
    tmp <- withr::local_tempdir()
    htc_gen_submit(output_file = "analysis.sub", output = tmp)
    expect_true(file.exists(file.path(tmp, "analysis.sub")))
})

test_that("htc_gen_submit() returns invisible NULL", {
    tmp <- withr::local_tempdir()
    result <- htc_gen_submit(output = tmp)
    expect_null(result)
})

# ---------------------------------------------------------------------------
# Argument validation
# ---------------------------------------------------------------------------

test_that("htc_gen_submit() errors when output_file does not end in .sub", {
    tmp <- withr::local_tempdir()
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
    expect_error(
        htc_gen_submit(mode = "batch", output = tmp),
        regexp = "should be one of"
    )
})

test_that("htc_gen_submit() errors on invalid resources preset", {
    tmp <- withr::local_tempdir()
    expect_error(
        htc_gen_submit(resources = "huge", output = tmp),
        regexp = "not a valid"
    )
})

test_that("htc_gen_submit() errors when mode = 'multiple' and queue_from is NULL", {
    tmp <- withr::local_tempdir()
    expect_error(
        htc_gen_submit(mode = "multiple", output = tmp),
        regexp = "queue_from"
    )
})

test_that("htc_gen_submit() errors when queue_from file does not exist", {
    tmp <- withr::local_tempdir()
    expect_error(
        htc_gen_submit(mode       = "multiple",
                       queue_from = file.path(tmp, "missing.csv"),
                       output     = tmp),
        regexp = "does not exist"
    )
})

test_that("htc_gen_submit() errors when queue_from lacks file_path column", {
    tmp      <- withr::local_tempdir()
    bad_path <- file.path(tmp, "bad.csv")
    readr::write_csv(data.frame(group_value = "a", n_rows = 1), bad_path)
    expect_error(
        htc_gen_submit(mode = "multiple", queue_from = bad_path, output = tmp),
        regexp = "file_path"
    )
})

test_that("htc_gen_submit() errors when custom_resources is NULL with resources = 'custom'", {
    tmp <- withr::local_tempdir()
    expect_error(
        htc_gen_submit(resources = "custom", output = tmp),
        regexp = "custom_resources"
    )
})

test_that("htc_gen_submit() errors when custom_resources is missing required keys", {
    tmp <- withr::local_tempdir()
    expect_error(
        htc_gen_submit(resources        = "custom",
                       custom_resources = list(cpus = 2),
                       output           = tmp),
        regexp = "missing"
    )
})

test_that("htc_gen_submit() warns when queue_from supplied with mode = 'single'", {
    tmp      <- withr::local_tempdir()
    manifest <- .write_manifest(tmp)
    expect_warning(
        htc_gen_submit(mode = "single", queue_from = manifest, output = tmp),
        regexp = "ignored"
    )
})

test_that("htc_gen_submit() warns when custom_resources supplied without resources = 'custom'", {
    tmp <- withr::local_tempdir()
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
    expect_warning(
        htc_gen_submit(gpu_options = list(request_gpus = 2), output = tmp),
        regexp = "ignored"
    )
})

# ---------------------------------------------------------------------------
# Submit file content — single mode
# ---------------------------------------------------------------------------

test_that("submit file starts with HTC Submit File comment", {
    tmp <- withr::local_tempdir()
    htc_gen_submit(output = tmp)
    lines <- read_subfile(tmp)
    expect_true(any(grepl("^# HTC Submit File", lines)))
})

test_that("submit file contains universe = container", {
    tmp <- withr::local_tempdir()
    htc_gen_submit(output = tmp)
    lines <- read_subfile(tmp)
    expect_true(any(grepl("universe = container", lines, fixed = TRUE)))
})

test_that("submit file contains container_image when supplied", {
    tmp <- withr::local_tempdir()
    htc_gen_submit(
        container_image = "docker://registry.doit.wisc.edu/netid/myimage",
        output          = tmp
    )
    lines <- read_subfile(tmp)
    expect_true(any(grepl("container_image = docker://", lines, fixed = TRUE)))
})

test_that("submit file contains placeholder comment when container_image is NULL", {
    tmp <- withr::local_tempdir()
    htc_gen_submit(output = tmp)
    lines <- read_subfile(tmp)
    expect_true(any(grepl("# container_image", lines, fixed = TRUE)))
})

test_that("submit file contains executable when supplied", {
    tmp <- withr::local_tempdir()
    htc_gen_submit(executable = "analysis.sh", output = tmp)
    lines <- read_subfile(tmp)
    expect_true(any(grepl("executable = analysis.sh", lines, fixed = TRUE)))
})

test_that("submit file contains $(ClusterID)-$(ProcID) in logging lines", {
    tmp <- withr::local_tempdir()
    htc_gen_submit(output = tmp)
    lines <- read_subfile(tmp)
    expect_true(any(grepl("$(ClusterID)-$(ProcID)", lines, fixed = TRUE)))
})

test_that("submit file contains log, error, and output logging lines", {
    tmp <- withr::local_tempdir()
    htc_gen_submit(output = tmp)
    lines <- read_subfile(tmp)
    expect_true(any(grepl("^log ", lines)))
    expect_true(any(grepl("^error ", lines)))
    expect_true(any(grepl("^output ", lines)))
})

test_that("submit file contains queue 1 in single mode", {
    tmp <- withr::local_tempdir()
    htc_gen_submit(output = tmp)
    lines <- read_subfile(tmp)
    expect_true(any(grepl("^queue 1$", lines)))
})

test_that("submit file queue reflects custom queue value", {
    tmp <- withr::local_tempdir()
    htc_gen_submit(queue = 5, output = tmp)
    lines <- read_subfile(tmp)
    expect_true(any(grepl("^queue 5$", lines)))
})

# ---------------------------------------------------------------------------
# Resource presets
# ---------------------------------------------------------------------------

test_that("small preset writes correct resource values", {
    tmp     <- withr::local_tempdir()
    htc_gen_submit(resources = "small", output = tmp)
    content <- paste(read_subfile(tmp), collapse = "\n")
    expect_match(content, "request_cpus   = 1",   fixed = TRUE)
    expect_match(content, "request_memory = 4GB", fixed = TRUE)
    expect_match(content, "request_disk   = 4GB", fixed = TRUE)
})

test_that("medium preset writes correct resource values", {
    tmp     <- withr::local_tempdir()
    htc_gen_submit(resources = "medium", output = tmp)
    content <- paste(read_subfile(tmp), collapse = "\n")
    expect_match(content, "request_cpus   = 4",    fixed = TRUE)
    expect_match(content, "request_memory = 16GB", fixed = TRUE)
    expect_match(content, "request_disk   = 15GB",  fixed = TRUE)
})

test_that("large preset writes correct resource values", {
    tmp     <- withr::local_tempdir()
    htc_gen_submit(resources = "large", output = tmp)
    content <- paste(read_subfile(tmp), collapse = "\n")
    expect_match(content, "request_cpus   = 8",    fixed = TRUE)
    expect_match(content, "request_memory = 64GB", fixed = TRUE)
    expect_match(content, "request_disk   = 32GB", fixed = TRUE)
})

test_that("custom preset writes supplied resource values", {
    tmp <- withr::local_tempdir()
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
    htc_gen_submit(output = tmp)
    lines <- read_subfile(tmp)
    expect_false(any(grepl("request_gpus", lines, fixed = TRUE)))
})

test_that("GPU section present when gpu = TRUE", {
    tmp <- withr::local_tempdir()
    htc_gen_submit(gpu = TRUE, output = tmp)
    lines <- read_subfile(tmp)
    expect_true(any(grepl("request_gpus = 1",    lines, fixed = TRUE)))
    expect_true(any(grepl("+WantGPULab = true",  lines, fixed = TRUE)))
})

test_that("GPU section reflects custom gpu_options", {
    tmp <- withr::local_tempdir()
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
    manifest <- .write_manifest(tmp)
    htc_gen_submit(mode = "multiple", queue_from = manifest, output = tmp)
    lines <- read_subfile(tmp)
    expect_true(any(grepl("queue file from subdatasets.csv", lines,
                          fixed = TRUE)))
})

test_that("multiple mode writes subdatasets.csv with bare filenames", {
    tmp      <- withr::local_tempdir()
    manifest <- .write_manifest(tmp, filenames = c("adelie.csv", "gentoo.csv"))
    htc_gen_submit(mode = "multiple", queue_from = manifest, output = tmp)
    expect_true(file.exists(file.path(tmp, "subdatasets.csv")))
    sub_df <- readr::read_csv(file.path(tmp, "subdatasets.csv"),
                              col_names      = FALSE,
                              show_col_types = FALSE)
    expect_equal(sub_df[[1]], c("adelie.csv", "gentoo.csv"))
})

test_that("multiple mode includes arguments = $(file)", {
    tmp      <- withr::local_tempdir()
    manifest <- .write_manifest(tmp, filenames = "adelie.csv")
    htc_gen_submit(mode = "multiple", queue_from = manifest, output = tmp)
    lines <- read_subfile(tmp)
    expect_true(any(grepl("arguments = $(file)", lines, fixed = TRUE)))
})

test_that("multiple mode includes $(file) in transfer_input_files", {
    tmp      <- withr::local_tempdir()
    manifest <- .write_manifest(tmp, filenames = "adelie.csv")
    htc_gen_submit(mode        = "multiple",
                   queue_from  = manifest,
                   input_files = "analysis.R",
                   output      = tmp)
    lines <- read_subfile(tmp)
    expect_true(any(grepl("$(file)", lines, fixed = TRUE)))
})

test_that("multiple mode defaults transfer_output_files to $(file)-results.tar.gz", {
    tmp      <- withr::local_tempdir()
    manifest <- .write_manifest(tmp, filenames = "adelie.csv")
    htc_gen_submit(mode = "multiple", queue_from = manifest, output = tmp)
    lines <- read_subfile(tmp)
    expect_true(any(grepl("$(file)-results.tar.gz", lines, fixed = TRUE)))
})

# ---------------------------------------------------------------------------
# comments and verbose
# ---------------------------------------------------------------------------

test_that("comments = TRUE writes comment lines to the submit file", {
    tmp <- withr::local_tempdir()
    htc_gen_submit(comments = TRUE, output = tmp)
    lines <- read_subfile(tmp)
    expect_true(sum(grepl("^#", lines)) > 2)
})

test_that("verbose = TRUE produces messages", {
    tmp <- withr::local_tempdir()
    expect_message(htc_gen_submit(verbose = TRUE, output = tmp))
})

test_that("verbose = FALSE produces no messages", {
    tmp <- withr::local_tempdir()
    expect_no_message(htc_gen_submit(verbose = FALSE, output = tmp))
})
