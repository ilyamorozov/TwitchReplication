clear all
clear matrix
clear mata
set scheme s2color


program main

	table_top_streamers          // table: top streamers and their schedules
	broadcast_schedule_visualize // figure: good-looking stream schedules
	game_schedule_visualize		 // figure: top streamers' broadcast timing for each of a few games
	time_figure                  // figure: reduced-form graph before-during-after
	broadcast_start_end_summary  // table: variance decomposition of start-end times
	fraction_sponsored           // compute share sponsored and partnered
	table_game_popularity        // replicates table 6 (streaming activity, viewership, and usage)
	summarize_iv_variation		 // top 5% streamers activity summary 
	streaming_fee_estimate       // estimate hourly wage from subs revenues
	summarize_game_char
	
end


program table_top_streamers

	* Remake streamers' top games *
	use "../../build/output/twitch_streams.dta", clear
	merge m:1 streamer using "../../build/output/streamer_chars.dta", keep(1 3) keepusing(is_big_streamer_p95) nogenerate 
	drop if is_big_streamer_p95 == 0
	keep if game_title != "JUST CHATTING" & game_title != "" & game_title != "MUSIC" & game_title != "CHESS" & game_title != "SLOTS" & game_title != "CTYPTO" & game_title != "SPORTS"
	gen count_time = 1
	collapse (sum) count_time, by(streamer game_title)
	gsort streamer -count_time
	by streamer: keep if _n == 1
	rename game_title primary_game
	save "../temp/primary_game.dta", replace

	* Subs revenues *
	use "../../build/output/daily_subs.dta", clear
	collapse (mean) subs_current subs_revenue, by(streamer)
	save "../temp/subs_revenues.dta", replace

	* Other variables *
	use "../../build/output/twitch_streams.dta", clear

	* adjust time to some "suitable time"	(leave at zero_hours if don't want to adjust)
	local zero_hours = 1000*60*60*0 // # of milliseconds in 0 hours
	replace time_utc = time_utc + `zero_hours'

	gen date = dofc(time_utc)
	format %d date
	gen hour = hh(time_utc) + mm(time_utc) / 60
	
	* Collapse to streamer date variable *
	collapse (mean) avg_concur_viewers=viewers (min) start_time=hour (max) end_time=hour max_concur_viewers=viewers, by(streamer date)
	sort streamer date
	gen length_hrs = end_time - start_time
	gen week = week(date)
	bysort streamer week: egen weekly_hours = sum(length_hrs)
	
	* Compute share of days active *
	sum date
	gen total_days_sample = `r(max)' - `r(min)' + 1
	gen days_active = 1
	
	* Cannot average weekly_hours yet -> leave one observation of that var per week *
	bysort streamer week (date): replace weekly_hours = . if _n ~= 1
	
	* Collapse to streamer level *
	collapse (first) total_days_sample (sum) days_active (mean) weekly_hours avg_concur_viewers avg_start_time=start_time avg_end_time=end_time daily_hours=length_hrs (sd) sd_daily_hours=length_hrs  sd_weekly_hours=weekly_hours sd_start_time=start_time sd_end_time=end_time (max) max_concur_viewers, by(streamer)
	replace days_active = (days_active / total_days_sample) * 100
	rename days_active days_active_perc
	drop total_days_sample
	
	* Merge in streamer chars and revenues *
	merge m:1 streamer using "../../build/output/streamer_chars.dta", keep(1 3) nogenerate 
	merge m:1 streamer using "../temp/primary_game.dta", keep(1 3) nogenerate 
	merge m:1 streamer using "../temp/subs_revenues.dta", keep(1 3) nogenerate
	keep if is_core_streamer == 1
	gsort -avg_concur_viewers
	gen num = _n
	order num streamer primary_game avg_concur_viewers max_concur_viewers days_active_perc daily_hours sd_daily_hours weekly_hours sd_weekly_hours avg_start_time sd_start_time avg_end_time sd_end_time subs_current subs_revenue is_big_streamer_p95
	keep  num streamer primary_game avg_concur_viewers max_concur_viewers days_active_perc daily_hours sd_daily_hours weekly_hours sd_weekly_hours avg_start_time sd_start_time avg_end_time sd_end_time subs_current subs_revenue is_big_streamer_p95
	save "../temp/streamer_stats_temp", replace
	
	* Add average all *
	use "../temp/streamer_stats_temp", clear
	collapse (mean) avg_concur_viewers-subs_revenue (firstnm) num streamer primary_game
	replace streamer = "Average All"
	replace primary_game = "N/A"
	replace num = .
	save "../temp/streamer_stats_avg", replace
	
	* Add average all *
	use "../temp/streamer_stats_temp", clear
	keep if is_big_streamer_p95 == 1
	collapse (mean) avg_concur_viewers-subs_revenue (firstnm) num streamer primary_game
	replace streamer = "Average Top"
	replace primary_game = "N/A"
	replace num = .
	save "../temp/streamer_stats_avg_top", replace
		
	* Merge *
	use "../temp/streamer_stats_temp", clear
	append using "../temp/streamer_stats_avg_top"
	append using "../temp/streamer_stats_avg"
	drop is_big_streamer_p95
	keep if num <= 30 | num == .
	* round variables
	replace avg_concur_viewers = round(avg_concur_viewers)
	foreach var in days_active_perc daily_hours weekly_hours avg_start_time sd_start_time avg_end_time sd_end_time subs_current subs_revenue {
		replace `var' = round(`var'*10)/10
	}
	* convert start/end minutes
	foreach var in avg_start_ sd_start_ avg_end_ sd_end_ {
		gen `var'hour = floor(`var'time)
		gen `var'min = round((`var'time - `var'hour) * 60 / 10) * 10
		drop `var'time
	}
	* adjust avg start and end to UTC
	foreach var in avg_start_ avg_end_ {
		replace `var'hour = `var'hour + 3 + 5
		replace `var'hour = `var'hour - 24 if `var'hour >= 24
	}
	keep if num == . | (num ~= . & num <= 15)
	drop subs_current subs_revenue days_active_perc
	export delimited using "../output/tables/section2/table_top_streamers.csv", quote replace

