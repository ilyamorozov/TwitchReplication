clear all
timer on 1


program main

	forvalues i = 1/2 {
		global specification = `i' // 1=sponsored, 2=partnered
		regressions_sponsored    // estimates parameters
		bootstrap_sponsored      // computes standard errors
	}
	
end


program regressions_sponsored

	* Load data *
	use "../temp/viewer_player_final.dta", clear
	select_frequently_sponsored
	
	* Build lagged variables *
	compute_lags

	* Estimate parameters *
	golden_search
	scalar delta_final = r(delta_estimate)
	scalar beta_final  = r(beta_estimate)
	scalar omega_final = r(omega_estimate)
	matrix TABLE = J(5,2,.)
	matrix TABLE[1,1] = round(delta_final,0.001)
	matrix TABLE[2,1] = round(beta_final,0.001)
	matrix TABLE[3,1] = round(omega_final,0.001)
	
	* First-stage F-statistics (no delta) *
	if $specification == 2 {	// if we do partnered regressions
		drop viewers_sponsored
		rename viewers_partner viewers_sponsored
	}
	gen logviewers_sponsored = log(viewers_sponsored + 1)
	gen logviewers_nonsponsored = log(viewers - viewers_sponsored + 1)
	local num_lags_iv = 12
	reghdfe logviewers_sponsored num_big_streamer_nonsponsored iv_lag1_nonsponsored-iv_lag`num_lags_iv'_nonsponsored num_big_streamer_sponsored iv_lag1_sponsored-iv_lag`num_lags_iv'_sponsored, absorb(game_date game_hour time_id) cluster(game_date)
	scalar fstat_1 = e(F)
	matrix TABLE[4,1] = round(fstat_1,0.1)
	reghdfe logviewers_nonsponsored num_big_streamer_nonsponsored iv_lag1_nonsponsored-iv_lag`num_lags_iv'_nonsponsored num_big_streamer_sponsored iv_lag1_sponsored-iv_lag`num_lags_iv'_sponsored, absorb(game_date game_hour time_id) cluster(game_date)
	scalar fstat_2 = e(F)
	matrix TABLE[5,1] = round(fstat_2,0.1)

	* Save table *
	svmat TABLE
	keep TABLE*
	local spec = $specification
	if $specification == 1 {
	    local fname = "sponsor"
	}
	if $specification == 2 {
	    local fname = "partner"
	}
	matrix colnames TABLE = EST SE
	matrix rownames TABLE = delta beta omega F_sponsored F_nonsponsored
	putexcel set "../output/tables/appendix/table_`fname'.xlsx", sheet("results") replace
	putexcel A1 = matrix(TABLE), rownames

end


program bootstrap_sponsored

	* Prepare subsample *
	use "../temp/viewer_player_final.dta", clear
	select_frequently_sponsored
	save "../temp/viewer_player_subsample.dta", replace

	* Bootstrap *
	local num_samples = 50 // paper: 50
	matrix BOOT_EST = J(`num_samples',4,.)
	forvalues i = 1/`num_samples' {
		display "Bootstrap sample: `i' out of `num_samples'"
		use "../temp/viewer_player_subsample.dta", replace
		set seed `i'
		rename game_date game_date_old
		bsample, cluster(game_date_old) idcluster(game_date)
		compute_lags_bootstrap
		golden_search
		matrix BOOT_EST[`i',1] = `i'
		matrix BOOT_EST[`i',2] = r(delta_estimate)
		matrix BOOT_EST[`i',3] = r(beta_estimate)
		matrix BOOT_EST[`i',4] = r(omega_estimate)
	}
	matrix list BOOT_EST
	
	* Save results *
	svmat BOOT_EST
	summarize BOOT_EST4
	scalar omega_std = r(sd)
	summarize BOOT_EST3
	scalar beta_std = r(sd)
	summarize BOOT_EST2
	scalar delta_std = r(sd)
	scalar list beta_std delta_std omega_std
	time_elapsed
	
	* Add estimates to the main table *
	matrix TABLE[1,2] = round(delta_std,0.001)
	matrix TABLE[2,2] = round(beta_std,0.001)
	matrix TABLE[3,2] = round(omega_std,0.001)
	local spec = $specification
	if $specification == 1 {
	    local fname = "sponsor"
	}
	if $specification == 2 {
	    local fname = "partner"
	}
	putexcel set "../output/tables/appendix/table_`fname'.xlsx", sheet("results") replace
	putexcel A1 = matrix(TABLE), rownames

end


program estimate_and_store

	golden_search
	scalar delta3 = r(delta_estimate)
	scalar beta3  = r(beta_estimate)
	scalar list
	
	matrix TABLE = J(4,3,.)
	matrix TABLE[1,1] = round(beta1,0.001)
	matrix TABLE[2,1] = round(std1,0.001)
	matrix TABLE[1,2] = round(beta2,0.001)
	matrix TABLE[2,2] = round(std2,0.001)
	matrix TABLE[1,3] = round(beta3,0.001)
	matrix TABLE[3,3] = round(delta3,0.001)
	matrix colnames TABLE = OLS IV1 IV2
	matrix rownames TABLE = beta beta_std delta delta_std

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
	scalar omega_est = r(omega)
	return scalar delta_estimate = delta_est
	return scalar beta_estimate  = beta_est
	return scalar omega_estimate = omega_est

end


program gmm_objective, rclass

    args delta

	* Generate lagged IVs and weighted sum of viewers *
	local num_lags = 3*24
	gen viewers_cumul_sponsored = viewers_sponsored
	gen viewers_cumul_partner = viewers_partner
	gen viewers_cumul = viewers
	forvalues j = 1/`num_lags' {
		scalar multiplier = (`delta'^`j')
		quietly: replace viewers_cumul = viewers_cumul  + multiplier * viewers_lag`j' if viewers_lag`j' != .
		quietly: replace viewers_cumul_sponsored = viewers_cumul_sponsored  + multiplier * viewers_lag`j'_sponsored if viewers_lag`j'_sponsored != .
		quietly: replace viewers_cumul_partner = viewers_cumul_partner  + multiplier * viewers_lag`j'_partner if viewers_lag`j'_partner != .
	}
	gen viewers_cumul_nonsponsored = viewers_cumul - viewers_cumul_sponsored
	gen viewers_cumul_nonpartner = viewers_cumul - viewers_cumul_partner
	foreach arg in _nonsponsored _nonpartner _sponsored _partner {
		gen logviewers_cumul`arg' = log(viewers_cumul`arg' + 1)
	}
	gen logviewers_cumul = log(viewers_cumul + 1)
	
	* Run regression and compute the objective function *
	local num_lags_iv = num_lags_iv[1]
	if $specification == 1 {
		ivreghdfe logplayers (logviewers_cumul_sponsored logviewers_cumul_nonsponsored = num_big_streamer_nonsponsored iv_lag1_nonsponsored-iv_lag`num_lags_iv'_nonsponsored num_big_streamer_sponsored iv_lag1_sponsored-iv_lag`num_lags_iv'_sponsored), absorb(game_date game_hour time_id) cluster(game_date) resid(resid)
	}
	if $specification == 2 {
		ivreghdfe logplayers (logviewers_cumul_partner logviewers_cumul_nonpartner = num_big_streamer_nonpartner iv_lag1_nonpartner-iv_lag`num_lags_iv'_nonpartner num_big_streamer_partner iv_lag1_partner-iv_lag`num_lags_iv'_partner), absorb(game_date game_hour time_id) cluster(game_date) resid(resid)
	}
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
	
	gen iv_lag0_sponsored = num_big_streamer_sponsored 
	forvalues j = 0/`num_lags_iv' {
		gen moment = iv_lag`j'_sponsored * resid
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

	drop viewers_cumul* logviewers_cumul* resid iv_lag0 iv_lag0_sponsored nobs
	
	return scalar gmm_obj_value = gmm_obj
	return scalar beta = COEF[1,2]
	return scalar omega = COEF[1,1] / COEF[1,2]
	
end 


program compute_lags

		local num_lags = 3*24
		forvalues j = 1/`num_lags' {
			quietly: bysort appid (time_utc): gen viewers_lag`j'_sponsored = viewers_sponsored[_n-`j']
		}
		forvalues j = 1/`num_lags' {
			quietly: bysort appid (time_utc): gen viewers_lag`j'_partner = viewers_partner[_n-`j']
		}
		forvalues j = 1/`num_lags' {
			quietly: bysort appid (time_utc): gen iv_lag`j'_sponsored = num_big_streamer_sponsored[_n-`j']
			quietly: gen iv_lag`j'_nonsponsored = iv_lag`j' - iv_lag`j'_sponsored
		}
		forvalues j = 1/`num_lags' {
			quietly: bysort appid (time_utc): gen iv_lag`j'_partner = num_big_streamer_partner[_n-`j']
			quietly: gen iv_lag`j'_nonpartner = iv_lag`j' - iv_lag`j'_partner
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
			quietly: bysort appid game_date (time_utc): gen viewers_lag`j'_sponsored = viewers_sponsored[_n-`j']
		}
		forvalues j = 1/`num_lags' {
			quietly: bysort appid game_date (time_utc): gen viewers_lag`j'_partner = viewers_partner[_n-`j']
		}
		forvalues j = 1/`num_lags' {
			quietly: bysort appid game_date (time_utc): gen iv_lag`j' = num_big_streamer_95[_n-`j']
		}
		forvalues j = 1/`num_lags' {
			quietly: bysort appid game_date (time_utc): gen iv_lag`j'_sponsored = num_big_streamer_sponsored[_n-`j']
			quietly: gen iv_lag`j'_nonsponsored = iv_lag`j' - iv_lag`j'_sponsored
		}
		forvalues j = 1/`num_lags' {
			quietly: bysort appid game_date (time_utc): gen iv_lag`j'_partner = num_big_streamer_partner[_n-`j']
			quietly: gen iv_lag`j'_nonpartner = iv_lag`j' - iv_lag`j'_partner
		}

end


program select_frequently_sponsored

	* Limit sample to games that are sponsored at least once *
	bysort appid: egen max_num_sponsored = max(num_big_streamer_sponsored)
	keep if max_num_sponsored > 0
	drop max_num_sponsored

end


program time_elapsed

	timer off 1
	timer list 1
	local time_elapsed = r(t1)/60
	display r(t1)/60
	
end


main

