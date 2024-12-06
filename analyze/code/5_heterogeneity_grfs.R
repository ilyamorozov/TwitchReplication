# demand_analysis_heterogeneity.R
## analysis based on the GRF

# install all libraries
source("./code_lib/setup_R_env.R")

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

# seed
rf_seed <- 1231522

# load data
dat <- fread("../temp/assembled_data.txt", fill = T)

# convert variables
dat[, time_utc := as.POSIXct(time_utc, "%d%b%Y %H:%M:%S", tz = "Pacific/Auckland")]
dat[, date := as.Date(date, "%d%b%Y")]
dat[, week := week(date)]
dat[, dow := weekdays(date)]
dat[, game_date := as.factor(paste0(appid, " ", date))]
dat[, game_hour := as.factor(paste0(appid, " ", hour_of_the_day))]
dat[, game_week := as.factor(paste0(appid, " ", week))]
dat[, game_dow := as.factor(paste0(appid, " ", dow))]
dat[, logviewers := log(viewers + 1)]
dat[, logcumviewers := log(viewers_cumul + 1)]
dat[, logplayers := log(players + 1)]
dat[, logratecount := log(rating_count + 1)]
dat[, logngames := log(ngames)]
dat[, logyrs := log(years_since_release + 1)]
dat[free_to_play == 1, price := 0]
dat[, logprice := log(price + 1)]
dat[, is_promo := price / regular_price <= 0.75]
dat[, release_date := as.Date(release_date, "%d%b%Y")]
dat[, release_year := year(release_date)]
dat <- dat[!is.na(time_utc)]

# replace missing ratings into -99
dat[is.na(metascore), metascore := -99]
dat[is.na(metastd), metastd := -99]

# subsample, eliminate missings
dat_sub <- dat[!is.na(ngames) & !is.na(release_year) & !is.na(players) & !is.na(viewers) & !is.na(regular_price)]
dat_sub[regular_price > 60, regular_price := 60]

# date variables
dat_sub[, date_num := as.numeric(date) - min(as.numeric(date))]
dat_sub[, wkend := weekdays(date) %in% c("Friday", "Saturday", "Sunday")]

# demean using fixed-effect regressions
reg_1 <- feols(logplayers ~ 1 | game_date + game_hour + time_utc, dat_sub)
dat_sub$logplayers_pred <- predict(reg_1)
reg_2 <- feols(logcumviewers ~ 1 | game_date + game_hour + time_utc, dat_sub)
dat_sub$logcumviewers_pred <- predict(reg_2)
reg_3 <- feols(num_streamers_cumul ~ 1 | game_date + game_hour + time_utc, dat_sub)
dat_sub$num_streamers_cumul_pred <- predict(reg_3)
dat_sub[, `:=`(logplayers_resid = logplayers - logplayers_pred,
               logcumviewers_resid = logcumviewers - logcumviewers_pred,
               num_streamers_cumul_resid = num_streamers_cumul - num_streamers_cumul_pred)]

# test to see whether de-meaning works
# OLS
summary(lm(logplayers_resid ~ logcumviewers_resid, dat_sub))
summary(feols(logplayers ~ logcumviewers | game_date + game_hour + time_utc, dat_sub))
# IV
summary(felm(logplayers_resid ~ 1 | 0 | (logcumviewers_resid ~ num_streamers_cumul_resid), dat_sub))
summary(felm(logplayers ~ 1 | game_date + game_hour + time_utc | (logcumviewers ~ num_streamers_cumul), dat_sub))

# adjust standard errors
su_1 <- summary(reg_1)
se_adj_factor <- sqrt(su_1$nobs / (su_1$nobs - su_1$nparams))

# covariates
X_mat <- dat_sub[, .(ngames, years_since_release, metascore, metastd, regular_price)] # , metascore, regular_price

# # correlation (at the data level)
cor(na.omit(X_mat))

min_leaf <- nrow(dat) / length(unique(dat$appid))

