# tests/testthat/test-htc-collect.R
#
# htc_collect() -- unpack downloaded results and return the job index, one
# row per job (S27). It never parses what the jobs wrote, so none of these
# tests need toolero or a valid output record.

# ---------------------------------------------------------------------------
# Fixture helpers
# ---------------------------------------------------------------------------

# Builds a results tarball the way a generated executable would: a tar of
# the results folder, taken from the job's scratch directory. `files` are
# paths inside the results folder; each gets a small RDS. `record = TRUE`
# adds a project-manifest.json whose content is deliberately not JSON, to
# show htc_collect() only checks that the file exists.
.build_result_tarball <- function(tarball_path,
                                  files          = "mtcars.rds",
                                  record         = FALSE,
                                  results_folder = "output") {
    build_dir <- withr::local_tempdir(.local_envir = parent.frame())
    out_dir   <- file.path(build_dir, results_folder)
    dir.create(out_dir, recursive = TRUE)

    for (f in files) {
        dir.create(dirname(file.path(out_dir, f)), recursive = TRUE,
                   showWarnings = FALSE)
        saveRDS(mtcars, file.path(out_dir, f))
    }
    if (record) {
        writeLines("not parsed by htc_collect()", file.path(out_dir, "project-manifest.json"))
    }

    withr::with_dir(build_dir, {
        suppressWarnings(
            utils::tar(tarball_path, files = results_folder,
                       compression = "gzip", tar = "internal")
        )
    })
    invisible(tarball_path)
}

# Writes the three HTCondor files htc_download() would have fetched.
.write_logs <- function(dir, cluster_id, proc_id) {
    for (ext in c("log", "err", "out")) {
        writeLines(ext, file.path(dir, paste0(cluster_id, "-", proc_id, "-job.", ext)))
    }
}

.state_single <- function(path, cluster_id = "6302860") {
    .update_manifest(
        mode            = "single",
        script_stem     = "analysis",
        output_files    = "analysis-results.tar.gz",
        results_folder  = "output",
        cluster_id      = cluster_id,
        container_image = "docker://registry.doit.wisc.edu/netid/img:1.0.0",
        path            = path
    )
}

.state_multiple <- function(path, subsets = c("adelie.csv", "chinstrap.csv", "gentoo.csv"),
                            cluster_id = "6302861") {
    .update_manifest(
        mode            = "multiple",
        script_stem     = "analysis",
        subsets         = subsets,
        results_folder  = "output",
        cluster_id      = cluster_id,
        container_image = "docker://registry.doit.wisc.edu/netid/img:1.0.0",
        path            = path
    )
}

job_index_columns <- c(
    "group_id", "proc_id", "cluster_id", "extracted", "n_files",
    "has_record", "output_dir", "files", "log", "err", "out",
    "container_image"
)

# ---------------------------------------------------------------------------
# Layer 1 -- argument validation
# ---------------------------------------------------------------------------

test_that("htc_collect() errors when no tarballs can be resolved", {
    withr::local_dir(withr::local_tempdir())
    expect_error(htc_collect(), regexp = "No tarballs")
})

test_that("htc_collect() errors when explicit tarballs are unnamed", {
    tmp <- withr::local_tempdir()
    f <- file.path(tmp, "results.tar.gz")
    writeLines("x", f)
    expect_error(
        htc_collect(tarballs = f),
        regexp = "named character vector"
    )
})

test_that("htc_collect() errors on duplicate group ids", {
    tmp <- withr::local_tempdir()
    f1 <- file.path(tmp, "a.tar.gz")
    f2 <- file.path(tmp, "b.tar.gz")
    writeLines("x", f1)
    writeLines("x", f2)
    expect_error(
        htc_collect(tarballs = c(adelie = f1, adelie = f2)),
        regexp = "duplicate"
    )
})

