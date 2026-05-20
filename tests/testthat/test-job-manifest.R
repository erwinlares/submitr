# tests/testthat/test-job-manifest.R

# ---------------------------------------------------------------------------
# .update_manifest() and .get_manifest()
# ---------------------------------------------------------------------------

test_that(".get_manifest() returns NULL when no manifest is set", {
    withr::local_options(submitr.job_manifest = NULL)
    expect_null(.get_manifest())
})

test_that(".update_manifest() stores key-value pairs", {
    withr::local_options(submitr.job_manifest = NULL)
    .update_manifest(mode = "single", cluster_id = "123")
    m <- .get_manifest()
    expect_equal(m$mode, "single")
    expect_equal(m$cluster_id, "123")
})

test_that(".update_manifest() merges without overwriting unrelated keys", {
    withr::local_options(submitr.job_manifest = NULL)
    .update_manifest(mode = "multiple")
    .update_manifest(cluster_id = "456")
    m <- .get_manifest()
    expect_equal(m$mode, "multiple")
    expect_equal(m$cluster_id, "456")
})

test_that(".update_manifest() overwrites existing keys", {
    withr::local_options(submitr.job_manifest = NULL)
    .update_manifest(cluster_id = "100")
    .update_manifest(cluster_id = "200")
    m <- .get_manifest()
    expect_equal(m$cluster_id, "200")
})

# ---------------------------------------------------------------------------
# .resolve_download_files() -- single mode
# ---------------------------------------------------------------------------

test_that("single mode resolves tarball and three log files", {
    manifest <- list(
        mode         = "single",
        output_files = "analysis-results.tar.gz",
        subsets      = NULL
    )
    files <- .resolve_download_files("123", manifest)
    expect_true("analysis-results.tar.gz" %in% files)
    expect_true("123-0-job.log" %in% files)
    expect_true("123-0-job.err" %in% files)
    expect_true("123-0-job.out" %in% files)
    expect_equal(length(files), 4L)
})

# ---------------------------------------------------------------------------
# .resolve_download_files() -- multiple mode
# ---------------------------------------------------------------------------

test_that("multiple mode resolves per-subset tarballs", {
    manifest <- list(
        mode         = "multiple",
        output_files = "$(file)-results.tar.gz",
        subsets      = c("adelie.csv", "chinstrap.csv", "gentoo.csv")
    )
    files <- .resolve_download_files("456", manifest)
    expect_true("adelie.csv-results.tar.gz" %in% files)
    expect_true("chinstrap.csv-results.tar.gz" %in% files)
    expect_true("gentoo.csv-results.tar.gz" %in% files)
})

test_that("multiple mode resolves per-process log files", {
    manifest <- list(
        mode         = "multiple",
        output_files = "$(file)-results.tar.gz",
        subsets      = c("adelie.csv", "chinstrap.csv", "gentoo.csv")
    )
    files <- .resolve_download_files("456", manifest)
    expect_true("456-0-job.log" %in% files)
    expect_true("456-1-job.log" %in% files)
    expect_true("456-2-job.log" %in% files)
    expect_true("456-0-job.err" %in% files)
    expect_true("456-1-job.err" %in% files)
    expect_true("456-2-job.err" %in% files)
    expect_true("456-0-job.out" %in% files)
    expect_true("456-1-job.out" %in% files)
    expect_true("456-2-job.out" %in% files)
})

test_that("multiple mode total file count is correct", {
    manifest <- list(
        mode         = "multiple",
        output_files = "$(file)-results.tar.gz",
        subsets      = c("adelie.csv", "chinstrap.csv", "gentoo.csv")
    )
    files <- .resolve_download_files("456", manifest)
    # 3 tarballs + 9 log files (3 jobs x 3 extensions)
    expect_equal(length(files), 12L)
})

test_that("multiple mode uses default tarball pattern when output_files is NULL", {
    manifest <- list(
        mode    = "multiple",
        subsets = c("a.csv", "b.csv")
    )
    files <- .resolve_download_files("789", manifest)
    expect_true("a.csv-results.tar.gz" %in% files)
    expect_true("b.csv-results.tar.gz" %in% files)
})

# ---------------------------------------------------------------------------
# .resolve_download_files() -- edge cases
# ---------------------------------------------------------------------------

test_that("defaults to single mode when mode is NULL in manifest", {
    manifest <- list(
        output_files = "results.tar.gz"
    )
    files <- .resolve_download_files("100", manifest)
    expect_true("results.tar.gz" %in% files)
    expect_true("100-0-job.log" %in% files)
    expect_equal(length(files), 4L)
})

# ---------------------------------------------------------------------------
# htc_download() -- manifest-driven resolution
# ---------------------------------------------------------------------------