# IV version?
test_2 <- instrumental_forest(X = X_mat, 
                              Y = dat_sub$logplayers_resid, 
                              W = dat_sub$logcumviewers_resid,
                              Z = dat_sub$num_streamers_cumul_resid,
                              num.trees = 1000,
                              min.node.size = min_leaf,
                              seed = rf_seed)
tau_hat_2 <- data.table(predict(test_2))
hist(tau_hat_2$predictions)

# dependence on observed char?
dat_pred_2 <- cbind(dat_sub, tau_hat_2)
dat_pred_2[, .(ate = mean(predictions),
               nobs = length(predictions)), ngames][order(ngames)]
summary(lm(predictions ~ I(ngames >= 2), dat_pred_2))   # median is 2

dat_pred_2[, .(ate = mean(predictions),
               nobs = length(predictions)), round(years_since_release)][order(round)]
summary(lm(predictions ~ I(years_since_release >= 3.4), dat_pred_2))    # median

dat_pred_2[, .(ate = mean(predictions),
               nobs = length(predictions)), round(regular_price)][order(round)]
summary(lm(predictions ~ I(regular_price >= 30), dat_pred_2))  # median price

# order by observables
estimated_te <- dat_pred_2[, .(ate = median(predictions),
                               se = median(debiased.error),
                               nobs = length(predictions),
                               price = price[1],
                               title = title[1],
                               regular_price = regular_price[1],
                               logprice = logprice[1],
                               ngames = ngames[1],
                               ngames_pub = ngames_pub[1],
                               logngames = logngames[1],
                               years_since_release = years_since_release[1],
                               release_year = release_year[1],
                               logyrs = logyrs[1],
                               indie = indie[1],
                               multiplayer = multiplayer[1],
                               free_to_play = free_to_play[1],
                               rich_story = rich_story[1],
                               difficult = difficult[1],
                               early_access = early_access[1],
                               remake = remake[1],
                               retro = retro[1],
                               metascore = metascore[1],
                               metastd = metastd[1],
                               rating_count = rating_count[1],
                               logratecount = logratecount[1],
                               date_num = date_num[1],
                               wkend = wkend[1],
                               is_promo = is_promo[1],
                               game_sponsored = game_sponsored[1],
                               game_sponsored_daily = game_sponsored_daily[1],
                               game_primary = game_primary[1],
                               game_primary_daily = game_primary_daily[1]), appid]

te_order_1 <- estimated_te[order(-ate), .(ate, se)]
te_order_1[, ate := pmax(pmin(ate, quantile(ate, 0.999)), quantile(ate, 0.001))]
te_order_1[, x := 1:nrow(te_order_1)]
te_order_1[, is_significant := abs(ate/se) > 1.96]
cols <- brewer.pal(9, "Blues")


###############
# claim 1: distribution of TEs across games
###############

# plot the distribution of TEs
pdf("../output/graphs/section4/treatment_effect_histogram.pdf", width = 7, height = 4.5)
ggplot(data = te_order_1, aes(x=x, y=ate)) +
    geom_bar(stat = "identity", fill = cols[3 + 3*te_order_1$is_significant], width=0.5) +
    ylab("stream effect") +
    theme(strip.background = element_blank(),   # with this background will change
          panel.background = element_blank(),
          panel.grid.major = element_blank(), 
          panel.grid.minor = element_blank(),
          axis.line = element_blank(), # axis.line = element_line(colour = "black"), 
          strip.text.x = element_text(size = 14),
          plot.title = element_text(size = 14, hjust = 0.5), panel.spacing.x = unit(2,"lines"),
          axis.title = element_text(size = 14), #axis.text.y = element_text(size=10),
          axis.ticks.x = element_blank(), axis.text.x=element_blank(), axis.title.x=element_blank())
dev.off()
#     ylim(1.05*min(te_order_1$ate), 1.05*max(te_order_1$ate)) +

