CUTBACK TEST OF MOLDED CLEAR FLEX 30 WAVEGUIDES
Paper Figure 11

Contents
  data\           4 raw VL53L8CH log files, one per waveguide length (050, 070, 090 and 110 mm)
  info_*.csv      Sensor configuration exported by the GUI
  LossProcessing.m
  ExportFigure.m
  Figures\        Exported figure (overwritten when the script runs)

Specimens
  Unplasticized Clear Flex 30 was cast in the polished cutback channel of the mold, treated with
  mold release, between Stretch Magic leads set 5, 7, 9 and 11 cm apart, and scraped flush.
  The waveguides were measured after removal from the mold.

Sensor settings
  These files were recorded with the GUI's MAXBINS preset (75 bins, 500 ms ranging period; see the
  info file), not the 144-bin, 250 ms setup used for the network tests.

How to run
  Open LossProcessing.m in MATLAB R2024a or later and click Run. The script reads the files in
  data\, prints the attenuation in dB/mm and the fitted line, and saves
  Figures\Optical_TPU_Signal_Characteristics.

Method
  For each file, the median of every histogram column over all frames is taken, and the largest
  median is the received signal. A straight line is fit to log10(signal) against length, and the
  loss in dB/mm is -10 times the slope (0.234 dB/mm with this data).
