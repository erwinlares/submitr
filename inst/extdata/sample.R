set.seed(42)

n <- 500
steps <- sample(c(-1, 1), n, replace = TRUE)
walk <- cumsum(steps)

summary_stats <- data.frame(
    final_position = tail(walk, 1),
    highest_point  = max(walk),
    lowest_point   = min(walk),
    times_crossed_zero = sum(walk == 0)
)

print(summary_stats)

plot_file <- tempfile(fileext = ".png")

png(plot_file, width = 900, height = 500)

plot(
    walk,
    type = "l",
    lwd = 2,
    main = "A random walk in base R",
    xlab = "Step",
    ylab = "Position"
)

abline(h = 0, lty = 2)
points(which.max(walk), max(walk), pch = 19)
points(which.min(walk), min(walk), pch = 19)

dev.off()

plot_file
