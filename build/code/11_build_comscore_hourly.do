clear
program drop _all


program main

	make_hourly_grid
	build_twitch_broadcasts_hourly
	build_twitch_views_hourly
	build_fav_streamer_broadcast
	merge_tables_hourly
	
end


program make_hourly_grid

	* Build balanced panel of machine_id x date x hour *
	use "../temp/comscore_individual_panel.dta", clear
	expand 24
	bysort machine_id date: gen hour = _n - 1
	save "../temp/consumer_date_hour_frame.dta", replace
	
end


program build_twitch_broadcasts_hourly

	* Build Twitchtracker hourly stream histories *
	use "../temp/twitch_tracker_historical.dta", clear                                     // this table has only one stream per streamer x date
	assert date > mdy(12,31,2018) &  date < mdy(1,1,2021)                                  // assert dates are selected correctly
	merge n:1 game_title using "../temp/steam_twitch_crosswalk.dta", keep(3) nogenerate	   // lookup Steam ID (most are merged)
	gen start_date = date
	drop if duration > 72
	keep if steam_id != .
	drop game_title
	gen end_time = start_time + duration
	gen first_hour = floor(start_time)
	gen last_hour = floor(end_time)
	gen num_hours = last_hour - first_hour + 1
	
	* Create as many hours as each stream lasted *
	expand num_hours
	bysort streamer date: gen num = _n
	bysort streamer date: gen hour = first_hour + _n - 1
	
	* Adjust dates accordingly (for streams that last into next days) *
	replace date = date + floor(hour/24) if hour >= 24                          // adjust date if lasts into next day
	replace hour = hour - 24*floor(hour/24) if hour >= 24                       // adjust hour if lasts into next day
	
	* Keep relevant variables and save *
	gen is_stream = 1
	bysort streamer date hour (start_date start_time): keep if _n == _N         // if two streams within same hour, keep the one that started later, drop about 0.02% obs
	keep streamer date hour twitch_id steam_id
	save "../temp/twitch_tracker_hourly.dta", replace
	
end	
	
	
program build_twitch_views_hourly
	
	// Which steam games did you watch on Twitch in any given hour? 
	use "../output/comscore_twitch.dta", clear 
	gen date = mdy(month, day, year)
	format date %d
	gen double time_stamp = ss2k*1000 + tc("31dec1999 00:00:30")                // comscore advertises ss2k = 'seconds since 2000' (not quite correct)
	format time_stamp %tC
	gen hour = hh(time_stamp)	
	clean_streamer_names
	keep machine_id date hour streamer
	order machine_id date hour streamer
	duplicates drop                                                             // unique streamers this person watched in any given hour
	gen watch_twitch = 1
	
	* Look up which games were streamed in each of these broadcasts *
	merge n:1 streamer date hour using "../temp/twitch_tracker_hourly.dta", keep(1 3) keepusing(steam_id) nogenerate

	* Extrapolate (makes assumptions about what game was streamed) *  // YH: I think my intention was to assume if the consumer is watching the channels that are not online at the moment, they are watching the game when the channel was last online. But if that's the intention, we should not extrapolate in the other direction
	gsort machine_id streamer date hour
	by machine_id streamer: replace steam_id = steam_id[_n-1] if steam_id[_n-1] != .	
// 	gsort machine_id streamer -date -hour
// 	by machine_id streamer: replace steam_id = steam_id[_n-1] if steam_id[_n-1] != .
	drop if steam_id == .  // drop if we do not know the game
	save "../temp/comscore_twitch_hourly.dta", replace							// 46,101 machines	

end


program build_fav_streamer_broadcast

	* Save everyone's favorite streamer *
	use "../temp/comscore_twitch_daily.dta", clear
	collapse (firstnm) fav_streamer, by(machine_id)
	save "../temp/fav_streamer.dta", replace
	
end


program merge_tables_hourly

	* first stack activities
	use "../output/comscore_twitch.dta", clear
	gen date = mdy(month, day, year)
	format date %d
	gen double time_stamp = ss2k*1000 + tc("31dec1999 00:00:30") // comscore advertises ss2k = 'seconds since 2000' (not quite correct)
	format time_stamp %tC
	gen hour = hh(time_stamp)
	gen flag_twitch = 1

	append using "../temp/comscore_purchases.dta"
	append using "../temp/comscore_purchases_others.dta"
	append using "../temp/comscore_steam_hourly.dta"
	append using "../temp/comscore_twitch_hourly.dta"
	collapse (max) purchase_game purchase_game_rtl browse_steam watch_twitch flag_twitch, by(machine_id date hour steam_id)
	save "../temp/all_activities_hourly.dta", replace
	
	* Keep machines on their days with SOME Twitch viewership *
	use "../temp/all_activities_hourly.dta", clear
	bysort machine_id date: egen any_activity = max(flag_twitch)
	keep if any_activity == 1
	keep machine_id date
	duplicates drop
	save "../temp/some_activity_date.dta", replace                              // save all relevant machine x date pairs, 179,547 machines
	
	* Build hourly balanced panel (machine_id x date x hour x steam_id combinations) *
	use "../temp/consumer_date_hour_frame.dta", clear																				// 8,611 machines
	merge n:1 machine_id date using "../temp/some_activity_date.dta", keep(3) nogenerate       // limit to selected machine-dates	// 8,611 machines
	expand 203 
	bysort machine_id date hour: gen new_game_id = _n
	merge n:1 new_game_id using "../temp/steam_game_names.dta", keepusing(steam_id) keep(3) nogenerate
	drop new_game_id
	save "../temp/consumer_date_hour_game_frame.dta", replace

	* Look up favorite streamers and what they broadcasted in that hour *
	use "../temp/consumer_date_hour_game_frame.dta", clear
	merge n:1 machine_id using "../temp/fav_streamer.dta", keep(1 3) nogenerate
	rename steam_id steam_id_watch
	rename fav_streamer streamer
	merge n:1 streamer date hour using "../temp/twitch_tracker_hourly.dta", keep(1 3) nogenerate
	gen fav_streamer_broadcast = (steam_id_watch == steam_id)
	drop streamer steam_id twitch_id
	rename steam_id_watch steam_id
	
	* Merge in all individual hourly activities *
	merge 1:1 machine_id date steam_id hour using "../temp/all_activities_hourly.dta", keep(1 3) nogenerate
	
	* Fill in zeros *
	foreach var in purchase_game purchase_game_rtl watch_twitch browse_steam fav_streamer_broadcast {
		replace `var' = 0 if `var' == .
	}

	* Generate FEs *
	egen machine_game = group(machine_id steam_id)	
	egen game_date    = group(steam_id date)
	egen game_hour    = group(steam_id hour)
	save "../output/comscore_balanced_panel_hourly.dta", replace

end

program clean_streamer_names

	* convert streamer
	gen str streamer_str = streamer
	replace streamer = ""
	compress streamer
	replace streamer = streamer_str
	drop streamer_str
	keep if strlen(streamer) <= 50
	compress streamer

end

main