end


program tabulate_and_count_games

	drop if value == ""
	keep steam_title value hours_streamed_000s
	gsort value -hours_streamed_000s
	by value: gen most_streamed_games = steam_title if _n == 1
	by value: replace most_streamed_games = most_streamed_games[_n-1] + ", " + steam_title if _n > 1

	count
	gen counter = 1
	gen total_num_games = r(N)
	gen relative_counter = 1 / total_num_games
	by value: egen num_games = sum(counter)
	by value: egen share_games = sum(relative_counter)
	by value: keep if _n <= 5
	by value: keep if _n == _N
	
end


program time_figure

	* Keep game-date pairs with only one big streamer *
	use "../temp/viewer_player_final.dta", replace
	bysort appid date: egen max_num_streamers = max(num_big_streamer_orig)
	keep if max_num_streamers==0 | max_num_streamers==1
	keep appid time_utc num_big_streamer_orig game_date game_hour time_id players viewers logviewers logplayers
	
	* Configuration *
	local periods_before = 10
	local periods_after  = 20
	local periods_between = `periods_before' + `periods_after'

	* Construct period indicators during and after streams (running variable method = non-overlapping windows) *
	gen period = .
	bysort appid (time_utc): replace period = 0 if _n == 1
	forvalues iter = 1/250 {
		bysort appid (time_utc): replace period = 0 if period[_n-1] == 0 & num_big_streamer_orig == 0 &  period == .
		bysort appid (time_utc): replace period = 0 if period[_n-1] == 0 & num_big_streamer_orig == 1 &  num_big_streamer_orig[_n-1] == 1 & period == .
		bysort appid (time_utc): replace period = 1 if period[_n-1] == 0 & num_big_streamer_orig == 1 &  num_big_streamer_orig[_n-1] == 0 & period == .
		bysort appid (time_utc): replace period = period[_n-1] + 1 if period[_n-1] > 0 & period[_n-1] < `periods_between' & period == .
		bysort appid (time_utc): replace period = 0 if period > `periods_after' & period ~= .
	}

	* Construct period indicators before streams *
	forvalues i = 1/`periods_before' {
		replace period = -`i' if period[_n+`i'] == 1
	}
	
	* Generate dummies *
	replace period = .  if period == 0
	replace period = period + `periods_before' + 1 if period ~= .
	replace period = period - 1 if period > `periods_before' + 1
	tab period, gen(dum_period)
	
	* save "../temp/time_since_stream_start.dta", replace
	export delimited appid time_utc viewers players num_big_streamer_orig period time_id using "..\temp\num_viewers_time.txt", delimiter(tab) replace
	
	* Regression *
	drop dum_period10
	reghdfe logplayers dum_period*, absorb(game_date game_hour time_id)
	regsave using "../temp/time_regression_second_stage.dta", replace	
	
	* First-stage *
	reghdfe logviewers dum_period*, absorb(game_date game_hour time_id)
	regsave using "../temp/time_regression_first_stage.dta", replace

	* plot
	use "../temp/time_regression_second_stage.dta", clear
	gen period = substr(var, 11, 12)
	destring period, replace force
	replace coef = 0 if period == .
	replace stderr = 0 if period == .
	replace period = 10 if period == .
	gen ub = coef + 1.96*stderr
	gen lb = coef - 1.96*stderr
	twoway scatter coef period, msize(1.0) mcolor(edkblue) || rcap lb ub period, xline(11, lwidth(thin) lpattern(dash) lcolor(eltblue)) xlabel(1 "-10h" 6 "-5h" 11 "start" 16 "+5h" 21 "+10h" 26 "+15h") ytitle(Log Players) lwidth(thin) lcolor(ebblue) xtitle(Time interval relative to the focal stream, height(7)) title("Number of players before, during, and after the focal stream", size(medium)) ylabel(-0.006 "-0.006" -0.003 "-0.003" 0 "0" 0.003 "0.003" 0.006 "0.006") graphregion(fcolor(white) lcolor(white)) plotregion(fcolor(white)) legend(off)
	graph export "../output/graphs/section3/players_over_time.png", as(png) replace
	graph export "../output/graphs/section3/players_over_time.eps", replace

	use "../temp/time_regression_first_stage.dta", clear
	gen period = substr(var, 11, 12)
	destring period, replace force
	replace coef = 0 if period == .
	replace stderr = 0 if period == .
	replace period = 10 if period == .
	gen ub = coef + 1.96*stderr
	gen lb = coef - 1.96*stderr
	twoway scatter coef period, msize(1.0) mcolor(edkblue) || rcap lb ub period, xline(11, lwidth(thin) lpattern(dash) lcolor(eltblue)) xlabel(1 "-10h" 6 "-5h" 11 "start" 16 "+5h" 21 "+10h" 26 "+15h") ytitle(Log Players) lwidth(thin) lcolor(ebblue) xtitle(Time interval relative to the focal stream, height(7)) title("Number of viewers before, during, and after the focal stream", size(medium)) graphregion(fcolor(white) lcolor(white)) plotregion(fcolor(white)) legend(off)
	graph export "../output/graphs/section3/viewers_over_time_first.png", as(png) replace
	graph export "../output/graphs/section3/viewers_over_time_first.eps", replace
	
