# tests/testthat/test-htc-gen-executable.R

read_script <- function(dir, filename = "job.sh") {
    readLines(file.path(dir, filename))
}

# ---------------------------------------------------------------------------
# File creation
# ---------------------------------------------------------------------------

test_that("htc_gen_executable() writes a .sh file to the output directory", {
    tmp <- withr::local_tempdir()
    htc_gen_executable(r_script = "analysis.R", output = tmp)
    expect_true(file.exists(file.path(tmp, "job.sh")))
})

test_that("htc_gen_executable() respects custom output_file name", {
    tmp <- withr::local_tempdir()
    htc_gen_executable(
        r_script    = "analysis.R",
        output_file = "analysis.sh",
        output      = tmp
    )
    expect_true(file.exists(file.path(tmp, "analysis.sh")))
})

test_that("htc_gen_executable() returns invisible NULL", {
    tmp <- withr::local_tempdir()
    result <- htc_gen_executable(r_script = "analysis.R", output = tmp)
    expect_null(result)
})

# ---------------------------------------------------------------------------
# Argument validation
# ---------------------------------------------------------------------------

test_that("htc_gen_executable() errors when output_file does not end in .sh", {
    tmp <- withr::local_tempdir()
    expect_error(
        htc_gen_executable(
            r_script    = "analysis.R",
            output_file = "job.bash",
            output      = tmp
        ),
        regexp = "\\.sh"
    )
})

test_that("htc_gen_executable() errors when output directory does not exist", {
    expect_error(
        htc_gen_executable(r_script = "analysis.R", output = "/nonexistent/path"),
        regexp = "does not exist"
    )
})

test_that("htc_gen_executable() errors on invalid mode", {
    tmp <- withr::local_tempdir()
    expect_error(
        htc_gen_executable(r_script = "analysis.R", mode = "batch", output = tmp),
        regexp = "should be one of"
    )
})

test_that("htc_gen_executable() errors when r_script is NULL", {
    tmp <- withr::local_tempdir()
    expect_error(
        htc_gen_executable(output = tmp),
        regexp = "r_script"
    )
})

# ---------------------------------------------------------------------------
# Script content -- shebang and shell options
# ---------------------------------------------------------------------------

test_that("script starts with #!/bin/bash", {
    tmp <- withr::local_tempdir()
    htc_gen_executable(r_script = "analysis.R", output = tmp)
    lines <- read_script(tmp)

    expect_equal(lines[[1]], "#!/bin/bash")
})

test_that("script includes set -euo pipefail after shebang", {
    tmp <- withr::local_tempdir()
    htc_gen_executable(r_script = "analysis.R", output = tmp)
    lines <- read_script(tmp)

    expect_equal(lines[[2]], "set -euo pipefail")
})

# ---------------------------------------------------------------------------
# Script content -- working directory
# ---------------------------------------------------------------------------

test_that("script changes to HTCondor scratch directory", {
    tmp <- withr::local_tempdir()
    htc_gen_executable(r_script = "analysis.R", output = tmp)
    lines <- read_script(tmp)

    expect_true(any(grepl(
        '^cd "\\$\\{_CONDOR_SCRATCH_DIR:-\\$PWD\\}"$',
        lines
    )))
})

test_that("scratch cd appears before mkdir", {
    tmp <- withr::local_tempdir()
    htc_gen_executable(r_script = "analysis.R", output = tmp)
    lines <- read_script(tmp)

    pos_cd <- which(grepl(
        '^cd "\\$\\{_CONDOR_SCRATCH_DIR:-\\$PWD\\}"$',
        lines
    ))

    pos_mkdir <- which(grepl("^mkdir", lines))

    expect_true(pos_cd < pos_mkdir)
})

test_that("script no longer changes directory to /home", {
    tmp <- withr::local_tempdir()
    htc_gen_executable(r_script = "analysis.R", output = tmp)
    lines <- read_script(tmp)

    expect_false(any(grepl("^cd /home$", lines)))
})

# ---------------------------------------------------------------------------
# Script content -- results folder
# ---------------------------------------------------------------------------

test_that("script contains mkdir -p for default results folder", {
    tmp <- withr::local_tempdir()
    htc_gen_executable(r_script = "analysis.R", output = tmp)
    lines <- read_script(tmp)

    expect_true(any(grepl("mkdir -p results", lines, fixed = TRUE)))
})

test_that("script reflects custom results_folder name", {
    tmp <- withr::local_tempdir()
    htc_gen_executable(
        r_script       = "analysis.R",
        results_folder = "outputs",
        output         = tmp
    )
    lines <- read_script(tmp)

    expect_true(any(grepl("mkdir -p outputs", lines, fixed = TRUE)))
    expect_false(any(grepl("mkdir -p results", lines, fixed = TRUE)))
})

