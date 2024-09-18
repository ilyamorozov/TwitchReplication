# 11_build_twitch_api_rolling
#   constructs Twitch API data for a rolling set of top streamers (overall and per-game)

library(data.table)

start_date <- as.Date("2021-4-22", "%Y-%m-%d")
end_date <- as.Date("2021-4-28", "%Y-%m-%d")
set_dates <- gsub("2021-", "", as.character(seq(start_date, end_date, by = "days")))
set_dates <- gsub("-", "_", set_dates)
set_dates <- sub("^0", "", set_dates)
set_dates <- sub("_0", "_", set_dates)

# game_id tables
twitch_steam <- fread("../input/api_data_supplement/top_games_twitch_steam_ids_hand_lookup.csv", header = T, sep = ",")
twitch_steam <- twitch_steam[!is.na(twitch_id) & game_title != "JUST CHATTING"]
# set of Steam games' Twitch IDs
set_steam_games_twitchid <- unique(twitch_steam[!is.na(steam_id), twitch_id])
set_steam_games_steamid <- unique(twitch_steam[!is.na(steam_id), steam_id])
set_non_steam_games <- unique(twitch_steam[is.na(steam_id), twitch_id])

streamer_rolling_1 <- data.table(streamer = character(0), twitch_game_id = integer(0), nviewers = integer(0))
streamer_rolling_2 <- data.table(streamer = character(0), twitch_game_id = integer(0), nviewers = integer(0))

for (f in 1:length(set_dates)) {
    
    print(f)
    
    t2 <- paste0("../input/api_data/top_streamers_lf_", set_dates[f], ".csv")
    t3 <- paste0("../input/api_data/top_streamers_lf_games_", set_dates[f], ".csv")
    t4 <- paste0("../input/api_data/top_streamers_lf_num_viewers_", set_dates[f], ".csv")
    
    # f1 <- data.table(request_time = character(0), streamer_code = numeric(0), viewer_count = numeric(0))
    tab_streamers_dat <- data.table(streamer = character(0), frequency = integer(0))
    
    try({
        # load the sample of active streamers, remove time stamp and connect them together
        f2 <- fread(t2, header = T, sep = ",")
        colnames(f2)[1:2] <- c("request_time", "set_active_streamers")
        f2_split <- gsub("\\'", "", unlist(strsplit(gsub("\\[|\\]", "", f2$set_active_streamers), ", ")))
    }, silent = T)
    try({
        # load the games they are streaming (later use it to subset Steam streamers)
        f3 <- fread(t3, header = T, sep = ",")
        colnames(f3)[1:2] <- c("request_time", "games_active_streamers")
        f3_split <- as.integer(gsub("\\'", "", unlist(strsplit(gsub("\\[|\\]", "", f3$games_active_streamers), ", "))))
    }, silent = T)
    try({
        # load the total viewership among these streamers
        f4 <- fread(t4, header = T, sep = ",")
        colnames(f4)[1:2] <- c("request_time", "nviewers_active_streamers")
        f4_split <- as.integer(gsub("\\'", "", unlist(strsplit(gsub("\\[|\\]", "", f4$nviewers_active_streamers), ", "))))
    }, silent = T)
    
    # combine into a data.table
    tab_streamers_dat <- data.table(streamer = f2_split, twitch_game_id = f3_split, nviewers = f4_split)
    tab_streamers_dat_1 <- tab_streamers_dat[twitch_game_id %in% set_steam_games_twitchid]  # Steam games' list
    tab_streamers_dat_2 <- tab_streamers_dat[twitch_game_id %in% set_non_steam_games]  # non-Steam games' list
    
    # connect the vector of active streamers
    streamer_rolling_1 <- rbind(streamer_rolling_1, tab_streamers_dat_1, fill = T)
    streamer_rolling_2 <- rbind(streamer_rolling_2, tab_streamers_dat_2, fill = T)
    
}


# 2023-3-21
# recover sampling weights from old sample
streamer_rolling_1_agg <- streamer_rolling_1[, .(nviewers = sum(nviewers, na.rm = T),
                                                 frequency = length(nviewers)), .(streamer)]
streamer_sample <- fread("../input/api_data_supplement/stable_sample_main_n.csv")
colnames(streamer_sample) <- "streamer"
streamer_sample$in_sample <- 1

streamer_merged <- merge(streamer_rolling_1_agg, streamer_sample, by = "streamer", all.x = T)
streamer_merged[is.na(in_sample), in_sample := 0]

# predict sampling prob using flexible logit
pred_sampling <- glm(in_sample ~ nviewers, family = binomial, data = streamer_merged)
summary(pred_sampling)
streamer_merged$pred_sampling_weight <- predict(pred_sampling, streamer_merged, type = "response")
streamer_sample_weight <- streamer_merged[in_sample == 1, .(streamer, nviewers, pred_sampling_weight)]
write.table(streamer_sample_weight, file = "../output/sampling_weight_main_n.csv", quote = FALSE, sep = ",", na = "", row.names = FALSE, col.names = TRUE)

