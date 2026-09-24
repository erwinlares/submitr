# tests/testthat/test-htc-collect.R
#
# htc_collect() -- stitching multi-job results back into one tibble (S-G1).

.make_project_manifest_json <- function(file_path, r_class = "data.frame") {
    as.character(jsonlite::toJSON(
        list(
            execution_context = "rscript",
            generated_at      = "2026-09-24T00:00:00.000Z",
            artifacts = list(list(
                file_path      = file_path,
                r_class        = r_class,
                timestamp      = "2026-09-24T00:00:00.000Z",
                function_used  = "saveRDS",
                status         = "success",
                error_message  = NA,
                note           = NA
            ))
        ),
        auto_unbox = TRUE, na = "null"
    ))
}

.build_result_tarball <- function(build_dir, tarball_path, file_name, r_class = "data.frame") {
    out_dir <- file.path(build_dir, "output")
    dir.create(out_dir, recursive = TRUE)
    saveRDS(mtcars, file.path(out_dir, file_name))
    writeLines(
        .make_project_manifest_json(file.path("output", file_name), r_class),
        file.path(out_dir, "project-manifest.json")
    )
    withr::with_dir(build_dir, {
        utils::tar(tarball_path, files = "output", compression = "gzip", tar = "internal")
    })
    invisible(tarball_path)
}

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

test_that("htc_collect() errors when a supplied tarball does not exist", {
    expect_error(
        htc_collect(tarballs = c(adelie = "/nonexistent/adelie-results.tar.gz")),
        regexp = "not found"
    )
})

# ---------------------------------------------------------------------------
# Layer 2 -- single mode
# ---------------------------------------------------------------------------

test_that("htc_collect() extracts a single-mode tarball and reads its project manifest", {
    build_dir  <- withr::local_tempdir()
    local_path <- withr::local_tempdir()
    tarball    <- file.path(local_path, "analysis-results.tar.gz")
    .build_result_tarball(build_dir, tarball, "mtcars.rds")

    manifest_dir <- withr::local_tempdir()
    .update_manifest(
        mode            = "single",
        script_stem     = "analysis",
        output_files    = "analysis-results.tar.gz",
        results_folder  = "output",
        path            = manifest_dir
    )

    extract_dir <- withr::local_tempdir()
    result <- suppressMessages(htc_collect(
        local_path  = local_path,
        extract_dir = extract_dir,
        path        = manifest_dir
    ))

    expect_equal(nrow(result), 1L)
    expect_equal(result$group_id, "analysis")
    expect_equal(result$file_path, "output/mtcars.rds")
    expect_true(file.exists(result$local_path))
    expect_equal(result$r_class, "data.frame")
    expect_equal(result$job_execution_context, "rscript")
})

# ---------------------------------------------------------------------------
# Layer 3 -- multiple mode
# ---------------------------------------------------------------------------

test_that("htc_collect() merges results across subsets with a group_id column", {
    manifest_dir <- withr::local_tempdir()
    local_path   <- withr::local_tempdir()

    build_adelie <- withr::local_tempdir()
    build_gentoo <- withr::local_tempdir()

    tarball_adelie <- file.path(local_path, "analysis-adelie-results.tar.gz")
    tarball_gentoo <- file.path(local_path, "analysis-gentoo-results.tar.gz")

    .build_result_tarball(build_adelie, tarball_adelie, "adelie-fit.rds", r_class = "lm")
    .build_result_tarball(build_gentoo, tarball_gentoo, "gentoo-fit.rds", r_class = "lm")

    .update_manifest(
        mode            = "multiple",
        script_stem     = "analysis",
        subsets         = c("adelie.csv", "gentoo.csv"),
        results_folder  = "output",
        path            = manifest_dir
    )

    extract_dir <- withr::local_tempdir()
    result <- suppressMessages(htc_collect(
        local_path  = local_path,
        extract_dir = extract_dir,
        path        = manifest_dir
    ))

    expect_equal(nrow(result), 2L)
    expect_setequal(result$group_id, c("adelie", "gentoo"))
    expect_true(all(file.exists(result$local_path)))
})

test_that("htc_collect() falls back to accumulator.csv with a warning when no project manifest exists", {
    build_dir  <- withr::local_tempdir()
    local_path <- withr::local_tempdir()
    tarball    <- file.path(local_path, "analysis-results.tar.gz")

    out_dir <- file.path(build_dir, "output")
    dir.create(out_dir)
    saveRDS(mtcars, file.path(out_dir, "mtcars.rds"))
    writeLines(
        c(
            '"file_path","r_class","timestamp","function_used","status","error_message","note"',
            '"output/mtcars.rds","data.frame","2026-09-24T00:00:00.000Z","saveRDS","success",,'
        ),
        file.path(out_dir, "accumulator.csv")
    )
    withr::with_dir(build_dir, {
        utils::tar(tarball, files = "output", compression = "gzip", tar = "internal")
    })

    manifest_dir <- withr::local_tempdir()
    .update_manifest(
        mode           = "single",
        script_stem    = "analysis",
        output_files   = "analysis-results.tar.gz",
        results_folder = "output",
        path           = manifest_dir
    )

    extract_dir <- withr::local_tempdir()
    expect_warning(
        result <- htc_collect(
            local_path  = local_path,
            extract_dir = extract_dir,
            path        = manifest_dir
        ),
        regexp = "accumulator"
    )

    expect_equal(nrow(result), 1L)
    expect_true(is.na(result$job_execution_context))
})

test_that("htc_collect() refuses to overwrite an existing extraction by default", {
    build_dir  <- withr::local_tempdir()
    local_path <- withr::local_tempdir()
    tarball    <- file.path(local_path, "analysis-results.tar.gz")
    .build_result_tarball(build_dir, tarball, "mtcars.rds")

    manifest_dir <- withr::local_tempdir()
    .update_manifest(
        mode           = "single",
        script_stem    = "analysis",
        output_files   = "analysis-results.tar.gz",
        results_folder = "output",
        path           = manifest_dir
    )

    extract_dir <- withr::local_tempdir()
    suppressMessages(htc_collect(local_path = local_path, extract_dir = extract_dir, path = manifest_dir))

    expect_error(
        htc_collect(local_path = local_path, extract_dir = extract_dir, path = manifest_dir),
        regexp = "already exists"
    )

    expect_no_error(suppressMessages(htc_collect(
        local_path  = local_path,
        extract_dir = extract_dir,
        path        = manifest_dir,
        overwrite   = TRUE
    )))
})
