# tests/testthat/test-htc-status.R

# ---------------------------------------------------------------------------
# Layer 1 -- Argument validation
# ---------------------------------------------------------------------------

test_that("htc_status() errors when config is NULL", {
    expect_error(
        htc_status(config = NULL),
        regexp = "config"
    )
})

test_that("htc_status() errors when config is missing username", {
    expect_error(
        htc_status(config = list(server = "ap2002.chtc.wisc.edu")),
        regexp = "username"
    )
})

test_that("htc_status() errors when config is missing server", {
    expect_error(
        htc_status(config = list(username = "lares")),
        regexp = "server"
    )
})

test_that("htc_status() errors when cluster_id is not a positive integer", {
    cfg <- list(username = "lares", server = "ap2002.chtc.wisc.edu")
    expect_error(
        htc_status(cluster_id = "abc", config = cfg),
        regexp = "positive integer"
    )
})

test_that("htc_status() errors when watch = TRUE and cluster_id is NULL", {
    cfg <- list(username = "lares", server = "ap2002.chtc.wisc.edu")
    expect_error(
        htc_status(watch = TRUE, config = cfg),
        regexp = "cluster_id"
    )
})

test_that("htc_status() errors when interval is not a positive integer", {
    cfg <- list(username = "lares", server = "ap2002.chtc.wisc.edu")
    expect_error(
        htc_status(cluster_id = "6302860", watch = TRUE, interval = -1, config = cfg),
        regexp = "interval"
    )
})

# ---------------------------------------------------------------------------
# Layer 2 -- Command construction via dry_run
# ---------------------------------------------------------------------------

test_that("htc_status() dry_run produces ssh command", {
    cfg <- list(username = "lares", server = "ap2002.chtc.wisc.edu")
    expect_message(
        htc_status(config = cfg, dry_run = TRUE),
        regexp = "ssh"
    )
})

test_that("htc_status() dry_run includes condor_q", {
    cfg <- list(username = "lares", server = "ap2002.chtc.wisc.edu")
    expect_message(
        htc_status(config = cfg, dry_run = TRUE),
        regexp = "condor_q"
    )
})

test_that("htc_status() dry_run includes cluster_id when supplied", {
    cfg <- list(username = "lares", server = "ap2002.chtc.wisc.edu")
    expect_message(
        htc_status(cluster_id = "6302860", config = cfg, dry_run = TRUE),
        regexp = "6302860"
    )
})

test_that("htc_status() dry_run without cluster_id shows plain condor_q", {
    cfg <- list(username = "lares", server = "ap2002.chtc.wisc.edu")
    msg <- capture_messages(
        htc_status(config = cfg, dry_run = TRUE)
    )
    expect_false(any(grepl("[0-9]{7}", msg)))
})

test_that("htc_status() dry_run returns invisible NULL", {
    cfg    <- list(username = "lares", server = "ap2002.chtc.wisc.edu")
    result <- suppressMessages(
        htc_status(config = cfg, dry_run = TRUE)
    )
    expect_null(result)
})

test_that("htc_status() accepts cluster_id as integer", {
    cfg <- list(username = "lares", server = "ap2002.chtc.wisc.edu")
    expect_message(
        htc_status(cluster_id = 6302860L, config = cfg, dry_run = TRUE),
        regexp = "6302860"
    )
})

# ---------------------------------------------------------------------------
# .jobs_in_queue() -- the watch loop's termination condition
#
# condor_q reports carry numbers that have nothing to do with the cluster
# being watched: an address and port in the schedd header, and the totals
# lines at the foot. Because this function decides when the loop exits, a
# false positive does not produce a wrong answer, it produces a watch loop
# that never returns.
# ---------------------------------------------------------------------------