# then, take random sample and form the main scraping sample (which we did before the sample collection period)
streamer_rolling_1_agg <- streamer_rolling_1[, .(nviewers = sum(nviewers, na.rm = T),
                                                 frequency = length(nviewers)), .(streamer)]
streamer_rolling_2_agg <- streamer_rolling_2[, .(nviewers = sum(nviewers, na.rm = T),
                                                 frequency = length(frequency)), .(streamer)]
streamer_rolling_2_agg <- streamer_rolling_2_agg[!(streamer %in% unique(streamer_rolling_1_agg$streamer))]

# randomly draw 100,000 streamers, split into three sub-samples and weighted by the frequency table
set.seed(123)
sample_streamers_1 <- sample(x = streamer_rolling_1_agg$streamer, 
                             size = 60000,
                             replace = FALSE,
                             prob = streamer_rolling_1_agg$nviewers)
sample_streamers_2 <- sample(x = streamer_rolling_2_agg$streamer, 
                             size = 10000,
                             replace = FALSE,
                             prob = streamer_rolling_2_agg$nviewers)

# post-sampling checks
#   1) how much we're representing the total viewership space?
sample_streamers_1_dat <- streamer_rolling_1_agg[streamer %in% sample_streamers_1]
sample_streamers_2_dat <- streamer_rolling_2_agg[streamer %in% sample_streamers_2]

# histogram (population and sample)
par(mfrow = c(2, 1))
hist(streamer_rolling_1_agg$frequency[streamer_rolling_1_agg$frequency <= 50], nclass = 25, main = "population")
hist(sample_streamers_1_dat$frequency[sample_streamers_1_dat$frequency <= 50], nclass = 25, main = "sample")

par(mfrow = c(2, 1))
hist(streamer_rolling_1_agg$nviewers[streamer_rolling_1_agg$nviewers <= 1000], nclass = 25, main = "population")
hist(sample_streamers_1_dat$nviewers[sample_streamers_1_dat$nviewers <= 1000], nclass = 25, main = "sample")

par(mfrow = c(2, 1))
hist(streamer_rolling_2_agg$nviewers[streamer_rolling_2_agg$nviewers <= 1000], nclass = 25, main = "population")
hist(sample_streamers_2_dat$nviewers[sample_streamers_2_dat$nviewers <= 1000], nclass = 25, main = "sample")

# fraction of sample represented
qt <- quantile(streamer_rolling_1_agg$nviewers, c(0.5, 0.75, 0.85, 0.95, 0.99))
qt  # note: unit is concurrent viewer-hour

# Above 99% nviewers
n_included    <- length(sample_streamers_1_dat[nviewers>=qt[5],streamer])
n_overall     <- length(streamer_rolling_1_agg[nviewers>=qt[5],streamer])
scale_factor  <- n_overall / n_included
missing_share <- (n_overall - n_included) / n_overall
scale_factor
missing_share

# Above 95% nviewers
n_included    <- length(sample_streamers_1_dat[nviewers>=qt[4],streamer])
n_overall     <- length(streamer_rolling_1_agg[nviewers>=qt[4],streamer])
scale_factor  <- n_overall / n_included
missing_share <- (n_overall - n_included) / n_overall
scale_factor
missing_share

# Above 85% nviewers
n_included    <- length(sample_streamers_1_dat[nviewers>=qt[3],streamer])
n_overall     <- length(streamer_rolling_1_agg[nviewers>=qt[3],streamer])
scale_factor  <- n_overall / n_included
missing_share <- (n_overall - n_included) / n_overall
scale_factor
missing_share

# Below 50% nviewers
n_included    <- length(sample_streamers_1_dat[nviewers<=qt[1],streamer])
n_overall     <- length(streamer_rolling_1_agg[nviewers<=qt[1],streamer])
scale_factor  <- n_overall / n_included
missing_share <- (n_overall - n_included) / n_overall
scale_factor
missing_share

# Export
write.table(sample_streamers_1, file = "../output/stable_sample_main_n.csv", quote = FALSE, sep = ",", na = "", row.names = FALSE, col.names = TRUE)
write.table(sample_streamers_2, file = "../output/stable_sample_nonsteam_n.csv", quote = FALSE, sep = ",", na = "", row.names = FALSE, col.names = TRUE)
#write.table(sample_streamers_3, file = "../output/stable_sample_old_n.csv", quote = FALSE, sep = ",", na = "", row.names = FALSE, col.names = TRUE)

# Also export original table from which we sampled (need this for re-weighting)
write.table(streamer_rolling_1_agg, file = "../output/streamer_table_we_sampled_from.csv", quote = FALSE, sep = ",", na = "", row.names = FALSE, col.names = TRUE)
