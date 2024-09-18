REM ****************************************************
REM * run_code.bat: double-click to run all scripts
REM ****************************************************

REM SET LOG=..\output\run_code.log

REM DELETE OUTPUT AND TEMP FOLDERS (COMMENTED OUT FOR NOW)
REM DEL /F /Q ..\output\
REM DEL /F /Q ..\output\figures\
REM DEL /F /Q ..\output\tables\

RMDIR ..\temp /S /Q
RMDIR ..\output /S /Q
MKDIR ..\temp
MKDIR ..\output

REM LOG START
REM ECHO run_code.bat started	>%LOG%
REM ECHO %DATE%		>>%LOG%
REM ECHO %TIME%		>>%LOG%
REM dir ..\output\ >>%LOG% 

REM RUN CODE
%STATAEXE% /e do 0_sample_prep.do
%STATAEXE% /e do 1_summary_stats.do
%STATAEXE% /e do 2_main_estimation.do
%STATAEXE% /e do 3_sponsored_organic.do
%STATAEXE% /e do 4_heterogeneity_median_splits.do
%REXE% CMD BATCH 5_heterogeneity_grfs.R
REM %STATAEXE% /e do 6_comscore.do
%REXE% CMD BATCH 7_roi_computations.R
REM %STATAEXE% /e do 8_demand_heterogeneity_cross_validation.R

REM COPY %LOG%+0_sample_prep.log+1_summary_stats.log+2_main_estimation.log+3_sponsored_organic.log+4_heterogeneity.log+5_demand_analysis_heterogeneity.Rout+6_comscore.log+7_top_stream_on_viewers.log+8_predicted_lift.Rout %LOG%
REM DEL 0_sample_prep.log 1_summary_stats.log 2_main_estimation.log 3_sponsored_organic.log 4_heterogeneity.log 5_demand_analysis_heterogeneity.Rout 6_comscore.log 7_top_stream_on_viewers.log 8_predicted_lift.Rout

REM LOG COMPLETE
REM ECHO run_code.bat completed	>>%LOG%
REM ECHO %DATE%		>>%LOG%
REM ECHO %TIME%		>>%LOG%

PAUSE