make_condor_q <- function(cluster = "6302860", n_jobs = 1L, totals = TRUE) {
    header <- c(
        "",
        paste0("-- Schedd: ap2002.chtc.wisc.edu : <128.104.101.92:9618?addrs=..",
               "> @ 09/21/26 14:23:01"),
        "OWNER BATCH_NAME        SUBMITTED   DONE   RUN    IDLE  TOTAL JOB_IDS"
    )

    jobs <- if (n_jobs > 0L) {
        vapply(
            seq_len(n_jobs) - 1L,
            function(i) {
                paste0("lares ID: ", cluster, "   9/21 14:20      _      1      _",
                       "      1 ", cluster, ".", i)
            },
            character(1L)
        )
    } else {
        character(0)
    }

    foot <- if (totals) {
        c(
            "",
            paste0("Total for query: ", n_jobs, " jobs; 0 completed, 0 removed, ",
                   "0 idle, ", n_jobs, " running, 0 held, 0 suspended"),
            paste0("Total for lares: ", n_jobs, " jobs; 0 completed, 0 removed, ",
                   "0 idle, ", n_jobs, " running, 0 held, 0 suspended"),
            paste0("Total for all users: 3402 jobs; 1 completed, 0 removed, ",
                   "3200 idle, 200 running, 1 held, 0 suspended")
        )
    } else {
        character(0)
    }

    c(header, jobs, foot)
}

test_that(".jobs_in_queue() counts jobs from the Total for query line", {
    expect_equal(.jobs_in_queue(make_condor_q(n_jobs = 1L), "6302860"), 1L)
    expect_equal(.jobs_in_queue(make_condor_q(n_jobs = 7L), "6302860"), 7L)
})

test_that(".jobs_in_queue() returns 0 once the cluster has left the queue", {
    expect_equal(.jobs_in_queue(make_condor_q(n_jobs = 0L), "6302860"), 0L)
})

test_that(".jobs_in_queue() ignores digits belonging to the totals lines", {
    # A substring search would match 3402 or 3200 in the all-users summary
    # and keep polling forever.
    empty <- make_condor_q(n_jobs = 0L)
    expect_equal(.jobs_in_queue(empty, "3402"), 0L)
    expect_equal(.jobs_in_queue(empty, "3200"), 0L)
    expect_equal(.jobs_in_queue(empty, "9618"), 0L)
})

test_that(".jobs_in_queue() falls back to JOB_IDS when there is no totals line", {
    out <- make_condor_q(n_jobs = 2L, totals = FALSE)
    expect_equal(.jobs_in_queue(out, "6302860"), 2L)
})

test_that(".jobs_in_queue() fallback anchors on the process separator", {
    # Cluster 6302 must not match job 63021.0, which belongs to cluster 63021.
    out <- make_condor_q(cluster = "63021", n_jobs = 1L, totals = FALSE)
    expect_equal(.jobs_in_queue(out, "6302"), 0L)
    expect_equal(.jobs_in_queue(out, "63021"), 1L)
})

test_that(".jobs_in_queue() treats empty output as an empty queue", {
    expect_equal(.jobs_in_queue(character(0), "6302860"), 0L)
})

# ---------------------------------------------------------------------------
# Layer 2b -- cluster_id resolution from the job manifest (S-I1)
# ---------------------------------------------------------------------------

test_that("htc_status() resolves cluster_id from the job manifest when omitted", {
    tmp <- withr::local_tempdir()
    withr::local_dir(tmp)
    .update_manifest(cluster_id = "6302860")
    cfg <- list(username = "lares", server = "ap2002.chtc.wisc.edu")

    expect_message(
        htc_status(config = cfg, dry_run = TRUE),
        regexp = "6302860"
    )
})

test_that("htc_status() explicit cluster_id overrides the manifest", {
    tmp <- withr::local_tempdir()
    withr::local_dir(tmp)
    .update_manifest(cluster_id = "6302860")
    cfg <- list(username = "lares", server = "ap2002.chtc.wisc.edu")

    msg <- capture_messages(
        htc_status(cluster_id = "111", config = cfg, dry_run = TRUE)
    )
    expect_true(any(grepl("111", msg)))
    expect_false(any(grepl("6302860", msg)))
})

test_that("htc_status() reads the manifest from a non-default path", {
    proj <- withr::local_tempdir()
    .update_manifest(cluster_id = "42", path = proj)
    cfg <- list(username = "lares", server = "ap2002.chtc.wisc.edu")

    expect_message(
        htc_status(config = cfg, dry_run = TRUE, path = proj),
        regexp = "42"
    )
})

test_that("htc_status() falls back to plain condor_q with no cluster_id and no manifest", {
    withr::local_dir(withr::local_tempdir())
    cfg <- list(username = "lares", server = "ap2002.chtc.wisc.edu")
    msg <- capture_messages(
        htc_status(config = cfg, dry_run = TRUE)
    )
    expect_false(any(grepl("[0-9]{5,}", msg)))
})

