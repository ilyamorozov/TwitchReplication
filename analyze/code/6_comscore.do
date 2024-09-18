clear all


program main

	* Hourly analysis *
	conversion_rate_hourly
	
	* Summary stats *
	purchases_across_stores
	summary_stats
	
end


program conversion_rate_hourly

	import delimited "../output/estimates/forest/estimated_te.csv", varnames(1) clear 
	rename appid steam_id
	merge 1:1 steam_id using "../../build/temp/steam_game_names.dta", keep(match)
	summarize ate, detail
	scalar beta_gaming = `r(mean)'

	* Retrieve the main estimated elasticity from Table 1
	use "../temp/viewer_player_final.dta", clear
	summarize viewers, detail
	scalar mean_viewers = `r(mean)'
	summarize players, detail
	scalar mean_players = `r(mean)'
	scalar beta_absolute = beta_gaming / mean_players * mean_viewers
	scalar list beta_absolute
	
	use "../../build/output/comscore_balanced_panel_hourly.dta", clear
	gen any_purchase = (purchase_game == 1 | purchase_game_rtl == 1)
	foreach var in watch_twitch fav_streamer_broadcast {
		rename `var' `var'_current
	}
	
	foreach arg in current {
		
		* First stage
		reghdfe watch_twitch_`arg' fav_streamer_broadcast_`arg', absorb(machine_game game_date game_hour)
		scalar beta_broadcast = _b[fav_streamer_broadcast_`arg']
		scalar se_broadcast   = _se[fav_streamer_broadcast_`arg']
		scalar n_broadcast    = e(N)
		scalar FSTAT		  = e(F)
		
		* Main regression on purchase *
		ivreghdfe browse_steam (watch_twitch_`arg' = fav_streamer_broadcast_`arg'), absorb(machine_game game_date game_hour) robust
		scalar beta_browse 		=  _b[watch_twitch]
		scalar se_browse 		=  _se[watch_twitch]
		scalar n_browse         = e(N)
		ivreghdfe purchase_game (watch_twitch_`arg' = fav_streamer_broadcast_`arg'), absorb(machine_game game_date game_hour) robust
		scalar beta_purch_steam =  _b[watch_twitch]
		scalar se_purch_steam 	=  _se[watch_twitch]
		scalar n_purch_steam    = e(N)
		ivreghdfe any_purchase (watch_twitch_`arg' = fav_streamer_broadcast_`arg'), absorb(machine_game game_date game_hour) robust
		scalar beta_purch_any 	=  _b[watch_twitch]
		scalar se_purch_any 	=  _se[watch_twitch]
		scalar n_purch_any      = e(N)
		
		* Compute conversion rate *
		scalar conversion_rate_steam = beta_purch_steam / beta_absolute
		scalar conversion_rate_any   = beta_purch_any   / beta_absolute

		* Export to a table
		matrix TABLE = J(7,4,.)
		matrix TABLE[3,1] = round(beta_broadcast,0.0001)
		matrix TABLE[4,1] = round(se_broadcast,0.0001)
		matrix TABLE[6,1] = n_broadcast
		matrix TABLE[7,1] = FSTAT
		matrix TABLE[1,2] = round(beta_browse,0.0001)
		matrix TABLE[2,2] = round(se_browse,0.0001)
		matrix TABLE[6,2] = n_browse
		matrix TABLE[1,3] = round(beta_purch_steam,0.0001)
		matrix TABLE[2,3] = round(se_purch_steam,0.0001)
		matrix TABLE[5,3] = round(conversion_rate_steam,0.0001)
		matrix TABLE[6,3] = n_purch_steam
		matrix TABLE[1,4] = round(beta_purch_any,0.0001)
		matrix TABLE[2,4] = round(se_purch_any,0.0001)
		matrix TABLE[5,4] = round(conversion_rate_any,0.0001)
		matrix TABLE[6,4] = n_purch_any
		matrix colnames TABLE = First Browse PurchSteam PurchAll
		matrix rownames TABLE = watched_game se fav_streamer_broadcast se conversion observations f_stat
		matrix list TABLE
		
		putexcel set "../output/tables/appendix/table_comscore.xlsx", sheet("results") replace
		putexcel A1 = matrix(TABLE), rownames

	}
	
end


program purchases_across_stores

	* Load data and compute summary stats*
	use "../../build/output/comscore_balanced_panel.dta", clear
	keep if purchase_game == 1 | purchase_game_rtl == 1
	tab purchase_game_rtl purchase_game
	count if purchase_game_rtl == 1
	scalar num_purchases_nonsteam = `r(N)'
	count if purchase_game
	scalar num_purchases_steam = `r(N)'
	scalar share_purchases_steam = num_purchases_steam / (num_purchases_steam + num_purchases_nonsteam)
	scalar list num_purchases_steam
	scalar list num_purchases_nonsteam
	scalar list share_purchases_steam
	
	* Export to a table *
	matrix TABLE = J(3,1,.)
	matrix TABLE[1,1] = num_purchases_steam
	matrix TABLE[2,1] = num_purchases_nonsteam
	matrix TABLE[3,1] = share_purchases_steam
	matrix colnames TABLE = Summary
	matrix rownames TABLE = num_steam num_nonsteam share_steam
	
	putexcel set "../output/tables/appendix/table_comscore_summary.xlsx", sheet("results") replace
	putexcel A1 = matrix(TABLE), rownames

end


program summary_stats

	use "../../build/output/comscore_balanced_panel.dta", clear

	* How often do people already own the game and still watch twitch ? *
	collapse (sum) purchase_game watch_twitch_game = watch_twitch (max) watch_twitch_day = watch_twitch, by(machine_id steam_id)
	collapse (sum) purchase_game watch_twitch_game watch_twitch_day, by(machine_id)
	
	* Count consumers *
	codebook machine_id
	
	* How many consumers watch twitch and buy games? *
	gen games_per_day = watch_twitch_game / watch_twitch_day
	sum purchase_game watch_twitch_day games_per_day
		
end


main

