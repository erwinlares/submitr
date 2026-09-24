# tests/testthat/test-job-manifest.R

# ---------------------------------------------------------------------------
# .update_manifest() and .get_manifest()
#
# The job manifest is persisted to htc-manifest.yaml in `path` (default
# "."), not to session options, so restarting a session no longer discards
# it (see the htc_start() tests below). Tests that call .update_manifest()/
# .get_manifest() without an explicit `path` run inside an isolated
# temporary working directory so no stray htc-manifest.yaml file leaks
# into the package source tree.
# ---------------------------------------------------------------------------

test_that(".get_manifest() returns NULL when no manifest file exists", {
    withr::local_dir(withr::local_tempdir())
    expect_null(.get_manifest())
})

test_that(".get_manifest() returns NULL for an empty manifest file", {
    tmp <- withr::local_tempdir()
    file.create(file.path(tmp, "htc-manifest.yaml"))
    expect_null(.get_manifest(path = tmp))
})

test_that(".update_manifest() stores key-value pairs", {
    withr::local_dir(withr::local_tempdir())
    .update_manifest(mode = "single", cluster_id = "123")
    m <- .get_manifest()
    expect_equal(m$mode, "single")
    expect_equal(m$cluster_id, "123")
})

test_that(".update_manifest() merges without overwriting unrelated keys", {
    withr::local_dir(withr::local_tempdir())
    .update_manifest(mode = "multiple")
    .update_manifest(cluster_id = "456")
    m <- .get_manifest()
    expect_equal(m$mode, "multiple")
    expect_equal(m$cluster_id, "456")
})

test_that(".update_manifest() overwrites existing keys", {
    withr::local_dir(withr::local_tempdir())
    .update_manifest(cluster_id = "100")
    .update_manifest(cluster_id = "200")
    m <- .get_manifest()
    expect_equal(m$cluster_id, "200")
})

test_that(".update_manifest() drops a key when passed NULL for it", {
    withr::local_dir(withr::local_tempdir())
    .update_manifest(subsets = c("a.csv", "b.csv"), mode = "multiple")
    .update_manifest(subsets = NULL, mode = "single")
    m <- .get_manifest()
    expect_null(m$subsets)
    expect_equal(m$mode, "single")
})

test_that(".update_manifest() persists htc-manifest.yaml to disk", {
    tmp <- withr::local_tempdir()
    withr::local_dir(tmp)
    .update_manifest(mode = "single", cluster_id = "999")
    expect_true(file.exists(file.path(tmp, "htc-manifest.yaml")))
})

test_that(".update_manifest() errors when path does not exist", {
    expect_error(
        .update_manifest(mode = "single", path = file.path(tempdir(), "no-such-dir")),
        regexp = "does not exist"
    )
})

test_that(".update_manifest() and .get_manifest() respect a custom path", {
    tmp <- withr::local_tempdir()
    .update_manifest(mode = "single", path = tmp)
    expect_true(file.exists(file.path(tmp, "htc-manifest.yaml")))
    m <- .get_manifest(path = tmp)
    expect_equal(m$mode, "single")
})

test_that(".get_manifest() simplifies stored vectors back to atomic vectors", {
    tmp <- withr::local_tempdir()
    .update_manifest(subsets = c("a.csv", "b.csv"), path = tmp)
    m <- .get_manifest(path = tmp)
    expect_equal(m$subsets, c("a.csv", "b.csv"))
    expect_false(is.list(m$subsets))
})

test_that("the manifest survives a simulated session restart", {
    tmp <- withr::local_tempdir()
    .update_manifest(mode = "single", cluster_id = "4242", path = tmp)

    # Nothing about the manifest lives in session options any more, so
    # clearing every submitr option must leave it intact.
    withr::local_options(submitr.config = NULL, submitr.job_manifest = NULL)

    m <- .get_manifest(path = tmp)
    expect_equal(m$cluster_id, "4242")
})

# ---------------------------------------------------------------------------
# .join_output_path()
# ---------------------------------------------------------------------------

