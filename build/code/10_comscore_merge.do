clear
program drop _all


program main

	build_nonsteam_purchases
	build_twitch_views_daily
	make_balanced_panel
	merge_tables

end

program build_nonsteam_purchases

	// how much purchases on Steam?
	use "../output/ecommerce_video_game.dta", clear
	rename raw_itemTotal price
	gen name = lower(itemName)
	clean_game_names
	merge n:1 name using "../temp/steam_game_names.dta", keep(3) nogenerate	
	merge n:1 machine_id using "../temp/ecommerce_all_purchasers.dta", keep(3) nogenerate
	gen ones = 1
	collapse (sum) freq = ones, by(domain_name)
	gsort -freq
	egen sum_freq = sum(freq)
	gen share = freq/sum_freq
	drop sum_freq
	export delimited "../output/domain_frequency_purchases.csv", replace

	use "../output/ecommerce_video_game.dta", clear
	keep if domain_name != "steampowered.com"
	rename raw_itemTotal price
	gen name = lower(itemName)
	clean_game_names
	merge n:1 name using "../temp/steam_game_names.dta", keep(3) nogenerate	
	collapse (mean) price_rtl = price (firstnm) hour, by(machine_id steam_id date)
	gen purchase_game_rtl = 1
	save "../temp/comscore_purchases_others.dta", replace	

end

program build_twitch_views_daily 

	// Which steam games did you watch on Twitch today? 

	* Load comscore viewership and merge with twitchtracker (lookup what game was streamed) *
	use "../output/comscore_twitch.dta", clear 
	gen date = mdy(month, day, year)
	format date %d
	clean_streamer_names
	keep machine_id date streamer
	duplicates drop                                                                                // unique streamers this person watched on any date
	
	* Save name of favorite streamer *
	bysort machine_id streamer: gen num_days = _N
	bysort machine_id (streamer): egen max_days = max(num_days)
	gen fav_streamer_aux = streamer if num_days == max_days
	bysort machine_id (date): egen fav_streamer = first(fav_streamer_aux)                          // save name of favorite streamer (take earliest in case of a tie)
	drop fav_streamer_aux num_days max_days
	gsort machine_id -date
	by machine_id: replace fav_streamer = fav_streamer[_n-1] if fav_streamer == "" & fav_streamer[_n-1] ~= "" // extrapolate favorite streamer names to all observations
	gsort machine_id date
	by machine_id: replace fav_streamer = fav_streamer[_n-1] if fav_streamer == "" & fav_streamer[_n-1] ~= ""

	* duplicate to allow for five streams a day *
	expand 5
	bysort machine_id streamer date: gen stream_id = _n

	* Merge with twitchtracker (lookup what game was streamed) *
	merge n:1 streamer date stream_id using "../temp/twitch_tracker_historical.dta", keep(3) nogenerate      // lookup which game was streamed back then
	merge n:1 game_title using "../temp/steam_twitch_crosswalk.dta", keep(3) nogenerate	           // for games watched on Twitch lookup Steam ID (most are merged)
	keep if machine_id != . & (twitch_id != . | steam_id != .)                                     // eliminate match mistakes and missing data
	collapse (firstnm) streamer fav_streamer, by(machine_id date steam_id)                         // list all games (with steam_ids) this person watched on Twitch
	keep if steam_id ~= .
	gen watch_twitch = 1
	save "../temp/comscore_twitch_daily.dta", replace
	
end


program make_balanced_panel

	// This program creates all machine_id x date x steam_id (game id) combinations
	* Start with the set of machines that ever had some Twitch activities *
	use "../output/comscore_twitch.dta", clear
	gen date = mdy(month, day, year)
	gen flag_twitch = 1

	* append other tables *
	append using "../temp/comscore_purchases.dta"
	append using "../temp/comscore_purchases_others.dta"
	append using "../temp/comscore_steam_daily.dta"
	
	* Keep users who visited Twitch at least once *
	bysort machine_id: egen any_twitch = max(flag_twitch)
	keep if any_twitch == 1																			// 179,547 machines after this step		
	
	* Keep users who purchased any games online (not only from the list of games we selected) *
	collapse (max) max_date = date (min) min_date = date, by(machine_id)
	merge 1:1 machine_id using "../temp/ecommerce_all_purchasers.dta", keep(match) nogenerate		// 8,611 machines after this step

	* Balance the panel (use first and last activity date for each user) *
	keep machine_id min_date max_date
	gen date_diff = max_date - min_date + 1
	expand date_diff
	bysort machine_id: gen date = min_date + _n - 1
	format date %d
	drop max_date min_date date_diff
	save "../temp/comscore_individual_panel.dta", replace // lookup list of dates for each user ("dates user was active in the panel")
	
	* Add a dimension to balanced panel: game *
	use "../temp/comscore_individual_panel.dta", clear
	expand 203
	bysort machine_id date: gen new_game_id = _n
	merge n:1 new_game_id using "../temp/steam_game_names.dta", keepusing(steam_id) nogenerate
	drop new_game_id
	save "../temp/comscore_balanced_panel.dta", replace  // creates all machine_id x date x steam_id (game id) combinations
	
end


