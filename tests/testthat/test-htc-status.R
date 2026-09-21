# tests/testthat/test-htc-status.R

# ---------------------------------------------------------------------------
# Layer 1 — Argument validation
# ---------------------------------------------------------------------------

test_that("htc_status() errors when config is NULL", {
    expect_error(
        htc_status(config = NULL),
        regexp = "config"
    )
})

test_that("htc_status() errors when config is missing username", {
    expect_error(
        htc_status(config = list(server = "ap2002.chtc.wisc.edu")),
        regexp = "username"
    )
})

test_that("htc_status() errors when config is missing server", {
    expect_error(
        htc_status(config = list(username = "lares")),
        regexp = "server"
    )
})

test_that("htc_status() errors when cluster_id is not a positive integer", {
    cfg <- list(username = "lares", server = "ap2002.chtc.wisc.edu")
    expect_error(
        htc_status(cluster_id = "abc", config = cfg),
        regexp = "positive integer"
    )
})

test_that("htc_status() errors when watch = TRUE and cluster_id is NULL", {
    cfg <- list(username = "lares", server = "ap2002.chtc.wisc.edu")
    expect_error(
        htc_status(watch = TRUE, config = cfg),
        regexp = "cluster_id"
    )
})

test_that("htc_status() errors when interval is not a positive integer", {
    cfg <- list(username = "lares", server = "ap2002.chtc.wisc.edu")
    expect_error(
        htc_status(cluster_id = "6302860", watch = TRUE, interval = -1, config = cfg),
        regexp = "interval"
    )
})

# ---------------------------------------------------------------------------
# Layer 2 — Command construction via dry_run
# ---------------------------------------------------------------------------

test_that("htc_status() dry_run produces ssh command", {
    cfg <- list(username = "lares", server = "ap2002.chtc.wisc.edu")
    expect_message(
        htc_status(config = cfg, dry_run = TRUE),
        regexp = "ssh"
    )
})

test_that("htc_status() dry_run includes condor_q", {
    cfg <- list(username = "lares", server = "ap2002.chtc.wisc.edu")
    expect_message(
        htc_status(config = cfg, dry_run = TRUE),
        regexp = "condor_q"
    )
})

test_that("htc_status() dry_run includes cluster_id when supplied", {
    cfg <- list(username = "lares", server = "ap2002.chtc.wisc.edu")
    expect_message(
        htc_status(cluster_id = "6302860", config = cfg, dry_run = TRUE),
        regexp = "6302860"
    )
})

test_that("htc_status() dry_run without cluster_id shows plain condor_q", {
    cfg <- list(username = "lares", server = "ap2002.chtc.wisc.edu")
    msg <- capture_messages(
        htc_status(config = cfg, dry_run = TRUE)
    )
    expect_false(any(grepl("[0-9]{7}", msg)))
})

test_that("htc_status() dry_run returns invisible NULL", {
    cfg    <- list(username = "lares", server = "ap2002.chtc.wisc.edu")
    result <- suppressMessages(
        htc_status(config = cfg, dry_run = TRUE)
    )
    expect_null(result)
})

test_that("htc_status() accepts cluster_id as integer", {
    cfg <- list(username = "lares", server = "ap2002.chtc.wisc.edu")
    expect_message(
        htc_status(cluster_id = 6302860L, config = cfg, dry_run = TRUE),
        regexp = "6302860"
    )
})

# ---------------------------------------------------------------------------
# Layer 3 — Integration (requires live CHTC connection)
# ---------------------------------------------------------------------------

test_that("htc_status() returns condor_q output as character vector", {
    skip_if_not(
        nchar(Sys.getenv("CHTC_USERNAME")) > 0,
        "CHTC_USERNAME not set — skipping integration test"
    )
    cfg <- list(
        username = Sys.getenv("CHTC_USERNAME"),
        server   = Sys.getenv("CHTC_SERVER", "ap2002.chtc.wisc.edu")
    )
    result <- htc_status(config = cfg)
    expect_type(result, "character")
    expect_true(length(result) > 0)
})