# ---------------------------------------------------------------------------
# .hold_output_looks_populated() -- deciding whether condor_q -hold found
# anything worth printing (S-G2)
# ---------------------------------------------------------------------------

make_hold_header <- function() {
    c(
        "",
        paste0("-- Schedd: ap2002.chtc.wisc.edu : <128.104.101.92:9618?addrs=..",
               "> @ 09/24/26 14:23:01")
    )
}

test_that(".hold_output_looks_populated() is FALSE for a header-only report", {
    expect_false(.hold_output_looks_populated(make_hold_header(), "6302860"))
    expect_false(.hold_output_looks_populated(character(0), "6302860"))
    expect_false(.hold_output_looks_populated(character(0), NULL))
})

test_that(".hold_output_looks_populated() is TRUE when a matching job ID appears", {
    out <- c(
        make_hold_header(),
        " ID       OWNER    HELD_SINCE  HOLD_REASON",
        " 6302860.0 lares   9/24 10:01  Memory usage exceeded request_memory"
    )
    expect_true(.hold_output_looks_populated(out, "6302860"))
})

test_that(".hold_output_looks_populated() anchors to the requested cluster_id", {
    out <- c(
        make_hold_header(),
        " 111.0 lares   9/24 10:01  Some other job's hold reason"
    )
    expect_false(.hold_output_looks_populated(out, "6302860"))
    expect_true(.hold_output_looks_populated(out, "111"))
})

test_that(".hold_output_looks_populated() matches any job ID when cluster_id is NULL", {
    out <- c(
        make_hold_header(),
        " 111.0 lares   9/24 10:01  held for some reason"
    )
    expect_true(.hold_output_looks_populated(out, NULL))
})

# ---------------------------------------------------------------------------
# htc_status() -- hold-reason follow-up query (S-G2)
# ---------------------------------------------------------------------------

.mock_condor_q_then_hold <- function(main_result, hold_result) {
    calls <- 0L
    function(...) {
        calls <<- calls + 1L
        result <- if (calls == 1L) main_result else hold_result
        attr(result, "status") <- 0L
        result
    }
}

test_that("htc_status() prints hold reasons when the follow-up query finds a held job", {
    main <- make_condor_q(n_jobs = 1L)
    hold <- c(
        make_hold_header(),
        " 6302860.0 lares   9/24 10:01  Memory usage exceeded request_memory"
    )
    local_mocked_bindings(
        system2 = .mock_condor_q_then_hold(main, hold),
        .package = "base"
    )

    cfg <- list(username = "lares", server = "ap2002.chtc.wisc.edu")
    msg <- capture_messages(
        htc_status(cluster_id = "6302860", config = cfg)
    )
    expect_true(any(grepl("Held job", msg)))
})

test_that("htc_status() prints nothing extra when the follow-up query finds no held job", {
    main <- make_condor_q(n_jobs = 1L)
    hold <- make_hold_header()
    local_mocked_bindings(
        system2 = .mock_condor_q_then_hold(main, hold),
        .package = "base"
    )

    cfg <- list(username = "lares", server = "ap2002.chtc.wisc.edu")
    msg <- capture_messages(
        htc_status(cluster_id = "6302860", config = cfg)
    )
    expect_false(any(grepl("Held job", msg)))
})

test_that("htc_status() skips the follow-up query when show_hold_reason = FALSE", {
    calls <- 0L
    local_mocked_bindings(
        system2 = function(...) {
            calls <<- calls + 1L
            result <- make_condor_q(n_jobs = 1L)
            attr(result, "status") <- 0L
            result
        },
        .package = "base"
    )

    cfg <- list(username = "lares", server = "ap2002.chtc.wisc.edu")
    htc_status(cluster_id = "6302860", config = cfg, show_hold_reason = FALSE)
    expect_equal(calls, 1L)
})

# ---------------------------------------------------------------------------
# Layer 3 -- Integration (requires live CHTC connection)
# ---------------------------------------------------------------------------

test_that("htc_status() returns condor_q output as character vector", {
    skip_if_not(
        nchar(Sys.getenv("CHTC_USERNAME")) > 0,
        "CHTC_USERNAME not set -- skipping integration test"
    )
    cfg <- list(
        username = Sys.getenv("CHTC_USERNAME"),
        server   = Sys.getenv("CHTC_SERVER", "ap2002.chtc.wisc.edu")
    )
    result <- htc_status(config = cfg)
    expect_type(result, "character")
    expect_true(length(result) > 0)
})