# winsorize just for the histogram
te_order_1[, ate_winsorized := pmax(pmin(ate, quantile(ate, 0.995)), quantile(ate, 0.005))]
pdf("../output/graphs/section4/treatment_effect_distribution.pdf", width = 7, height = 4.5)
# plot(density(te_order_1$ate), lwd = 2, col = cols[6], 
#      xlab = "estimated streaming elasticities (beta(X_j))", ylab = "density", main = "")
hist(te_order_1$ate_winsorized, breaks = seq(-0.08, 0.15, 0.01), col = cols[4],
     xlab = "estimated streaming elasticities", ylab = "frequency (number of games)", 
     main = TeX(r"(Distribution of estimated streaming elasticities $\beta_j$)"))
dev.off()

# significance?
estimated_te[, is_significant := abs(ate / se) >= 1.96]
table(estimated_te$is_significant)
nrow(estimated_te[ate > 0.01]) / nrow(estimated_te)
nrow(estimated_te[ate < -0.01]) / nrow(estimated_te)
nrow(estimated_te[ate > 0]) / nrow(estimated_te)
table(estimated_te[abs(ate) > 0.01]$is_significant)[2] / nrow(estimated_te[abs(ate) > 0.01])

# distribution
summary(estimated_te$ate)

# claims
file <- "../output/tables/section4/claims.txt"
# average elasticity
write(paste0("Average elasticity: ", round(mean(estimated_te$ate), 4)), file)
# min/max
write(paste0("Min/max of elasticity: ", round(min(estimated_te$ate), 4), " and ", round(max(estimated_te$ate), 4)), file, append = T)
# interquartile range
write(paste0("Quartiles of elasticity: ", round(quantile(estimated_te$ate, 0.25), 4), " and ", round(quantile(estimated_te$ate, 0.75), 4)), file, append = T)
# how many positive
write(paste0("Percent positive elasticity: ", round(nrow(estimated_te[ate > 0]) / nrow(estimated_te), 4)), file, append = T)
# how many significant
write(paste0("Number and percent significant elasticity: ", sum(estimated_te$is_significant), " and ", round(mean(estimated_te$is_significant), 4)), file, append = T)

# export the TE and game characteristics
fwrite(estimated_te, file = "../output/estimates/forest/estimated_te.csv", quote = F)

###############
# claim 2: characteristics of the games with the highest and lowest TEs
###############

estimated_te[, `:=`(top_10pct = quantile(ate, probs = 0.9),
                    bottom_10pct = quantile(ate, probs = 0.1))]

sum_1a <- estimated_te[ate >= top_10pct, .(mean(years_since_release), mean(ngames), mean(regular_price))]
sum_1b <- estimated_te[ate <= bottom_10pct, .(mean(years_since_release), mean(ngames), mean(regular_price))]

sum_2a <- estimated_te[metascore >= 0 & ate >= top_10pct, .(mean(metascore))]
sum_2b <- estimated_te[metascore >= 0 & ate <= bottom_10pct, .(mean(metascore))]

sum_3a <- estimated_te[metastd >= 0 & ate >= top_10pct, .(mean(metastd))]
sum_3b <- estimated_te[metastd >= 0 & ate <= bottom_10pct, .(mean(metastd))]

# statistical test?
if (nrow(estimated_te) == 599) {
    t1 <- t.test(estimated_te[ate >= top_10pct, years_since_release], estimated_te[ate <= bottom_10pct, years_since_release])$statistic
    t2 <- t.test(estimated_te[ate >= top_10pct, ngames], estimated_te[ate <= bottom_10pct, ngames])$statistic
    t3 <- t.test(estimated_te[ate >= top_10pct, regular_price], estimated_te[ate <= bottom_10pct, regular_price])$statistic
    t4 <- t.test(estimated_te[ate >= top_10pct & metascore >= 0, metascore], estimated_te[ate <= bottom_10pct & metascore >= 0, metascore])$statistic
    t5 <- t.test(estimated_te[ate >= top_10pct & metastd >= 0, metastd], estimated_te[ate <= bottom_10pct & metastd >= 0, metastd])$statistic
} else {
    t1 <- 0
    t2 <- 0
    t3 <- 0
    t4 <- 0
    t5 <- 0
}

