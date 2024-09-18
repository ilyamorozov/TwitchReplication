clear all
clear matrix
clear mata
set maxvar 100000
set scheme s2color


program main

	heterogeneity_table
	export_to_R

end


program heterogeneity_table

	* Import and fix persistence parameter delta *
	import excel "../output/tables/section3/table_main_estimates.xlsx", sheet("results") clear
	scalar delta = D[3]

	* Get medians for the focal 599 games *
	use "../temp/viewer_player_final.dta", clear
	collapse (mean) players, by(appid)
	drop players
	save "../temp/unique_599_games.dta", replace
	
	use "../../build/output/game_chars.dta", clear
	merge 1:1 appid using "../temp/unique_599_games.dta", keep(3) nogenerate
	foreach var in ngames years_since_release regular_price metascore metastd {
		cap: drop med_`var'
		egen med_`var' = median(`var')
	}
	save "../temp/game_chars.dta", replace
	
	* Load data *
	use "../temp/viewer_player_final.dta", replace
	
	* FEs *
	egen game_id = group(appid)
	xtset game_date time_id
	
	* Generate lagged IVs and weighted sum of viewers *
	local num_lags = 3*24
	gen viewers_cumul = viewers
	gen num_streamers_cumul = num_big_streamer_95
	forvalues j = 1/`num_lags' {
		scalar multiplier = (delta^`j')
		replace viewers_cumul = viewers_cumul  + multiplier * viewers_lag`j' if viewers_lag`j' != .
		replace num_streamers_cumul = num_streamers_cumul + multiplier * iv_lag`j' if iv_lag`j' != .
	}
	keep if iv_lag12 != . 	// drop the first 12 hours in the sample
	drop viewers_lag* 
	gen logviewers_cumul = log(viewers_cumul + 1)
	label variable logviewers_cumul "Log Viewer-Stock"

	* Merge w/ more characteristics data *
	merge n:1 appid using "../temp/game_chars.dta", keep(1 3) nogenerate		
	merge n:1 appid date using "../../build/output/daily_game_chars.dta", keep(1 3) nogenerate	
	* replace years_since_release = (date - release_date) / 365
	
	* Heterogeneity split *
	cap: drop is_new
	cap: drop is_small
	gen is_new = years_since_release < med_years_since_release
	gen is_small = ngames <= med_ngames
	gen is_high = metascore > med_metascore if metascore != .
	gen is_cheap = regular_price < med_regular_price
	gen is_niche = metastd > med_metastd if metastd != .
	
	* Number of games in each group? *
	codebook appid if is_new   == 1  // new
	codebook appid if is_new   == 0	 // old
	codebook appid if is_small == 1  // small
	codebook appid if is_small == 0	 // big
	codebook appid if is_cheap == 1	 // low price
	codebook appid if is_cheap == 0  // high price
	codebook appid if is_high  == 1  // high quality
	codebook appid if is_high  == 0  // low quality
	codebook appid if is_niche == 1  // dispersed ratings
	codebook appid if is_niche == 0  // less dispersed

	* (Table 11) Heterogeneity: simple split *
	local tableOptions "nocons label se dec(3)"
	
	matrix TABLE = J(10,2,.)
	
	ivreghdfe logplayers (logviewers_cumul = num_big_streamer_95 iv_lag1-iv_lag12) if is_new == 1, absorb(game_date game_hour time_id) cluster(game_date)
	matrix TABLE[1,1] = round(_b[logviewers_cumul],0.001)
	matrix TABLE[1,2] = round(_se[logviewers_cumul],0.001)
	
	ivreghdfe logplayers (logviewers_cumul = num_big_streamer_95 iv_lag1-iv_lag12) if is_new == 0, absorb(game_date game_hour time_id) cluster(game_date) 
	matrix TABLE[2,1] = round(_b[logviewers_cumul],0.001)
	matrix TABLE[2,2] = round(_se[logviewers_cumul],0.001)
	
	ivreghdfe logplayers (logviewers_cumul = num_big_streamer_95 iv_lag1-iv_lag12) if is_small == 1, absorb(game_date game_hour time_id) cluster(game_date) 
	matrix TABLE[3,1] = round(_b[logviewers_cumul],0.001)
	matrix TABLE[3,2] = round(_se[logviewers_cumul],0.001)
	
	ivreghdfe logplayers (logviewers_cumul = num_big_streamer_95 iv_lag1-iv_lag12) if is_small == 0, absorb(game_date game_hour time_id) cluster(game_date) 
	matrix TABLE[4,1] = round(_b[logviewers_cumul],0.001)
	matrix TABLE[4,2] = round(_se[logviewers_cumul],0.001)
	
	ivreghdfe logplayers (logviewers_cumul = num_big_streamer_95 iv_lag1-iv_lag12) if is_cheap == 1, absorb(game_date game_hour time_id) cluster(game_date) 
	matrix TABLE[5,1] = round(_b[logviewers_cumul],0.001)
	matrix TABLE[5,2] = round(_se[logviewers_cumul],0.001)
	
	ivreghdfe logplayers (logviewers_cumul = num_big_streamer_95 iv_lag1-iv_lag12) if is_cheap == 0, absorb(game_date game_hour time_id) cluster(game_date) 
	matrix TABLE[6,1] = round(_b[logviewers_cumul],0.001)
	matrix TABLE[6,2] = round(_se[logviewers_cumul],0.001)
	
	ivreghdfe logplayers (logviewers_cumul = num_big_streamer_95 iv_lag1-iv_lag12) if is_high == 1, absorb(game_date game_hour time_id) cluster(game_date) 
	matrix TABLE[7,1] = round(_b[logviewers_cumul],0.001)
	matrix TABLE[7,2] = round(_se[logviewers_cumul],0.001)
	
	ivreghdfe logplayers (logviewers_cumul = num_big_streamer_95 iv_lag1-iv_lag12) if is_high == 0, absorb(game_date game_hour time_id) cluster(game_date) 
	matrix TABLE[8,1] = round(_b[logviewers_cumul],0.001)
	matrix TABLE[8,2] = round(_se[logviewers_cumul],0.001)
	
	ivreghdfe logplayers (logviewers_cumul = num_big_streamer_95 iv_lag1-iv_lag12) if is_niche == 1, absorb(game_date game_hour time_id) cluster(game_date) 
	matrix TABLE[9,1] = round(_b[logviewers_cumul],0.001)
	matrix TABLE[9,2] = round(_se[logviewers_cumul],0.001)
	
	ivreghdfe logplayers (logviewers_cumul = num_big_streamer_95 iv_lag1-iv_lag12) if is_niche == 0, absorb(game_date game_hour time_id) cluster(game_date) 
	matrix TABLE[10,1] = round(_b[logviewers_cumul],0.001)
	matrix TABLE[10,2] = round(_se[logviewers_cumul],0.001)
	
	matrix rownames TABLE = new_games old_games small_publisher big_publisher inexpensive expensive high_quality low_quality niche mainstream
	putexcel set "../output/tables/appendix/median_splits_iv.xlsx", sheet("results") replace
	putexcel A1 = matrix(TABLE), rownames
	
end

program export_to_R

	keep appid title time_utc date hour_of_the_day viewers players viewers_cumul num_big_streamer_95 num_streamers_cumul ngames ngames_pub years_since_release release_date rating_count metascore  metastd multiplayer-publisher_size regular_price game_sponsored game_primary game_sponsored_daily game_primary_daily
	keep if time_utc != . & viewers != . & players != .
	export delimited using "../temp/assembled_data.txt", delimiter(tab) replace

end


main

