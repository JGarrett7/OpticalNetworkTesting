PRESSING TESTS ON THE HARD-JUNCTION PROTOTYPE NETWORK
Paper Figures 3 and 7

Contents
  data\                      20 raw VL53L8CH log files, one per run (Sensors A-D, five runs each)
  processed_data_files.mat   Output of stages 1-3 of MultiPeakPressure.m: raw histogram tables,
                             initial guesses, bounds and fitted heights and positions for every frame
  master_curves.mat          Master curves used by the fit (identical copy of the file in
                             2026-03-20_NetworkPeakLocationTests)
  MultiPeakPressure.m        Analysis script
  ExportFigure.m             Figure export helper
  Figures\                   Exported figures (overwritten when the script runs).
                             Histogram_File1_Row195.fig is the published version of Figure 3.
  RunTime.txt                Curve-fitting benchmark reported in the paper

Test
  Each sensor segment of the prototype was held in a 3D-printed fixture, and a hooked weight set
  pressed on the waveguide with its 2 mm diameter hook. Each run started unloaded. The weight was
  placed, held, removed and increased by 20 g, from 60 g to 220 g (nine masses), with the
  waveguide unloaded between masses. Some sensors needed a longer dwell to give a stable
  signal: about 3 s per mass was used for Sensor A and about 10 s for Sensors B, C and D.

File names
  data_VL53L8CH__AIKit__CNH_4x4_ONECNH__<yyyyMMdd>_<HHmmss>_Sensor<X>_Start<g>_Increment<g>_Stop<g>_Run<n>.csv
    Sensor<X>      Sensor pressed (A, B, C or D)
    Start, Stop    First and last mass in grams
    Increment      Mass added between steps in grams
    Run<n>         Run number (1-5)

How to run
  1. Open MultiPeakPressure.m in MATLAB R2024a or later and click Run.
  2. In the stage selector:
       Figure 7: choose stage 6.
       Figure 3: choose stage 4. In the player, set File # to 1, move the slider to row 195
                 and click Export Frame.
  3. Stages 1-3 reprocess the raw data, take about 30 minutes and overwrite
     processed_data_files.mat. They are not needed to reproduce the figures.

Notes
  - A run is used in Figure 7 only if the step detection finds one step for each of the nine
    masses on the sensor's primary peak. With the included results, Sensor A runs 3 and 4 and
    Sensor C runs 1 and 2 are not used. The script lists rejected runs in the Command Window.
  - Each loaded value is the median normalized height within the detected step. The 0 g value is
    the 95th percentile of the run's 3 s moving-median trace, which follows the unloaded signal
    for peaks that drop under load. Peak 3 of Sensor A rises under load, so its 0 g value (about
    0.64) follows the loaded signal rather than the unloaded signal (about 0.46 to 0.52).
  - Heights are normalized by the largest fitted height of the same peak across all runs of the
    same sensor.
  - Whiskers end at the most extreme value within 1.5 times the interquartile range. As in the
    published Figure 7, values beyond the whiskers are not drawn (5 of the 480 plotted values).
    Set showOutliers = true at the top of the script to draw them. Every value is used for the
    medians, quartiles and trend lines.