test_that("an existing folder stops the collection before anything is extracted", {
    state       <- withr::local_tempdir()
    local_path  <- withr::local_tempdir()
    extract_dir <- withr::local_tempdir()
    .state_multiple(state, subsets = c("adelie.csv", "gentoo.csv"))
    .build_result_tarball(file.path(local_path, "analysis-adelie-results.tar.gz"))
    .build_result_tarball(file.path(local_path, "analysis-gentoo-results.tar.gz"))

    dir.create(file.path(extract_dir, "gentoo"))

    expect_error(
        htc_collect(local_path = local_path, extract_dir = extract_dir, path = state),
        regexp = "already exist"
    )
    # adelie comes first in the loop, but the check runs before the loop.
    expect_false(dir.exists(file.path(extract_dir, "adelie")))
})

# ---------------------------------------------------------------------------
# Layer 2 -- single mode
# ---------------------------------------------------------------------------

test_that("htc_collect() returns the job index with the documented columns", {
    state      <- withr::local_tempdir()
    local_path <- withr::local_tempdir()
    .state_single(state)
    .build_result_tarball(file.path(local_path, "analysis-results.tar.gz"))

    index <- suppressMessages(htc_collect(
        local_path  = local_path,
        extract_dir = withr::local_tempdir(),
        path        = state
    ))

    expect_s3_class(index, "tbl_df")
    expect_identical(names(index), job_index_columns)
    expect_equal(nrow(index), 1L)
})

test_that("a single-mode job is indexed with values from the submission state", {
    state       <- withr::local_tempdir()
    local_path  <- withr::local_tempdir()
    extract_dir <- withr::local_tempdir()
    .state_single(state, cluster_id = "6302860")
    .build_result_tarball(file.path(local_path, "analysis-results.tar.gz"))

    index <- suppressMessages(htc_collect(
        local_path  = local_path,
        extract_dir = extract_dir,
        path        = state
    ))

    expect_equal(index$group_id, "analysis")
    expect_identical(index$proc_id, 0L)
    expect_equal(index$cluster_id, "6302860")
    expect_true(index$extracted)
    expect_identical(index$n_files, 1L)
    expect_false(index$has_record)
    expect_equal(index$output_dir, file.path(extract_dir, "analysis", "output"))
    expect_true(dir.exists(index$output_dir))
    expect_equal(index$files[[1]], "mtcars.rds")
    expect_equal(index$container_image, "docker://registry.doit.wisc.edu/netid/img:1.0.0")
})

test_that("files are relative to output_dir and include nested folders", {
    state      <- withr::local_tempdir()
    local_path <- withr::local_tempdir()
    .state_single(state)
    .build_result_tarball(
        file.path(local_path, "analysis-results.tar.gz"),
        files = c("tables/summary.rds", "figures/mass.rds")
    )

    index <- suppressMessages(htc_collect(
        local_path  = local_path,
        extract_dir = withr::local_tempdir(),
        path        = state
    ))

    expect_setequal(index$files[[1]], c("figures/mass.rds", "tables/summary.rds"))
    expect_true(all(file.exists(file.path(index$output_dir, index$files[[1]]))))
})

test_that("has_record reports an output record without reading it", {
    state      <- withr::local_tempdir()
    local_path <- withr::local_tempdir()
    .state_single(state)
    .build_result_tarball(file.path(local_path, "analysis-results.tar.gz"), record = TRUE)

    # The record's content is not JSON; a parser would fail here.
    expect_no_error(
        index <- suppressMessages(htc_collect(
            local_path  = local_path,
            extract_dir = withr::local_tempdir(),
            path        = state
        ))
    )
    expect_true(index$has_record)
    expect_true("project-manifest.json" %in% index$files[[1]])
})

test_that("log, err, and out point at the HTCondor files beside the tarball", {
    state      <- withr::local_tempdir()
    local_path <- withr::local_tempdir()
    .state_single(state, cluster_id = "6302860")
    .build_result_tarball(file.path(local_path, "analysis-results.tar.gz"))
    .write_logs(local_path, "6302860", 0L)

    index <- suppressMessages(htc_collect(
        local_path  = local_path,
        extract_dir = withr::local_tempdir(),
        path        = state
    ))

    expect_equal(index$log, file.path(local_path, "6302860-0-job.log"))
    expect_equal(index$err, file.path(local_path, "6302860-0-job.err"))
    expect_equal(index$out, file.path(local_path, "6302860-0-job.out"))
})