program merge_tables

	* Merge Twitch views + Steam browse + purchases *
	use "../temp/comscore_balanced_panel.dta", clear
	merge 1:1 machine_id date steam_id using "../temp/comscore_twitch_daily.dta",     keep(1 3) keepusing(watch_twitch fav_streamer)  nogenerate
	merge 1:1 machine_id date steam_id using "../temp/comscore_steam_daily.dta",      keep(1 3) keepusing(browse_steam)               nogenerate
	merge 1:1 machine_id date steam_id using "../temp/comscore_purchases.dta",        keep(1 3) keepusing(purchase_game price)        nogenerate
	merge 1:1 machine_id date steam_id using "../temp/comscore_purchases_others.dta", keep(1 3) keepusing(purchase_game_rtl price_rt) nogenerate
	
	* Extrapolate favorite streamer names to all observations *
	gsort machine_id -date
	by machine_id: replace fav_streamer = fav_streamer[_n-1] if fav_streamer == "" & fav_streamer[_n-1] ~= "" 
	gsort machine_id date
	by machine_id: replace fav_streamer = fav_streamer[_n-1] if fav_streamer == "" & fav_streamer[_n-1] ~= ""

	* Add IV variable = my favorite streamer played game j on twitch today *
	rename fav_streamer streamer
	merge n:1 streamer date steam_id using "../temp/twitch_tracker_historical_steam_id.dta", keep(1 3)   // look up which game was streamed by favorite streamer on that date
	gen fav_streamer_broadcast = _merge == 3
	drop duration streamer price price_rtl _merge
	
	* fill zeros *
	foreach var in watch_twitch browse_steam purchase_game purchase_game_rtl {
		replace `var' = 0 if `var' == .
	}
	
	* Construct fixed effects for regressions *
	gen any_purchase  = (purchase_game == 1 | purchase_game_rtl == 1)
	gen week          = week(date)
	gen dow           = dow(date)
	gen year          = year(date)
	egen machine_game = group(machine_id steam_id)	
	egen game_week    = group(steam_id year week)
	egen game_dow     = group(steam_id dow)
	save "../output/comscore_balanced_panel.dta", replace
	
end


program clean_game_names

	replace name = "grand theft auto v" if regexm(name, "grand theft auto v")
	replace name = "terraria" if regexm(name, "terraria")
	replace name = "the elder scrolls v: skyrim" if regexm(name, "the elder scrolls v: skyrim")
	replace name = "tom clancy's rainbow six: seige" if regexm(name, "tom clancy's rainbow six: seige")
	replace name = "tom clancy's rainbow six: seige" if regexm(name, "tom clancy's rainbow six seige")
	replace name = "stardew valley" if regexm(name, "stardew valley")
	replace name = "rocket league" if regexm(name, "rocket league")
	replace name = "undertale" if regexm(name, "undertale")
	replace name = "left 4 dead 2" if regexm(name, "left 4 dead 2")
	replace name = "cyberpunk 2077" if regexm(name, "cyberpunk 2077")
	replace name = "dead by daylight" if regexm(name, "dead by daylight")
	replace name = "slime rancher" if regexm(name, "slime rancher")
	replace name = "planet coaster" if regexm(name, "planet coaster")
	replace name = "subnautica" if regexm(name, "subnautica")
	replace name = "farming simulator 19" if regexm(name, "farming simulator 19")
	replace name = "portal 2" if regexm(name, "portal 2")
	replace name = "hollow knight" if regexm(name, "hollow knight")
	replace name = "red dead redemption 2" if regexm(name, "red dead redemption 2")
	replace name = "risk of rain 2" if regexm(name, "risk of rain 2")
	replace name = "cuphead" if regexm(name, "cuphead")
	replace name = "call of duty: world at war" if regexm(name, "call of duty world at war")
	replace name = "call of duty: world at war" if regexm(name, "call of duty: world at war")
	replace name = "fallout 4" if regexm(name, "fallout 4")
	replace name = "payday 2" if regexm(name, "payday 2")
	replace name = "doom eternal" if regexm(name, "doom eternal")
	replace name = "nba 2k20" if regexm(name, "nba 2k20")
	replace name = "persona 4 golden" if regexm(name, "persona 4 golden")
	replace name = "a hat in time" if regexm(name, "a hat in time")
	replace name = "age of empires ii" if regexm(name, "age of empires ii")
	replace name = "sea of thieves" if regexm(name, "sea of thieves")
	replace name = "resident evil 3" if regexm(name, "resident evil 3")
	replace name = "call of duty: black ops ii" if regexm(name, "black ops ii ")
	replace name = "assetto corsa" if regexm(name, "assetto corsa")
	replace name = "borderlands 2" if regexm(name, "borderlands 2")
	replace name = "dayz" if regexm(name, "dayz")
	replace name = "celeste" if regexm(name, "celeste")
	replace name = "final fantasy vii" if regexm(name, "final fantasy vii")
	replace name = "dragon ball fighterz" if regexm(name, "dragon ball fighterz")
	replace name = "dragon ball fighterz" if regexm(name, "dragon ball fighter z")
	replace name = "ori and the will of the wisps" if regexm(name, "ori and the will of the wisps")
	replace name = "kenshi" if regexm(name, "kenshi")
	replace name = "europa universalis iv" if regexm(name, "europa universalis iv")
	replace name = "microsoft flight simulator" if regexm(name, "microsoft flight simulator")
	replace name = "little nightmares" if regexm(name, "little nightmares")
	replace name = "borderlands 3" if regexm(name, "borderlands 3")
	replace name = "nba 2k21" if regexm(name, "nba 2k21")
	replace name = "enter the gungeon" if regexm(name, "enter the gungeon")
	replace name = "tekken 7" if regexm(name, "tekken 7")
	replace name = "descenders" if regexm(name, "descenders")
	
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
