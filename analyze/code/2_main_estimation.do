clear all
timer on 1
set maxvar 100000
set scheme s2color
set seed 12313554


program main

	* Estimate first stage regression (viewers on streamer counts) *
	regress_viewers_on_streamers

	* Main table (streaming effect estimates) *
	main_estimates                 // replicates table 3 with the main estimates
	main_estimates_bootstrap       // replicates bootstrap standard errors in table 3
		
	* Robustness analyses *
	robustness_checks              // replicates table c1 in the appendix (robustness)
	robustness_distributed_lags    // replicates distributed lag figure in the appendix
	
	* Interpret magnitudes *
	interpretation

end


program regress_viewers_on_streamers

	* Load data *
	use "../temp/viewer_player_final.dta", clear
	bysort appid: egen ever_sponsored = max(num_big_streamer_sponsored) // limit sample to games that are sponsored at least once

	* Regression main *
	xtset appid time_id
	reghdfe viewers num_big_streamer_nonsponsored num_big_streamer_sponsored if ever_sponsored > 0, absorb(game_date game_hour time_id) cluster(game_date)
	scalar beta_3o = _b[num_big_streamer_nonsponsored]
	scalar se_3o = _se[num_big_streamer_nonsponsored]	
	scalar beta_3s = _b[num_big_streamer_sponsored]
	scalar se_3s = _se[num_big_streamer_sponsored]
	scalar n_3s = e(N)

	* Regressions robust *
	reghdfe viewers num_big_streamer_95, absorb(game_date game_hour time_id) cluster(game_date)
	scalar beta_1s = _b[num_big_streamer_95]
	scalar se_1s = _se[num_big_streamer_95]
	scalar n_1s = e(N)
	reghdfe viewers num_big_streamer_95 if ever_sponsored > 0, absorb(game_date game_hour time_id) cluster(game_date)
	scalar beta_2s = _b[num_big_streamer_95]
	scalar se_2s = _se[num_big_streamer_95]
	scalar n_2s = e(N)

	* Save results in a table *
	matrix TABLE1 = J(7,2,.)
	matrix TABLE1[1,1] = round(beta_3s, 0.1)
	matrix TABLE1[2,1] = round(se_3s, 0.1)
	matrix TABLE1[3,1] = round(beta_3o, 0.1)
	matrix TABLE1[4,1] = round(se_3o, 0.1)
	matrix TABLE1[7,1] = n_3s
	matrix TABLE1[5,2] = round(beta_1s, 0.1)
	matrix TABLE1[6,2] = round(se_1s, 0.1)
	matrix TABLE1[7,2] = n_1s
	matrix list TABLE1
	matrix rownames TABLE1 = top_sponsored se top_organic se top_streamers se num_obs
	putexcel set "../output/tables/appendix/table_viewer_lift.xlsx", sheet("results") replace
	putexcel A1 = matrix(TABLE1), rownames
	
end


program main_estimates

	* Main *
	use "../temp/viewer_player_final.dta", clear
	estimate_and_store
	putexcel set "../output/tables/section3/table_main_estimates.xlsx", sheet("results") replace
	putexcel A1 = matrix(TABLE), rownames
	
end