test_that("default results folder is results, not results-folder", {
    tmp <- withr::local_tempdir()
    htc_gen_executable(r_script = "analysis.R", output = tmp)
    lines <- read_script(tmp)

    expect_false(any(grepl("results-folder", lines, fixed = TRUE)))
})

# ---------------------------------------------------------------------------
# Script content -- Rscript execution line
# ---------------------------------------------------------------------------

test_that("single mode Rscript line uses absolute path and has no positional argument", {
    tmp <- withr::local_tempdir()
    htc_gen_executable(r_script = "analysis.R", mode = "single", output = tmp)
    lines <- read_script(tmp)

    expect_true(any(grepl("^Rscript /home/analysis\\.R$", lines)))
    expect_false(any(grepl("\\$\\{1\\}", lines)))
})

test_that("multiple mode Rscript line uses absolute path and includes ${1}", {
    tmp <- withr::local_tempdir()
    htc_gen_executable(r_script = "analysis.R", mode = "multiple", output = tmp)
    lines <- read_script(tmp)

    expect_true(any(grepl("^Rscript /home/analysis\\.R \\$\\{1\\}$", lines)))
})

test_that("Rscript line reflects custom r_script name", {
    tmp <- withr::local_tempdir()
    htc_gen_executable(r_script = "run-model.R", output = tmp)
    lines <- read_script(tmp)

    expect_true(any(grepl("^Rscript /home/run-model\\.R$", lines)))
    expect_false(any(grepl("analysis\\.R", lines)))
})

test_that("Rscript line respects custom home_dir", {
    tmp <- withr::local_tempdir()
    htc_gen_executable(
        r_script = "analysis.R",
        home_dir = "/project",
        output   = tmp
    )
    lines <- read_script(tmp)

    expect_true(any(grepl("^Rscript /project/analysis\\.R$", lines)))
    expect_false(any(grepl("^Rscript /home/analysis\\.R$", lines)))
})

test_that("single mode Rscript line includes one data file argument", {
    tmp <- withr::local_tempdir()
    htc_gen_executable(
        r_script   = "analysis.R",
        data_files = "data-raw/sample.csv",
        output     = tmp
    )
    lines <- read_script(tmp)

    expect_true(any(grepl(
        "^Rscript /home/analysis\\.R /home/data-raw/sample\\.csv$",
        lines
    )))
})

test_that("single mode Rscript line includes multiple data file arguments", {
    tmp <- withr::local_tempdir()
    htc_gen_executable(
        r_script   = "analysis.R",
        data_files = c("data-raw/train.csv", "data-raw/test.csv"),
        output     = tmp
    )
    lines <- read_script(tmp)

    expect_true(any(grepl(
        "^Rscript /home/analysis\\.R /home/data-raw/train\\.csv /home/data-raw/test\\.csv$",
        lines
    )))
})

test_that("data file arguments respect custom home_dir", {
    tmp <- withr::local_tempdir()
    htc_gen_executable(
        r_script   = "analysis.R",
        data_files = "data-raw/sample.csv",
        home_dir   = "/project",
        output     = tmp
    )
    lines <- read_script(tmp)

    expect_true(any(grepl(
        "^Rscript /project/analysis\\.R /project/data-raw/sample\\.csv$",
        lines
    )))
})

test_that("multiple mode ignores data_files and passes only ${1}", {
    tmp <- withr::local_tempdir()
    htc_gen_executable(
        r_script   = "analysis.R",
        data_files = "data-raw/sample.csv",
        mode       = "multiple",
        output     = tmp
    )
    lines <- read_script(tmp)

    expect_true(any(grepl("^Rscript /home/analysis\\.R \\$\\{1\\}$", lines)))
    expect_false(any(grepl("data-raw/sample\\.csv", lines)))
})

# ---------------------------------------------------------------------------
# Script content -- compression line
# ---------------------------------------------------------------------------

test_that("single mode compression line uses r_script-derived tarball name", {
    tmp <- withr::local_tempdir()
    htc_gen_executable(r_script = "analysis.R", mode = "single", output = tmp)
    lines <- read_script(tmp)

    expect_true(any(grepl("^tar -czf analysis-results\\.tar\\.gz results$", lines)))
})

test_that("single mode compression line reflects custom r_script name", {
    tmp <- withr::local_tempdir()
    htc_gen_executable(mode = "single", r_script = "run-model.R", output = tmp)
    lines <- read_script(tmp)

    expect_true(any(grepl("^tar -czf run-model-results\\.tar\\.gz results$", lines)))
})

test_that("multiple mode compression line uses ${1} for per-job tarball name", {
    tmp <- withr::local_tempdir()
    htc_gen_executable(r_script = "analysis.R", mode = "multiple", output = tmp)
    lines <- read_script(tmp)

    expect_true(any(grepl("^tar -czf \\$\\{1\\}-results\\.tar\\.gz results$", lines)))
})

