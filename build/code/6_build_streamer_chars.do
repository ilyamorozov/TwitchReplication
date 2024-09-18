clear
program drop _all


program main

	build_viewers
	build_primary_language
	build_primary_games
	find_core_streamers
	merge_characteristics
	
end


program build_viewers

	use "../output/twitch_streams.dta", clear
	generate date = dofc( time_utc )
	format date %td
	collapse (mean) daily_viewers_avg=viewers (sum) daily_viewers_total=viewers,        by(streamer date)
	collapse (mean) daily_viewers_avg         (sum) total_viewers=daily_viewers_total,  by(streamer)
	egen cutoff_p95           = pctile(total_viewers), p(95)
	egen cutoff_p99           = pctile(total_viewers), p(99)
	egen cutoff_p9975         = pctile(total_viewers), p(99.75)
	gen is_big_streamer_p95   = (total_viewers >= cutoff_p95)
	gen is_big_streamer_p99   = (total_viewers >= cutoff_p99)
	gen is_big_streamer_p9975 = (total_viewers >= cutoff_p9975)
	drop cutoff*
	save "../temp/streamer_chars1.dta", replace

end


program build_primary_language

	use "../output/twitch_streams.dta", clear
	gen language_freq = 1
	collapse (sum) language_freq, by(streamer language)
	bysort streamer (language): keep if _n == _N
	drop language_freq
	save "../temp/streamer_chars2.dta", replace

end


program build_primary_games

	* first build primary game
	use "../output/twitch_streams.dta", clear
	keep if appid ~= .   // keep only Steam games
	collapse (sum) viewers (first) game_title, by(streamer appid)
	bysort streamer: egen total_viewers = sum(viewers)
	gen viewer_share = viewers / total_viewers
	gsort streamer -viewer_share
	by streamer: gen game_rank = _n
	keep if game_rank == 1 & viewer_share >= 0.25
	rename game_title primary_steam_game
	rename appid primary_steam_appid
	keep streamer primary_steam_game primary_steam_appid
	save "../temp/streamer_chars_primary.dta", replace
	
	* other games (including non-Steam games)
	use "../output/twitch_streams.dta", clear
	merge n:1 streamer using "../temp/streamer_chars_primary.dta"
	drop if appid == primary_steam_appid
	collapse (sum) viewers (first) appid, by(streamer game_title)
	bysort streamer: egen total_viewers = sum(viewers)
	gen viewer_share = viewers / total_viewers
	gsort streamer -viewer_share
	by streamer: gen game_rank = _n
	keep if game_rank <= 3
	drop viewer_share total_viewers viewers
	reshape wide game_title appid, i(streamer) j(game_rank)
	rename game_title1 secondary_game
	rename appid1 secondary_appid
	rename game_title2 third_game
	rename appid2 third_appid
	rename game_title3 fourth_game
	rename appid3 fourth_appid
	keep streamer secondary_game secondary_appid third_game third_appid fourth_game fourth_appid 
	merge n:1 streamer using "../temp/streamer_chars_primary.dta"
	save "../temp/streamer_chars3.dta", replace

end


program find_core_streamers

	* Get list of 60K selected streamers *
	import delimited "../../build/output/sampling_weight_main_n.csv", varnames(1) clear
	rename nviewers viewers_pre_sample
	rename pred_sampling_weight scaling_factor
	gen is_core_streamer = 1
	drop viewers_pre_sample
	save "../temp/core_streamer.dta", replace
	
end


program merge_characteristics

	use "../temp/streamer_chars1.dta", clear
	merge 1:1 streamer using "../temp/streamer_chars2.dta", nogenerate
	merge 1:1 streamer using "../temp/streamer_chars3.dta", nogenerate
	merge 1:1 streamer using "../temp/core_streamer.dta", nogenerate keep(1 3)
	replace is_core_streamer = 0 if is_core_streamer == .
	replace primary_steam_game = "N/A" if primary_steam_game == ""
	save "../output/streamer_chars.dta", replace

end


main

