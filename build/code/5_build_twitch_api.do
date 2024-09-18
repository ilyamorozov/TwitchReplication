clear
program drop _all


program main

	build_crosswalks
	build_num_viewers
	build_stream_type
	build_game_id
	build_stream_language
	build_stream_title_tags
	merge_twitch_tables

end


program build_crosswalks

	* Streamer dictionaries *
	import delimited "../input/crosswalks/twitch_df_header_recode_dict.csv", varnames(1) clear
	gen period = 1
	save "../temp/streamer_dictionary1.dta", replace
	import delimited "../input/crosswalks/twitch_df_header_recode_dict_stable_4_30.csv", varnames(1) clear
	gen period = 2
	save "../temp/streamer_dictionary2.dta", replace
	import delimited "../input/crosswalks/twitch_df_header_recode_dict_stable_5_1.csv", varnames(1) clear
	gen period = 3
	save "../temp/streamer_dictionary3.dta", replace
	import delimited "../input/crosswalks/twitch_df_header_recode_dict_stable_n.csv", varnames(1) clear
	gen period = 4
	save "../temp/streamer_dictionary4.dta", replace
	
	* Game ID steam-twitch crosswalk *
	import delimited "../input/crosswalks/top_games_twitch_steam_ids_hand_lookup.csv", varnames(1) clear
	rename twitch_id twitch_game_id
	rename steam_id appid
	format %25s game_title
	save "../temp/games_crosswalk.dta", replace
	
	* Stable streamer set *
	use "../temp/streamer_dictionary4.dta", clear
	keep streamer
	sort streamer 
	save "../temp/stable_streamer_set.dta", replace

end


program define_periods

	gen period = .
	replace period = 1 if time <= tc("30apr2021 18:40:00")                                     // Until 30apr2021 18:40:00
	replace period = 2 if time >  tc("30apr2021 18:40:00") & time <= tc("01may2021 14:40:00")  // 30apr2021 18:40:00 to 01may2021 14:40:00
	replace period = 3 if time >  tc("01may2021 14:40:00") & time <= tc("11may2021 01:00:00")  // 01may2021 14:40:00 to 11may2021 01:00:00
	replace period = 4 if time >  tc("11may2021 01:00:00")                                     // 11may2021 01:00:00 onwards

end


program lookup_streamer_names

	capture gen streamer_code = num - 2			// YH: in the title/tag data, we already have streamer_code, but need to check whether that definition is the same as yours
	merge m:1 period streamer_code using "../temp/streamer_dictionary1.dta"
	drop if _merge == 2
	drop _merge
	merge m:1 period streamer_code using "../temp/streamer_dictionary2.dta", update
	drop if _merge == 2
	drop _merge
	merge m:1 period streamer_code using "../temp/streamer_dictionary3.dta", update
	drop if _merge == 2
	drop _merge
	merge m:1 period streamer_code using "../temp/streamer_dictionary4.dta", update
	drop if _merge == 2
	drop _merge
	drop if streamer == "" // investigate why observations missing from dict #2 and #3
	drop period

end


program convert_time_to_utc

/*
	local 5hours = 1000*60*60*5 // # of milliseconds in 5 hours
	gen double time_utc = time + `5hours'
*/

	local 3hours = 1000*60*60*3 // # of milliseconds in 8 hours
	gen double time_utc = time - `3hours'

	format time_utc %tc

end


program build_num_viewers

	* Merge streamer datasets *
	local satafiles: dir "../temp/num_viewers/" files "*.dta"
	local counter = 1
	foreach file of local satafiles {
		
		use "../temp/num_viewers/`file'", clear
		drop if viewers == 0
		
		if `counter' > 1 append using "../temp/twitch_num_viewers.dta"
		save "../temp/twitch_num_viewers.dta", replace
		local counter = `counter' + 1
		
	}

	* Merge data to streamer names *
	use "../temp/twitch_num_viewers.dta", clear
	define_periods
	lookup_streamer_names
	convert_time_to_utc

	* Save data *
	sort  streamer time_utc
	order streamer time_utc viewers
	keep  streamer time_utc viewers
	duplicates drop streamer time_utc, force
	save "../temp/twitch_num_viewers.dta", replace

end


program build_stream_type

	* Merge streamer datasets *
	local satafiles: dir "../temp/stream_type/" files "*.dta"
	local counter = 1
	foreach file of local satafiles {
		
		use "../temp/stream_type/`file'", clear
		rename viewers live
		drop if live == ""

		if `counter' > 1 append using "../temp/twitch_stream_type.dta"
		save "../temp/twitch_stream_type.dta", replace
		local counter = `counter' + 1
		
	}

	* Merge data to streamer names *
	use "../temp/twitch_stream_type.dta", clear
	define_periods
	lookup_streamer_names
	convert_time_to_utc

	* Save data *
	sort  streamer time_utc
	order streamer time_utc live
	keep  streamer time_utc live
	duplicates drop streamer time_utc, force
	save "../temp/twitch_stream_type.dta", replace

