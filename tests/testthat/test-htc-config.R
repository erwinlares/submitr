# tests/testthat/test-htc-config.R

# ---------------------------------------------------------------------------
# Layer 1 — Argument validation
# ---------------------------------------------------------------------------

test_that("htc_config() errors when username is empty string in non-interactive mode", {
    tmp <- withr::local_tempdir()
    withr::local_dir(tmp)
    expect_error(
        htc_config(username = "", server = "ap2002.chtc.wisc.edu"),
        regexp = "username"
    )
})

test_that("htc_config() errors when server is empty string in non-interactive mode", {
    tmp <- withr::local_tempdir()
    withr::local_dir(tmp)
    expect_error(
        htc_config(username = "lares", server = ""),
        regexp = "server"
    )
})

# ---------------------------------------------------------------------------
# Layer 2 — File creation and reading
# ---------------------------------------------------------------------------

test_that("htc_config() creates htc.cfg when username and server are supplied", {
    tmp <- withr::local_tempdir()
    withr::local_dir(tmp)
    local_mocked_bindings(
        system2 = function(...) 0L,
        .package = "base"
    )
    htc_config(username = "lares", server = "ap2002.chtc.wisc.edu")
    expect_true(file.exists(file.path(tmp, "htc.cfg")))
})

test_that("htc_config() writes correct username and server to htc.cfg", {
    tmp <- withr::local_tempdir()
    withr::local_dir(tmp)
    local_mocked_bindings(
        system2 = function(...) 0L,
        .package = "base"
    )
    htc_config(username = "lares", server = "ap2002.chtc.wisc.edu")
    cfg <- yaml::read_yaml(file.path(tmp, "htc.cfg"))
    expect_equal(cfg$username, "lares")
    expect_equal(cfg$server, "ap2002.chtc.wisc.edu")
})

test_that("htc_config() returns a list with username and server", {
    tmp <- withr::local_tempdir()
    withr::local_dir(tmp)
    local_mocked_bindings(
        system2 = function(...) 0L,
        .package = "base"
    )
    result <- htc_config(username = "lares", server = "ap2002.chtc.wisc.edu")
    expect_type(result, "list")
    expect_named(result, c("username", "server"))
})

test_that("htc_config() reads existing htc.cfg without prompting", {
    tmp <- withr::local_tempdir()
    withr::local_dir(tmp)
    yaml::write_yaml(
        list(username = "lares", server = "ap2002.chtc.wisc.edu"),
        file.path(tmp, "htc.cfg")
    )
    local_mocked_bindings(
        system2 = function(...) 0L,
        .package = "base"
    )
    result <- htc_config()
    expect_equal(result$username, "lares")
    expect_equal(result$server, "ap2002.chtc.wisc.edu")
})

test_that("htc_config() adds htc.cfg to .gitignore on creation", {
    tmp <- withr::local_tempdir()
    withr::local_dir(tmp)
    local_mocked_bindings(
        system2 = function(...) 0L,
        .package = "base"
    )
    htc_config(username = "lares", server = "ap2002.chtc.wisc.edu")
    gitignore <- readLines(file.path(tmp, ".gitignore"), warn = FALSE)
    expect_true("htc.cfg" %in% gitignore)
})

test_that("htc_config() does not duplicate htc.cfg in .gitignore", {
    tmp <- withr::local_tempdir()
    withr::local_dir(tmp)
    writeLines("htc.cfg", file.path(tmp, ".gitignore"))
    local_mocked_bindings(
        system2 = function(...) 0L,
        .package = "base"
    )
    htc_config(username = "lares", server = "ap2002.chtc.wisc.edu")
    gitignore <- readLines(file.path(tmp, ".gitignore"), warn = FALSE)
    expect_equal(sum(gitignore == "htc.cfg"), 1L)
})

test_that("htc_config() overwrites existing htc.cfg when overwrite = TRUE", {
    tmp <- withr::local_tempdir()
    withr::local_dir(tmp)
    yaml::write_yaml(
        list(username = "old_user", server = "ap2001.chtc.wisc.edu"),
        file.path(tmp, "htc.cfg")
    )
    local_mocked_bindings(
        system2 = function(...) 0L,
        .package = "base"
    )
    htc_config(
        username  = "lares",
        server    = "ap2002.chtc.wisc.edu",
        overwrite = TRUE
    )
    cfg <- yaml::read_yaml(file.path(tmp, "htc.cfg"))
    expect_equal(cfg$username, "lares")
    expect_equal(cfg$server, "ap2002.chtc.wisc.edu")
})

test_that("htc_config() does not overwrite existing htc.cfg when overwrite = FALSE", {
    tmp <- withr::local_tempdir()
    withr::local_dir(tmp)
    yaml::write_yaml(
        list(username = "old_user", server = "ap2001.chtc.wisc.edu"),
        file.path(tmp, "htc.cfg")
    )
    local_mocked_bindings(
        system2 = function(...) 0L,
        .package = "base"
    )
    htc_config(overwrite = FALSE)
    cfg <- yaml::read_yaml(file.path(tmp, "htc.cfg"))
    expect_equal(cfg$username, "old_user")
})

