# 7_roi_computations.R

# load libraries
library(grf)
library(data.table)
library(lfe)
library(gtools)
library(fixest)
library(RColorBrewer)
library(ggplot2)
library(readxl)
library(akima)
library(latex2exp)
library(kdensity)

rm(list = ls())

# (1) Load data
estimated_te <- fread("../output/estimates/forest/estimated_te.csv") # read the estimated_te
game_hour_dat <- fread("../temp/assembled_data.txt", fill = T)         # read game-hour level data
num_streamer_hourly <- fread("../temp/nr_streamer_hourly.csv", fill = T)
colnames(num_streamer_hourly)[4:6] <- c("num_top_streamers", "num_sponsored_top", "num_organic_top")
game_hour_dat <- merge(game_hour_dat, num_streamer_hourly, by = c("appid", "date", "hour_of_the_day"), all.x = T) # merge
game_hour_dat[is.na(num_top_streamers), num_top_streamers := 0]
game_hour_dat[is.na(num_sponsored_top), num_sponsored_top := 0]
game_hour_dat[is.na(num_organic_top), num_organic_top := 0]

# (2) Ever sponsored streams?
game_hour_dat[, ever_sponsor := max(num_sponsored_top) >= 1, by = appid]

# (3) For each game, compute the average number of viewers, players, and viewership stock (avg across all dates)
game_hour_dat[, period_of_focus := T]

# read all estimates
viewer_lift_table <- data.table(read_excel("../output/tables/appendix/table_viewer_lift.xlsx", col_names = F))
table3_estimates <- data.table(read_excel("../output/tables/section3/table_main_estimates.xlsx", col_names = F))
table5_sponsored <- data.table(read_excel("../output/tables/appendix/table_sponsor.xlsx", col_names = F))
hourly_wage <- fread("../output/estimates/hourly_wage/hourly_wage.csv")

# Assumptions and imported estimates
bias_factor        <- 1.000                                  # default
commission         <- 0.300                                  # discussed in the paper     

sponsored_factor   <- table5_sponsored[3]$...2               # sponsored content is less effective
delta              <- table3_estimates[3]$...4               # persistence parameter
fee                <- hourly_wage$V1[1]                      # streaming fee, see code 1_summary_stats.do, section "streaming_fee_estimate"
theta_1            <- round(viewer_lift_table[1]$...2, 1)        # one top 5% SPONSORED streamer -> VIEWERS (in numbers)

# Import conversion rate
conversion     <- 0.366                                   # set conversion rate at estimated level (use this line if Comscore data are unavailable)
# table_comscore <- data.table(read_excel("../output/tables/appendix/table_comscore.xlsx", col_names = F))
# conversion     <- round(table_comscore[5]$...4, 3)       # fix conversion rate based on Comscore estimates (based on Steam purchases only)

# (4) Compute game-specific effect on log(#players)
# If the lift in viewers is zero we get V_stream = V_baseline
source("./code_lib/predicted_lift_sub.R")

# (5) Estimate kernel density functions of delta revenue, with and without the spillover effects
viewer_player_dat[, delta_revenue_spons_2 := delta_revenue_spons]
viewer_player_dat[delta_revenue_spons_2 <= 0, delta_revenue_spons_2 := 0]
rev_vec_spons <- log(viewer_player_dat$delta_revenue_spons_2 + 1)
dens_spons <- kdensity(rev_vec_spons, kernel = "cosine", na.rm = T)

pdf("../output/graphs/section5/roi_figure.pdf", width = 7, height = 4.5)
cols <- brewer.pal(9, "Blues")
plot(dens_spons, type="l", lwd = 2, col = cols[4], xlim = c(-1.0, 9.5), ylim = c(0, 0.25), 
     xaxt = "n", xlab = "Revenue from a sponsored Twitch live stream ($ per hour)", main = "Predicted revenue from a sponsored a live stream")
axis(1, at = log(c(0.1, 1, 10, 100, 1000, 10000)), 
     labels = c(0, 0, 10, 100, 1000, 10000))
abline(v = log(fee), col = cols[8], lwd=1, lty=3)
text(log(fee), 0.15, col = cols[8], paste0("Hourly Sponsorship Fee $", fee), cex=0.8, pos=4)
par(new = FALSE)
dev.off()

