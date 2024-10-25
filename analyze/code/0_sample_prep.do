clear all
clear matrix
clear mata
set maxvar 100000
set scheme s2color


program main

	create_directories
	build_stream_table
	build_broadcast_history
	build_10min
	build_1h
	build_daily
	build_time_table
	build_subs_table
	
end


program create_directories

	cap mkdir ../output/cross_validation/
	cap mkdir ../output/estimates/
	cap mkdir ../output/estimates/
	cap mkdir ../output/estimates/forest/
	cap mkdir ../output/estimates/forest/cross_validation/
	cap mkdir ../output/estimates/hourly_wage/
	cap mkdir ../output/graphs/
	cap mkdir ../output/graphs/appendix/
	cap mkdir ../output/graphs/appendix/validate_aggregation/
	cap mkdir ../output/graphs/appendix/validate_aggregation/
	cap mkdir ../output/graphs/section3/
	cap mkdir ../output/graphs/section3/schedules/
	cap mkdir ../output/graphs/section4/
	cap mkdir ../output/graphs/section4/cross_validation/
	cap mkdir ../output/graphs/section4/cross_validation/1/
	cap mkdir ../output/graphs/section4/cross_validation/2/
	cap mkdir ../output/graphs/section4/cross_validation/4/
	cap mkdir ../output/graphs/section4/cross_validation/8/
	cap mkdir ../output/graphs/section5/
	cap mkdir ../output/tables/
	cap mkdir ../output/tables/appendix/
	cap mkdir ../output/tables/appendix/main_results_robust/
	cap mkdir ../output/tables/section2/
	cap mkdir ../output/tables/section3/
	cap mkdir ../output/tables/section3/bootstrap_samples/
	cap mkdir ../output/tables/section4/
	cap mkdir ../output/tables/section5/
	
end


program build_stream_table

	* Generate stream-level data *
	use "../../build/output/twitch_streams.dta", clear
	keep if time_utc > tc("11may2021 01:00:00") 
	merge n:1 streamer using "../../build/output/streamer_chars.dta", keep(3) nogenerate
	bysort streamer (time_utc): gen double diff_time = (time_utc - time_utc[_n-1]) / 1000 / 60		// measured in minutes
	bysort streamer (time_utc): gen diff_game = game_title != game_title[_n-1]
	gen stream_start = diff_time >= 20 | diff_time == . | diff_game == 1
	bysort streamer (time_utc): gen stream_id = sum(stream_start)
	gen is_primary_game = primary_steam_appid == appid & primary_steam_appid != .
	gen is_chat = game_title == "JUST CHATTING"
	gen is_other_game = is_primary_game == 0 & is_chat == 0
	bysort streamer stream_id: egen start_time = min(time_utc)
	bysort streamer stream_id: egen end_time = max(time_utc)
	bysort streamer stream_id: keep if _n == 1
	keep streamer stream_id start_time end_time game_title appid is_primary_game is_chat is_other_game is_partner scaling_factor
	gen duration = (end_time - start_time) / 1000 / 60
	save "../temp/stream_dat.dta", replace
	
	* Compute and save stream duration *
	use "../temp/stream_dat.dta", clear
	merge n:1 streamer using "../../build/output/streamer_chars.dta", keep(3) keepusing(is_big_streamer_p95) nogenerate
	keep if is_big_streamer_p95 == 1
	collapse (mean) duration, by(appid)
	replace duration = duration / 60
	drop if appid == .
	* 585 out of 599 games were ever broadcasted by top streamers
	export delimited using "../temp/average_stream_duration.txt", delimiter(tab) replace	
	
	* Flag streamers with highly irregular schedules (for robustness regressions) *
	use "../temp/stream_dat.dta", clear
	merge n:1 streamer using "../../build/output/streamer_chars.dta", keep(3) keepusing(is_big_streamer_p95) nogenerate
	gen date       = dofc(start_time)
	gen start_hour = hh(start_time)
	gen end_hour   = hh(end_time)
	format date %d
	collapse (min) start_hour (max) end_hour (firstnm) is_big_streamer_p95, by(streamer date)                // work hours
	collapse (sd) sd_start_hour=start_hour sd_end_hour=end_hour (firstnm) is_big_streamer_p95, by(streamer)  // variation in work hours
	gen sd_schedule_average     = (sd_start_hour + sd_end_hour) / 2 
	drop if sd_start_hour == . | sd_end_hour == .
	keep if is_big_streamer_p95 == 1
	egen sd_schedule_quantile   = xtile(sd_schedule_average), n(2)
	assert sd_schedule_quantile ~= .
	gen flag_irregular_schedule = (sd_schedule_quantile == 2)
	keep streamer flag_irregular_schedule sd_schedule_average
	mean sd_schedule_average if flag_irregular_schedule == 1
	save "../temp/streamers_with_irregular_hours.dta", replace
	
