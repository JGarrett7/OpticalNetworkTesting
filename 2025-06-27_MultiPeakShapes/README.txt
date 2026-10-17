TWO-PATH RESOLUTION TEST
Paper section "Multiplexing Resolution Limit"

Contents
  Two Path Experiment\       26 recordings, one per pair of path lengths, the sensor
                             configuration (info_*.csv) and a description of the setup
  Changing Amplitude\        3 single-path recordings at varying amplitude, used to build the
                             pulse shape for this test
  PeakLossShape.m            Analysis script
  normalized_curve_fit.mat   Pulse shape (pchip interpolant), written by the script
  curve_peak_width.mat       Width of the pulse shape in bins, written by the script

Test
  Two optical paths shared a splitter. One path was fixed at 5 cm, and the other was shortened
  in steps from 95 cm to 5 cm so the two peaks overlapped more and more. These recordings used a
  75-bin histogram (see the info file).

File names
  data_VL53L8CH__AIKit__CNH_4x4_ONECNH__<yyyyMMdd>_<HHmmss>_<long>cmx<short>cm.csv
    <long>, <short>   The two path lengths in centimeters

How to run
  Open PeakLossShape.m in MATLAB R2024a or later and click Run. For every
  recording, the Command Window shows the known and predicted path lengths and the absolute
  errors. A summary table at the end lists every configuration by path-length difference and
  marks whether both errors are within the 5 mm criterion used in the paper.

Notes
  - Fitted positions (bins) are converted to lengths (mm) with the linear constants mmPerBin and
    offsetMm at the top of the script.
  - Every configuration with a path-length difference of 10 cm or less fails the 5 mm criterion,
    and so do the 25, 30 and 35 cm configurations. For those three, findpeaks finds one merged
    peak, and the fit started from that guess doesn't separate the two pulses accurately. Every
    other difference above 10 cm passes.
  - Each run also writes one CurveFitting_<short>-<long> figure per configuration (lengths in mm)
    and three figures of the pulse shape to this folder.