end

program build_game_id

	* Merge streamer datasets *
	local satafiles: dir "../temp/game_id/" files "*.dta"
	local counter = 1
	foreach file of local satafiles {
		
		use "../temp/game_id/`file'", clear
		rename game_id twitch_game_id

		if `counter' > 1 append using "../temp/twitch_game_id.dta"
		save "../temp/twitch_game_id.dta", replace
		local counter = `counter' + 1
		
	}

	* Merge data to streamer names *
	use "../temp/twitch_game_id.dta", clear
	define_periods
	lookup_streamer_names
	convert_time_to_utc

	* Save data *
	sort  streamer time_utc
	order streamer time_utc twitch_game_id
	keep  streamer time_utc twitch_game_id
	duplicates drop streamer time_utc, force
	save "../temp/twitch_game_id.dta", replace

end


program build_stream_language

	* Merge streamer datasets *
	local satafiles: dir "../temp/stream_language/" files "*.dta"
	local counter = 1
	foreach file of local satafiles {
		
		use "../temp/stream_language/`file'", clear
	
		if `counter' > 1 append using "../temp/twitch_stream_language.dta"
		save "../temp/twitch_stream_language.dta", replace
		local counter = `counter' + 1
		
	}

	* Merge data to streamer names *
	use "../temp/twitch_stream_language.dta", clear
	define_periods
	lookup_streamer_names
	convert_time_to_utc
	
	* Save data *
	sort  streamer time_utc
	order streamer time_utc language
	keep  streamer time_utc language
	duplicates drop streamer time_utc, force
	save "../temp/twitch_stream_language.dta", replace

end


program build_stream_title_tags

	* Import titles and tags + keep non-zero observations *
	import delimited "../temp/stream_text.txt", clear

	* Round time to the nearest 10-min interval *
	gen double time = clock(substr(request_time, 1, 6) + "2021" + substr(request_time, 9, 5) + "0:00", "MDY hms") // Round min to 10s and sec to 00s *
	format time %tc
	
	* Merge data to streamer names *
	define_periods
	lookup_streamer_names
	convert_time_to_utc
	
	* Once partner - always partner
	bysort streamer: egen max_is_partner = max(is_partner)
	replace is_partner = max_is_partner
	drop max_is_partner
	
	* Save data *
	duplicates drop streamer time_utc, force // where do these duplicates come from?
	sort  streamer time_utc
	order streamer time_utc
	keep  streamer time_utc is_sponsored-is_tutorial_tag
	save "../temp/twitch_stream_title_tags.dta", replace

end


program merge_twitch_tables

	* Merge viewers and live status *
	use "../temp/twitch_num_viewers.dta", clear
	duplicates drop streamer time_utc, force
	merge 1:1 streamer time_utc using "../temp/twitch_stream_type.dta"
	replace live = "NA" if _merge == 1    // unmatched from master = missing data (only collected "type" after 4/16)
	replace viewers = 0 if _merge == 2    // unmatched from using = zero viewers ("live" but zero viewers)
	drop _merge
	
	* Merge with game IDs *
	merge 1:1 streamer time_utc using "../temp/twitch_game_id.dta"
	drop if _merge == 1                   // no game ID data (empty responses from API)
	drop if _merge == 2                   // unclear where these non-matches come from
	drop _merge
	
	* Merge with stream languages *
	merge 1:1 streamer time_utc using "../temp/twitch_stream_language.dta"
	drop if _merge == 2                   // unclear where these non-matches come from
	drop _merge
	dominant_language_insteadof_na
	
	* Merge with titles and tags *
	merge 1:1 streamer time_utc using "../temp/twitch_stream_title_tags.dta"
	drop if _merge == 2                   // unclear where these non-matches come from
	drop _merge
	foreach var of varlist is_sponsored-is_tutorial_tag {
		replace `var' = 0 if `var' == .
	}
	
	* Merge with steam game IDs *
	destring twitch_game_id, replace
	merge m:1 twitch_game_id using "../temp/games_crosswalk.dta"
	drop if _merge == 2
	drop _merge
	
	* Keep the stable streamer sample (11may2021 onwards) *
	merge m:1 streamer using "../temp/stable_streamer_set.dta", keep(matched) nogenerate
	
	* Save dataset *
	sort streamer time_utc
	save "../output/twitch_streams.dta", replace
	
end


program dominant_language_insteadof_na

	gen count = 1
	bysort streamer language: egen language_freq = sum(count)
	replace language_freq = 0 if language == ""
	gsort streamer -language_freq
	by streamer: gen language_dominant = language if _n == 1
	by streamer: replace language_dominant = language_dominant[_n-1] if language_dominant == ""
	replace language = language_dominant if language == ""
	drop language_dominant language_freq count

end


main





