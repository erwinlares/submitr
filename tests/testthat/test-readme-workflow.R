# tests/testthat/test-readme-workflow.R
#
# Regression tests against README.md's documented workflow and reference
# tables, not against the package's correctness in general -- the other
# test files already cover that. This file exists because the failure mode
# it guards against already happened once (S20 in submitr-audit.qmd): the
# README's own worked example silently went stale after Phase 4 changed the
# output folder and the tarball naming convention, and nothing caught it
# until a manual read turned up a doubled heading and a workflow that still
# taught results_folder = "results".
#
# Design choice: this does not parse README.md's fenced code blocks and
# eval() them directly. Half of the documented workflow (htc_start(),
# htc_upload(), htc_submit(), htc_status(), and htc_download() without
# dry_run) requires a live SSH connection to a CHTC submit node, and mocking
# every remote call well enough to eval the literal markdown safely would be
# more fragile than the drift it protects against. Instead, each test below
# reproduces one documented code block using the literal argument values
# README.md shows, points `output`/`path` at a temporary directory, and
# checks the result against claims made elsewhere in the README: the job
# manifest's own example YAML, the resource preset table, the
# results-naming table, and the quick function reference. If the README's
# prose and its own code block ever drift from each other, or from what the
# functions actually do, one of these tests fails.
#
# What this does NOT cover: htc_start()'s interactive prompts, and the
# network-touching halves of htc_upload()/htc_submit()/htc_status()/
# htc_download(). Those are exercised elsewhere (test-htc-*.R) via mocked
# bindings and dry_run = TRUE, and by the opt-in Layer 3 integration tests
# that require a real htc.cfg.

# ---------------------------------------------------------------------------
# "A first workflow" -- steps 2 and 3, single-job mode
# ---------------------------------------------------------------------------

test_that("the first-workflow example generates a consistent submit file and executable", {
    tmp <- withr::local_tempdir()

    htc_gen_submit(
        output_file     = "analysis.sub",
        container_image = "registry.doit.wisc.edu/your.netid/my-analysis:1.0.0",
        executable      = "analysis.sh",
        r_script        = "R/analysis.R",
        resources       = "small",
        comments        = TRUE,
        output          = tmp
    )
    htc_gen_executable(
        r_script    = "R/analysis.R",
        output_file = "analysis.sh",
        comments    = TRUE,
        output      = tmp
    )

    expect_true(file.exists(file.path(tmp, "analysis.sub")))
    expect_true(file.exists(file.path(tmp, "analysis.sh")))

    sub_text <- paste(readLines(file.path(tmp, "analysis.sub")), collapse = "\n")
    # The README's own code block omits the docker:// prefix here (a
    # different block, under ### htc_gen_submit(), includes it explicitly),
    # so this also locks down that htc_gen_submit() really does add it.
    expect_true(grepl(
        "container_image = docker://registry.doit.wisc.edu/your.netid/my-analysis:1.0.0",
        sub_text, fixed = TRUE
    ))
    expect_true(grepl("executable = analysis.sh", sub_text, fixed = TRUE))
    expect_true(grepl(
        "transfer_output_files = analysis-results.tar.gz", sub_text, fixed = TRUE
    ))

    sh_lines <- readLines(file.path(tmp, "analysis.sh"))
    expect_equal(sh_lines[[1]], "#!/bin/bash")
    expect_true(any(grepl(
        "tar -czf analysis-results.tar.gz output", sh_lines, fixed = TRUE
    )))
})

test_that("the job manifest after steps 2-3 matches the fields README's example shows", {
    tmp <- withr::local_tempdir()

    htc_gen_submit(
        output_file     = "analysis.sub",
        container_image = "registry.doit.wisc.edu/your.netid/my-analysis:1.0.0",
        executable      = "analysis.sh",
        r_script        = "R/analysis.R",
        resources       = "small",
        comments        = TRUE,
        output          = tmp
    )
    htc_gen_executable(
        r_script    = "R/analysis.R",
        output_file = "analysis.sh",
        comments    = TRUE,
        output      = tmp
    )

    m <- .get_manifest(path = tmp)
    # cluster_id and remote_path are the two fields left off this check --
    # both are written by htc_submit(), which needs a live connection and so
    # is out of scope here (see file header).
    expect_equal(m$submit_file, "analysis.sub")
    expect_equal(m$executable_file, "analysis.sh")
    expect_equal(m$r_script, "R/analysis.R")
    expect_equal(m$script_stem, "analysis")
    expect_equal(m$mode, "single")
    expect_equal(m$output_files, "analysis-results.tar.gz")
})

# ---------------------------------------------------------------------------
# "Steps 4 and 7 take no arguments" -- htc_upload()/htc_download() resolve
# automatically once the manifest is populated
# ---------------------------------------------------------------------------