end


program broadcast_schedule_visualize

	* Use a stream_time_table *
	use "../temp/time_table.dta", clear
	expand 500
	bysort time_utc: gen stream_id = _n
	save "../temp/stream_time_table.dta", replace
	
	foreach streamer in auronplay loud_coringa ibai ranboolive sapnap xqcow rocketleague flashpoint asmongold thisisnotgeorgenotfound montanablack88 rubius mizkif karlnetwork shroud {
			
			use "../temp/stream_dat.dta", clear
			keep if streamer == "`streamer'"
			gen date = dofc(start_time) 	// start date
			gen is_game = is_primary_game == 1 | is_other_game == 1
			keep if is_primary_game == 1 | is_chat == 1 | is_other_game == 1
			format date %d
			merge 1:n stream_id date using "../temp/stream_time_table.dta"
			keep if time_utc <= end_time & time_utc >= start_time
			gen hour_min = round((hh(time_utc) * 60 + mm(time_utc)) / 10) * 10
			gen start_hour_min = round((hh(start_time) * 60 + mm(start_time)) / 10) * 10
			gen end_hour_min = round((hh(end_time) * 60 + mm(end_time)) / 10) * 10
			egen med_start = median(start_hour_min)
			egen med_end = median(end_hour_min)
			local st = med_start[1]
			local ed = med_end[1]
			
			keep if date >= 22475 & date <= 22569	// focus on after July 14, 2021 and before Oct 16, 2021 /// NOTE: time is the focal time (Alaskan) plus 8 hours, which is UTC
			
			if "`streamer'" == "auronplay" {
				keep if hour_min >= 240 & hour_min <= 1140
				twoway scatter hour_min date if is_game == 1, xtitle("") ytitle("") ylabel(240 "12pm" 420 "3" 600 "6pm" 780 "9" 960 "12am" 1140 "3", labsize(large))                   ///
																					xlabel(22476 "Jul-15" 22507 "Aug-15" 22538 "Sep-15" 22568 "Oct-15", labsize(huge))                 ///
																					msize(vsmall) msymbol(S) title("`streamer''s broadcast schedule", size(huge)) color(navy)       ///
					|| scatter hour_min date if is_chat == 1, msize(vsmall) msymbol(O) color(eltblue) legend(order(1 "game" 2 "chat") size(large) ring(0) pos(11) col(1) width(10)) ///
																					graphregion(fcolor(white) lcolor(white)) plotregion(fcolor(white))
				graph export "../output/graphs/section3/schedules/schedule_`streamer'_long.png", as(png) width(1200) height(300) replace
			}
			else if "`streamer'" == "loud_coringa" {
				keep if hour_min >= 600 & hour_min <= 1500
				twoway scatter hour_min date if is_game == 1, xtitle("") ytitle("") ylabel(600 "6pm" 780 "9" 960 "12am" 1140 "3" 1320 "6am" 1500 "9")                                  ///
																					xlabel(22476 "Jul-15" 22507 "Aug-15" 22538 "Sep-15" 22568 "Oct-15", labsize(huge))                 ///
																					msize(vsmall) msymbol(S) title("`streamer''s broadcast schedule", size(huge)) color(navy)       ///
					|| scatter hour_min date if is_chat == 1, msize(vsmall) msymbol(O) color(eltblue) legend(order(1 "game" 2 "chat") size(large) ring(0) pos(11) col(1) width(10)) ///
																					graphregion(fcolor(white) lcolor(white)) plotregion(fcolor(white))
				graph export "../output/graphs/section3/schedules/schedule_`streamer'_long.png", as(png) width(1200) height(300) replace
			}
			else {
				twoway scatter hour_min date if is_game == 1, xtitle("") ytitle("") ylabel(240 "12pm" 420 "3pm" 600 "6pm" 780 "9" 960 "12am" 1140 "3" 1320 "6am" 1500 "9am")           ///
																					xlabel(22476 "Jul-15" 22507 "Aug-15" 22538 "Sep-15" 22568 "Oct-15", labsize(huge))                 ///
																					msize(vsmall) msymbol(S) title("`streamer''s broadcast schedule", size(huge)) color(navy)       ///
					|| scatter hour_min date if is_chat == 1, msize(vsmall) msymbol(O) color(eltblue) legend(order(1 "game" 2 "chat") size(large) ring(0) pos(11) col(1) width(10)) ///
																					graphregion(fcolor(white) lcolor(white)) plotregion(fcolor(white))
				graph export "../output/graphs/section3/schedules/schedule_`streamer'_long.png", as(png) width(1200) height(300) replace
			}
	
	}