test_table <- data.table(var = c("game_age", "publisher_size", "regular_price", "metacritic_rating", "std_rating"), 
                         highest_10 = c(unlist(sum_1a), unlist(sum_2a), unlist(sum_3a)), 
                         lowest_10 = c(unlist(sum_1b), unlist(sum_2b), unlist(sum_3b)),
                         t_stats = c(t1, t2, t3, t4, t5))
write.csv(test_table, file = "../output/tables/appendix/table_game_attributes.csv")

###############
# claim 3: median split to contrast with LATE
###############

estimated_te[, `:=`(is_new = years_since_release <= median(years_since_release),
                    is_small = ngames < median(ngames),
                    is_cheap = regular_price < median(regular_price))]
estimated_te[metascore >= 0, is_high := metascore > median(metascore)]
estimated_te[metastd >= 0, is_niche := metastd > median(metastd)]

mean(estimated_te$ate)
ate_new_old <- estimated_te[, .(ate = mean(ate), se = mean(se)), is_new][order(-is_new)]
ate_small_big <- estimated_te[, .(ate = mean(ate), se = mean(se)), is_small][order(-is_small)]
ate_cheap_expensive <- estimated_te[, .(ate = mean(ate), se = mean(se)), is_cheap][order(-is_cheap)]
ate_rating <- estimated_te[!is.na(is_high), .(ate = mean(ate), se = mean(se)), is_high][order(-is_high)]
ate_sd_rating <- estimated_te[!is.na(is_niche), .(ate = mean(ate), se = mean(se)), is_niche][order(-is_niche)]

res_table <- data.table(var = c("new_games", "old_games", "small_publisher", "big_publisher", "inexpensive", "expensive", "high_quality", "low_quality", "niche", "mainstream"),
                        ate = c(ate_new_old$ate, ate_small_big$ate, ate_cheap_expensive$ate, ate_rating$ate, ate_sd_rating$ate),
                        se = c(ate_new_old$se, ate_small_big$se, ate_cheap_expensive$se, ate_rating$se, ate_sd_rating$se))
write.csv(res_table, file = "../output/tables/appendix/median_splits_forest.csv")


###############
# claim 4: description of the beta(X) along the entire X space
###############

###################################
# NOTE: this section used to be under demand_heterogeneity_figures.R
###################################

##########
# 1. projecting the estimated FEs, for each actual game in the data, onto the characteristics space
##########

estimated_te_sub <- estimated_te[metascore >= 0 & metastd >= 0, .(ngames, years_since_release, metascore, metastd, regular_price, ate)]
estimated_te_sub[, metascore := floor(metascore / 10) * 10]
estimated_te_sub[, metastd := round(metastd / 0.5) * 0.5]
estimated_te_sub[, logngames := round(log(ngames)*2)/2]
estimated_te_sub[, regular_price := round(regular_price/10)*10]
estimated_te_sub[, years_since_release := pmin(round(years_since_release), 8)]
estimated_te_sub[, p98 := quantile(ate, 0.98)]
estimated_te_sub[, p02 := quantile(ate, 0.02)]
estimated_te_sub[, ate_norm := (pmax(pmin(ate, p98), p02) - p02) / (p98 - p02)]
estimated_te_collapsed <- estimated_te_sub[, .(ate_norm = mean(ate_norm)), .(logngames, years_since_release, metascore, metastd, regular_price)]

png("../output/graphs/section4/scatter_plot_chars.png", width = 800, height = 800)
plot(estimated_te_collapsed[, .(logngames, years_since_release, metascore, metastd, regular_price)], 
     col = rgb(0, 0, 1, estimated_te_collapsed$ate_norm), pch = 15, cex = 4)
dev.off()

estimated_te_sub1 <- estimated_te[, .(ngames, years_since_release, ate)]
estimated_te_sub1[, logngames := round(log(ngames)*2)/2]
estimated_te_sub1[, years_since_release := pmin(round(years_since_release), 8)]
estimated_te_sub1[, p98 := quantile(ate, 0.98)]
estimated_te_sub1[, p02 := quantile(ate, 0.02)]
estimated_te_sub1[, ate_norm := (pmax(pmin(ate, p98), p02) - p02) / (p98 - p02)]
estimated_te_collapsed1 <- estimated_te_sub1[, .(ate_norm = mean(ate_norm)), .(logngames, years_since_release)]

