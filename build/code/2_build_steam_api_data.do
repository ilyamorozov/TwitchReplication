clear
program drop _all


program main

	build_player_counts
	clean_player_counts
	
end


program build_player_counts

	*** Merge all game usage data files ***
	local satafiles: dir "../input/api_data/player_counts/" files "*.csv"
	local counter = 1
	foreach file of local satafiles {
		
		display "Counter value: `counter'"
		
		* Variable names *
		import delimited "../input/api_data/player_counts/`file'", varnames(nonames) rowrange(1:1) clear 
		drop v1
		gen obs = 1
		reshape long v, i(obs) j(num)
		drop obs
		rename v appid
		save "../temp/varnames.dta", replace

		* Game usage data *
		import delimited "../input/api_data/player_counts/`file'", varnames(1) clear
		duplicates drop request_time, force
		reshape long v, i(request_time) j(num)
		rename v players
		merge m:1 num using "../temp/varnames.dta", keep(match) nogenerate
		drop num
		gen double time = clock(substr(request_time, 1, 6) + "2021" + substr(request_time, 9, 5) + "0:00", "MDY hms") // Round min to 10s and sec to 00s *
		format time %tc
		drop request_time
		order appid time players
		sort appid time
		
		if `counter'>1 append using "../temp/steam_players.dta"
		save "../temp/steam_players.dta", replace
		local counter = `counter' + 1
		
	}
	erase "../temp/varnames.dta"

end

	
program clean_player_counts

	*** Clean game usage data ***
	* Convert time CST -> UTC *
	use "../temp/steam_players.dta", clear
	/*
	local 5hours = 1000*60*60*5 // # of milliseconds in 5 hours
	gen double time_utc = time + `5hours'
	format time_utc %tc
	*/
	local 3hours = 1000*60*60*3 // # of milliseconds in 8 hours
	gen double time_utc = time - `3hours'
	format time_utc %tc
	drop time
	order appid time_utc players
	sort appid time_utc

	* Drop duplicates *
	duplicates drop appid time_utc players, force
	duplicates drop appid time_utc, force
	sort appid time_utc

	* Replace missings and blackouts (API not responding) with averages *
	bysort time_utc: egen max_players = max(players)
	bysort appid (time_utc): replace players = 0.5*players[_n-1] + 0.5*players[_n+1] if players == . | max_players == 0
	drop max_players
	keep if time_utc >  tc("11may2021 01:00:00") 
	save "../output/players.dta", replace

end


main