test_that("htc_download() errors when no files and no manifest", {
    withr::local_options(
        submitr.config       = list(username = "test", server = "test.edu"),
        submitr.job_manifest = NULL
    )
    expect_error(
        htc_download(),
        regexp = "No files specified"
    )
})

test_that("htc_download() errors when no files and no cluster_id in manifest", {
    withr::local_options(
        submitr.config       = list(username = "test", server = "test.edu"),
        submitr.job_manifest = list(mode = "single", output_files = "results.tar.gz")
    )
    expect_error(
        htc_download(),
        regexp = "No.*cluster_id"
    )
})

test_that("htc_download() uses manifest cluster_id when not supplied explicitly", {
    withr::local_options(
        submitr.config       = list(username = "test", server = "test.edu"),
        submitr.job_manifest = list(
            mode         = "single",
            output_files = "results.tar.gz",
            cluster_id   = "999"
        )
    )
    expect_message(
        htc_download(dry_run = TRUE, verbose = TRUE),
        regexp = "cluster.*999"
    )
})

test_that("htc_download() explicit cluster_id overrides manifest", {
    withr::local_options(
        submitr.config       = list(username = "test", server = "test.edu"),
        submitr.job_manifest = list(
            mode         = "single",
            output_files = "results.tar.gz",
            cluster_id   = "999"
        )
    )
    msg <- capture.output(
        htc_download(cluster_id = "888", dry_run = TRUE, verbose = TRUE),
        type = "message"
    )
    expect_true(any(grepl("888", msg)))
    expect_false(any(grepl("999", msg)))
})

test_that("htc_download() dry_run shows correct files for single mode", {
    withr::local_options(
        submitr.config       = list(username = "test", server = "test.edu"),
        submitr.job_manifest = list(
            mode         = "single",
            output_files = "analysis-results.tar.gz",
            cluster_id   = "500"
        )
    )
    msg <- capture.output(
        htc_download(dry_run = TRUE),
        type = "message"
    )
    cmd <- paste(msg, collapse = " ")
    expect_true(grepl("analysis-results.tar.gz", cmd))
    expect_true(grepl("500-0-job.log", cmd))
})

test_that("htc_download() dry_run shows correct files for multiple mode", {
    withr::local_options(
        submitr.config       = list(username = "test", server = "test.edu"),
        submitr.job_manifest = list(
            mode         = "multiple",
            output_files = "$(file)-results.tar.gz",
            subsets      = c("adelie.csv", "gentoo.csv"),
            cluster_id   = "600"
        )
    )
    msg <- capture.output(
        htc_download(dry_run = TRUE),
        type = "message"
    )
    cmd <- paste(msg, collapse = " ")
    expect_true(grepl("adelie.csv-results.tar.gz", cmd))
    expect_true(grepl("gentoo.csv-results.tar.gz", cmd))
    expect_true(grepl("600-0-job", cmd))
    expect_true(grepl("600-1-job", cmd))
})

test_that("htc_download() with explicit files ignores manifest", {
    withr::local_options(
        submitr.config       = list(username = "test", server = "test.edu"),
        submitr.job_manifest = list(
            mode         = "single",
            output_files = "manifest-results.tar.gz",
            cluster_id   = "700"
        )
    )
    msg <- capture.output(
        htc_download(files = "my-custom-file.tar.gz", dry_run = TRUE),
        type = "message"
    )
    cmd <- paste(msg, collapse = " ")
    expect_true(grepl("my-custom-file.tar.gz", cmd))
    expect_false(grepl("manifest-results", cmd))
})

# ---------------------------------------------------------------------------
# Pipeline integration: manifest builds up across functions
# ---------------------------------------------------------------------------

test_that("manifest accumulates across htc_gen_submit and htc_gen_executable", {
    withr::local_options(submitr.job_manifest = NULL)

    .update_manifest(mode = "multiple", output_files = "$(file)-results.tar.gz",
                     subsets = c("a.csv", "b.csv"))
    .update_manifest(r_script = "analysis.R", results_folder = "results")
    .update_manifest(cluster_id = "12345")

    m <- .get_manifest()
    expect_equal(m$mode, "multiple")
    expect_equal(m$output_files, "$(file)-results.tar.gz")
    expect_equal(m$subsets, c("a.csv", "b.csv"))
    expect_equal(m$r_script, "analysis.R")
    expect_equal(m$results_folder, "results")
    expect_equal(m$cluster_id, "12345")
})

test_that("htc_start clears stale manifest", {
    withr::local_options(
        submitr.job_manifest = list(cluster_id = "old_job"),
        submitr.config       = NULL
    )

    tmp <- withr::local_tempdir()
    writeLines("username: testuser\nserver: testserver.edu\n",
               file.path(tmp, "htc.cfg"))

    suppressMessages(htc_start(path = tmp))

    expect_null(.get_manifest())
})