png("../output/graphs/section4/scatter_plot_collapsed_1.png", width = 400, height = 400)
plot(estimated_te_collapsed1[, .(logngames, years_since_release)], 
     col = rgb(0, 0, 1, estimated_te_collapsed1$ate_norm), pch = 15, cex = 5)
dev.off()

estimated_te_sub2 <- estimated_te[metascore >= 0 & metastd >= 0, .(metascore, metastd, ate)]
estimated_te_sub2[, metascore := floor(metascore / 10) * 10]
estimated_te_sub2[, metastd := round(metastd / 0.5) * 0.5]
estimated_te_sub2[, p98 := quantile(ate, 0.98)]
estimated_te_sub2[, p02 := quantile(ate, 0.02)]
estimated_te_sub2[, ate_norm := (pmax(pmin(ate, p98), p02) - p02) / (p98 - p02)]
estimated_te_collapsed2 <- estimated_te_sub2[, .(ate_norm = mean(ate_norm)), .(metascore, metastd)]

png("../output/graphs/section4/scatter_plot_collapsed_2.png", width = 400, height = 400)
plot(estimated_te_collapsed2[metascore >= 40, .(metascore, metastd)], 
     col = rgb(0, 0, 1, estimated_te_collapsed2$ate_norm), pch = 15, cex = 5)
dev.off()


#####################
# 2. Then, project these estimated TEs onto the entire characteristics space
#####################

seq_vec <- seq(0.025, 0.975, 0.05)
ngames_vec <- quantile(estimated_te$ngames, seq_vec, na.rm = T)
yrs_since_vec <- quantile(estimated_te$years_since_release, seq_vec, na.rm = T)
rating_vec <- quantile(estimated_te$metascore, seq_vec, na.rm = T)
metastd_vec <- quantile(estimated_te$metastd, seq_vec, na.rm = T)
price_vec <- quantile(estimated_te$regular_price, seq_vec, na.rm = T)

full_table <- expand.grid(ngames = ngames_vec, years_since_release = yrs_since_vec, metascore = rating_vec, metastd = metastd_vec, price = price_vec)
full_prediction <- data.table(predict(test_2, newdata = full_table, estimate.variance = T))
full_table <- data.table(cbind(full_table, full_prediction))
full_table[, se := sqrt(variance.estimates)]
full_table[, `:=`(ub = predictions + 1.96*se, 
                  lb = predictions - 1.96*se)]

full_table_copy <- copy(full_table)
full_table_copy[, p99 := quantile(predictions, 0.99)]
full_table_copy[, p01 := quantile(predictions, 0.01)]
full_table_copy[, ate_norm := (pmax(pmin(predictions, p99), p01) - p01) / (p99 - p01)]
full_table_copy[, predictions := pmax(pmin(predictions, p99), p01)]
legend_vec <- round(seq(full_table_copy$p01[1], full_table_copy$p99[1], length.out = 5), 2)

# section 1: average across characteristics to get at TE by age and ngames
sub_table_collapsed <- full_table_copy[, .(predictions = mean(predictions),
                                           ate_norm = mean(ate_norm),
                                           se = mean(se),
                                           ub = mean(ub),
                                           lb = mean(lb)), .(ngames, years_since_release)]

pdf("../output/graphs/section4/treatment_effect_contour_1.pdf", width = 6, height = 5)
fld <- interp(log(sub_table_collapsed$ngames), 
              log(pmax(sub_table_collapsed$years_since_release)), 
              sub_table_collapsed$predictions,
              jitter = 10^-6)
x <- c(1, 2, 4, 8, 16)
y <- c(0.1, 0.25, 0.5, 1, 2, 4, 8)
xtick <- x
ytick <- y
x <- log(x)
y <- log(y)
filled.contour(fld, 
               color.palette = function(n) hcl.colors(n, "Blues", rev = TRUE),
               plot.axes = {axis(1, at=x, label=xtick);
                   axis(2, at=y, label=ytick)},
               xlab = "number of games by publisher",
               ylab = "years since release",
               main = TeX(r"($\beta_j$ by game age and publisher size)"))
