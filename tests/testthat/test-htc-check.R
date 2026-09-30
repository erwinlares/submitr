# tests/testthat/test-htc-check.R
#
# htc_check() -- preflight validation before upload/submission (S-G4).

test_that(".parse_size_gb() parses common HTCondor size strings", {
    expect_equal(.parse_size_gb("16GB"), 16)
    expect_equal(.parse_size_gb("512MB"), 0.5)
    expect_equal(.parse_size_gb("1TB"), 1024)
    expect_equal(.parse_size_gb("4"), 4 / 1024) # unitless == MB, per HTCondor
})

test_that(".parse_size_gb() returns NA for unparseable input", {
    expect_true(is.na(.parse_size_gb("lots")))
    expect_true(is.na(.parse_size_gb(NA_character_)))
    expect_true(is.na(.parse_size_gb(NULL)))
})

test_that("htc_check() passes cleanly when everything resolves and exists", {
    # setup.R stands in for .image_check_tool() with one that finds no
    # container tool, so the placeholder image below is never probed and
    # this test gives the same answer on every machine.
    tmp <- withr::local_tempdir()
    withr::local_dir(tmp)
    writeLines("# analysis", "analysis.R")

    result <- suppressMessages(htc_check(
        container_image = "registry.doit.wisc.edu/netid/myimage:1.0.0",
        input_files      = "analysis.R",
        resources        = list(cpus = 1L, memory = "4GB", disk = "4GB"),
        verbose          = FALSE
    ))

    expect_equal(nrow(result), 0L)
})

test_that("htc_check() flags a missing input file as an error", {
    result <- suppressMessages(suppressWarnings(htc_check(
        input_files = "does-not-exist.R",
        verbose     = FALSE
    )))

    expect_true(any(result$check == "input_files" & result$severity == "error"))
})

test_that("htc_check() flags a missing data file as an error", {
    result <- suppressMessages(suppressWarnings(htc_check(
        data_files = "does-not-exist.csv",
        verbose    = FALSE
    )))

    expect_true(any(result$check == "data_files" & result$severity == "error"))
})

test_that("htc_check() flags an implausible cpu request", {
    result <- suppressMessages(suppressWarnings(htc_check(
        resources = list(cpus = 128L, memory = "4GB", disk = "4GB"),
        verbose   = FALSE
    )))

    expect_true(any(result$check == "resources" & result$severity == "warning"))
})

test_that("htc_check() flags an implausibly large memory request", {
    result <- suppressMessages(suppressWarnings(htc_check(
        resources = list(cpus = 1L, memory = "512GB", disk = "4GB"),
        verbose   = FALSE
    )))

    expect_true(any(
        result$check == "resources" & grepl("request_memory", result$message)
    ))
})

test_that("htc_check() flags a container_image tagged latest", {
    result <- suppressMessages(suppressWarnings(htc_check(
        container_image = "registry.doit.wisc.edu/netid/myimage:latest",
        verbose          = FALSE
    )))

    expect_true(any(result$check == "container_image" & result$severity == "warning"))
})

test_that("htc_check() treats a missing tag the same as an explicit :latest", {
    result <- suppressMessages(suppressWarnings(htc_check(
        container_image = "registry.doit.wisc.edu/netid/myimage",
        verbose          = FALSE
    )))

    expect_true(any(result$check == "container_image" & result$severity == "warning"))
})

test_that("htc_check() resolves everything from the submission state when omitted", {
    # No container tool is found here either (see setup.R).
    tmp <- withr::local_tempdir()
    withr::local_dir(tmp)
    writeLines("# analysis", "analysis.R")

    htc_gen_submit(
        container_image = "registry.doit.wisc.edu/netid/myimage:1.0.0",
        r_script        = "analysis.R",
        input_files     = "analysis.R",
        resources       = "small",
        output          = tmp
    )

    result <- suppressMessages(htc_check(path = tmp))
    expect_equal(nrow(result), 0L)
})

