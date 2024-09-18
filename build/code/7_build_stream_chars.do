clear
program drop _all


program main

	build_stream_characteristics

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


main