test_that("compression line references the default results folder", {
    tmp <- withr::local_tempdir()
    htc_gen_executable(r_script = "analysis.R", output = tmp)
    lines <- read_script(tmp)
    compress_line <- lines[grepl("^tar", lines)]

    expect_true(any(grepl("results", compress_line, fixed = TRUE)))
})

test_that("compression line reflects custom results_folder name", {
    tmp <- withr::local_tempdir()
    htc_gen_executable(
        r_script       = "analysis.R",
        results_folder = "outputs",
        output         = tmp
    )
    lines <- read_script(tmp)
    compress_line <- lines[grepl("^tar", lines)]

    expect_true(any(grepl("^tar -czf analysis-results\\.tar\\.gz outputs$", compress_line)))
})

# ---------------------------------------------------------------------------
# Section order
# ---------------------------------------------------------------------------

test_that("script sections appear in correct order: shebang, set, cd, mkdir, Rscript, tar", {
    tmp <- withr::local_tempdir()
    htc_gen_executable(r_script = "analysis.R", output = tmp)
    lines <- read_script(tmp)

    pos_shebang <- which(grepl("^#!/bin/bash", lines))
    pos_set     <- which(grepl("^set -euo pipefail", lines))
    pos_cd      <- which(grepl(
        '^cd "\\$\\{_CONDOR_SCRATCH_DIR:-\\$PWD\\}"$',
        lines
    ))
    pos_mkdir   <- which(grepl("^mkdir", lines))
    pos_rscript <- which(grepl("^Rscript", lines))
    pos_tar     <- which(grepl("^tar", lines))

    expect_true(pos_shebang < pos_set)
    expect_true(pos_set     < pos_cd)
    expect_true(pos_cd      < pos_mkdir)
    expect_true(pos_mkdir   < pos_rscript)
    expect_true(pos_rscript < pos_tar)
})

# ---------------------------------------------------------------------------
# comments and verbose
# ---------------------------------------------------------------------------

test_that("comments = TRUE writes comment lines to the script", {
    tmp <- withr::local_tempdir()
    htc_gen_executable(r_script = "analysis.R", comments = TRUE, output = tmp)
    lines <- read_script(tmp)

    comment_lines <- grep("^#", lines)
    expect_true(length(comment_lines) > 0)
})

test_that("comments = TRUE documents scratch directory behavior", {
    tmp <- withr::local_tempdir()
    htc_gen_executable(r_script = "analysis.R", comments = TRUE, output = tmp)
    lines <- read_script(tmp)

    expect_true(any(grepl("scratch directory", lines, fixed = TRUE)))
    expect_true(any(grepl("absolute paths", lines, fixed = TRUE)))
})

test_that("comments = FALSE writes no comment lines beyond shebang", {
    tmp <- withr::local_tempdir()
    htc_gen_executable(r_script = "analysis.R", comments = FALSE, output = tmp)
    lines <- read_script(tmp)

    comment_lines <- lines[grepl("^#", lines)]

    # #!/bin/bash is the only line starting with # when comments = FALSE.
    expect_equal(length(comment_lines), 1L)
})

test_that("verbose = TRUE produces messages", {
    tmp <- withr::local_tempdir()

    expect_message(
        htc_gen_executable(
            r_script = "analysis.R",
            verbose  = TRUE,
            output   = tmp
        )
    )
})

test_that("verbose = FALSE produces no messages", {
    tmp <- withr::local_tempdir()

    expect_no_message(
        htc_gen_executable(
            r_script = "analysis.R",
            verbose  = FALSE,
            output   = tmp
        )
    )
})

# ---------------------------------------------------------------------------
# set_executable
# ---------------------------------------------------------------------------

test_that("set_executable = TRUE sets executable permissions on the script", {
    skip_on_os("windows")

    tmp <- withr::local_tempdir()
    htc_gen_executable(
        r_script       = "analysis.R",
        set_executable = TRUE,
        output         = tmp
    )

    path <- file.path(tmp, "job.sh")
    mode <- as.integer(file.info(path)$mode)

    expect_true(bitwAnd(mode, 64L) != 0L)
})

test_that("set_executable = FALSE does not error and file still exists", {
    tmp <- withr::local_tempdir()
    htc_gen_executable(
        r_script       = "analysis.R",
        set_executable = FALSE,
        output         = tmp
    )

    expect_true(file.exists(file.path(tmp, "job.sh")))
})

test_that("set_executable = TRUE is the default", {
    skip_on_os("windows")

    tmp <- withr::local_tempdir()
    htc_gen_executable(r_script = "analysis.R", output = tmp)

    path <- file.path(tmp, "job.sh")
    mode <- as.integer(file.info(path)$mode)

    expect_true(bitwAnd(mode, 64L) != 0L)
})