program main_estimates_bootstrap

	* Bootstrap *
	local num_samples = 50 // paper: 50
	matrix BOOT_EST = J(`num_samples',3,.)
	forvalues i = 1/`num_samples' {
		display "Bootstrap sample: `i' out of `num_samples'"
		use "../temp/viewer_player_final.dta", clear
		set seed `i'
		rename game_date game_date_old
		bsample, cluster(game_date_old) idcluster(game_date)
		compute_lags_bootstrap
		golden_search
		matrix BOOT_EST[`i',1] = `i'
		matrix BOOT_EST[`i',2] = r(delta_estimate)
		matrix BOOT_EST[`i',3] = r(beta_estimate)
	}
	matrix list BOOT_EST
	
	* Compute bootstrap S.E. *
	svmat BOOT_EST
	summarize BOOT_EST3
	scalar beta_std = r(sd)
	summarize BOOT_EST2
	scalar delta_std = r(sd)
	keep BOOT_*
	save "../output/tables/section3/bootstrap_samples/table_bootstrap_draws.dta", replace // save bootstrap draws
	
	* Add estimates to the main table *
	matrix TABLE[2,3] = round(beta_std,0.001)
	matrix TABLE[4,3] = round(delta_std,0.001)
	matrix colnames TABLE = OLS IV1 IV2
	matrix rownames TABLE = beta beta_std delta delta_std fstat
	putexcel set "../output/tables/section3/table_main_estimates.xlsx", sheet("results") replace
	putexcel A1 = matrix(TABLE), rownames

end


program robustness_checks
	
	* Main + game-week FEs *
	use "../temp/viewer_player_final.dta", clear
	drop game_date
	rename game_week game_date
	estimate_and_store
	putexcel set "../output/tables/appendix/main_results_robust/main_gameweek_fe.xlsx", sheet("results") replace
	putexcel A1 = matrix(TABLE), rownames
	
	* Main + 6 lags*
	use "../temp/viewer_player_final.dta", clear
	replace num_lags_iv = 6
	estimate_and_store
	putexcel set "../output/tables/appendix/main_results_robust/main_6lags.xlsx", sheet("results") replace
	putexcel A1 = matrix(TABLE), rownames
	
	* Main + 18 lags*
	use "../temp/viewer_player_final.dta", clear
	replace num_lags_iv = 18
	estimate_and_store
	putexcel set "../output/tables/appendix/main_results_robust/main_18lags.xlsx", sheet("results") replace
	putexcel A1 = matrix(TABLE), rownames
	
	* Main + 10-min intervals *
	use "../temp/viewer_player_10min.dta", clear
	gen num_lags_iv = 6
	compute_lags
	keep if iv_lag6 != .
	drop iv_lag2-iv_lag6 iv_lag8-iv_lag12 iv_lag14-iv_lag18 iv_lag20-iv_lag24 iv_lag26-iv_lag30 // take lags with 6-time-interval gap (hourly)
	rename iv_lag7  iv_lag2
	rename iv_lag13 iv_lag3
	rename iv_lag19 iv_lag4
	rename iv_lag25 iv_lag5
	rename iv_lag31 iv_lag6
	gen time_id = time_utc
	estimate_and_store
	putexcel set "../output/tables/appendix/main_results_robust/main_10min.xlsx", sheet("results") replace
	putexcel A1 = matrix(TABLE), rownames
	
	* Main + positive IV variation *
	use "../temp/viewer_player_final.dta", clear
	keep if no_instruments==0
	estimate_and_store
	putexcel set "../output/tables/appendix/main_results_robust/main_noiv.xlsx", sheet("results") replace
	putexcel A1 = matrix(TABLE), rownames
	
	* Main + drop zero player/viewer periods *
	use "../temp/viewer_player_final.dta", clear
	keep if no_players==0 & no_viewers==0
	estimate_and_store
	putexcel set "../output/tables/appendix/main_results_robust/main_noiv_nozeros.xlsx", sheet("results") replace
	putexcel A1 = matrix(TABLE), rownames

	* Main + only irregular schedules *
	use "../temp/viewer_player_final.dta", clear
	rename iv_lag_irreg* iv_temp*
	drop iv_lag*
	rename iv_temp* iv_lag*
	drop num_big_streamer_95
	rename num_big_streamer_95_irreg num_big_streamer_95
	estimate_and_store
	putexcel set "../output/tables/appendix/main_results_robust/only_irregular_hours.xlsx", sheet("results") replace
	putexcel A1 = matrix(TABLE), rownames
	
end


program estimate_and_store

	* Regression estimates *
	reg logplayers logviewers, cluster(game_date)
	scalar beta1 =  _b[logviewers]
	scalar std1  = _se[logviewers]
	ivreghdfe logplayers (logviewers = num_big_streamer_95), absorb(game_date game_hour time_id) cluster(game_date)
	scalar beta2 =  _b[logviewers]
	scalar std2  = _se[logviewers]
	golden_search
	scalar delta3 = r(delta_estimate)
	scalar beta3  = r(beta_estimate)
	scalar list
	
	* First-stage F-statistics (no delta) *
	reghdfe logviewers num_big_streamer_95, absorb(game_date game_hour time_id) cluster(game_date)
	scalar FSTAT2 = e(F)
	
	* First-stage F-statistics (with delta) *
	local delta = delta3
	gen viewers_cumul = viewers
	local num_lags = 3*24
	forvalues j = 1/`num_lags' {
		scalar multiplier = (`delta'^`j')
		quietly: replace viewers_cumul = viewers_cumul + multiplier * viewers_lag`j' if viewers_lag`j' != .
	}
	gen logviewers_cumul = log(viewers_cumul + 1)
	
	local num_lags_iv = num_lags_iv[1]
	reghdfe logviewers_cumul num_big_streamer_95 iv_lag1-iv_lag`num_lags_iv', absorb(game_date game_hour time_id) cluster(game_date)
	scalar FSTAT3 = e(F)
	scalar b_current = _b[num_big_streamer_95]

	* Save results in a matrix *
	matrix TABLE = J(5,3,.)
	matrix TABLE[1,1] = round(beta1,0.001)
	matrix TABLE[2,1] = round(std1,0.001)
	matrix TABLE[1,2] = round(beta2,0.001)
	matrix TABLE[2,2] = round(std2,0.001)
	matrix TABLE[1,3] = round(beta3,0.001)
	matrix TABLE[3,3] = round(delta3,0.001)
	matrix TABLE[5,2] = round(FSTAT2,0.1)
	matrix TABLE[5,3] = round(FSTAT3,0.1)
	matrix colnames TABLE = OLS IV1 IV2
	matrix rownames TABLE = beta beta_std delta delta_std fstat

end


program robustness_distributed_lags

	use "../temp/viewer_player_final.dta", replace
	
	* Create lagged variables * Note: three loops below generate the "right" ordering of variables
	drop viewers_lag* iv_lag*
	local num_lags = 30
	forvalues j = 1/`num_lags' {
		bysort appid (time_utc): gen viewers_lag`j' = viewers[_n-`j']
	}
	forvalues j = 1/`num_lags' {
		bysort appid (time_utc): gen iv_lag`j' = num_big_streamer_95[_n-`j']
	}
	forvalues j = 1/`num_lags' {
		gen logviewers`j' = log(viewers_lag`j' + 1)
	}

	* Estimate the advertising stock regression *
	ivreghdfe logplayers (logviewers logviewers1-logviewers`num_lags' = num_big_streamer_95 iv_lag1-iv_lag`num_lags'), absorb(game_date game_hour time_id) cluster(game_date)
	coefplot, vertical xlabel(1 "current" 4 "3" 7 "6" 10 "9" 13 "12" 16 "15" 19 "18" 22 "21" 25 "24" 28 "27" 31 "30") ytitle(Log Viewers) xtitle(hour) graphregion(fcolor(white) lcolor(white)) plotregion(fcolor(white))
	graph export "../output/graphs/appendix/figure_distributed_lags.png", as(png) replace
	graph export "../output/graphs/appendix/figure_distributed_lags.eps", replace
	
end


program gmm_objective, rclass

    args delta
	gen viewers_cumul = viewers
	local num_lags = 3*24
	forvalues j = 1/`num_lags' {
		scalar multiplier = (`delta'^`j')
		quietly: replace viewers_cumul = viewers_cumul + multiplier * viewers_lag`j' if viewers_lag`j' != .
	}
	gen logviewers_cumul = log(viewers_cumul + 1)
	
	local num_lags_iv = num_lags_iv[1]
	ivreghdfe logplayers (logviewers_cumul = num_big_streamer_95 iv_lag1-iv_lag`num_lags_iv'), absorb(game_date game_hour time_id) cluster(game_date) resid(resid)
	matrix COEF = e(b)
	
	* Compute GMM objective function
	scalar gmm_obj = 0
	gen nobs = _N
	
    egen avg_resid = mean(resid)
	scalar gmm_obj = gmm_obj + avg_resid[1] * avg_resid[1]
	drop avg_resid
	
	gen iv_lag0 = num_big_streamer_95
	forvalues j = 0/`num_lags_iv' {
		gen moment = iv_lag`j' * resid
		egen avg_moment = mean(moment)
		scalar gmm_obj = gmm_obj + avg_moment[1] * avg_moment[1]
		drop moment avg_moment
	}
	
	preserve
		collapse (sum) sum_resid = resid (firstnm) nobs, by(game_date)
		gen avg_moments = sum_resid / nobs
		gen sq_moments = avg_moments * avg_moments
		egen sum_sq_moments = total(sq_moments)
		scalar gmm_obj = gmm_obj + sum_sq_moments[1]
	restore

	preserve
		collapse (sum) sum_resid = resid (firstnm) nobs, by(game_hour)
		gen avg_moments = sum_resid / nobs
		gen sq_moments = avg_moments * avg_moments
		egen sum_sq_moments = total(sq_moments)
		scalar gmm_obj = gmm_obj + sum_sq_moments[1]
	restore
	
	preserve
		collapse (sum) sum_resid = resid (firstnm) nobs, by(time_id)
		gen avg_moments = sum_resid / nobs
		gen sq_moments = avg_moments * avg_moments
		egen sum_sq_moments = total(sq_moments)
		scalar gmm_obj = gmm_obj + sum_sq_moments[1]
	restore

	drop viewers_cumul logviewers_cumul resid iv_lag0 nobs
	
	return scalar gmm_obj_value = gmm_obj
	return scalar beta = COEF[1,1]
	
end 


program interpretation

	* Load estimates *
	import excel "../output/tables/section3/table_main_estimates.xlsx", sheet("results") clear
	scalar beta  = D[1]
	scalar delta = D[3]
	scalar list beta delta
	
	* Lift in viewers from one top streamer *
	use "../temp/viewer_player_final.dta", clear
	reghdfe viewers num_big_streamer_95, absorb(game_date game_hour time_id) cluster(game_date)
	gen lift_viewers = _b[num_big_streamer_95]
	
	* Lift in players from one top streamer *
	sum viewers, detail
	scalar viewers0 = r(mean) // use mean 
	sum players, detail
	scalar players0 = r(mean) // use mean
	scalar viewers1 = viewers0 + lift_viewers
	scalar viewer_stock0 = viewers0 / (1 - delta)
	scalar viewer_stock1 = viewers1 / (1 - delta)
	scalar lift_players = (1 + players0) * (((1 + viewer_stock1) / (1 + viewer_stock0))^beta - 1)
	scalar list lift_players viewer_stock0 viewer_stock1
	
	* Gauge ROI of the median game *
	scalar conversion_rate = 0.28
	scalar median_price    = 20
	scalar sponsor_fee     = 144
	scalar profit_margin   = 0.7
	scalar median_revenue  = lift_players * median_price * conversion_rate * profit_margin
	scalar median_ROI_perc = 100 * (median_revenue - sponsor_fee) / sponsor_fee
	scalar list median_revenue median_ROI_perc

end


program golden_search, rclass

	scalar gold_ratio = 1.618033
	scalar a_val = 0.000
	scalar b_val = 0.999 
	scalar c_val = b_val - (b_val - a_val) / gold_ratio
	scalar d_val = a_val + (b_val - a_val) / gold_ratio
	scalar tol   = 0.00001
	scalar diff  = 10000
	while diff > tol {
		quietly gmm_objective c_val
		scalar fval_c = r(gmm_obj_value)
		quietly gmm_objective d_val
		scalar fval_d = r(gmm_obj_value)
		if (fval_c < fval_d) { 
			scalar b_val = d_val
		}
		if (fval_c >= fval_d) { 
			scalar a_val = c_val
		}
		scalar diff  = abs(b_val - a_val)
		scalar c_val = b_val - (b_val - a_val) / gold_ratio
		scalar d_val = a_val + (b_val - a_val) / gold_ratio
		local a_val  = round(a_val,0.001)
		local b_val  = round(b_val,0.001)
		local diff   = round(diff,0.001)
		local tol    = round(tol,0.001)
		display "Lower bound: `a_val'   Upper bound: `b_val',   Difference: `diff',   Tolerance: `tol'" 
	}
	scalar delta_est = (a_val + b_val) / 2
	gmm_objective delta_est
	scalar beta_est = r(beta)
	return scalar delta_estimate = delta_est
	return scalar beta_estimate  = beta_est

end


program compute_lags

	local num_lags = 3*24
	forvalues j = 1/`num_lags' {
		quietly: bysort appid (time_utc): gen viewers_lag`j' = viewers[_n-`j']
	}
	forvalues j = 1/`num_lags' {
		quietly: bysort appid (time_utc): gen iv_lag`j' = num_big_streamer_95[_n-`j']
	}

end


program compute_lags_bootstrap

	capture drop viewers_lag*
	capture drop iv_lag*

	local num_lags = 3*24
	forvalues j = 1/`num_lags' {
		quietly: bysort appid game_date (time_utc): gen viewers_lag`j' = viewers[_n-`j']
	}
	forvalues j = 1/`num_lags' {
		quietly: bysort appid game_date (time_utc): gen iv_lag`j' = num_big_streamer_95[_n-`j']
	}

end


program time_elapsed

	timer off 1
	timer list 1
	local time_elapsed = r(t1)/60
	display r(t1)/60
	
end


main