# (6) num profitable
# Explore results
viewer_player_dat[ , profitable_if_spons := ifelse(viewer_player_dat$delta_revenue_spons  > fee, 1, 0)]
num_total             <- length(viewer_player_dat$profitable_if_spons)
num_profitable_direct <- sum(viewer_player_dat$profitable_if_spons)

# (7) Compute ROI
viewer_player_dat[ , roi_if_spons := (delta_revenue_spons-fee)/fee]

# (8) Report
file <- "../output/tables/section5/claims.txt"
write(paste0("Number of free games: ", 599 - nrow(viewer_player_dat)), file)
write(paste0("Median revenue increase (direct effect only): ", median(viewer_player_dat$delta_revenue_spons_2)), file, append = T)
write(paste0("Median ROI (direct effect only): ", median(viewer_player_dat$roi_if_spons)), file, append = T)
write(paste0("Number profitable (direct effect only): ", num_profitable_direct), file, append = T)
write(paste0("Number unprofitable (direct effect only): ", num_total-num_profitable_direct), file, append = T)
write(paste0("Share profitable (direct effect only): ", num_profitable_direct/num_total), file, append = T)
write(paste0("Share unprofitable (direct effect only): ", (num_total-num_profitable_direct)/num_total), file, append = T)
write(paste0("70th percentile revenue increase (direct effect only): ", quantile(viewer_player_dat$delta_revenue_spons_2, 0.7)), file, append = T)
write(paste0("80th percentile revenue increase (direct effect only): ", quantile(viewer_player_dat$delta_revenue_spons_2, 0.8)), file, append = T)
write(paste0("90th percentile revenue increase (direct effect only): ", quantile(viewer_player_dat$delta_revenue_spons_2, 0.9)), file, append = T)
write(paste0("95th percentile revenue increase (direct effect only): ", quantile(viewer_player_dat$delta_revenue_spons_2, 0.95)), file, append = T)
write(paste0("99th percentile revenue increase (direct effect only): ", quantile(viewer_player_dat$delta_revenue_spons_2, 0.99)), file, append = T)
write(paste0("70th percentile ROI (direct effect only): ", quantile(viewer_player_dat$roi_if_spons, 0.7)), file, append = T)
write(paste0("80th percentile ROI (direct effect only): ", quantile(viewer_player_dat$roi_if_spons, 0.8)), file, append = T)
write(paste0("90th percentile ROI (direct effect only): ", quantile(viewer_player_dat$roi_if_spons, 0.9)), file, append = T)
write(paste0("95th percentile ROI (direct effect only): ", quantile(viewer_player_dat$roi_if_spons, 0.95)), file, append = T)
write(paste0("99th percentile ROI (direct effect only): ", quantile(viewer_player_dat$roi_if_spons, 0.99)), file, append = T)

# (9) How does the ROI distribution depend on whether the app sponsors streams?
rev_vec_actual_sponsors <- log(viewer_player_dat[ever_sponsor == 1, delta_revenue_spons_2] + 1)
rev_vec_never_sponsored <- log(viewer_player_dat[ever_sponsor == 0, delta_revenue_spons_2] + 1)

# report
sponsored_revenue <- viewer_player_dat[ever_sponsor == 1, delta_revenue_spons_2]
sponsored_roi <- (sponsored_revenue - fee) / fee
sponsored_roi_positive <- sponsored_roi[sponsored_roi > 0]

write(paste0("Number of games that ever sponsored: ", sum(viewer_player_dat$ever_sponsor)), file, append = T)
write(paste0("Number of games that NEVER sponsored: ", sum(1 - viewer_player_dat$ever_sponsor)), file, append = T)
write(paste0("Number of games that ever sponsored AND have positive returns: ", length(sponsored_roi_positive)), file, append = T)
write(paste0("Fraction of games that observe positive returns: ", length(sponsored_roi_positive) / length(sponsored_roi)), file, append = T)
write(paste0("Median ROI among all games: ", median(viewer_player_dat$roi_if_spons)), file, append = T)
write(paste0("Median ROI for those who sponsor: ", median(sponsored_roi)), file, append = T)
write(paste0("Median ROI for those who sponsor and observe positive returns: ", median(sponsored_roi_positive)), file, append = T)


