STRETCHING TESTS ON THE HARD-JUNCTION PROTOTYPE NETWORK
Paper Figures 8 and 9

Contents
  data\                      30 raw VL53L8CH log files: 20 hand-stretched runs (five per sensor) and
                             10 clamp-rig runs (five each for Sensors B and C)
  processed_data_files.mat   Output of stages 1-3 of MultiPeakStretch.m for all 30 runs
  master_curves.mat          Master curves used by the fit (identical copy of the file in
                             2026-03-20_NetworkPeakLocationTests)
  MultiPeakStretch.m         Analysis script
  ExportFigure.m             Figure export helper
  Figures\                   Exported figures (overwritten when the script runs)

Tests
  Hand runs (plotted in the paper): each sensor was held between lightly pinched fingers at two
  points and stretched by hand. Grip spacings were set using the 2 in (5.08 cm) hole spacing of
  the optical table, and the stretch was applied in 2 in steps with about 5 s at each step.
    Sensor A: 2 in section stretched by 2 in (5 cm by 5 cm)
    Sensor B: 6 in section stretched by 6 in (15 cm by 15 cm)
    Sensor C: 14 in section stretched by 10 in (35 cm by 25 cm)
    Sensor D: 2 in section stretched by 2 in (5 cm by 5 cm)

  Clamp-rig runs (not plotted): Sensors B and C were also stretched 1 in with pressure grips on a
  linear stage. These runs are included because the normalization uses them (see Notes).

File names
  data_VL53L8CH__AIKit__CNH_4x4_ONECNH__<yyyyMMdd>_<HHmmss>_Sensor<X>_<Hand|Rig>_Start<in>in_Increment<in>in_Change<in>in_Run<n>.csv
    Sensor<X>      Sensor stretched (A, B, C or D)
    Hand or Rig    Stretching method
    Start          Initial grip spacing in inches
    Increment      Step size in inches
    Change         Total elongation in inches
    Run<n>         Run number (1-5)

How to run
  1. Open MultiPeakStretch.m in MATLAB R2024a or later and click Run.
  2. In the stage selector, choose stage 6 (Figures 8 and 9).
  3. Stages 1-3 reprocess the raw data, take about 30 minutes and overwrite
     processed_data_files.mat. They are not needed to reproduce the figures.

Notes
  - Heights are normalized by the largest fitted height of the same peak across all runs of the
    same sensor, including the rig runs. The rig runs set the maximum for Sensor B Peak 1 and for
    Sensor C Peaks 2 and 3, so removing them would change those normalized amplitudes.
  - Each 0 cm value is the median before the stretch, and each stretched value is the median on
    the stretch plateau. The stretch distance on the plots is Change x 2.54, rounded to the
    nearest centimeter.
  - On the stretch plateau, Peak 3 sits at its upper position bound (bin 94.34) in all five
    Sensor C hand runs and in Sensor D hand run 1, so those shift values are set by the bound.
  - Shifts within 1e-9 bins of zero (numerical round-off, two values) are drawn as exactly zero.
    The trend-line equations use the unrounded values.
  - Whiskers end at the most extreme value within 1.5 times the interquartile range. As in the
    published Figures 8 and 9, values beyond the whiskers are not drawn (5 of the 240 plotted
    values). Set showOutliers = true at the top of the script to draw them. Every value is used
    for the medians, quartiles and trend lines.
