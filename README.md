# Soft optical networks: data and code

Raw data, processed results, microscopy images and MATLAB code for:

> J. G. Williamson and J. Schultz, "Toward Soft Optical Networks for Deformation Sensing." *Journal details to be added at publication.*

The scripts reproduce the plotted figures and the measured values reported in the paper from the data in this repository.

## Requirements

- MATLAB R2024a or later (tested in R2026a)
- Curve Fitting Toolbox
- Signal Processing Toolbox

## Quick start

1. Download or clone the repository and keep the folder structure.
2. Open the script for the figure you want (see the table below) and click **Run**. Each script switches to its own folder, so relative paths work wherever the repository is saved.
3. The pressure and stretch scripts open a stage selector because their processed results are included. Choose only the stages listed in the table. Stages 1 to 3 reprocess the raw data, take about 30 minutes per script and overwrite the included `processed_data_files.mat`.
4. Figures are saved to a `Figures` folder next to each script, as `.fig`, `.eps` and `.png` (300 dpi).

## Where each result comes from

| Paper item | Folder | Script | What to run |
|---|---|---|---|
| Figure 3 | `2026-03-10_NetworkPressureTests` | `MultiPeakPressure.m` | Stage 4. In the player, set File # to 1, move the slider to row 195 and click **Export Frame**. |
| Figure 7 (a-d) | `2026-03-10_NetworkPressureTests` | `MultiPeakPressure.m` | Stage 6 |
| Figures 8 and 9 (a-d) | `2026-03-12_NetworkStretchTests` | `MultiPeakStretch.m` | Stage 6 |
| Figure 11 and the 0.2 dB/mm attenuation | `2025-11-03_MiniscusTearingCutbacks/2025-12-10_ClearFlex30_10-0_MoldRelease_CutbackOutOfMold` | `LossProcessing.m` | Run (a few seconds). The loss is printed in the Command Window. |
| Figure 12 and Supplementary Figures S1 and S2 | `2025-10-21_MeniscusTearingMicroscopy` | none | Image files, listed in that folder's README |
| Multiplexing resolution limit (10 cm) | `2025-06-27_MultiPeakShapes` | `PeakLossShape.m` | Run. A summary table is printed in the Command Window. |
| Master curves | `2026-03-20_NetworkPeakLocationTests` | `SinglePeakTester.m` | Optional. `master_curves.mat` is included; stage 2 regenerates it. |
| 17.3 ms per frame | `2026-03-10_NetworkPressureTests` | `MultiPeakPressure.m` | Stage 3 prints the average fitting time per frame. The recorded benchmark is in `RunTime.txt`. |

Figures 1, 2, 4, 5, 6 and 10 are simulation renderings, drawings, CAD renderings and photographs, so no data for them is included.

### Differences from the published figures

Legend positions in the published figures were placed by hand, and the scripts put them close to those positions. `Figures/Histogram_File1_Row195.fig` in the pressure folder is the published version of Figure 3.

## Folder contents

| Folder | Contents |
|---|---|
| `2025-06-27_MultiPeakShapes` | Two-path resolution test: 26 two-path recordings, 3 single-path recordings used to build the pulse shape, and `PeakLossShape.m` |
| `2025-10-21_MeniscusTearingMicroscopy` | The 8 microscopy images used in Figure 12 and Figures S1 and S2 |
| `2025-11-03_MiniscusTearingCutbacks` | Cutback test of molded Clear Flex 30 waveguides (4 lengths) and `LossProcessing.m` |
| `2026-03-10_NetworkPressureTests` | Pressing tests (20 runs), processed results and `MultiPeakPressure.m` |
| `2026-03-12_NetworkStretchTests` | Stretching tests (30 runs), processed results and `MultiPeakStretch.m` |
| `2026-03-20_NetworkPeakLocationTests` | Single-path calibration recordings, master curves and `SinglePeakTester.m` |

Each folder has a `README.txt` with test details, file naming and run instructions.

## Data format

All sensor data are CSV logs exported by the STMicroelectronics MZ-AI GUI for the VL53L8CH time-of-flight sensor, with one row per frame.

- `.HostTimestamp`: time the host received the frame, in seconds (Unix time). The scripts convert it to seconds from the first frame.
- `cnh__hist_bin_<b>_a<k>`: compact normalized histogram value for bin `b` (starting at 0) and aggregate `k` (0 to 15). The network tests merge the whole SPAD array into one 1x1 zone, so only aggregate `a0` holds data, and the scripts read every 16th column. Values are in kcps.
- The other columns are standard GUI outputs and aren't used by the scripts.
- `info_*.csv` files are the sensor configuration exported by the GUI.

