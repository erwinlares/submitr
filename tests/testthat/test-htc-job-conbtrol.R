# tests/testthat/test-htc-job-control.R
#
# htc_cancel() and htc_release() (S-G2).

# ---------------------------------------------------------------------------
# htc_cancel() -- Layer 1: argument validation
# ---------------------------------------------------------------------------

test_that("htc_cancel() errors when config is NULL", {
    expect_error(
        htc_cancel(cluster_id = 42, config = NULL),
        regexp = "config"
    )
})

test_that("htc_cancel() errors when cluster_id is not supplied and no manifest exists", {
    withr::local_dir(withr::local_tempdir())
    cfg <- list(username = "lares", server = "ap2002.chtc.wisc.edu")
    expect_error(
        htc_cancel(config = cfg),
        regexp = "cluster_id"
    )
})

test_that("htc_cancel() never falls back to removing every job", {
    # A bare condor_rm with no ID removes everything the user has queued.
    # htc_cancel() must never construct that command by accident.
    withr::local_dir(withr::local_tempdir())
    cfg <- list(username = "lares", server = "ap2002.chtc.wisc.edu")
    expect_error(
        htc_cancel(config = cfg, dry_run = TRUE),
        regexp = "cluster_id"
    )
})

test_that("htc_cancel() errors when cluster_id is not a positive integer", {
    cfg <- list(username = "lares", server = "ap2002.chtc.wisc.edu")
    expect_error(
        htc_cancel(cluster_id = "abc", config = cfg),
        regexp = "positive integer"
    )
})

test_that("htc_cancel() errors when reason is not a single string", {
    cfg <- list(username = "lares", server = "ap2002.chtc.wisc.edu")
    expect_error(
        htc_cancel(cluster_id = 42, reason = c("a", "b"), config = cfg, dry_run = TRUE),
        regexp = "reason"
    )
})

# ---------------------------------------------------------------------------
# htc_cancel() -- Layer 2: command construction via dry_run
# ---------------------------------------------------------------------------

test_that("htc_cancel() dry_run produces the condor_rm command", {
    cfg <- list(username = "lares", server = "ap2002.chtc.wisc.edu")
    msg <- capture_messages(
        htc_cancel(cluster_id = 42, config = cfg, dry_run = TRUE)
    )
    cmd <- paste(msg, collapse = " ")
    expect_true(grepl("condor_rm 42", cmd, fixed = TRUE))
})

test_that("htc_cancel() dry_run includes the reason flag when supplied", {
    cfg <- list(username = "lares", server = "ap2002.chtc.wisc.edu")
    msg <- capture_messages(
        htc_cancel(cluster_id = 42, reason = "wrong image", config = cfg, dry_run = TRUE)
    )
    cmd <- paste(msg, collapse = " ")
    expect_true(grepl("-reason", cmd, fixed = TRUE))
    expect_true(grepl("wrong image", cmd, fixed = TRUE))
})

test_that("htc_cancel() resolves cluster_id from the job manifest", {
    tmp <- withr::local_tempdir()
    withr::local_dir(tmp)
    .update_manifest(cluster_id = "42")

    cfg <- list(username = "lares", server = "ap2002.chtc.wisc.edu")
    msg <- capture_messages(htc_cancel(config = cfg, dry_run = TRUE))
    expect_true(any(grepl("42", msg, fixed = TRUE)))
})

test_that("htc_cancel() explicit cluster_id overrides the manifest", {
    tmp <- withr::local_tempdir()
    withr::local_dir(tmp)
    .update_manifest(cluster_id = "42")

    cfg <- list(username = "lares", server = "ap2002.chtc.wisc.edu")
    msg <- capture_messages(htc_cancel(cluster_id = 99, config = cfg, dry_run = TRUE))
    cmd <- paste(msg, collapse = " ")
    expect_true(grepl("condor_rm 99", cmd, fixed = TRUE))
})

# ---------------------------------------------------------------------------
# htc_cancel() -- Layer 3: mocked execution
# ---------------------------------------------------------------------------

test_that("htc_cancel() succeeds against a mocked condor_rm", {
    local_mocked_bindings(
        system2 = function(...) {
            result <- "Cluster 42 has been marked for removal."
            attr(result, "status") <- 0L
            result
        },
        .package = "base"
    )
    cfg <- list(username = "lares", server = "ap2002.chtc.wisc.edu")
    expect_no_error(htc_cancel(cluster_id = 42, config = cfg))
})

test_that("htc_cancel() aborts on a nonzero exit code", {
    local_mocked_bindings(
        system2 = function(...) {
            result <- "condor_rm: error"
            attr(result, "status") <- 1L
            result
        },
        .package = "base"
    )
    cfg <- list(username = "lares", server = "ap2002.chtc.wisc.edu")
    expect_error(htc_cancel(cluster_id = 42, config = cfg), regexp = "condor_rm")
})

# ---------------------------------------------------------------------------
# htc_release() -- Layer 1 and 2
# ---------------------------------------------------------------------------

test_that("htc_release() errors when config is NULL", {
    expect_error(
        htc_release(cluster_id = 42, config = NULL),
        regexp = "config"
    )
})

test_that("htc_release() errors when cluster_id is not supplied and no manifest exists", {
    withr::local_dir(withr::local_tempdir())
    cfg <- list(username = "lares", server = "ap2002.chtc.wisc.edu")
    expect_error(
        htc_release(config = cfg),
        regexp = "cluster_id"
    )
})

test_that("htc_release() errors when cluster_id is not a positive integer", {
    cfg <- list(username = "lares", server = "ap2002.chtc.wisc.edu")
    expect_error(
        htc_release(cluster_id = "abc", config = cfg),
        regexp = "positive integer"
    )
})

test_that("htc_release() dry_run produces the condor_release command", {
    cfg <- list(username = "lares", server = "ap2002.chtc.wisc.edu")
    msg <- capture_messages(
        htc_release(cluster_id = 42, config = cfg, dry_run = TRUE)
    )
    cmd <- paste(msg, collapse = " ")
    expect_true(grepl("condor_release 42", cmd, fixed = TRUE))
})

test_that("htc_release() resolves cluster_id from the job manifest", {
    tmp <- withr::local_tempdir()
    withr::local_dir(tmp)
    .update_manifest(cluster_id = "7")

    cfg <- list(username = "lares", server = "ap2002.chtc.wisc.edu")
    msg <- capture_messages(htc_release(config = cfg, dry_run = TRUE))
    expect_true(any(grepl("7", msg, fixed = TRUE)))
})

# ---------------------------------------------------------------------------
# htc_release() -- Layer 3: mocked execution
# ---------------------------------------------------------------------------

test_that("htc_release() succeeds against a mocked condor_release", {
    local_mocked_bindings(
        system2 = function(...) {
            result <- "Cluster 42 has been released."
            attr(result, "status") <- 0L
            result
        },
        .package = "base"
    )
    cfg <- list(username = "lares", server = "ap2002.chtc.wisc.edu")
    expect_no_error(htc_release(cluster_id = 42, config = cfg))
})

test_that("htc_release() aborts on a nonzero exit code", {
    local_mocked_bindings(
        system2 = function(...) {
            result <- "condor_release: error"
            attr(result, "status") <- 1L
            result
        },
        .package = "base"
    )
    cfg <- list(username = "lares", server = "ap2002.chtc.wisc.edu")
    expect_error(htc_release(cluster_id = 42, config = cfg), regexp = "condor_release")
})
