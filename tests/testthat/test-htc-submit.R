# tests/testthat/test-htc-submit.R

# ---------------------------------------------------------------------------
# Layer 1 -- Argument validation
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
# Layer 2 -- Command construction via dry_run
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
# Remote command quoting
#
# Two shells see the remote command: system2() runs the ssh invocation
# through a local shell, and sshd runs the command string through a shell on
# the submit node. A leading tilde has to survive the first unexpanded and be
# expanded by the second, which is why it cannot simply be passed through
# shQuote().
# ---------------------------------------------------------------------------

test_that(".shell_quote() leaves ordinary filenames untouched", {
    expect_equal(.shell_quote("job.sub"), "job.sub")
    expect_equal(.shell_quote("analysis-2026.sub"), "analysis-2026.sub")
    expect_equal(.shell_quote("sub/dir/job.sub"), "sub/dir/job.sub")
})

test_that(".sh_word() wraps a plain string in single quotes", {
    expect_equal(.sh_word("job.sub"),  "'job.sub'")
    expect_equal(.sh_word("my job"),   "'my job'")
    expect_equal(.sh_word("$HOME"),    "'$HOME'")
    expect_equal(.sh_word("`whoami`"), "'`whoami`'")
})

test_that(".sh_word() closes and reopens around an embedded apostrophe", {
    # a'b becomes 'a'"'"'b', which a POSIX shell reads back as the single
    # word a'b. The idiom avoids a backslash, so there is no escape
    # processing to reason about on either the R or the shell side.
    expect_equal(.sh_word("a'b"), "'a'\"'\"'b'")
    expect_equal(.sh_word("'"),   "''\"'\"''")
})

test_that(".sh_word() output is one word however many specials it holds", {
    nasty <- "a'b$c`d e.sub"
    quoted <- .sh_word(nasty)
    expect_true(startsWith(quoted, "'"))
    expect_true(endsWith(quoted, "'"))
    # Every apostrophe in the payload is carried by the "'" escape, so no
    # bare apostrophe can terminate the quoting early.
    expect_false(grepl("[^\"]'[^\"]", substr(quoted, 2, nchar(quoted) - 1)))
})

test_that(".shell_quote() quotes anything a shell would interpret", {
    expect_equal(.shell_quote("my job.sub"),  .sh_word("my job.sub"))
    expect_equal(.shell_quote("job;rm.sub"),  .sh_word("job;rm.sub"))
    expect_equal(.shell_quote("Erwin's.sub"), .sh_word("Erwin's.sub"))
    expect_equal(.shell_quote("job$x.sub"),   .sh_word("job$x.sub"))
})

test_that(".quote_remote_path() leaves a bare tilde path expandable", {
    expect_equal(.quote_remote_path("~/"), "~/")
    expect_equal(.quote_remote_path("~"),  "~")
})

test_that(".quote_remote_path() does not quote an ordinary tilde path", {
    expect_equal(.quote_remote_path("~/projects/penguins/"),
                 "~/projects/penguins/")
    expect_equal(.quote_remote_path("~lares/jobs/"), "~lares/jobs/")
})

test_that(".quote_remote_path() keeps the tilde outside the quotes", {
    # Quoting the whole path would make the tilde literal and cd '~/' fails.
    # Adjacent quoted and unquoted fragments concatenate into one word, so
    # ~/'my data/' reaches cd as a single expanded argument.
    expect_equal(.quote_remote_path("~/my data/"),
                 paste0("~/", .sh_word("my data/")))
})

test_that(".quote_remote_path() quotes an absolute path with a space", {
    expect_equal(.quote_remote_path("/scratch/my data/"),
                 .sh_word("/scratch/my data/"))
})

test_that(".cli_escape() doubles braces so cli prints them literally", {
    expect_equal(.cli_escape("ERROR: {Requirements}"), "ERROR: {{Requirements}}")
    expect_equal(.cli_escape("no braces here"), "no braces here")
})

test_that("htc_submit() dry_run is unchanged for ordinary arguments", {
    # Quoting engages only where it is needed, so the command a reader checks
    # before running reads exactly as it did before quoting existed.
    cfg <- list(username = "lares", server = "ap2002.chtc.wisc.edu")
    msg <- capture_messages(
        htc_submit(submit_file = "job.sub", config = cfg, dry_run = TRUE)
    )
    expect_true(any(grepl("'cd ~/ && condor_submit job.sub'", msg, fixed = TRUE)))
})

test_that("htc_submit() dry_run keeps a submit file with a space in one piece", {
    cfg <- list(username = "lares", server = "ap2002.chtc.wisc.edu")
    msg <- capture_messages(
        htc_submit(submit_file = "my analysis.sub", config = cfg, dry_run = TRUE)
    )
    expect_true(grepl("'my analysis.sub'", paste(msg, collapse = " "), fixed = TRUE))
})

test_that("an apostrophe in the submit file cannot terminate the quoting", {
    hostile <- "x'; echo nope; echo '.sub"
    quoted  <- .shell_quote(hostile)

    expect_equal(quoted, .sh_word(hostile))
    expect_false(identical(quoted, hostile))
    # The dangerous reading is the command separator escaping the quoted run.
    expect_false(grepl("^'x'; echo", quoted))
})

test_that("htc_submit() dry_run neutralises a separator inside the filename", {
    cfg <- list(username = "lares", server = "ap2002.chtc.wisc.edu")
    msg <- capture_messages(
        htc_submit(
            submit_file = "x'; echo nope; echo '.sub",
            config      = cfg,
            dry_run     = TRUE
        )
    )
    cmd <- paste(msg, collapse = " ")
    expect_false(grepl("condor_submit x'; echo", cmd, fixed = TRUE))
    expect_false(grepl("condor_submit x';", cmd, fixed = TRUE))
})

