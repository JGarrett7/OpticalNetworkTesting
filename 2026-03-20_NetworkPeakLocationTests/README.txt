MASTER CURVE CALIBRATION FOR THE HARD-JUNCTION PROTOTYPE NETWORK
Paper section "Empirical Master Curve Generation"

Contents
  data\                              3 raw VL53L8CH log files, one per optical path (Peak1, Peak2, Peak3)
  SinglePeakTester.m                 Builds the master curves and checks them with single-curve fits
  master_curves.mat                  Master curves (pchip interpolants) used by the pressure and
                                     stretch scripts
  single_peak_calibration_data.mat   Loaded data and single-curve fits from SinglePeakTester.m

Test
  Each path was recorded with the other paths disconnected, so only one peak was present. The
  sensors on that path were pressed by hand to record the peak at many amplitudes.

How to run (optional)
  master_curves.mat is included, so this script is not needed to reproduce the paper figures.
  1. Open SinglePeakTester.m in MATLAB R2024a or later and click Run.
  2. Stage 2 rebuilds master_curves.mat from the data. Stage 5 plots the fitted peak positions
     and prints their minimum, median and maximum.
  The pressure and stretch folders hold their own copies of master_curves.mat. They are
  identical to this one but are not updated automatically if you rebuild it.