end


program build_broadcast_history

	* Prepare historical streams to measure whether streamer has broadcasted the game before *
	use "../../build/temp/twitch_tracker_historical_full.dta", clear
	merge n:1 game_title using "../../build/temp/steam_twitch_crosswalk.dta", keep(3) keepusing(steam_id) nogenerate
	rename steam_id appid
	collapse (min) first_date_historical = date, by(streamer appid) 
	drop if appid == .
	save "../temp/first_stream_date.dta", replace

end


program build_10min

	* Load streams *
	use "../../build/output/twitch_streams.dta", clear
	keep if time_utc > tc("11may2021 01:00:00") 
	merge n:1 streamer using "../../build/output/streamer_chars.dta", keep(3) nogenerate
	merge n:1 streamer using "../temp/streamers_with_irregular_hours.dta", keep(1 3) nogenerate
	replace flag_irregular_schedule = 0 if flag_irregular_schedule == .
	keep if appid != . & is_core_streamer == 1	// keep steam games, core streamers (60k)
	
	* First stream date (historical data) *
	gen date = dofc(time_utc)
	format %d date
	merge n:1 streamer appid using "../temp/first_stream_date.dta", keep(1 3) nogenerate
	bysort streamer appid: egen first_broadcast_date = min(date)
	gen have_broadcasted_before = (date > first_broadcast_date) | (date > first_date_historical)

	* Rescale viewer counts (scaling factor = sampling probability) *
	replace viewers         = viewers / scaling_factor
	gen viewers_sponsored   = is_sponsored * viewers
	gen viewers_partner     = is_partner   * viewers
	//gen viewers_nonsponsored = (1 - is_sponsored) * viewers
	//gen viewers_nonpartner = (1 - is_partner) * viewers
	
	* Rescale top 5% streamer counts (sponsored and partnered) *
	gen is_big_streamer_orig         = is_big_streamer_p95                      // keep this for the RDD graphs
	replace is_big_streamer_p95      = is_big_streamer_p95 / scaling_factor
	gen is_big_streamer_sponsored    = is_sponsored     * is_big_streamer_p95
	gen is_big_streamer_partner      = is_partner       * is_big_streamer_p95
	gen is_big_streamer_nonsponsored = (1-is_sponsored) * is_big_streamer_p95
	gen is_big_streamer_nonpartner   = (1-is_partner)   * is_big_streamer_p95
	gen is_big_organic_ext           = (1-is_sponsored) * is_big_streamer_p95 * have_broadcasted_before

	* Construct verion of IV based on only streamers with irregular schedules *
	gen is_big_streamer_95_irreg = flag_irregular_schedule * is_big_streamer_p95

	* Collapse to game-time level *
	collapse (sum) viewers viewers_sponsored viewers_partner          ///
		num_big_streamer_orig          = is_big_streamer_orig         ///
	    num_big_streamer_95            = is_big_streamer_p95          ///
	    num_big_streamer_95_irreg      = is_big_streamer_95_irreg     ///
		num_big_streamer_sponsored     = is_big_streamer_sponsored    /// 
		num_big_streamer_partner       = is_big_streamer_partner      ///
		num_big_streamer_nonsponsored  = is_big_streamer_nonsponsored ///
		num_big_streamer_nonpartner    = is_big_streamer_nonpartner   ///
		num_big_organic_ext            = is_big_organic_ext, by(appid time_utc)
		
	* Merge with player counts *
	merge 1:1 appid time_utc using "../../build/output/players.dta"
	drop if _merge == 1                                                       // drop games only in master (games not included into analysis)
	foreach var of varlist viewers num_big_* viewers_* {
		replace `var' = 0 if _merge == 2									  // fill viewers with zeros (have player counts but nobody streams)
	}
	bysort appid (time_utc): replace players = players[_n-1] if players == .  // fill in gaps in player counts (affects very few obs)
	drop _merge

	* Remove top streamers from player counts (remove direct effect on player counts) *
	replace players = max(players - num_big_streamer_95, 0)
	drop if time_utc == .
	
	* Verify that the panel is complete *
	fillin appid time_utc
	assert _fillin == 0
	drop _fillin
	
	* Generate date *
	gen date = dofc(time_utc)
	format %d date

	* Logs *
	foreach var in viewers players {
		gen log`var' = log(`var' + 1)
	}
	
	* Save high-freq data for over-time figures *
	generate_fixed_effects
	
	* Filter 599 games (games that have 1.streams, 2.usage, 3.characteristics)
	merge n:1 appid using "../../build/output/game_chars.dta", keepusing(appid) keep(3) nogenerate
    bysort appid: egen avg_players = mean(player)
    drop if avg_players == 0 // drop two games, now 599 games
    drop avg_players
	
	* Assert no unexpected missings (complete data) *
	sum viewers
	assert r(N) == _N
	sum players
	assert r(N) == _N
	sum game_date
	assert r(N) == _N
	sum num_big_streamer_95
	assert r(N) == _N

	* Save data *
	save "../temp/viewer_player_10min.dta", replace
	