test_that("htc_check() detects a multiple-mode subset that no longer exists on disk", {
    tmp <- withr::local_tempdir()
    withr::local_dir(tmp)

    manifest_csv <- file.path(tmp, "manifest.csv")
    subset_a <- file.path(tmp, "adelie.csv")
    writeLines("x", subset_a)
    readr::write_csv(
        data.frame(group_value = "adelie", n_rows = 1L, file_path = subset_a),
        manifest_csv
    )

    htc_gen_submit(
        mode        = "multiple",
        queue_from  = manifest_csv,
        r_script    = "analysis.R",
        input_files = "analysis.R",
        output      = tmp
    )

    # Simulate the subset file having been moved or deleted since the split.
    unlink(subset_a)

    result <- suppressMessages(suppressWarnings(htc_check(path = tmp)))
    expect_true(any(result$check == "subdatasets" & result$severity == "error"))
})

test_that("htc_check() skips checks silently when nothing is supplied or recorded", {
    withr::local_dir(withr::local_tempdir())
    result <- suppressMessages(htc_check(verbose = FALSE))
    expect_equal(nrow(result), 0L)
})

# ---------------------------------------------------------------------------
# The image reachability probe
#
# setup.R stands in for .image_check_tool() for the whole suite, so no real
# container tool runs during tests. These tests replace it, and the probe
# itself, locally.
# ---------------------------------------------------------------------------

test_that("check_image = FALSE never asks a container tool", {
    local_mocked_bindings(
        .image_check_tool = function() stop("should not be called"),
        .inspect_image    = function(...) stop("should not be called")
    )

    expect_no_error(
        result <- suppressMessages(htc_check(
            container_image = "registry.doit.wisc.edu/netid/myimage:1.0.0",
            check_image     = FALSE,
            path            = withr::local_tempdir()
        ))
    )
    expect_equal(nrow(result), 0L)
})

test_that("check_image = FALSE still flags a latest tag", {
    # htc_check() summarizes what it found as a warning of its own.
    expect_warning(
        result <- suppressMessages(htc_check(
            container_image = "registry.doit.wisc.edu/netid/myimage:latest",
            check_image     = FALSE,
            path            = withr::local_tempdir()
        )),
        regexp = "0 errors and 1 warning"
    )

    expect_true(any(result$check == "container_image" & result$severity == "warning"))
})

test_that("an image the container tool finds raises no issue", {
    local_mocked_bindings(
        .image_check_tool = function() "podman",
        .inspect_image    = function(tool, image) 0L
    )

    result <- suppressMessages(htc_check(
        container_image = "docker://registry.doit.wisc.edu/netid/myimage:1.0.0",
        path            = withr::local_tempdir()
    ))

    expect_equal(nrow(result), 0L)
})

test_that("an image the container tool cannot find is a warning, not an error", {
    local_mocked_bindings(
        .image_check_tool = function() "docker",
        .inspect_image    = function(tool, image) 1L
    )

    expect_warning(
        result <- suppressMessages(htc_check(
            container_image = "registry.doit.wisc.edu/netid/myimage:1.0.0",
            path            = withr::local_tempdir()
        )),
        regexp = "0 errors and 1 warning"
    )

    expect_true(any(
        result$check == "container_image" &
            result$severity == "warning" &
            grepl("Could not confirm", result$message)
    ))
    expect_false(any(result$severity == "error"))
})

test_that("the probe is given the image without its docker:// prefix", {
    seen <- NULL
    local_mocked_bindings(
        .image_check_tool = function() "podman",
        .inspect_image    = function(tool, image) {
            seen <<- image
            0L
        }
    )

    suppressMessages(htc_check(
        container_image = "docker://registry.doit.wisc.edu/netid/myimage:1.0.0",
        path            = withr::local_tempdir()
    ))

    expect_equal(seen, "registry.doit.wisc.edu/netid/myimage:1.0.0")
})

test_that("check_image must be TRUE or FALSE", {
    expect_error(htc_check(check_image = NA), regexp = "check_image")
    expect_error(htc_check(check_image = "yes"), regexp = "check_image")
})