end


program game_schedule_visualize

	//foreach j in 570 {
	foreach j in 570 730 39210 252950 271590 359550 381210 1085660 1172470 {
		use "../temp/stream_dat.dta", clear
		replace  game_title = "GTA V" if game_title == "GRAND THEFT AUTO V"
		replace  game_title = "RAINBOX SIX" if game_title == "TOM CLANCYS RAINBOW SIX SIEGE"
		replace  game_title = "CS:GO" if game_title == "COUNTER-STRIKE: GLOBAL OFFENSIVE"
		keep if appid == `j'
		gen date = dofc(start_time) 	// start date
		gen date_end = dofc(end_time) 	// end date
		keep if date >= date("2021-06-01", "YMD") & date <= date("2021-06-10", "YMD") & date_end <= date("2021-06-10", "YMD")
		merge n:1 streamer using "../temp/streamer_stats_temp.dta", keep(3) keepusing(is_big_streamer_p95) nogen
		keep if is_big_streamer_p95 == 1
		drop stream_id
		gen stream_id = _n 	// just for matching the time table data
		merge 1:n stream_id using "../temp/stream_time_table.dta", keep(3) nogen
		keep if time_utc <= end_time & time_utc >= start_time 
		egen streamer_id = group(streamer)
		local title = game_title[1]
		twoway scatter streamer_id time_utc if streamer_id <= 30, msize(tiny) msymbol(S) color(navy) title("Live Broadcast Schedules of Top Streamers (`title')", size(medium)) xtitle("date and time") ytitle("top streamer") graphregion(fcolor(white) lcolor(white)) plotregion(fcolor(white))
		graph export "../output/graphs/section3/schedules/schedule_game_`j'.png", as(png) width(1200) height(500) replace
	}
	graph close
	
