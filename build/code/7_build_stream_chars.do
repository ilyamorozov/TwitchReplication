clear
program drop _all


program main

	build_stream_characteristics
	build_twitch_stream_history
end


program build_stream_characteristics

	*** Build the list of all streams with their characteristics ***
	* Define streams from raw 10-min data (started streaming another game -> interpret as a new stream) *
	use "../output/twitch_streams.dta", clear
	gen end_of_stream = .
	gen stream_id = .
	replace game_title = "UNKNOWN" if game_title == ""
	bysort streamer (time_utc): replace end_of_stream = 1 if (game_title[_n+1] ~= game_title) | (time_utc[_n+1] - time_utc > 600000)
	bysort streamer (time_utc): replace stream_id = 1 if _n == 1
	bysort streamer (time_utc): replace stream_id = stream_id[_n-1] + (end_of_stream[_n-1] == 1) if stream_id == . & _n > 1
	drop end_of_stream

	* Collapse to stream-level *
	collapse (first) game_title appid (sum) total_viewers=viewers (mean) avg_viewers=viewers (min) start_time=time_utc (max) end_time=time_utc is_sponsored, by(streamer stream_id)
	gen start_date = dofc(start_time)
	gen end_date   = dofc(end_time)
	gen length_min = (end_time - start_time) / 60000
	format start_date end_date %td

	* Mark top 5% streamers *
	merge m:1 streamer using "../output/streamer_chars.dta", nogenerate
	gen is_primary = (appid == primary_steam_appid & appid~=. & primary_steam_appid~=.)
	gen is_secondary = (game_title == secondary_game & game_title != "")
	gen is_third = (game_title == third_game & game_title != "")
	gen is_fourth = (game_title == fourth_game & game_title != "")
	drop daily_viewers_avg language primary_steam_appid primary_steam_game secondary_appid secondary_game third_appid third_game fourth_appid fourth_game
	save "../output/stream_chars.dta", replace

end


program build_twitch_stream_history

	* Assemble TwitchTracker data *
	import delimited "../input/data_twitch_tracker/batch_2/streams.csv", clear
	gen date2 = substr(date, 1, 10)
	keep name date2 time duration viewers unique_viewers games  
	save "../temp/twitch_tracker_streams_temp.dta", replace
	foreach var in streams_2 streams_3 {
		import delimited "../input/data_twitch_tracker/batch_2/`var'.csv", clear
		gen date2 = substr(date, 1, 10)
		keep name date2 time duration viewers unique_viewers games  
		save "../temp/stream_temp.dta", replace
		use "../temp/twitch_tracker_streams_temp.dta", clear
		append using "../temp/stream_temp.dta"
		save "../temp/twitch_tracker_streams_temp.dta", replace
	}
	foreach var in streams streams_2 streams_3 {
		import delimited "../input/data_twitch_tracker/batch_1/`var'.csv", clear
		gen date2 = substr(date, 1, 10)
		keep name date2 time duration viewers unique_viewers games  
		save "../temp/stream_temp.dta", replace
		use "../temp/twitch_tracker_streams_temp.dta", clear
		append using "../temp/stream_temp.dta"
		save "../temp/twitch_tracker_streams_temp.dta", replace
	}
	
	duplicates drop
	gen date = date(date2, "YMD")
	format date %d
	drop date2
	
	gen start_hour = substr(time, 1, 2)
	gen start_minute = substr(time, 4, 2)
	destring start_hour, replace force
	destring start_minute, replace force
	gen start_time = start_hour + start_minute/60

	* Exclude popular non-game content *
	replace games = regexr(games, "^Just Chatting$|Just Chatting, |, Just Chatting|, Just Chatting, ", "") 
	replace games = regexr(games, "^Twitch Sings$|Twitch Sings, |, Twitch Sings|, Twitch Sings, ", "") 
	replace games = regexr(games, "^Music$|Music, |, Music|, Music, ", "") 
	replace games = regexr(games, "^Art$|Art, |, Art|, Art, ", "") 
	replace games = regexr(games, "^Sports$|Sports, |, Sports|, Sports, ", "") 
	replace games = regexr(games, "^Science & Technology$|Science & Technology, |, Science & Technology|, Science & Technology, ", "") 
	replace games = regexr(games, "^Talk Shows & Podcasts$|Talk Shows & Podcasts, |, Talk Shows & Podcasts|, Talk Shows & Podcasts, ", "") 

	* Exclude popular non-steam games *
	replace games = regexr(games, "^League of Legends$|League of Legends, |, League of Legends|, League of Legends, ", "") 
	replace games = regexr(games, "^Fortnite$|Fortnite, |, Fortnite|, Fortnite, ", "") 
	replace games = regexr(games, "^Overwatch$|Overwatch, |, Overwatch|, Overwatch, ", "") 
	replace games = regexr(games, "^StarCraft II$|StarCraft II, |, StarCraft II|, StarCraft II, ", "") 
	replace games = regexr(games, "^Minecraft$|Minecraft, |, Minecraft|, Minecraft, ", "") 
	replace games = regexr(games, "^World of Warcraft$|World of Warcraft, |, World of Warcraft|, World of Warcraft, ", "") 
	replace games = regexr(games, "^VALORANT$|VALORANT, |, VALORANT|, VALORANT, ", "") 
	replace games = regexr(games, "^Teamfight Tactics$|Teamfight Tactics, |, Teamfight Tactics|, Teamfight Tactics, ", "") 

	* Clean game titles *
	replace games = regexr(games, "^ |^, ", "") 
	keep if games != ""

	* Keep the first game if there are multiple games *
	replace games = regexr(games, ", .*", "") 
	
	* Rename *
	rename name streamer
	save "../temp/twitch_tracker_historical_raw.dta", replace

	use "../temp/twitch_tracker_historical_raw.dta", clear
	
	* Generate stream ID per streamer-date *
	gsort streamer date -duration
	by streamer date: gen stream_id = _n		// 88% streams are the only stream of the day, 11% streams are the second stream of the day, 5 streams goes to 
	keep if stream_id <= 5
	keep streamer date stream_id games viewers unique_viewers start_time duration
		
	* Extract game title *
	gen     game_title = upper(games)
	replace game_title = regexr(game_title, "'", "")
	replace game_title = regexr(game_title, "Ã©", "É")
	replace game_title = regexr(game_title, "é", "É")
	
	save "../temp/twitch_tracker_historical_full.dta", replace
	
	keep if year(date) == 2019 | year(date) == 2020
	save "../temp/twitch_tracker_historical.dta", replace
	
end


main