test_that("htc_config() warns when server is unreachable (exit 255)", {
    tmp <- withr::local_tempdir()
    withr::local_dir(tmp)
    local_mocked_bindings(
        system2 = function(...) 255L,
        .package = "base"
    )
    expect_warning(
        htc_config(username = "lares", server = "ap2002.chtc.wisc.edu"),
        regexp = "reach"
    )
})

test_that("htc_config() informs when connected but not authenticated (non-zero, non-255)", {
    tmp <- withr::local_tempdir()
    withr::local_dir(tmp)
    local_mocked_bindings(
        system2 = function(...) 1L,
        .package = "base"
    )
    expect_message(
        htc_config(username = "lares", server = "ap2002.chtc.wisc.edu"),
        regexp = "authenticat"
    )
})

# ---------------------------------------------------------------------------
# check_server, and the options that set its default
#
# The probe is a convenience for someone sitting at a prompt. In a script,
# a test suite or a CRAN check it has no audience, and reading a config file
# should not require a network.
# ---------------------------------------------------------------------------

test_that("check_server = FALSE skips the probe when reading an existing config", {
    tmp <- withr::local_tempdir()
    withr::local_dir(tmp)
    yaml::write_yaml(
        list(username = "lares", server = "ap2002.chtc.wisc.edu"),
        file.path(tmp, "htc.cfg")
    )
    # Reaching for the network would now fail the test loudly rather than
    # quietly warning, which is the point of the argument.
    local_mocked_bindings(
        system2 = function(...) stop("system2() should not have been called"),
        .package = "base"
    )

    expect_no_error(suppressMessages(htc_config(check_server = FALSE)))
})

test_that("check_server = FALSE skips the probe when creating a config", {
    tmp <- withr::local_tempdir()
    withr::local_dir(tmp)
    local_mocked_bindings(
        system2 = function(...) stop("system2() should not have been called"),
        .package = "base"
    )

    suppressMessages(
        htc_config(
            username     = "lares",
            server       = "ap2002.chtc.wisc.edu",
            check_server = FALSE
        )
    )
    expect_true(file.exists(file.path(tmp, "htc.cfg")))
})

test_that("the submitr.check_server option supplies the default", {
    tmp <- withr::local_tempdir()
    withr::local_dir(tmp)
    withr::local_options(submitr.check_server = FALSE)
    local_mocked_bindings(
        system2 = function(...) stop("system2() should not have been called"),
        .package = "base"
    )

    expect_no_error(
        suppressMessages(
            htc_config(username = "lares", server = "ap2002.chtc.wisc.edu")
        )
    )
})

test_that("an explicit check_server argument overrides the option", {
    tmp <- withr::local_tempdir()
    withr::local_dir(tmp)
    withr::local_options(submitr.check_server = FALSE)
    local_mocked_bindings(system2 = function(...) 255L, .package = "base")

    expect_warning(
        htc_config(
            username     = "lares",
            server       = "ap2002.chtc.wisc.edu",
            check_server = TRUE
        ),
        regexp = "reach"
    )
})

test_that("submitr.verbose = FALSE silences the progress messages", {
    tmp <- withr::local_tempdir()
    withr::local_dir(tmp)
    yaml::write_yaml(
        list(username = "lares", server = "ap2002.chtc.wisc.edu"),
        file.path(tmp, "htc.cfg")
    )
    withr::local_options(submitr.verbose = FALSE)

    expect_no_message(htc_config(check_server = FALSE))
})

test_that("ControlMaster notice references htc_upload/htc_download, not removed functions", {
    tmp <- withr::local_tempdir()
    withr::local_dir(tmp)
    local_mocked_bindings(
        system2 = function(...) 0L,
        .package = "base"
    )
    msg <- capture.output(
        htc_config(username = "lares", server = "ap2002.chtc.wisc.edu"),
        type = "message"
    )
    cmd <- paste(msg, collapse = " ")
    expect_true(grepl("htc_upload", cmd, fixed = TRUE))
    expect_true(grepl("htc_download", cmd, fixed = TRUE))
    expect_false(grepl("htc_stage", cmd, fixed = TRUE))
    expect_false(grepl("htc_fetch_results", cmd, fixed = TRUE))
})

# ---------------------------------------------------------------------------
# Layer 3 — Integration (requires live htc.cfg and CHTC connection)
# ---------------------------------------------------------------------------

test_that("htc_config() connects to a live CHTC server", {
    skip_if_not(
        file.exists("htc.cfg"),
        "htc.cfg not found — skipping live connection test"
    )
    result <- htc_config()
    expect_type(result, "list")
    expect_named(result, c("username", "server"))
    expect_true(nchar(result$username) > 0)
    expect_true(nchar(result$server) > 0)
})