test_that("htc_upload() resolves step 4 with no arguments, per the README's claim", {
    tmp <- withr::local_tempdir()

    htc_gen_submit(
        output_file = "analysis.sub",
        executable  = "analysis.sh",
        r_script    = "R/analysis.R",
        output      = tmp
    )
    htc_gen_executable(
        r_script    = "R/analysis.R",
        output_file = "analysis.sh",
        output      = tmp
    )

    cfg <- list(username = "your.netid", server = "ap2002.chtc.wisc.edu")
    msg <- capture_messages(
        htc_upload(config = cfg, dry_run = TRUE, path = tmp)
    )
    cmd <- paste(msg, collapse = " ")
    expect_true(grepl("analysis.sub", cmd, fixed = TRUE))
    expect_true(grepl("analysis.sh", cmd, fixed = TRUE))
})

test_that("htc_download() resolves step 7 with no arguments, per the README's claim", {
    tmp <- withr::local_tempdir()

    htc_gen_submit(
        output_file = "analysis.sub",
        executable  = "analysis.sh",
        r_script    = "R/analysis.R",
        output      = tmp
    )
    htc_gen_executable(
        r_script    = "R/analysis.R",
        output_file = "analysis.sh",
        output      = tmp
    )
    # Stand in for htc_submit(), which needs a live connection: record what
    # it would have written, using the same cluster ID as the README's own
    # example manifest under "## The job manifest".
    .update_manifest(cluster_id = "6302860", remote_path = "~/", path = tmp)

    cfg <- list(username = "your.netid", server = "ap2002.chtc.wisc.edu")
    msg <- capture_messages(
        htc_download(config = cfg, dry_run = TRUE, path = tmp)
    )
    cmd <- paste(msg, collapse = " ")
    expect_true(grepl("analysis-results.tar.gz", cmd, fixed = TRUE))
    expect_true(grepl("6302860-0-job.log", cmd, fixed = TRUE))
})

# ---------------------------------------------------------------------------
# "Scaling to many jobs" -- multiple-job mode
# ---------------------------------------------------------------------------

test_that("the scaling-up example produces matching submit and executable files", {
    tmp <- withr::local_tempdir()
    manifest_csv <- file.path(tmp, "manifest.csv")
    readr::write_csv(
        data.frame(file_path = file.path(tmp, c("adelie.csv", "gentoo.csv"))),
        manifest_csv
    )

    htc_gen_submit(
        output_file     = "analysis.sub",
        container_image = "registry.doit.wisc.edu/your.netid/my-analysis:1.0.0",
        executable      = "analysis.sh",
        r_script        = "R/analysis.R",
        input_files     = "R/analysis.R",
        mode            = "multiple",
        queue_from      = manifest_csv,
        resources       = "medium",
        comments        = TRUE,
        output          = tmp
    )
    htc_gen_executable(
        r_script    = "R/analysis.R",
        output_file = "analysis.sh",
        mode        = "multiple",
        comments    = TRUE,
        output      = tmp
    )

    sub_text <- paste(readLines(file.path(tmp, "analysis.sub")), collapse = "\n")
    expect_true(grepl(
        "transfer_output_files = analysis-$Fn(file)-results.tar.gz",
        sub_text, fixed = TRUE
    ))

    sh_lines <- readLines(file.path(tmp, "analysis.sh"))
    tar_line <- grep("^tar", sh_lines, value = TRUE)
    expect_true(grepl(
        "analysis-${1%.*}-results.tar.gz", tar_line, fixed = TRUE
    ))
})

test_that("the results-naming table holds: single name unchanged, multiple gains the script stem", {
    expect_equal(.tarball_name("analysis"), "analysis-results.tar.gz")
    expect_equal(.tarball_name("analysis", "adelie"), "analysis-adelie-results.tar.gz")
})

# ---------------------------------------------------------------------------
# Resource preset table
# ---------------------------------------------------------------------------

test_that("the resource preset table matches the shipped htc-resources.yaml", {
    resources_file <- system.file(
        "extdata", "htc-resources.yaml",
        package = "submitr", mustWork = TRUE
    )
    presets <- yaml::read_yaml(resources_file)

    expect_equal(as.integer(presets$small$cpus), 1L)
    expect_equal(presets$small$memory, "4GB")
    expect_equal(presets$small$disk, "4GB")

    expect_equal(as.integer(presets$medium$cpus), 4L)
    expect_equal(presets$medium$memory, "16GB")
    expect_equal(presets$medium$disk, "15GB")

    expect_equal(as.integer(presets$large$cpus), 8L)
    expect_equal(presets$large$memory, "64GB")
    expect_equal(presets$large$disk, "32GB")
})

# ---------------------------------------------------------------------------
# Quick function reference and stated defaults
# ---------------------------------------------------------------------------

test_that("every function named in the quick function reference table still exists", {
    fns <- c(
        "htc_start", "htc_config", "htc_gen_submit", "htc_gen_executable",
        "htc_upload", "htc_submit", "htc_status", "htc_download"
    )
    for (fn in fns) {
        expect_true(exists(fn, mode = "function"), info = fn)
    }
})

test_that("htc_gen_executable()'s results_folder still defaults to output/", {
    expect_equal(formals(htc_gen_executable)$results_folder, "output")
})