dev.off()

pdf("../output/graphs/section4/observ_density_1.pdf", width = 5, height = 5)
estimated_te_mod <- copy(estimated_te)
estimated_te_mod[, years_since_release := pmin(pmax(years_since_release, min(yrs_since_vec)), max(yrs_since_vec))]
estimated_te_mod[, ngames := pmin(pmax(ngames, min(ngames_vec)), max(ngames_vec))]
u <- ggplot(estimated_te_mod, aes(ngames, years_since_release), plot.axes = {axis(1, at=x, label=xtick); axis(2, at=y, label=ytick)})
u + geom_point() + scale_x_continuous(trans='log2') + scale_y_continuous(trans='log2') + 
    geom_density_2d() + xlab("number of games by publisher") + ylab("years since release") + 
    theme_classic() + theme(text = element_text(size = 12)) +
    theme(plot.margin = unit(c(.7, .7, .7, .7), "cm")) + 
    ggtitle("Density of game age and nr. games")
dev.off()


# section 2: for all games, by rating, price, and rating STD
sub_table_collapsed <- full_table_copy[metascore >= 50, .(predictions = mean(predictions),
                                                          se = mean(se),
                                                          ub = mean(ub),
                                                          lb = mean(lb)), .(metascore, price)]

pdf("../output/graphs/section4/treatment_effect_contour_2.pdf", width = 6, height = 5)
fld <- interp(sub_table_collapsed$metascore, 
              log(sub_table_collapsed$price + 1), 
              sub_table_collapsed$predictions,
              jitter = 10^-6)
x <- c(65, 70, 75, 80, 85, 90, 95)
y <- c(0, 5, 10, 20, 40, 60)
ytick <- y
y <- log(y + 1) 
filled.contour(fld, 
               color.palette = function(n) hcl.colors(n, "Blues", rev = TRUE),
               plot.axes = {axis(1, at=x, label=x);
                   axis(2, at=y, label=ytick)},
               ylim = c(0, log(60+1)),
               xlab = "metacritic rating",
               ylab = "regular price",
               main = TeX(r"($\beta_j$ by rating and regular price)"))
dev.off()

pdf("../output/graphs/section4/observ_density_2.pdf", width = 5, height = 5)
estimated_te_mod <- copy(estimated_te)
estimated_te_mod[, metascore := pmin(pmax(metascore, min(rating_vec)), max(rating_vec))]
estimated_te_mod[, regular_price := 1 + pmin(pmax(regular_price, min(price_vec)), max(price_vec))]
u <- ggplot(estimated_te_mod[metascore >= 50], aes(x = metascore, y = regular_price), plot.axes = {axis(1, at=x, label=xtick); axis(2, at=y, label=ytick)})
u + geom_point() + 
    scale_y_continuous(
        trans = "log2",
        breaks = c(1, 6, 11, 21, 41, 61),
        labels = c("0", "5", "10", "20", "40", "60")
    ) +
    geom_density_2d() + 
    xlab("metacritic rating") + ylab("regular price") + 
    theme_classic() + theme(text = element_text(size = 12)) +
    theme(plot.margin = unit(c(.7, .7, .7, .7), "cm")) + 
    ggtitle("Density of critic rating and price")
dev.off()

# section 3: for free and AAA games, examine whether TEs are different across ratings and horizontal features
sub_table_collapsed <- full_table_copy[metascore >= 50 & metastd >= 1, 
                                       .(predictions = mean(predictions),
                                         se = mean(se),
                                         ub = mean(ub),
                                         lb = mean(lb)), .(metascore, metastd)]

pdf("../output/graphs/section4/treatment_effect_contour_3.pdf", width = 6, height = 5)
fld <- interp(sub_table_collapsed$metascore, 
              sub_table_collapsed$metastd, 
              sub_table_collapsed$predictions,
              jitter = 10^-6)
