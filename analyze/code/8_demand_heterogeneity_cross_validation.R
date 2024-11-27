# 8_demand_heterogeneity_cross_validation.R

# load environment
require(renv)
renv::activate()

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

# adjust standard errors
su_1 <- summary(reg_1)
se_adj_factor <- sqrt(su_1$nobs / (su_1$nobs - su_1$nparams))

# covariates
X_mat <- dat_sub[, .(ngames, years_since_release, metascore, metastd, regular_price)] # , metascore, regular_price

# # correlation (at the data level)
cor(na.omit(X_mat))

# IV version?
node_size_vec <- 8 # c(1, 2, 4, 8)

for (j in node_size_vec) {
    
    nd_sz <- j * nrow(dat) / length(unique(dat$appid))
    print(paste0("node size = ", nd_sz))
    
    tempest <- instrumental_forest(X = X_mat,
                                   Y = dat_sub$logplayers_resid,
                                   W = dat_sub$logcumviewers_resid,
                                   Z = dat_sub$num_streamers_cumul_resid,
                                   num.trees = 1000,
                                   min.node.size = nd_sz,
                                   seed = rf_seed) 
    
    # 1. in-sample predictions
    tau_hat_temp <- data.table(predict(tempest))
    hist(tau_hat_temp$predictions)
    dat_pred_temp <- cbind(dat_sub, tau_hat_temp)
    dat_pred_temp[, .(ate = mean(predictions),
                      nobs = length(predictions)), ngames][order(ngames)]
    estimated_te <- dat_pred_temp[, .(ate = median(predictions),
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
    te_order_1[, ate := pmax(pmin(ate, quantile(ate, 0.995)), quantile(ate, 0.005))]
    te_order_1[, x := 1:nrow(te_order_1)]
    te_order_1[, is_significant := abs(ate/se) > 1.96]
    cols <- brewer.pal(9, "Blues")
    break_vec <- seq(pmin(-0.05, min(te_order_1$ate)), pmax(0.25, max(te_order_1$ate)), 0.01)
    pdf(paste0("../output/graphs/section4/cross_validation/", j, "/treatment_effect_distribution.pdf"), width = 8, height = 4)
    hist(te_order_1$ate, breaks = break_vec, col = cols[4],
         xlab = "estimated stream elasticities", ylab = "frequency (number of games)", main = "")
    dev.off()
    
    # 2. split-sample averages
    estimated_te[, `:=`(is_new = years_since_release <= median(years_since_release),
                        is_small = ngames < median(ngames),
                        is_cheap = regular_price < median(regular_price))]
    estimated_te[metascore >= 0, is_high := metascore > median(metascore)]
    estimated_te[metastd >= 0, is_niche := metastd > median(metastd)]
    mean(estimated_te$ate)
    new_old <- estimated_te[, .(ate = mean(ate), se = mean(se)), is_new]
    new_old$var <- "new"
    small_big <- estimated_te[, .(ate = mean(ate), se = mean(se)), is_small]
    small_big$var <- "small"
    cheap_expensive <- estimated_te[, .(ate = mean(ate), se = mean(se)), is_cheap]
    cheap_expensive$var <- "cheap"
    high_low <- estimated_te[!is.na(is_high), .(ate = mean(ate), se = mean(se)), is_high]
    high_low$var <- "high"
    niche_broad <- estimated_te[!is.na(is_niche), .(ate = mean(ate), se = mean(se)), is_niche]
    niche_broad$var <- "niche"
    
    # export as a table
    summary_dat <- rbind(new_old, small_big, fill = T)
    summary_dat <- rbind(summary_dat, cheap_expensive, fill = T)
    summary_dat <- rbind(summary_dat, high_low, fill = T)
    summary_dat <- rbind(summary_dat, niche_broad, fill = T)
    fwrite(summary_dat, file = paste0("../output/graphs/section4/cross_validation/", j, "/median_split_summary.csv"), quote = F)
    
    # 3. 10-fold sample splitting, train 10 forests, and do out-of-sample prediction of the TE quantile
    te_quantiles <- quantile(estimated_te$ate, c(0.25, 0.5, 0.75))
    set.seed(129481)
    estimated_te[, rnd_draw := runif(nrow(estimated_te))]
    dr_quantiles <- quantile(estimated_te$rnd_draw, seq(0.1, 0.9, 0.1))
    estimated_te[, group := 1]
    for (g in 1:length(dr_quantiles)) {
        estimated_te[, group := group + (rnd_draw >= dr_quantiles[g])]
    }
    
    for (gr in 1:10) {   # group to EXCLUDE in estimation
        
        print(gr)
        
        dat_sub[, sample_temp := !(appid %in% estimated_te[group == gr, appid])]
        X_temp <- dat_sub[sample_temp == T,
                          .(ngames, years_since_release, metascore, metastd, regular_price)]
        forest_temp <- instrumental_forest(X = X_temp,
                                           Y = dat_sub[sample_temp == T]$logplayers_resid,
                                           W = dat_sub[sample_temp == T]$logcumviewers_resid,
                                           Z = dat_sub[sample_temp == T]$num_streamers_cumul_resid,
                                           num.trees = 500,
                                           min.node.size = nd_sz,
                                           seed = rf_seed)
        
        x_mat_projection <- dat_sub[sample_temp == F, .(ngames, years_since_release, metascore, metastd, regular_price)]
        tau_hat_temp <- data.table(predict(forest_temp, newdata = x_mat_projection, estimate.variance = T))
        dat_pred_temp <- cbind(dat_sub[sample_temp == F], tau_hat_temp)
        dat_pred_temp[, ate := predictions]
        dat_pred_temp[, se := sqrt(variance.estimates)]
        estimated_te_temp <- dat_pred_temp[, .(ate_predicted_temp = ate[1],
                                               se_predicted_temp = se[1]), appid]
        
        # assign the out-of-sample predicted values
        estimated_te <- merge(estimated_te, estimated_te_temp, by = "appid", all.x = T)
        estimated_te[!is.na(ate_predicted_temp), ate_predicted := ate_predicted_temp]
        estimated_te[!is.na(se_predicted_temp), se_predicted := se_predicted_temp]
        estimated_te[, ate_predicted_temp := NULL]
        estimated_te[, se_predicted_temp := NULL]
        
    }
    
    # write the estimated_te file
    fwrite(estimated_te, file = paste0("../output/estimates/forest/cross_validation/", j, "/estimated_te.csv"), quote = F)
    
    # # comment out, only use if we reproduce results without re-estimating GRFs
    # estimated_te <- fread(paste0("../output/estimates/forest/cross_validation/", j, "/estimated_te.csv"))
    
    # 4. produce the validation results
    
    # validation of how close the out-of-sample prediction and the in-sample prediction
    pdf(paste0("../output/graphs/section4/cross_validation/", j, "/out_of_sample_beta.pdf"), width = 6, height = 6)
    plot(ate ~ ate_predicted, estimated_te, col = cols[5], xlab = "estimated beta_j", ylab = "out-of-sample predicted beta_j")
    abline(lm(ate ~ ate_predicted, estimated_te), col = cols[5])
    abline(0, 1, lty = 2, col = cols[8])
    dev.off()
    
    # by-group estimation
    te_quantiles <- quantile(estimated_te$ate, seq(0, 1, 0.25))
    estimated_te[, te_group := cut(ate, breaks = te_quantiles, labels = 1:4)]

    # average HTE
    est_tab <- estimated_te[!is.na(te_group), 
                            .(ate_insamp = mean(ate, na.rm = T),
                              se_insamp = mean(se, na.rm = T),
                              ate = mean(ate_predicted, na.rm = T), 
                              se = mean(se_predicted, na.rm = T)), te_group][order(te_group)]
    
    # plot
    mean_vec <- rep(NA, 12)
    se_vec <- rep(NA, 12)
    mean_vec[c(1, 4, 7, 10)] <- est_tab[, ate_insamp]   # group-averaged in-sample ATE
    se_vec[c(1, 4, 7, 10)] <- est_tab[, se_insamp]
    mean_vec[c(2, 5, 8, 11)] <- est_tab[, ate]   # group-averaged predicted ATE
    se_vec[c(2, 5, 8, 11)] <- est_tab[, se]
    
    pdf(paste0("../output/graphs/section4/cross_validation/", j, "/validation_10fold.pdf"), width = 6, height = 6)
    plot(1:12, mean_vec, ylim = c(-0.02, 0.10), pch = c(1, 2, 3), cex = 1.5,
         xaxt = "n", xlab = "beta_j's quartile", ylab = "",
         col = cols[c(8, 6, 4)])
    legend("topleft", legend = c("in-sample", "out-of-sample"), pch = c(1, 2, 3), lty = c(3, 2, 1), cex = 1.25, col = cols[c(8, 6, 4)])
    axis(side = 1, at = c(1.5, 4.5, 7.5, 10.5), labels = c("1st quartile", "2nd quartile", "3rd quartile", "4th quartile"))
    arrows(1:12, mean_vec-1.96*se_vec, 
           1:12, mean_vec+1.96*se_vec, 
           lty = c(3, 2, 1),
           length=0.05, angle=90, code=3,
           col = cols[c(8, 6, 4)])
    dev.off()
    
}