test_that("log, err, and out are NA when the files were not downloaded", {
    state      <- withr::local_tempdir()
    local_path <- withr::local_tempdir()
    .state_single(state)
    .build_result_tarball(file.path(local_path, "analysis-results.tar.gz"))

    index <- suppressMessages(htc_collect(
        local_path  = local_path,
        extract_dir = withr::local_tempdir(),
        path        = state
    ))

    expect_true(is.na(index$log))
    expect_true(is.na(index$err))
    expect_true(is.na(index$out))
})

test_that("an empty results folder is indexed as zero files, without a warning", {
    state      <- withr::local_tempdir()
    local_path <- withr::local_tempdir()
    .state_single(state)
    .build_result_tarball(file.path(local_path, "analysis-results.tar.gz"),
                          files = character(0))

    expect_no_warning(
        index <- suppressMessages(htc_collect(
            local_path  = local_path,
            extract_dir = withr::local_tempdir(),
            path        = state
        ))
    )
    expect_true(index$extracted)
    expect_identical(index$n_files, 0L)
    expect_identical(index$files[[1]], character(0))
})

test_that("a tarball without the results folder is extracted, flagged, and warned about", {
    state      <- withr::local_tempdir()
    local_path <- withr::local_tempdir()
    .state_single(state)
    .build_result_tarball(file.path(local_path, "analysis-results.tar.gz"),
                          results_folder = "results")

    expect_warning(
        index <- suppressMessages(htc_collect(
            local_path  = local_path,
            extract_dir = withr::local_tempdir(),
            path        = state
        )),
        regexp = "no .*output"
    )
    expect_true(index$extracted)
    expect_true(is.na(index$output_dir))
    expect_identical(index$n_files, 0L)
})

test_that("overwrite = TRUE re-extracts over an earlier collection", {
    state       <- withr::local_tempdir()
    local_path  <- withr::local_tempdir()
    extract_dir <- withr::local_tempdir()
    .state_single(state)
    .build_result_tarball(file.path(local_path, "analysis-results.tar.gz"))

    suppressMessages(htc_collect(local_path = local_path, extract_dir = extract_dir, path = state))

    expect_error(
        htc_collect(local_path = local_path, extract_dir = extract_dir, path = state),
        regexp = "already exist"
    )
    expect_no_error(suppressMessages(htc_collect(
        local_path  = local_path,
        extract_dir = extract_dir,
        path        = state,
        overwrite   = TRUE
    )))
})

# ---------------------------------------------------------------------------
# Layer 3 -- multiple mode
# ---------------------------------------------------------------------------

test_that("three subsets give a three-row index, in submission order, with no warnings", {
    state      <- withr::local_tempdir()
    local_path <- withr::local_tempdir()
    .state_multiple(state)
    for (g in c("adelie", "chinstrap", "gentoo")) {
        .build_result_tarball(file.path(local_path, paste0("analysis-", g, "-results.tar.gz")))
    }

    expect_no_warning(
        index <- suppressMessages(htc_collect(
            local_path  = local_path,
            extract_dir = withr::local_tempdir(),
            path        = state
        ))
    )
    expect_equal(nrow(index), 3L)
    expect_equal(index$group_id, c("adelie", "chinstrap", "gentoo"))
    expect_identical(index$proc_id, 0:2)
    expect_true(all(index$extracted))
    expect_equal(unique(index$cluster_id), "6302861")
})

