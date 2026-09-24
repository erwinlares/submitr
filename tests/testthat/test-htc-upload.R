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

test_that("htc_upload() errors when files is omitted and no manifest is available", {
    # files now defaults to NULL and falls back to the job manifest, so this
    # case only errors when there is no manifest to fall back to. The
    # temporary working directory guarantees that.
    withr::local_dir(withr::local_tempdir())
    cfg <- list(username = "lares", server = "ap2002.chtc.wisc.edu")
    expect_error(
        htc_upload(config = cfg),
        regexp = "files"
    )
})

test_that("htc_upload() errors when files is empty", {
    withr::local_dir(withr::local_tempdir())
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
# Layer 2b — job manifest recording (S-I1)
# ---------------------------------------------------------------------------

.mock_scp_success <- function() {
    function(...) 0L
}

test_that("htc_upload() records remote_path in the job manifest on success", {
    tmp <- withr::local_tempdir()
    withr::local_dir(tmp)
    f   <- file.path(tmp, "job.sub")
    writeLines("queue 1", f)
    local_mocked_bindings(system2 = .mock_scp_success(), .package = "base")

    cfg <- list(username = "lares", server = "ap2002.chtc.wisc.edu")
    htc_upload(files = f, remote_path = "~/projects/", config = cfg)

    m <- .get_manifest()
    expect_equal(m$remote_path, "~/projects/")
})

test_that("htc_upload() does not record remote_path in the manifest on dry_run", {
    tmp <- withr::local_tempdir()
    withr::local_dir(tmp)
    f   <- file.path(tmp, "job.sub")
    writeLines("queue 1", f)

    cfg <- list(username = "lares", server = "ap2002.chtc.wisc.edu")
    htc_upload(files = f, remote_path = "~/projects/", config = cfg, dry_run = TRUE)

    expect_null(.get_manifest())
})

test_that("htc_upload() resolves remote_path from the manifest when omitted", {
    tmp <- withr::local_tempdir()
    withr::local_dir(tmp)
    f   <- file.path(tmp, "job.sub")
    writeLines("queue 1", f)
    .update_manifest(remote_path = "~/penguins/")

    cfg <- list(username = "lares", server = "ap2002.chtc.wisc.edu")
    expect_message(
        htc_upload(files = f, config = cfg, dry_run = TRUE),
        regexp = "penguins"
    )
})

test_that("htc_upload() explicit remote_path overrides the value in the manifest", {
    tmp <- withr::local_tempdir()
    withr::local_dir(tmp)
    f   <- file.path(tmp, "job.sub")
    writeLines("queue 1", f)
    .update_manifest(remote_path = "~/penguins/")

    cfg <- list(username = "lares", server = "ap2002.chtc.wisc.edu")
    msg <- capture_messages(
        htc_upload(files = f, remote_path = "~/other/", config = cfg, dry_run = TRUE)
    )
    expect_true(any(grepl("other", msg)))
    expect_false(any(grepl("penguins", msg)))
})

# ---------------------------------------------------------------------------
# Layer 2c — preflight check integration (S-G4)
# ---------------------------------------------------------------------------

test_that("htc_upload() aborts before uploading when check = TRUE finds an error", {
    tmp <- withr::local_tempdir()
    withr::local_dir(tmp)
    f <- file.path(tmp, "job.sub")
    writeLines("queue 1", f)
    # Not an error about `files` itself -- an error htc_check() would find in
    # the manifest, to confirm htc_upload() is actually running the check
    # rather than just re-validating its own files argument.
    .update_manifest(input_files = file.path(tmp, "missing.R"), path = tmp)

    cfg <- list(username = "lares", server = "ap2002.chtc.wisc.edu")
    expect_error(
        suppressWarnings(suppressMessages(
            htc_upload(files = f, config = cfg, check = TRUE, path = tmp)
        )),
        regexp = "Preflight check"
    )
})

test_that("htc_upload() proceeds when check = TRUE finds only warnings", {
    tmp <- withr::local_tempdir()
    withr::local_dir(tmp)
    f <- file.path(tmp, "job.sub")
    writeLines("queue 1", f)
    # container_image tagged :latest is a warning, not an error -- should not
    # block the upload.
    .update_manifest(
        container_image = "docker://registry.doit.wisc.edu/netid/myimage:latest",
        path            = tmp
    )
    local_mocked_bindings(system2 = .mock_scp_success(), .package = "base")

    cfg <- list(username = "lares", server = "ap2002.chtc.wisc.edu")
    expect_no_error(
        suppressWarnings(suppressMessages(
            htc_upload(files = f, config = cfg, check = TRUE, path = tmp)
        ))
    )
})

test_that("htc_upload() does not run the preflight check when check = FALSE (default)", {
    tmp <- withr::local_tempdir()
    withr::local_dir(tmp)
    f <- file.path(tmp, "job.sub")
    writeLines("queue 1", f)
    # Would be an error-level issue if htc_check() ran against this manifest;
    # since check defaults to FALSE, it should never be evaluated.
    .update_manifest(input_files = file.path(tmp, "missing.R"), path = tmp)
    local_mocked_bindings(system2 = .mock_scp_success(), .package = "base")

    cfg <- list(username = "lares", server = "ap2002.chtc.wisc.edu")
    expect_no_error(
        htc_upload(files = f, config = cfg, path = tmp)
    )
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