test_that(".join_output_path() leaves the name alone for the working directory", {
    expect_equal(.join_output_path(".", "job.sub"), "job.sub")
    expect_equal(.join_output_path("./", "job.sub"), "job.sub")
    expect_equal(.join_output_path(NULL, "job.sub"), "job.sub")
})

test_that(".join_output_path() joins a real output directory", {
    expect_equal(.join_output_path("jobs", "job.sub"), file.path("jobs", "job.sub"))
})

# ---------------------------------------------------------------------------
# .read_project_config()
#
# Behind htc_config()'s project_config argument (S13). Most of the coverage
# for this lives in test-htc-config.R, exercised through htc_config()
# itself; these test the helper directly.
# ---------------------------------------------------------------------------

test_that(".read_project_config() returns folders and conventions", {
    tmp <- withr::local_tempdir()
    yaml::write_yaml(
        list(
            schema_version = 1L,
            folders        = c("R", "output"),
            conventions    = list(output_dir = "output", script_dir = "R")
        ),
        file.path(tmp, "_toolero.yml")
    )

    result <- .read_project_config(file.path(tmp, "_toolero.yml"))
    expect_equal(result$folders, c("R", "output"))
    expect_equal(result$conventions$output_dir, "output")
})

test_that(".read_project_config() errors when the file does not exist", {
    expect_error(
        .read_project_config(file.path(tempdir(), "no-such-toolero.yml")),
        regexp = "not found"
    )
})

test_that(".read_project_config() handles a config with no conventions", {
    tmp <- withr::local_tempdir()
    yaml::write_yaml(
        list(schema_version = 1L, folders = c("R", "output")),
        file.path(tmp, "_toolero.yml")
    )

    result <- .read_project_config(file.path(tmp, "_toolero.yml"))
    expect_equal(result$folders, c("R", "output"))
    expect_null(result$conventions)
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
        mode        = "multiple",
        script_stem = "analysis",
        subsets     = c("adelie.csv", "chinstrap.csv", "gentoo.csv")
    )
    files <- .resolve_download_files("456", manifest)
    expect_true("analysis-adelie-results.tar.gz" %in% files)
    expect_true("analysis-chinstrap-results.tar.gz" %in% files)
    expect_true("analysis-gentoo-results.tar.gz" %in% files)
})

test_that("multiple mode resolves per-process log files", {
    manifest <- list(
        mode        = "multiple",
        script_stem = "analysis",
        subsets     = c("adelie.csv", "chinstrap.csv", "gentoo.csv")
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
        mode        = "multiple",
        script_stem = "analysis",
        subsets     = c("adelie.csv", "chinstrap.csv", "gentoo.csv")
    )
    files <- .resolve_download_files("456", manifest)
    # 3 tarballs + 9 log files (3 jobs x 3 extensions)
    expect_equal(length(files), 12L)
})

