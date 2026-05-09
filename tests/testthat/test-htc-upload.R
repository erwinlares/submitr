# tests/testthat/test-htc-upload.R

# ---------------------------------------------------------------------------
# Layer 1 — Argument validation
# ---------------------------------------------------------------------------

test_that("htc_upload() errors when config is NULL", {
    tmp <- withr::local_tempdir()
    f   <- file.path(tmp, "job.sub")
    writeLines("queue 1", f)
    expect_error(
        htc_upload(files = f, config = NULL),
        regexp = "config"
    )
})

test_that("htc_upload() errors when config is missing username", {
    tmp <- withr::local_tempdir()
    f   <- file.path(tmp, "job.sub")
    writeLines("queue 1", f)
    expect_error(
        htc_upload(files = f, config = list(server = "ap2002.chtc.wisc.edu")),
        regexp = "username"
    )
})

test_that("htc_upload() errors when config is missing server", {
    tmp <- withr::local_tempdir()
    f   <- file.path(tmp, "job.sub")
    writeLines("queue 1", f)
    expect_error(
        htc_upload(files = f, config = list(username = "lares")),
        regexp = "server"
    )
})

test_that("htc_upload() errors when files is missing", {
    cfg <- list(username = "lares", server = "ap2002.chtc.wisc.edu")
    expect_error(
        htc_upload(config = cfg),
        regexp = "files"
    )
})

test_that("htc_upload() errors when files is empty", {
    cfg <- list(username = "lares", server = "ap2002.chtc.wisc.edu")
    expect_error(
        htc_upload(files = character(0), config = cfg),
        regexp = "files"
    )
})

test_that("htc_upload() errors when a file does not exist", {
    cfg <- list(username = "lares", server = "ap2002.chtc.wisc.edu")
    expect_error(
        htc_upload(files = "/nonexistent/file.sub", config = cfg),
        regexp = "do not exist"
    )
})

# ---------------------------------------------------------------------------
# Layer 2 — Command construction via dry_run
# ---------------------------------------------------------------------------

test_that("htc_upload() dry_run produces scp command", {
    tmp <- withr::local_tempdir()
    f   <- file.path(tmp, "job.sub")
    writeLines("queue 1", f)
    cfg <- list(username = "lares", server = "ap2002.chtc.wisc.edu")
    expect_message(
        htc_upload(files = f, config = cfg, dry_run = TRUE),
        regexp = "scp"
    )
})

test_that("htc_upload() dry_run includes the remote destination", {
    tmp <- withr::local_tempdir()
    f   <- file.path(tmp, "job.sub")
    writeLines("queue 1", f)
    cfg <- list(username = "lares", server = "ap2002.chtc.wisc.edu")
    expect_message(
        htc_upload(files = f, config = cfg, dry_run = TRUE),
        regexp = "lares@ap2002.chtc.wisc.edu"
    )
})

test_that("htc_upload() dry_run includes the default remote_path ~/", {
    tmp <- withr::local_tempdir()
    f   <- file.path(tmp, "job.sub")
    writeLines("queue 1", f)
    cfg <- list(username = "lares", server = "ap2002.chtc.wisc.edu")
    expect_message(
        htc_upload(files = f, config = cfg, dry_run = TRUE),
        regexp = "~/"
    )
})

test_that("htc_upload() dry_run reflects custom remote_path", {
    tmp <- withr::local_tempdir()
    f   <- file.path(tmp, "job.sub")
    writeLines("queue 1", f)
    cfg <- list(username = "lares", server = "ap2002.chtc.wisc.edu")
    expect_message(
        htc_upload(
            files       = f,
            config      = cfg,
            remote_path = "~/projects/",
            dry_run     = TRUE
        ),
        regexp = "projects"
    )
})

test_that("htc_upload() dry_run adds -r flag for directory", {
    tmp     <- withr::local_tempdir()
    sub_dir <- file.path(tmp, "jobs")
    dir.create(sub_dir)
    cfg <- list(username = "lares", server = "ap2002.chtc.wisc.edu")
    expect_message(
        htc_upload(files = sub_dir, config = cfg, dry_run = TRUE),
        regexp = "-r"
    )
})

test_that("htc_upload() dry_run does not add -r flag for plain files", {
    tmp <- withr::local_tempdir()
    f   <- file.path(tmp, "job.sub")
    writeLines("queue 1", f)
    cfg <- list(username = "lares", server = "ap2002.chtc.wisc.edu")
    msg <- capture_messages(
        htc_upload(files = f, config = cfg, dry_run = TRUE)
    )
    expect_false(any(grepl("\\-r", msg)))
})

test_that("htc_upload() dry_run returns invisible NULL", {
    tmp <- withr::local_tempdir()
    f   <- file.path(tmp, "job.sub")
    writeLines("queue 1", f)
    cfg    <- list(username = "lares", server = "ap2002.chtc.wisc.edu")
    result <- suppressMessages(
        htc_upload(files = f, config = cfg, dry_run = TRUE)
    )
    expect_null(result)
})

# ---------------------------------------------------------------------------
# Layer 3 — Integration (requires live CHTC connection)
# ---------------------------------------------------------------------------

test_that("htc_upload() copies a file to the submit node", {
    skip_if_not(
        nchar(Sys.getenv("CHTC_USERNAME")) > 0,
        "CHTC_USERNAME not set — skipping integration test"
    )
    tmp <- withr::local_tempdir()
    f   <- file.path(tmp, "test-upload.txt")
    writeLines("test", f)
    cfg <- list(
        username = Sys.getenv("CHTC_USERNAME"),
        server   = Sys.getenv("CHTC_SERVER", "ap2002.chtc.wisc.edu")
    )
    expect_no_error(htc_upload(files = f, config = cfg))
})