end


program build_1h
	
	* Round time to the half-hour level and aggregate (take average #viewers and #players, and max #streamers)
	use "../temp/viewer_player_10min.dta", clear
	gen double time_utc_hr = floor(time_utc / 1000 / 3600) * 1000 * 3600	// 100 seconds * 1000 milliseconds
	format time_utc_hr %tc
	replace time_utc = time_utc_hr
	
	* Collapse to hour level *
	collapse (mean) players viewers viewers_sponsored viewers_partner ///
	         (max)  num_big_streamer_orig          ///
			        num_big_streamer_95            ///
			        num_big_streamer_95_irreg      ///
					num_big_streamer_sponsored     ///
					num_big_streamer_partner       ///
					num_big_streamer_nonsponsored  ///
					num_big_streamer_nonpartner    ///
					num_big_organic_ext            ///
			 (firstnm) date, by(appid time_utc)

	* FEs *
	generate_fixed_effects

	* Time_id: round time to hours * 
	gen double time_id	 = round(time_utc / 1000 / 3600)
	egen m_time_id		 = min(time_id)
	replace time_id		 = time_id - m_time_id + 1
	
	* Flag games with no IV variation and low player/viewer counts *
	bysort appid: egen max_big_streamers = max(num_big_streamer_95)
    bysort appid: egen avg_players       = mean(players)
	bysort appid: egen avg_viewers       = mean(viewers)
	gen no_instruments = (max_big_streamers == 0)  // no IV variation
	gen no_players = (avg_players < 10)            // low player counts 
	gen no_viewers = (avg_viewers < 10)            // low viewer counts
	drop avg_players avg_viewers max_big_streamers
	
	* Precompute lags for regressions
	local num_lags = 3*24
	forvalues j = 1/`num_lags' {
		quietly: bysort appid (time_utc): gen viewers_lag`j' = viewers[_n-`j']
	}
	forvalues j = 1/`num_lags' {
		quietly: bysort appid (time_utc): gen iv_lag`j'        = num_big_streamer_95[_n-`j']
	}
	forvalues j = 1/`num_lags' {
		quietly: bysort appid (time_utc): gen iv_lag_irreg`j'  = num_big_streamer_95_irreg[_n-`j']
	}

	* Assert no unexpected missings (complete data) *
	sum viewers
	assert r(N) == _N
	sum players
	assert r(N) == _N
	sum game_date
	assert r(N) == _N
	sum num_big_streamer_95
	assert r(N) == _N
	
	* Logs and variable labels *
	foreach var in viewers players {
		gen log`var' = log(`var' + 1)
	}
	label variable logviewers "Log Contemporaneous Viewers"
	label variable num_big_streamer_95 "Nr. Live Top Streamers"
	label variable num_big_streamer_95_irreg "Nr. Live Top Streamers with irregular hours"
	
	* Save data for regression analysis *
	gen num_lags_iv = 12
	keep if iv_lag12 != .
	save "../temp/viewer_player_final.dta", replace
	
	* Export the number of streamers to text *
	use "../temp/viewer_player_final.dta", clear
	
	export delimited appid date hour_of_the_day num_big_streamer_95 num_big_streamer_sponsored num_big_streamer_nonsponsored ///
		using "../temp/nr_streamer_hourly.csv", replace