test_that("a missing tarball becomes a failed row and a warning, not an error", {
    state      <- withr::local_tempdir()
    local_path <- withr::local_tempdir()
    .state_multiple(state, cluster_id = "6302861")
    .build_result_tarball(file.path(local_path, "analysis-adelie-results.tar.gz"))
    .build_result_tarball(file.path(local_path, "analysis-gentoo-results.tar.gz"))
    # chinstrap (process 1) failed: no tarball, but its logs came back.
    .write_logs(local_path, "6302861", 1L)

    expect_warning(
        index <- suppressMessages(htc_collect(
            local_path  = local_path,
            extract_dir = withr::local_tempdir(),
            path        = state
        )),
        regexp = "1 of 3 tarballs could not be collected"
    )

    failed <- index[index$group_id == "chinstrap", ]
    expect_false(failed$extracted)
    expect_true(is.na(failed$output_dir))
    expect_true(is.na(failed$n_files))
    expect_true(is.na(failed$has_record))
    expect_identical(failed$files[[1]], character(0))
    expect_equal(failed$err, file.path(local_path, "6302861-1-job.err"))

    expect_true(all(index$extracted[index$group_id != "chinstrap"]))
})

test_that("a tarball that will not extract becomes a failed row and a warning", {
    state      <- withr::local_tempdir()
    local_path <- withr::local_tempdir()
    extract_dir <- withr::local_tempdir()
    .state_single(state)
    writeLines("not a tarball", file.path(local_path, "analysis-results.tar.gz"))

    expect_warning(
        index <- suppressMessages(htc_collect(
            local_path  = local_path,
            extract_dir = extract_dir,
            path        = state
        )),
        regexp = "Could not be extracted"
    )
    expect_false(index$extracted)
    # A failed extraction leaves nothing half-written behind.
    expect_false(dir.exists(file.path(extract_dir, "analysis")))
})

test_that("explicit tarballs that do not exist become failed rows", {
    expect_warning(
        index <- suppressMessages(htc_collect(
            tarballs    = c(adelie = "/nonexistent/adelie-results.tar.gz"),
            extract_dir = withr::local_tempdir(),
            path        = withr::local_tempdir()
        )),
        regexp = "Not found"
    )
    expect_false(index$extracted)
})

test_that("explicit tarballs match process numbers from the submission state when they can", {
    state      <- withr::local_tempdir()
    local_path <- withr::local_tempdir()
    .state_multiple(state)
    adelie <- .build_result_tarball(file.path(local_path, "analysis-adelie-results.tar.gz"))
    other  <- .build_result_tarball(file.path(local_path, "elsewhere.tar.gz"))

    index <- suppressMessages(htc_collect(
        tarballs    = c(gentoo = adelie, stray = other),
        extract_dir = withr::local_tempdir(),
        path        = state
    ))

    expect_identical(index$proc_id, c(2L, NA_integer_))
})

test_that("explicit tarballs work with no submission state at all", {
    local_path <- withr::local_tempdir()
    tarball    <- .build_result_tarball(file.path(local_path, "analysis-results.tar.gz"))

    index <- suppressMessages(htc_collect(
        tarballs    = c(analysis = tarball),
        extract_dir = withr::local_tempdir(),
        path        = withr::local_tempdir()
    ))

    expect_true(index$extracted)
    expect_true(is.na(index$proc_id))
    expect_true(is.na(index$cluster_id))
    expect_true(is.na(index$container_image))
    expect_true(is.na(index$err))
})

# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

test_that(".collect_proc_ids() numbers subsets from zero in submission order", {
    manifest <- list(mode = "multiple", subsets = c("a.csv", "b.csv", "c.csv"))
    expect_identical(.collect_proc_ids(c("c", "a", "z"), manifest), c(2L, 0L, NA_integer_))
})

test_that(".collect_proc_ids() gives a single-mode job process 0", {
    manifest <- list(mode = "single", script_stem = "analysis")
    expect_identical(.collect_proc_ids("analysis", manifest), 0L)
    expect_identical(.collect_proc_ids(c("analysis", "other"), manifest), c(0L, NA_integer_))
})

test_that(".collect_proc_ids() returns NA without a submission state", {
    expect_identical(.collect_proc_ids(c("a", "b"), NULL), c(NA_integer_, NA_integer_))
})
