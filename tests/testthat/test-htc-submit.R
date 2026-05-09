# tests/testthat/test-htc-submit.R

# ---------------------------------------------------------------------------
# Layer 1 — Argument validation
# ---------------------------------------------------------------------------

test_that("htc_submit() errors when config is NULL", {
    expect_error(
        htc_submit(config = NULL),
        regexp = "config"
    )
})

test_that("htc_submit() errors when config is missing username", {
    expect_error(
        htc_submit(config = list(server = "ap2002.chtc.wisc.edu")),
        regexp = "username"
    )
})

test_that("htc_submit() errors when config is missing server", {
    expect_error(
        htc_submit(config = list(username = "lares")),
        regexp = "server"
    )
})

test_that("htc_submit() errors when submit_file does not end in .sub", {
    cfg <- list(username = "lares", server = "ap2002.chtc.wisc.edu")
    expect_error(
        htc_submit(submit_file = "job.txt", config = cfg),
        regexp = "\\.sub"
    )
})

# ---------------------------------------------------------------------------
# Layer 2 — Command construction via dry_run
# ---------------------------------------------------------------------------

test_that("htc_submit() dry_run produces ssh command", {
    cfg <- list(username = "lares", server = "ap2002.chtc.wisc.edu")
    expect_message(
        htc_submit(submit_file = "job.sub", config = cfg, dry_run = TRUE),
        regexp = "ssh"
    )
})

test_that("htc_submit() dry_run includes condor_submit", {
    cfg <- list(username = "lares", server = "ap2002.chtc.wisc.edu")
    expect_message(
        htc_submit(submit_file = "job.sub", config = cfg, dry_run = TRUE),
        regexp = "condor_submit"
    )
})

test_that("htc_submit() dry_run includes cd into remote_path", {
    cfg <- list(username = "lares", server = "ap2002.chtc.wisc.edu")
    expect_message(
        htc_submit(submit_file = "job.sub", config = cfg, dry_run = TRUE),
        regexp = "cd"
    )
})

test_that("htc_submit() dry_run includes the default remote_path ~/", {
    cfg <- list(username = "lares", server = "ap2002.chtc.wisc.edu")
    expect_message(
        htc_submit(submit_file = "job.sub", config = cfg, dry_run = TRUE),
        regexp = "~/"
    )
})

test_that("htc_submit() dry_run reflects custom remote_path", {
    cfg <- list(username = "lares", server = "ap2002.chtc.wisc.edu")
    expect_message(
        htc_submit(
            submit_file = "job.sub",
            remote_path = "~/projects/",
            config      = cfg,
            dry_run     = TRUE
        ),
        regexp = "projects"
    )
})

test_that("htc_submit() dry_run reflects custom submit_file name", {
    cfg <- list(username = "lares", server = "ap2002.chtc.wisc.edu")
    expect_message(
        htc_submit(
            submit_file = "analysis.sub",
            config      = cfg,
            dry_run     = TRUE
        ),
        regexp = "analysis.sub"
    )
})

test_that("htc_submit() dry_run single-quotes the remote command", {
    cfg <- list(username = "lares", server = "ap2002.chtc.wisc.edu")
    msg <- capture_messages(
        htc_submit(submit_file = "job.sub", config = cfg, dry_run = TRUE)
    )
    expect_true(any(grepl("'cd", msg, fixed = TRUE)))
})

test_that("htc_submit() dry_run returns invisible NULL", {
    cfg    <- list(username = "lares", server = "ap2002.chtc.wisc.edu")
    result <- suppressMessages(
        htc_submit(submit_file = "job.sub", config = cfg, dry_run = TRUE)
    )
    expect_null(result)
})

# ---------------------------------------------------------------------------
# Layer 3 — Integration (requires live CHTC connection)
# ---------------------------------------------------------------------------

test_that("htc_submit() submits a job and returns a cluster ID", {
    skip_if_not(
        nchar(Sys.getenv("CHTC_USERNAME")) > 0,
        "CHTC_USERNAME not set — skipping integration test"
    )
    cfg <- list(
        username = Sys.getenv("CHTC_USERNAME"),
        server   = Sys.getenv("CHTC_SERVER", "ap2002.chtc.wisc.edu")
    )
    sub_file <- system.file("extdata", "hello-world.sub", package = "submitr")
    sh_file  <- system.file("extdata", "hello-world.sh",  package = "submitr")
    htc_upload(files = c(sub_file, sh_file), config = cfg)
    cluster_id <- htc_submit(submit_file = "hello-world.sub", config = cfg)
    expect_type(cluster_id, "character")
    expect_true(grepl("^[0-9]+$", cluster_id))
})