// 	foreach j in 570 730 39210 252950 271590 359550 381210 1085660 1172470 {
// 		use "../temp/stream_dat.dta", clear
// 		keep if appid == `j'
// 		gen date = dofc(start_time) 	// start date
// 		gen date_end = dofc(end_time) 	// end date
// 		keep if date >= date("2021-06-01", "YMD") & date <= date("2021-06-03", "YMD") & date_end <= date("2021-06-03", "YMD")
// 		merge n:1 streamer using "../temp/streamer_stats_temp.dta", keep(3) keepusing(is_big_streamer_p95) nogen
// 		keep if is_big_streamer_p95 == 1
// 		drop stream_id
// 		gen stream_id = _n 	// just for matching the time table data
// 		merge 1:n stream_id using "../temp/stream_time_table.dta", keep(3) nogen
// 		keep if time_utc <= end_time & time_utc >= start_time 
// 		egen streamer_id = group(streamer)
// 		local title = game_title[1]
// 		twoway scatter streamer_id time_utc if streamer_id <= 25, msize(vsmall) msymbol(S) color(eltblue) title(`title') xtitle("date and time") ytitle("streamer") graphregion(fcolor(white) lcolor(white)) plotregion(fcolor(white))
// 		graph export "../output/graphs/section3/schedules/schedule_game_`j'.png", as(png) width(1200) height(300) replace
// 	}
		
end			