# ---------------------------------------------------------------------------
# Layer 2b -- job manifest recording
# ---------------------------------------------------------------------------

.mock_condor_submit <- function(cluster = "42") {
    function(...) {
        result <- paste0("1 job(s) submitted to cluster ", cluster, ".")
        attr(result, "status") <- 0L
        result
    }
}

test_that("htc_submit() records cluster_id and remote_path in the job manifest", {
    tmp <- withr::local_tempdir()
    withr::local_dir(tmp)
    local_mocked_bindings(system2 = .mock_condor_submit("42"), .package = "base")

    cfg <- list(username = "lares", server = "ap2002.chtc.wisc.edu")
    cluster_id <- suppressMessages(htc_submit(
        submit_file = "job.sub",
        remote_path = "~/projects/",
        config      = cfg
    ))
    expect_equal(cluster_id, "42")

    m <- .get_manifest()
    expect_equal(m$cluster_id, "42")
    expect_equal(m$remote_path, "~/projects/")
})

test_that("htc_submit() writes the cluster ID to the manifest at path", {
    project <- withr::local_tempdir()
    jobs    <- withr::local_tempdir()
    withr::local_dir(project)
    local_mocked_bindings(system2 = .mock_condor_submit("99"), .package = "base")

    # The manifest the generators wrote lives in `jobs`, so that is where the
    # cluster ID has to land. Writing it to the working directory instead
    # would leave htc_download() reading a manifest with a cluster ID but no
    # job metadata, or vice versa.
    cfg <- list(username = "lares", server = "ap2002.chtc.wisc.edu")
    suppressMessages(htc_submit(
        submit_file = "job.sub",
        config      = cfg,
        path        = jobs
    ))

    expect_equal(.get_manifest(path = jobs)$cluster_id, "99")
    expect_null(.get_manifest(path = project))
})

test_that("htc_submit() resolves submit_file and remote_path from the manifest", {
    # As htc_gen_submit() and htc_upload() would have recorded them on
    # earlier calls in the pipeline.
    tmp <- withr::local_tempdir()
    withr::local_dir(tmp)
    .update_manifest(submit_file = "analysis.sub", remote_path = "~/penguins/")
    local_mocked_bindings(system2 = .mock_condor_submit("42"), .package = "base")

    cfg <- list(username = "lares", server = "ap2002.chtc.wisc.edu")
    msg <- capture_messages(htc_submit(config = cfg, verbose = TRUE))
    expect_true(any(grepl("analysis.sub", msg, fixed = TRUE)))
    expect_true(any(grepl("penguins", msg, fixed = TRUE)))
})

test_that("htc_submit() explicit submit_file and remote_path override the manifest", {
    tmp <- withr::local_tempdir()
    withr::local_dir(tmp)
    .update_manifest(submit_file = "analysis.sub", remote_path = "~/penguins/")
    local_mocked_bindings(system2 = .mock_condor_submit("42"), .package = "base")

    cfg <- list(username = "lares", server = "ap2002.chtc.wisc.edu")
    suppressMessages(htc_submit(
        submit_file = "job.sub",
        remote_path = "~/other/",
        config      = cfg
    ))

    m <- .get_manifest()
    expect_equal(m$submit_file, "job.sub")
    expect_equal(m$remote_path, "~/other/")
})

test_that("htc_submit() falls back to hardcoded defaults with no manifest", {
    withr::local_dir(withr::local_tempdir())
    cfg <- list(username = "lares", server = "ap2002.chtc.wisc.edu")
    msg <- capture_messages(
        htc_submit(config = cfg, dry_run = TRUE)
    )
    expect_true(any(grepl("job.sub", msg, fixed = TRUE)))
    expect_true(any(grepl("~/", msg, fixed = TRUE)))
})

test_that("htc_submit() records submit_file in the manifest after a successful submission", {
    tmp <- withr::local_tempdir()
    withr::local_dir(tmp)
    local_mocked_bindings(system2 = .mock_condor_submit("42"), .package = "base")

    cfg <- list(username = "lares", server = "ap2002.chtc.wisc.edu")
    suppressMessages(htc_submit(submit_file = "analysis.sub", config = cfg))

    m <- .get_manifest()
    expect_equal(m$submit_file, "analysis.sub")
})

test_that("htc_submit() appends to the manifest without disturbing job metadata", {
    tmp <- withr::local_tempdir()
    withr::local_dir(tmp)
    .update_manifest(mode = "multiple", subsets = c("a.csv", "b.csv"))
    local_mocked_bindings(system2 = .mock_condor_submit("7"), .package = "base")

    cfg <- list(username = "lares", server = "ap2002.chtc.wisc.edu")
    suppressMessages(htc_submit(submit_file = "job.sub", config = cfg))

    m <- .get_manifest()
    expect_equal(m$cluster_id, "7")
    expect_equal(m$mode, "multiple")
    expect_equal(m$subsets, c("a.csv", "b.csv"))
})

# ---------------------------------------------------------------------------
# Layer 3 -- Integration (requires live CHTC connection)
# ---------------------------------------------------------------------------

test_that("htc_submit() submits a job and returns a cluster ID", {
    skip_if_not(
        nchar(Sys.getenv("CHTC_USERNAME")) > 0,
        "CHTC_USERNAME not set -- skipping integration test"
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