end


program build_daily

	* collapse (mean) players viewers (max) num_big_streamer_95 (firstnm) date, by(appid time_utc)
	collapse (mean) players viewers viewers_sponsored viewers_partner (max) num_big_streamer_95 ///
		num_big_streamer_sponsored num_big_streamer_partner, by(appid date)

	* FEs *
	gen  week 		     = week(date)
	gen  dow 		     = dow(date)
	egen game_week 	     = group(appid week)
	egen game_dow 	     = group(appid dow)
	
	* Variable labels for output tables *
	foreach var in viewers players {
		gen log`var' = log(`var' + 1)
	}
	label variable logviewers "Log Contemporaneous Viewers"
	label variable num_big_streamer_95 "Nr. Live Top Streamers"
	
	* Precompute lags for regressions
	local num_lags = 6
	forvalues j = 1/`num_lags' {
		quietly: bysort appid (date): gen viewers_lag`j' = viewers[_n-`j']
	}
	forvalues j = 1/`num_lags' {
		quietly: bysort appid (date): gen iv_lag`j'      = num_big_streamer_95[_n-`j']
	}

	* Save data for regression analysis *
	gen num_lags_iv = 6
	keep if iv_lag6 != .
	save "../temp/viewer_player_daily.dta", replace

end


program build_time_table

	use "../temp/viewer_player_final.dta", clear
	collapse (firstnm) date, by(time_utc)
	save "../temp/time_table.dta", replace

end


program build_subs_table

	* work hours
	use "../temp/stream_dat.dta", clear
	gen date = dofc(start_time)
	format date %d
	collapse (sum) duration, by(streamer date)
	gen work_hours = duration / 60
	replace work_hours = 24 if work_hours > 24 & work_hours != .
	drop duration
	save "../temp/work_hours.dta", replace
	
	* daily subs income
	use "../../build/output/daily_subs.dta", clear
	merge n:1 streamer using "../../build/output/streamer_chars.dta", keepusing(is_big_streamer_p95 primary_steam_appid) keep(3) nogenerate
	foreach var in subs_current subs_revenue {
		bysort streamer (date): gen d_`var' = `var' - `var'[_n-1]
		replace d_`var' = 0 if d_`var' < 0	
		* this step assumes that increases in d_var comes from new subs (which is reasonable), but that all new subs are from increases in d_var (e.g., 1 unsub and 1 new sub would cancel out)
	}
	merge 1:1 streamer date using "../temp/work_hours.dta", keep(1 3)
	replace work_hours = 0 if work_hours == .
	* keep if date >= date("01jun2021", "DMY")
	collapse (sum) work_hours d_subs_revenue d_subs_current (firstnm) primary_steam_appid is_big_streamer_p95, by(streamer)
	gen wage = d_subs_revenue / work_hours
	save "../temp/streamer_implied_wage.dta", replace
	export delimited using "../temp/streamer_implied_wage.txt", delimiter(tab) replace	

end


program generate_fixed_effects

	gen  hour_of_the_day = hh(time_utc)
	gen  week 		     = week(date)
	gen  dow 		     = dow(date)
	egen game_week 	     = group(appid week)
	egen game_dow 	     = group(appid dow)
	egen game_date       = group(appid date)
	egen game_hour       = group(appid hour_of_the_day)

end


main