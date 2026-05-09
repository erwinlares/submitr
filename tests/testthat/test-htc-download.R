# tests/testthat/test-htc-download.R

# ---------------------------------------------------------------------------
# Layer 1 — Argument validation
# ---------------------------------------------------------------------------

test_that("htc_download() errors when config is NULL", {
    expect_error(
        htc_download(files = "results.tar.gz", config = NULL),
        regexp = "config"
    )
})

test_that("htc_download() errors when config is missing username", {
    expect_error(
        htc_download(
            files  = "results.tar.gz",
            config = list(server = "ap2002.chtc.wisc.edu")
        ),
        regexp = "username"
    )
})

test_that("htc_download() errors when config is missing server", {
    expect_error(
        htc_download(
            files  = "results.tar.gz",
            config = list(username = "lares")
        ),
        regexp = "server"
    )
})

test_that("htc_download() errors when files is missing", {
    cfg <- list(username = "lares", server = "ap2002.chtc.wisc.edu")
    expect_error(
        htc_download(config = cfg),
        regexp = "files"
    )
})

test_that("htc_download() errors when files is empty", {
    cfg <- list(username = "lares", server = "ap2002.chtc.wisc.edu")
    expect_error(
        htc_download(files = character(0), config = cfg),
        regexp = "files"
    )
})

test_that("htc_download() errors when local_path does not exist", {
    cfg <- list(username = "lares", server = "ap2002.chtc.wisc.edu")
    expect_error(
        htc_download(
            files      = "results.tar.gz",
            local_path = "/nonexistent/path",
            config     = cfg
        ),
        regexp = "does not exist"
    )
})

# ---------------------------------------------------------------------------
# Layer 2 — Command construction via dry_run (plain filenames)
# ---------------------------------------------------------------------------

test_that("htc_download() dry_run produces scp command for plain filename", {
    cfg <- list(username = "lares", server = "ap2002.chtc.wisc.edu")
    tmp <- withr::local_tempdir()
    expect_message(
        htc_download(
            files      = "results.tar.gz",
            local_path = tmp,
            config     = cfg,
            dry_run    = TRUE
        ),
        regexp = "scp"
    )
})

test_that("htc_download() dry_run includes remote host for plain filename", {
    cfg <- list(username = "lares", server = "ap2002.chtc.wisc.edu")
    tmp <- withr::local_tempdir()
    expect_message(
        htc_download(
            files      = "results.tar.gz",
            local_path = tmp,
            config     = cfg,
            dry_run    = TRUE
        ),
        regexp = "lares@ap2002.chtc.wisc.edu"
    )
})

test_that("htc_download() dry_run includes filename for plain filename", {
    cfg <- list(username = "lares", server = "ap2002.chtc.wisc.edu")
    tmp <- withr::local_tempdir()
    expect_message(
        htc_download(
            files      = "results.tar.gz",
            local_path = tmp,
            config     = cfg,
            dry_run    = TRUE
        ),
        regexp = "results.tar.gz"
    )
})

test_that("htc_download() dry_run includes default remote_path ~/", {
    cfg <- list(username = "lares", server = "ap2002.chtc.wisc.edu")
    tmp <- withr::local_tempdir()
    expect_message(
        htc_download(
            files      = "results.tar.gz",
            local_path = tmp,
            config     = cfg,
            dry_run    = TRUE
        ),
        regexp = "~/"
    )
})

test_that("htc_download() dry_run reflects custom remote_path", {
    cfg <- list(username = "lares", server = "ap2002.chtc.wisc.edu")
    tmp <- withr::local_tempdir()
    expect_message(
        htc_download(
            files       = "results.tar.gz",
            remote_path = "~/projects/",
            local_path  = tmp,
            config      = cfg,
            dry_run     = TRUE
        ),
        regexp = "projects"
    )
})

# ---------------------------------------------------------------------------
# Layer 2 — Command construction via dry_run (glob patterns)
# ---------------------------------------------------------------------------

test_that("htc_download() dry_run single-quotes glob pattern", {
    cfg <- list(username = "lares", server = "ap2002.chtc.wisc.edu")
    tmp <- withr::local_tempdir()
    msg <- capture_messages(
        htc_download(
            files      = "*.tar.gz",
            local_path = tmp,
            config     = cfg,
            dry_run    = TRUE
        )
    )
    expect_true(any(grepl("'", msg, fixed = TRUE)))
})

test_that("htc_download() dry_run does not quote plain filename", {
    cfg <- list(username = "lares", server = "ap2002.chtc.wisc.edu")
    tmp <- withr::local_tempdir()
    msg <- capture_messages(
        htc_download(
            files      = "results.tar.gz",
            local_path = tmp,
            config     = cfg,
            dry_run    = TRUE
        )
    )
    # Plain filename should not be wrapped in single quotes
    expect_false(any(grepl("'lares@", msg, fixed = TRUE)))
})

test_that("htc_download() dry_run includes glob pattern in command", {
    cfg <- list(username = "lares", server = "ap2002.chtc.wisc.edu")
    tmp <- withr::local_tempdir()
    expect_message(
        htc_download(
            files      = "*.tar.gz",
            local_path = tmp,
            config     = cfg,
            dry_run    = TRUE
        ),
        regexp = "*.tar.gz",
        fixed  = TRUE
    )
})

test_that("htc_download() dry_run handles job.* glob pattern", {
    cfg <- list(username = "lares", server = "ap2002.chtc.wisc.edu")
    tmp <- withr::local_tempdir()
    expect_message(
        htc_download(
            files      = "job.*",
            local_path = tmp,
            config     = cfg,
            dry_run    = TRUE
        ),
        regexp = "job.*",
        fixed  = TRUE
    )
})

test_that("htc_download() dry_run returns invisible NULL", {
    cfg    <- list(username = "lares", server = "ap2002.chtc.wisc.edu")
    tmp    <- withr::local_tempdir()
    result <- suppressMessages(
        htc_download(
            files      = "results.tar.gz",
            local_path = tmp,
            config     = cfg,
            dry_run    = TRUE
        )
    )
    expect_null(result)
})

# ---------------------------------------------------------------------------
# Layer 3 — Integration (requires live CHTC connection)
# ---------------------------------------------------------------------------

test_that("htc_download() retrieves a file from the submit node", {
    skip_if_not(
        nchar(Sys.getenv("CHTC_USERNAME")) > 0,
        "CHTC_USERNAME not set — skipping integration test"
    )
    cfg <- list(
        username = Sys.getenv("CHTC_USERNAME"),
        server   = Sys.getenv("CHTC_SERVER", "ap2002.chtc.wisc.edu")
    )
    tmp <- withr::local_tempdir()
    expect_no_error(
        htc_download(files = "job.log", local_path = tmp, config = cfg)
    )
})