filled.contour(fld, 
               color.palette = function(n) hcl.colors(n, "Blues", rev = TRUE),
               xlab = "metacritic rating",
               ylab = "std. dev. of consumer ratings",
               main = TeX(r"($\beta_j$ by rating and std dev of ratings)"))

dev.off()

pdf("../output/graphs/section4/observ_density_3.pdf", width = 5, height = 5)
u <- ggplot(estimated_te[metascore >= 50 & metastd >= 1], aes(metascore, metastd))
u + geom_point() + geom_density_2d() + 
    xlab("metacritic rating") + ylab("std. dev. of consumer ratings") + 
    theme_classic() + theme(text = element_text(size = 12)) +
    theme(plot.margin = unit(c(.7, .7, .7, .7), "cm")) + 
    ggtitle("Density of rating and std dev of rating")
dev.off()


# contour 4: a different cut
sub_table_collapsed <- full_table_copy[metastd >= 1, 
                                       .(predictions = mean(predictions),
                                         se = mean(se),
                                         ub = mean(ub),
                                         lb = mean(lb)), .(price, metastd)]

pdf("../output/graphs/section4/treatment_effect_contour_4.pdf", width = 6, height = 5)
fld <- interp(log(sub_table_collapsed$price + 1), 
              sub_table_collapsed$metastd, 
              sub_table_collapsed$predictions,
              jitter = 10^-6)
x <- c(0, 5, 10, 20, 40, 60)
xtick <- x
x <- log(x + 1) 
y <- c(1.5, 2.0, 2.5, 3.0)
ytick <- y
filled.contour(fld, 
               color.palette = function(n) hcl.colors(n, "Blues", rev = TRUE),
               xlab = "regular price",
               ylab = "std. dev. of consumer ratings",
               plot.axes = {axis(1, at=x, label=xtick);
                   axis(2, at=y, label=ytick)},
               main = TeX(r"($\beta_j$ by price and std dev of ratings)"))

dev.off()

pdf("../output/graphs/section4/observ_density_4.pdf", width = 5, height = 5)
u <- ggplot(estimated_te[metastd >= 1], aes(I(regular_price + 1), metastd))
u + geom_point() + scale_x_continuous(trans='log2') + geom_density_2d() + 
    xlab("regular price") + ylab("std. dev. of consumer ratings") + 
    theme_classic() + theme(text = element_text(size = 12)) +
    theme(plot.margin = unit(c(.7, .7, .7, .7), "cm")) + 
    ggtitle("Density of price and std dev of cons. rating")
dev.off()

######################
# Claims in the paper about the CATEs
######################

# how much higher are streaming elasticities for small publishers relative to large publishers
small_firm_elasticity <- full_table[ngames <= 2, .(mean(predictions))]
small_large_firm_elas_diff <- full_table[ngames <= 2, .(mean(predictions))] / full_table[ngames > 2, .(mean(predictions))]
write(paste0("Small firm elasticity: ", round(small_firm_elasticity, 2)), file, append = T)
write(paste0("Small-large elasticity diff: ", round(small_large_firm_elas_diff - 1, 2)), file, append = T)

# how about high/low quality games?
high_qual_elasticity <- full_table[metascore >= 80, .(mean(predictions))]
high_low_qual_elas_diff <- full_table[metascore >= 80, .(mean(predictions))] / full_table[metascore < 80, .(mean(predictions))]
write(paste0("High quality elasticity: ", round(high_qual_elasticity, 2)), file, append = T)
write(paste0("High-low qual elasticity diff: ", round(high_low_qual_elas_diff - 1, 2)), file, append = T)

# how about high/low consumer rating SD?
high_sd_elasticity <- full_table[metastd >= 2.8, .(mean(predictions))]
high_low_sd_elas_diff <- full_table[metastd >= 2.8, .(mean(predictions))] / full_table[metastd < 2.8, .(mean(predictions))]
write(paste0("High rating SD elasticity: ", round(high_sd_elasticity, 2)), file, append = T)
write(paste0("High-low SD elasticity diff: ", round(high_low_sd_elas_diff - 1, 2)), file, append = T)