program broadcast_start_end_summary

	* Decomposition *
	foreach fixedeffect in game_date appid {
		
		use "../temp/stream_dat.dta", clear
		merge n:1 streamer using "../../build/output/streamer_chars.dta", keep(3) nogenerate
		keep if appid != . & is_core_streamer == 1	// keep steam games, core streamers (60k)
		gen date 			= dofc(start_time)
		gen shour        	= hh(start_time)
		gen smin         	= mm(start_time)
		gen ehour        	= hh(end_time)
		gen emin         	= mm(end_time)
		gen start_hour   	= shour + smin/60
		gen end_hour     	= ehour + emin/60
		replace duration 	= duration / 60
		egen streamer_game  = group(streamer appid)
		egen game_date 		= group(appid date)
		matrix TABLE = J(6,4,.)
	
		* All streamers *
		local counter = 1
		foreach var in start_hour end_hour duration {
			quietly reghdfe `var', absorb(`fixedeffect') residuals(`var'_resid1)
			scalar var_games = e(r2)
			quietly reghdfe `var'_resid1, absorb(streamer_game)
			scalar var_streamers = e(r2) / (1-var_games)
			scalar var_overtime = 1 - var_games - var_streamers
			drop `var'_resid1
			matrix TABLE[`counter',2] = 100 * round(var_games,0.001)
			matrix TABLE[`counter',3] = 100 * round(var_streamers,0.001)
			matrix TABLE[`counter',4] = 100 * round(var_overtime,0.001)
			local counter = `counter' + 1
		}
		sum start_hour
		matrix TABLE[1,1] = round(r(sd),0.01)
		sum end_hour
		matrix TABLE[2,1] = round(r(sd),0.01)
		sum duration
		matrix TABLE[3,1] = round(r(sd),0.01)
		
		* Top 5% streamers *
		keep if is_big_streamer_p95 == 1
		foreach var in start_hour end_hour duration {
			quietly reghdfe `var', absorb(`fixedeffect') residuals(`var'_resid1)
			scalar var_games = e(r2)
			quietly reghdfe `var'_resid1, absorb(streamer_game)
			scalar var_streamers = e(r2) / (1-var_games)
			scalar var_overtime = 1 - var_games - var_streamers
			drop `var'_resid1
			matrix TABLE[`counter',2] = 100 * round(var_games,0.001)
			matrix TABLE[`counter',3] = 100 * round(var_streamers,0.001)
			matrix TABLE[`counter',4] = 100 * round(var_overtime,0.001)
			local counter = `counter' + 1
		}
		sum start_hour
		matrix TABLE[4,1] = round(r(sd),0.01)
		sum end_hour
		matrix TABLE[5,1] = round(r(sd),0.01)
		sum duration
		matrix TABLE[6,1] = round(r(sd),0.01)

		* Table 2: decomposition of start times, end times, and duration *
		matrix list TABLE
		matrix rownames TABLE = all_start_se all_end_se all_duration_se top_start_se top_end_se top_duration_se
		putexcel set "../output/tables/appendix/table_time_decomposition_`fixedeffect'.xlsx", sheet("results") replace
		putexcel A1 = matrix(TABLE), rownames
		
	}
					
end


program fraction_sponsored

	use "../../build/output/twitch_streams.dta", clear
	keep if time_utc > tc("11may2021 01:00:00") 
	merge n:1 streamer using "../../build/output/streamer_chars.dta", keep(3) nogenerate
	keep if appid != . & is_core_streamer == 1	// keep steam games, core streamers (60k)

	tab is_sponsored	// 1.04% sponsored
	tab is_partner		// 0.16% partner
	
	tab is_sponsored if is_big_streamer_p95 == 1	// 3.14% sponsored
	tab is_partner	 if is_big_streamer_p95 == 1	// 0.87% partnered
	
end


program table_game_popularity

	* Select games to be consistent with the estimation sample *
	use "../temp/viewer_player_final.dta", clear
	collapse (sum) hours_played_per_day = players, by(appid date)
	collapse (mean) hours_played_per_day (sum) hours_played = hours_played_per_day, by(appid)
	gen hours_played_000s = hours_played / 1000
	drop hours_played
	save "../temp/games_select.dta", replace

	* Table: game characteristics *
	use "../../build/output/game_chars.dta", clear
	merge 1:1 appid using "../temp/games_select.dta", keep(match) nogenerate
	label variable num_streams             "Num Streams All"
	label variable num_top                 "Num Streams Top"
	label variable hours_streamed_000s     "Hours Streamed 1000s"
	label variable time_viewed_hrs_000s    "Hours Viewed 1000s"
	label variable hours_played_000s       "Hours Played 1000s"
	label variable num_streams_per_day     "Num Streams All per Day"
	label variable num_top_per_day         "Num Streams Top per Day"
	label variable hours_streamed_per_day  "Hours Streamed per Day"
	label variable time_viewed_hrs_per_day "Hours Viewed per Day"
	label variable hours_played_per_day    "Hours Played per Day"
	label variable ngames                  "Developer size (# games)"
	label variable years_since_release     "Years Since Release"
	label variable metascore               "Rating Metascore"
	label variable regular_price           "Regular Price"
	label variable metastd                 "Rating Std"
	estpost summarize num_streams-time_viewed_hrs_000s hours_played_000s num_streams_per_day-time_viewed_hrs_per_day hours_played_per_day, detail
	esttab using "../output/tables/appendix/table_game_popularity.csv", replace cells("mean(fmt(1)) sd(fmt(1)) p5(fmt(1)) p25(fmt(1)) p50(fmt(1)) p75(fmt(1)) p95(fmt(1))") nomtitle noobs label b(%8.2f)

end


program summarize_iv_variation

	* Compute average and maximum number of top streamers (daily) *
	use "../temp/viewer_player_final.dta", clear
	gen num_big_streamer_95_pos = num_big_streamer_95 if num_big_streamer_95 > 0
	collapse (max) max_num_streamers_live=num_big_streamer_95 (mean) avg_num_streamers_live=num_big_streamer_95 avg_num_streamers_live_pos=num_big_streamer_95_pos, by(appid date)
	collapse (mean) max_num_streamers_live avg_num_streamers_live avg_num_streamers_live_pos, by(appid)
	save "../temp/iv_variation.dta", replace
	
	* Compute average stream duration among top streamers *
	use "../../build/output/twitch_streams.dta", clear
	keep if time_utc > tc("11may2021 01:00:00") 
	merge n:1 streamer using "../../build/output/streamer_chars.dta", keep(3) nogenerate
	keep if appid != . & is_core_streamer == 1	// keep steam games, core streamers (60k)
	gen date = dofc(time_utc)
	format %d date
	gen time_intervals = 10 // minutes in each interval
	collapse (sum) stream_time_min = time_intervals,  by(appid date streamer)
	collapse (mean) avg_stream_time_min=stream_time_min, by(appid date)
	collapse (mean) avg_stream_time_min, by(appid)
	gen avg_stream_time_hrs = avg_stream_time_min / 60
	merge 1:1 appid using "../temp/iv_variation.dta", keep(match) nogenerate
	label variable avg_num_streamers_live "Avg no. streamers live"
	label variable avg_num_streamers_live_pos "Avg no. streamers live (if at least one)"
	label variable max_num_streamers_live "Max no. streamers live"
	label variable avg_stream_time_hrs    "Stream duration (hrs)"
	estpost summarize avg_num_streamers_live avg_num_streamers_live_pos max_num_streamers_live avg_stream_time_hrs, detail
	esttab using "../output/tables/appendix/table_variation_top_streamers.csv", replace cells("mean(fmt(2)) sd(fmt(2)) p5(fmt(2)) p25(fmt(2)) p50(fmt(2)) p75(fmt(2)) p95(fmt(2))") nomtitle noobs label b(%8.2f)

end


program streaming_fee_estimate

	* Load stream-level data *
	use "../../build/output/twitch_streams.dta", clear
	
	* Clean time variables *
	local zero_hours = 1000*60*60*0 // # of milliseconds in 0 hours
	replace time_utc = time_utc + `zero_hours'
	gen date = dofc(time_utc)
	format %d date
	
	* Number of days covered by the sample *
	egen start_date_sample = min(date)
	egen end_date_sample = max(date)
	gen num_days_sample = end_date_sample - start_date_sample + 1
	
	* Number of hours each streamer was live during the entire sample period *
	gen hours = 1/6 // each period is 10 minutes
	collapse (sum) total_hours_sample = hours (firstnm) num_days_sample, by(streamer)
	gen hours_per_day = total_hours_sample / num_days_sample
	gen hours_per_month = hours_per_day * 30
	
	* Merge in subs revenue and compute hourly wage *
	merge m:1 streamer using "../../build/output/streamer_chars.dta", keep(match) nogenerate 
	merge m:1 streamer using "../temp/subs_revenues.dta", keep(match) nogenerate
	keep if is_core_streamer == 1
	gen hourly_wage = subs_revenue / hours_per_month
	
	* Summary (claims in the paper) *
	sum hourly_wage
	sum subs_current if subs_revenue != .
	sum hours_per_month if subs_revenue != .
	sum subs_revenue
	sum hourly_wage if is_big_streamer_p95 == 1
	sum subs_current if subs_revenue != . & is_big_streamer_p95 == 1
	sum hours_per_month if subs_revenue != . & is_big_streamer_p95 == 1
	sum subs_revenue if is_big_streamer_p95 == 1

	* Save the estimate *
	keep if is_big_streamer_p95 == 1
	egen hourly_wage_avg = mean(hourly_wage)
	replace hourly_wage_avg = round(hourly_wage_avg)
	keep hourly_wage_avg
	keep if _n == 1
	export delimited using "../output/estimates/hourly_wage/hourly_wage.csv", novarnames replace
	
end


program summarize_game_char

	use "../../build/output/game_chars.dta", clear
	
	* #games by publishers
	su ngames_pub, detail 	// median is 3
	gen fewer_than_two = ngames_pub <= 2
	tab fewer_than_two		// 47%
	
	* years since launched
// 	gen days_since_release = date("2021-05-11", "YMD") - release_date
	su years_since_release, detail	// median is 2.62
	
	* price
	su regular_price if regular_price > 0, detail	// median price is $19.99, 1-99 pct is $3.99 - $59.99
	
	* ratings
	su metascore, detail							// 80 median, 42-95
	
	
end

main