The network tests (pressure, stretch and calibration) use 144 histogram bins and a 250 ms ranging period, as described in the paper. The cutback files were recorded with the GUI's MAXBINS preset (75 bins, 500 ms ranging period), and the two-path files with 75 bins. The `info_*.csv` file in each of those folders has the full settings.

## Processed results

- `processed_data_files.mat` (pressure and stretch folders): output of stages 1 to 3, including the raw histogram tables, initial guesses, bounds and fitted heights and positions for every frame. Saved as MAT-file version 7.3. MATLAB may show a warning when loading these in an older release than the one that created them.
- `master_curves.mat`: the three master curves (pchip interpolants). The pressure, stretch and calibration folders each hold an identical copy.
- `single_peak_calibration_data.mat`: output of `SinglePeakTester.m`.
- `normalized_curve_fit.mat` and `curve_peak_width.mat`: written by `PeakLossShape.m` each time it runs.

The `filepath` field inside the processed files records where the raw files were stored on the original analysis computer. The scripts don't use it.

## Analysis notes

- **Pressing (Figure 7).** Each run's loading steps are detected on the sensor's primary peak (Peak 1 for Sensor A, Peak 2 for Sensors B and D, Peak 3 for Sensor C). A run is used only if exactly one step is found for each of the nine masses, and the script lists rejected runs in the Command Window. With the included results, Figure 7 uses runs 1, 2 and 5 for Sensor A, runs 3, 4 and 5 for Sensor C, and all five runs for Sensors B and D. Each loaded value is the median normalized height within its step. The 0 g value is the 95th percentile of the run's 3 s moving-median trace, which follows the unloaded signal for peaks that drop under load. Peak 3 of Sensor A rises under load, so its 0 g value (about 0.64) follows the loaded signal rather than the unloaded signal (about 0.46 to 0.52).
- **Stretching (Figures 8 and 9).** Only the hand-stretched runs are plotted. Each 0 cm value is the median before the stretch, and each stretched value is the median on the stretch plateau. Shifts are plateau position minus pre-stretch position, in bins. On the stretch plateau, Peak 3 sits at its upper position bound in all five Sensor C runs and in Sensor D run 1, so those shifts are limited by the bound.
- **Normalization.** Heights are divided by the largest fitted height of the same peak across all runs of the same sensor. For stretching, this includes the clamp-rig runs for Sensors B and C, which are included in the data for that reason.
- **Box plots.** Boxes span the 25th to 75th percentiles, with a line at the median. Whiskers end at the most extreme value within 1.5 times the interquartile range. As in the published figures, values beyond the whiskers aren't drawn: 5 of the 480 values in Figure 7 and 5 of the 240 values in Figures 8 and 9. Set `showOutliers = true` at the top of `MultiPeakPressure.m` or `MultiPeakStretch.m` to draw them. Every value is used for the medians, quartiles and trend lines. The equations above each plot are linear fits through the box medians.
- **Fit bounds.** Each position has a lower bound just below its calibrated location. For pressing, each position is held in a window less than half a bin wide, and Peak 1's height is held within 20% of the largest raw histogram peak between bins 60 and 75 of that frame. For stretching, each position can move up to 7.5 bins above its pressing window. Other heights only need to be non-negative. In the pressing fits, Peak 2 sits at its lower position bound and Peak 3 at its upper position bound in every frame. The values are set in the `peak_guess` function at the end of `MultiPeakPressure.m` and `MultiPeakStretch.m`.
- **Two-path test.** The summary table from `PeakLossShape.m` shows errors above 5 mm for every path-length difference of 10 cm or less, and also for 25, 30 and 35 cm. For those three, `findpeaks` finds one merged peak, and the fit started from that guess doesn't separate the two pulses accurately. Every other difference above 10 cm meets the criterion.

## License

- Code (`*.m` files): GNU General Public License v3.0. See `CODE_LICENSE`.
- Data and images (all other files): CC0 1.0 Universal. See `DATA_LICENSE`.

## How to cite

Please cite the paper above. To cite this repository, use **Cite this repository** on GitHub, which reads `CITATION.cff`.

## Funding

This work was supported by the NSF through EFRI grant 1935312.

## Contact

Questions about the data or code: open an issue on this repository.
