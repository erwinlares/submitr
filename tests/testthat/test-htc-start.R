# tests/testthat/test-htc-start.R

# ---------------------------------------------------------------------------
# .resolve_config() -- internal helper
# ---------------------------------------------------------------------------

test_that(".resolve_config() returns explicit config when provided", {
    cfg <- list(username = "lares", server = "ap2002.chtc.wisc.edu")
    result <- .resolve_config(cfg)
    expect_equal(result$username, "lares")
    expect_equal(result$server, "ap2002.chtc.wisc.edu")
})

test_that(".resolve_config() falls back to session option", {
    withr::local_options(submitr.config = list(
        username = "lares",
        server   = "ap2002.chtc.wisc.edu"
    ))
    result <- .resolve_config(NULL)
    expect_equal(result$username, "lares")
    expect_equal(result$server, "ap2002.chtc.wisc.edu")
})

test_that(".resolve_config() errors when no config is available", {
    withr::local_options(submitr.config = NULL)
    expect_error(
        .resolve_config(NULL),
        regexp = "No HTC config found"
    )
})

test_that(".resolve_config() errors when config is missing username", {
    cfg <- list(server = "ap2002.chtc.wisc.edu")
    expect_error(
        .resolve_config(cfg),
        regexp = "missing"
    )
})

test_that(".resolve_config() errors when config is missing server", {
    cfg <- list(username = "lares")
    expect_error(
        .resolve_config(cfg),
        regexp = "missing"
    )
})

test_that("explicit config overrides session option", {
    withr::local_options(submitr.config = list(
        username = "session-user",
        server   = "session-server"
    ))
    explicit <- list(username = "explicit-user", server = "explicit-server")
    result <- .resolve_config(explicit)
    expect_equal(result$username, "explicit-user")
    expect_equal(result$server, "explicit-server")
})

# ---------------------------------------------------------------------------
# htc_start()
# ---------------------------------------------------------------------------

test_that("htc_start() stores config in options", {
    tmp <- withr::local_tempdir()
    cfg_content <- "username: testuser\nserver: testserver.edu\n"
    writeLines(cfg_content, file.path(tmp, "htc.cfg"))

    withr::local_options(submitr.config = NULL)

    suppressMessages(htc_start(path = tmp))

    stored <- getOption("submitr.config")
    expect_false(is.null(stored))
    expect_equal(stored$username, "testuser")
    expect_equal(stored$server, "testserver.edu")
})

test_that("htc_start() returns config invisibly", {
    tmp <- withr::local_tempdir()
    cfg_content <- "username: testuser\nserver: testserver.edu\n"
    writeLines(cfg_content, file.path(tmp, "htc.cfg"))

    withr::local_options(submitr.config = NULL)

    result <- suppressMessages(htc_start(path = tmp))

    expect_equal(result$username, "testuser")
    expect_equal(result$server, "testserver.edu")
})

test_that("htc_start() prints a success message", {
    tmp <- withr::local_tempdir()
    cfg_content <- "username: testuser\nserver: testserver.edu\n"
    writeLines(cfg_content, file.path(tmp, "htc.cfg"))

    withr::local_options(submitr.config = NULL)

    expect_message(
        htc_start(path = tmp),
        regexp = "Session started"
    )
})

test_that("clearing submitr.config option removes session config", {
    withr::local_options(submitr.config = list(
        username = "lares",
        server   = "ap2002.chtc.wisc.edu"
    ))

    options(submitr.config = NULL)
    expect_null(getOption("submitr.config"))
})

# ---------------------------------------------------------------------------
# Integration: session config flows through to htc_*() functions
# ---------------------------------------------------------------------------

test_that("htc_upload() uses session config when config = NULL", {
    withr::local_options(submitr.config = list(
        username = "lares",
        server   = "ap2002.chtc.wisc.edu"
    ))

    tmp <- withr::local_tempdir()
    writeLines("queue 1", file.path(tmp, "job.sub"))

    expect_message(
        htc_upload(
            files   = file.path(tmp, "job.sub"),
            dry_run = TRUE
        ),
        regexp = "scp.*lares@ap2002"
    )
})

test_that("htc_download() uses session config when config = NULL", {
    withr::local_options(submitr.config = list(
        username = "lares",
        server   = "ap2002.chtc.wisc.edu"
    ))

    tmp <- withr::local_tempdir()

    expect_message(
        htc_download(
            files      = "*.tar.gz",
            local_path = tmp,
            dry_run    = TRUE
        ),
        regexp = "scp.*lares@ap2002"
    )
})
