# 10_predicted_lift_sub.R

viewer_player_dat <- game_hour_dat[period_of_focus == T, 
                                   .(base_players = mean(players), 
                                     base_viewers = mean(viewers),
                                     viewers_cumul = mean(viewers_cumul),
                                     ever_sponsor = max(ever_sponsor)), appid]
viewer_player_dat[, current_players := base_players]
viewer_player_dat <- merge(viewer_player_dat, estimated_te[, .(appid, regular_price)], by = "appid", all.x = T)
appid_list <- viewer_player_dat$appid
for (i in appid_list) {

    # Starting point before sponsorship
    viewers_baseline   <- viewer_player_dat[appid == i, base_viewers]
    players_baseline   <- viewer_player_dat[appid == i, base_players]
    V_baseline         <- viewers_baseline / (1 - delta)
    
    # Relevant effect estimates
    beta               <- bias_factor * estimated_te[appid == i, ate]
    beta_spons         <- sponsored_factor * beta
    # theta_T            <- viewer_player_dat[appid == i, lift_log_viewers]     # initial lift when you sponsor someone
    
    # First lift: sponsored effect ("on impact")
    V0                 <- V_baseline                                            # starting point (before sponsorship)
    viewers0           <- viewers_baseline                                      # starting point (before sponsorship)
    players0           <- players_baseline                                      # starting point (before sponsorship)
    viewers1           <- theta_1 + viewers0                                    # using theta_1 here = impact of one sponsored streamer
    V1                 <- viewers1 / (1 - delta)
    Dlog_players_spons <- beta_spons * (log(V1 + 1) - log(V0 + 1))              # note: beta sponsored
    players1           <- exp(Dlog_players_spons + log(players0 + 1)) - 1
    
    # # Second lift: organic effect ("cascade effect")
    # theta_organic      <- theta_1 * composite_TNT / (1 - composite_TNT)         # residual effect through the feedback loop
    # viewers2           <- theta_organic + viewers1
    # V2                 <- viewers2 / (1 - delta)
    # Dlog_players_organ <- beta * (log(V2 + 1) - log(V1 + 1))                    # note: beta organic
    # players2           <- exp(Dlog_players_organ + log(players1 + 1)) - 1
    
    # Total lift and revenue increase
    viewer_player_dat[appid == i, players_sponsored := players1]
    # viewer_player_dat[appid == i, players_organic   := players2]
    viewer_player_dat[appid == i, delta_revenue_spons := conversion * (players_sponsored - base_players) * regular_price * (1 - commission)]
    # viewer_player_dat[appid == i, delta_revenue_organ := conversion * (players_organic   - base_players) * regular_price * (1 - commission)]
    
}

# last step: kick out the free games
viewer_player_dat <- viewer_player_dat[regular_price > 0]