test_that("multiple mode falls back to the subset stem alone without a script stem", {
    manifest <- list(
        mode    = "multiple",
        subsets = c("a.csv", "b.csv")
    )
    files <- .resolve_download_files("789", manifest)
    expect_true("a-results.tar.gz" %in% files)
    expect_true("b-results.tar.gz" %in% files)
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
# .resolve_upload_files()
#
# Every field consumed here is a path as seen from the machine running R,
# never the bare name HTCondor sees on the submit node.
# ---------------------------------------------------------------------------

test_that(".resolve_upload_files() returns character(0) when manifest is NULL", {
    expect_equal(.resolve_upload_files(NULL), character(0))
})

test_that(".resolve_upload_files() returns character(0) for a manifest with no files", {
    expect_equal(.resolve_upload_files(list(mode = "single")), character(0))
})

test_that(".resolve_upload_files() collects submit, executable, and input files", {
    manifest <- list(
        submit_path     = "job.sub",
        executable_path = "job.sh",
        input_files     = "analysis.R"
    )
    files <- .resolve_upload_files(manifest)
    expect_equal(files, c("job.sub", "job.sh", "analysis.R"))
})

test_that(".resolve_upload_files() uses submit_path, not the bare submit_file", {
    manifest <- list(
        submit_file     = "job.sub",
        submit_path     = file.path("jobs", "job.sub"),
        executable_file = "job.sh",
        executable_path = file.path("jobs", "job.sh")
    )
    files <- .resolve_upload_files(manifest)
    expect_equal(files, file.path("jobs", c("job.sub", "job.sh")))
    expect_false("job.sub" %in% files)
})

test_that(".resolve_upload_files() adds subdatasets and subset files in multiple mode", {
    manifest <- list(
        submit_path      = "job.sub",
        executable_path  = "job.sh",
        mode             = "multiple",
        subdatasets_path = "subdatasets.csv",
        subset_files     = c("a.csv", "b.csv")
    )
    files <- .resolve_upload_files(manifest)
    expect_true("subdatasets.csv" %in% files)
    expect_true("a.csv" %in% files)
    expect_true("b.csv" %in% files)
})

test_that(".resolve_upload_files() omits subdatasets and subset files in single mode", {
    manifest <- list(
        submit_path      = "job.sub",
        executable_path  = "job.sh",
        mode             = "single",
        subdatasets_path = "subdatasets.csv",
        subset_files     = c("a.csv", "b.csv")
    )
    files <- .resolve_upload_files(manifest)
    expect_false("subdatasets.csv" %in% files)
    expect_false("a.csv" %in% files)
})

test_that(".resolve_upload_files() drops duplicate entries", {
    manifest <- list(
        submit_path = "job.sub",
        input_files = c("job.sub", "analysis.R")
    )
    files <- .resolve_upload_files(manifest)
    expect_equal(files, c("job.sub", "analysis.R"))
})

# ---------------------------------------------------------------------------
# htc_download() -- manifest-driven resolution
# ---------------------------------------------------------------------------

test_that("htc_download() errors when no files and no manifest", {
    withr::local_dir(withr::local_tempdir())
    withr::local_options(
        submitr.config = list(username = "test", server = "test.edu")
    )
    expect_error(
        htc_download(),
        regexp = "No files specified"
    )
})

test_that("htc_download() errors when no files and no cluster_id in manifest", {
    withr::local_dir(withr::local_tempdir())
    withr::local_options(
        submitr.config = list(username = "test", server = "test.edu")
    )
    .update_manifest(mode = "single", output_files = "results.tar.gz")
    expect_error(
        htc_download(),
        regexp = "No.*cluster_id"
    )
})

test_that("htc_download() uses manifest cluster_id when not supplied explicitly", {
    withr::local_dir(withr::local_tempdir())
    withr::local_options(
        submitr.config = list(username = "test", server = "test.edu")
    )
    .update_manifest(
        mode         = "single",
        output_files = "results.tar.gz",
        cluster_id   = "999"
    )
    expect_message(
        htc_download(dry_run = TRUE, verbose = TRUE),
        regexp = "cluster.*999"
    )
})

test_that("htc_download() explicit cluster_id overrides manifest", {
    withr::local_dir(withr::local_tempdir())
    withr::local_options(
        submitr.config = list(username = "test", server = "test.edu")
    )
    .update_manifest(
        mode         = "single",
        output_files = "results.tar.gz",
        cluster_id   = "999"
    )
    msg <- capture.output(
        htc_download(cluster_id = "888", dry_run = TRUE, verbose = TRUE),
        type = "message"
    )
    expect_true(any(grepl("888", msg)))
    expect_false(any(grepl("999", msg)))
})

test_that("htc_download() reads the manifest from a custom path", {
    tmp <- withr::local_tempdir()
    withr::local_dir(withr::local_tempdir())
    withr::local_options(
        submitr.config = list(username = "test", server = "test.edu")
    )
    .update_manifest(
        mode         = "single",
        output_files = "elsewhere-results.tar.gz",
        cluster_id   = "777",
        path         = tmp
    )
    msg <- capture.output(
        htc_download(dry_run = TRUE, path = tmp),
        type = "message"
    )
    expect_true(grepl("elsewhere-results.tar.gz", paste(msg, collapse = " ")))
})

test_that("htc_download() dry_run shows correct files for single mode", {
    withr::local_dir(withr::local_tempdir())
    withr::local_options(
        submitr.config = list(username = "test", server = "test.edu")
    )
    .update_manifest(
        mode         = "single",
        output_files = "analysis-results.tar.gz",
        cluster_id   = "500"
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
    withr::local_dir(withr::local_tempdir())
    withr::local_options(
        submitr.config = list(username = "test", server = "test.edu")
    )
    .update_manifest(
        mode        = "multiple",
        script_stem = "analysis",
        subsets     = c("adelie.csv", "gentoo.csv"),
        cluster_id  = "600"
    )
    msg <- capture.output(
        htc_download(dry_run = TRUE),
        type = "message"
    )
    cmd <- paste(msg, collapse = " ")
    expect_true(grepl("analysis-adelie-results.tar.gz", cmd))
    expect_true(grepl("analysis-gentoo-results.tar.gz", cmd))
    expect_true(grepl("600-0-job", cmd))
    expect_true(grepl("600-1-job", cmd))
})

# ---------------------------------------------------------------------------
# htc_download() -- remote_path resolution
# ---------------------------------------------------------------------------

test_that("htc_download() uses manifest remote_path when not supplied explicitly", {
    withr::local_dir(withr::local_tempdir())
    withr::local_options(
        submitr.config = list(username = "test", server = "test.edu")
    )
    .update_manifest(
        mode         = "single",
        output_files = "results.tar.gz",
        cluster_id   = "321",
        remote_path  = "~/projects/penguins/"
    )
    msg <- capture.output(
        htc_download(dry_run = TRUE),
        type = "message"
    )
    cmd <- paste(msg, collapse = " ")
    expect_true(grepl("~/projects/penguins/", cmd, fixed = TRUE))
})

test_that("htc_download() explicit remote_path overrides the manifest", {
    withr::local_dir(withr::local_tempdir())
    withr::local_options(
        submitr.config = list(username = "test", server = "test.edu")
    )
    .update_manifest(
        mode         = "single",
        output_files = "results.tar.gz",
        cluster_id   = "321",
        remote_path  = "~/projects/penguins/"
    )
    msg <- capture.output(
        htc_download(remote_path = "~/elsewhere/", dry_run = TRUE),
        type = "message"
    )
    cmd <- paste(msg, collapse = " ")
    expect_true(grepl("~/elsewhere/", cmd, fixed = TRUE))
    expect_false(grepl("penguins", cmd, fixed = TRUE))
})

test_that("htc_download() honours manifest remote_path even with explicit files", {
    withr::local_dir(withr::local_tempdir())
    withr::local_options(
        submitr.config = list(username = "test", server = "test.edu")
    )
    .update_manifest(remote_path = "~/projects/penguins/")
    msg <- capture.output(
        htc_download(files = "my-custom-file.tar.gz", dry_run = TRUE),
        type = "message"
    )
    cmd <- paste(msg, collapse = " ")
    expect_true(grepl("~/projects/penguins/my-custom-file.tar.gz", cmd, fixed = TRUE))
})

test_that("htc_download() defaults remote_path to ~/ when no manifest value exists", {
    withr::local_dir(withr::local_tempdir())
    withr::local_options(
        submitr.config = list(username = "test", server = "test.edu")
    )
    .update_manifest(
        mode         = "single",
        output_files = "results.tar.gz",
        cluster_id   = "321"
    )
    msg <- capture.output(
        htc_download(dry_run = TRUE),
        type = "message"
    )
    cmd <- paste(msg, collapse = " ")
    expect_true(grepl("~/", cmd, fixed = TRUE))
})

test_that("htc_download() with explicit files ignores the manifest file list", {
    withr::local_dir(withr::local_tempdir())
    withr::local_options(
        submitr.config = list(username = "test", server = "test.edu")
    )
    .update_manifest(
        mode         = "single",
        output_files = "manifest-results.tar.gz",
        cluster_id   = "700"
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
# htc_upload() -- manifest-driven resolution
# ---------------------------------------------------------------------------

test_that("htc_upload() errors when files = NULL and no manifest exists", {
    withr::local_dir(withr::local_tempdir())
    cfg <- list(username = "lares", server = "ap2002.chtc.wisc.edu")
    expect_error(
        htc_upload(config = cfg),
        regexp = "files"
    )
})

test_that("htc_upload() resolves files from the manifest when files = NULL", {
    tmp <- withr::local_tempdir()
    withr::local_dir(tmp)
    writeLines("queue 1", file.path(tmp, "job.sub"))
    writeLines("#!/bin/bash", file.path(tmp, "job.sh"))
    .update_manifest(submit_path = "job.sub", executable_path = "job.sh")

    cfg <- list(username = "lares", server = "ap2002.chtc.wisc.edu")
    msg <- capture_messages(
        htc_upload(config = cfg, dry_run = TRUE)
    )
    cmd <- paste(msg, collapse = " ")
    expect_true(grepl("job.sub", cmd, fixed = TRUE))
    expect_true(grepl("job.sh", cmd, fixed = TRUE))
})

test_that("htc_upload() includes subdatasets and subset files in multiple mode", {
    tmp <- withr::local_tempdir()
    withr::local_dir(tmp)
    writeLines("queue 1", file.path(tmp, "job.sub"))
    writeLines("#!/bin/bash", file.path(tmp, "job.sh"))
    writeLines("a", file.path(tmp, "a.csv"))
    writeLines("file", file.path(tmp, "subdatasets.csv"))
    .update_manifest(
        submit_path      = "job.sub",
        executable_path  = "job.sh",
        mode             = "multiple",
        subdatasets_path = "subdatasets.csv",
        subset_files     = "a.csv"
    )

    cfg <- list(username = "lares", server = "ap2002.chtc.wisc.edu")
    msg <- capture_messages(
        htc_upload(config = cfg, dry_run = TRUE)
    )
    cmd <- paste(msg, collapse = " ")
    expect_true(grepl("subdatasets.csv", cmd, fixed = TRUE))
    expect_true(grepl("a.csv", cmd, fixed = TRUE))
})

test_that("htc_upload() reads the manifest from a custom path", {
    project <- withr::local_tempdir()
    jobs    <- withr::local_tempdir()
    withr::local_dir(project)

    writeLines("queue 1", file.path(jobs, "job.sub"))
    .update_manifest(submit_path = file.path(jobs, "job.sub"), path = jobs)

    cfg <- list(username = "lares", server = "ap2002.chtc.wisc.edu")
    msg <- capture_messages(
        htc_upload(config = cfg, dry_run = TRUE, path = jobs)
    )
    expect_true(grepl("job.sub", paste(msg, collapse = " "), fixed = TRUE))
})

test_that("htc_upload() errors informatively when the manifest names a missing file", {
    withr::local_dir(withr::local_tempdir())
    .update_manifest(submit_path = "job.sub")

    cfg <- list(username = "lares", server = "ap2002.chtc.wisc.edu")
    expect_error(
        htc_upload(config = cfg, dry_run = TRUE),
        regexp = "do not exist"
    )
})

test_that("htc_upload() explicit files ignores the manifest", {
    tmp <- withr::local_tempdir()
    withr::local_dir(tmp)
    other <- file.path(tmp, "other.sub")
    writeLines("queue 1", other)
    .update_manifest(submit_path = "job.sub")

    cfg <- list(username = "lares", server = "ap2002.chtc.wisc.edu")
    msg <- capture_messages(
        htc_upload(files = other, config = cfg, dry_run = TRUE)
    )
    cmd <- paste(msg, collapse = " ")
    expect_true(grepl("other.sub", cmd, fixed = TRUE))
    expect_false(grepl("job.sub", cmd, fixed = TRUE))
})

# ---------------------------------------------------------------------------
# Pipeline integration: manifest builds up across functions
# ---------------------------------------------------------------------------

test_that("manifest accumulates across htc_gen_submit and htc_gen_executable", {
    withr::local_dir(withr::local_tempdir())

    .update_manifest(mode = "multiple",
                     output_files = "analysis-$Fn(file)-results.tar.gz",
                     subsets = c("a.csv", "b.csv"))
    .update_manifest(r_script = "analysis.R", results_folder = "results")
    .update_manifest(cluster_id = "12345")

    m <- .get_manifest()
    expect_equal(m$mode, "multiple")
    expect_equal(m$output_files, "analysis-$Fn(file)-results.tar.gz")
    expect_equal(m$subsets, c("a.csv", "b.csv"))
    expect_equal(m$r_script, "analysis.R")
    expect_equal(m$results_folder, "results")
    expect_equal(m$cluster_id, "12345")
})

test_that("the two generators write to one shared manifest", {
    tmp <- withr::local_tempdir()
    withr::local_dir(tmp)
    manifest_csv <- file.path(tmp, "manifest.csv")
    readr::write_csv(
        data.frame(
            group_value = c("adelie", "gentoo"),
            n_rows      = c(100L, 100L),
            file_path   = file.path(tmp, c("adelie.csv", "gentoo.csv"))
        ),
        manifest_csv
    )

    htc_gen_submit(
        mode        = "multiple",
        queue_from  = manifest_csv,
        r_script    = "analysis.R",
        input_files = "analysis.R",
        output      = tmp
    )
    htc_gen_executable(r_script = "analysis.R", output = tmp)

    m <- .get_manifest(path = tmp)
    expect_equal(m$mode, "multiple")
    expect_equal(m$submit_file, "job.sub")
    expect_equal(m$executable_file, "job.sh")
    expect_equal(m$r_script, "analysis.R")
    expect_equal(m$subsets, c("adelie.csv", "gentoo.csv"))
})

test_that("the tarball job.sh builds is the one htc_download() asks for", {
    # The regression guard for the whole naming class. Three places express
    # the same name in three different ways, because three different things
    # resolve them: ${1%.*} on the execute node, $Fn(file) at condor_submit
    # time, and file_path_sans_ext() in R. If they ever drift apart the job
    # runs to completion and then the results quietly fail to come home.
    tmp <- withr::local_tempdir()
    withr::local_dir(tmp)
    manifest_csv <- file.path(tmp, "manifest.csv")
    readr::write_csv(
        data.frame(
            group_value = c("adelie", "gentoo"),
            n_rows      = c(100L, 100L),
            file_path   = file.path(tmp, c("adelie.csv", "gentoo.csv"))
        ),
        manifest_csv
    )

    htc_gen_submit(
        mode        = "multiple",
        queue_from  = manifest_csv,
        r_script    = "R/analysis.R",
        input_files = "R/analysis.R",
        output      = tmp
    )
    htc_gen_executable(
        r_script = "R/analysis.R",
        mode     = "multiple",
        output   = tmp
    )

    # What the shell script creates on the execute node for subset adelie.csv.
    tar_line <- grep("^tar", readLines(file.path(tmp, "job.sh")), value = TRUE)
    built    <- sub("^tar -czf ([^ ]+) .*$", "\\1", tar_line)
    built    <- sub("${1%.*}", "adelie", built, fixed = TRUE)

    # What htc_download() will ask the submit node to send back.
    wanted <- .resolve_download_files("123", .get_manifest(path = tmp))

    expect_equal(built, "analysis-adelie-results.tar.gz")
    expect_true(built %in% wanted)
})

test_that("generated files are findable via the paths the manifest records", {
    tmp <- withr::local_tempdir()
    withr::local_dir(tmp)
    htc_gen_submit(output = tmp)
    htc_gen_executable(r_script = "analysis.R", output = tmp)

    m <- .get_manifest(path = tmp)
    # The regression this guards: recording bare filenames rather than paths
    # made htc_upload() look for job.sub in the working directory.
    expect_true(file.exists(m$submit_path))
    expect_true(file.exists(m$executable_path))
})

test_that("htc_start() does not clear an existing job manifest", {
    tmp <- withr::local_tempdir()
    withr::local_dir(tmp)
    withr::local_options(submitr.config = NULL)


    # Simulate a manifest left over from an earlier session, e.g. one that
    # ended (or crashed) after htc_gen_submit()/htc_gen_executable() but
    # before htc_download().
    .update_manifest(cluster_id = "old_job")

    writeLines("username: testuser\nserver: testserver.edu\n",
               file.path(tmp, "htc.cfg"))

    suppressMessages(htc_start(path = tmp, check_server = FALSE))

    m <- .get_manifest()
    expect_equal(m$cluster_id, "old_job")
})
