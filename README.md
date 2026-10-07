PlumeTracker is a MATLAB-based application designed to estimate, track, and analyze the velocity dynamics of volcanic fumaroles, gas plumes, and diffuse emissions from video files. Developed at the University of Palermo, the software couples optical flow tracking engines with a multi-stage spatial-temporal filtering pipeline to isolate fluid motion from ambient environmental noise.

Processing starts with an interactive GUI where the user configures parameters, selects the primary estimation engine, and calibrates spatial metrics. The system integrates two distinct motion tracking algorithms:
- RAFT (Recurrent All-Pairs Field Transforms): A deep-learning optical flow engine that constructs all-pair correlation volumes and iteratively refines motion fields using Gated Recurrent Units (GRUs): a type of recurrent neural network architecture designed to process sequential data and propagate context across iterations. Accelerated by CUDA GPUs (NVIDIA's parallel computing platform), it excels at tracking complex, non-linear fluid turbulence, low-contrast puff edges, and dynamic luminance gradients.
- Farneback: A classical, dense optical flow method that approximates local image neighborhoods using two-dimensional quadratic polynomials. It operates efficiently on standard CPUs, making it ideal for lightweight processing without dedicated deep-learning hardware.

Pixel-to-meter scaling is established using one of two methods:
1. Field References: Manual placement of known reference lines within the scene, either a single line at the emission distance for uniform scaling, or two lines at different depths to construct a spatially variant pixel-to-meter map that compensates for perspective tilt across image.
2. Camera Optics: In absence of physical length references within the image, pixel-to-meter scaling is analytically calculated based on the camera-to-target distance (d), the horizontal lens Field of View (FOV), and the horizontal resolution in pixels (W_px), using the trigonometric relation:
   Scene Width (m) = 2 * d * tan(FOV / 2)
   Meters per Pixel = Scene Width (m) / W_px

Once spatial scaling is defined, an interactive polygonal Region of Interest (ROI) isolates the active gas plume. For each consecutive frame pair, the raw displacement vector field undergoes a four-stage cleanup pipeline:
1. Spatial median filtering to smooth extreme vector peaks and eliminate high-frequency noise.
2. Temporal coherence testing to verify directional persistence across frames, discarding vectors whose angular deviation exceeds a configured tolerance.
3. Adaptive morphological filtering to remove isolated vector clusters smaller than a specified fraction of the total ROI area.
4. ROI coverage density validation, flagging frame values as NaN if active plume coverage falls below a minimum threshold to eliminate noise from lighting shifts during gas-free intervals.

During execution, PlumeTracker updates a synchronized display featuring (i) the video feed, (ii) a velocity colormap overlaid with velocity vector field arrows and an auto-fitted orthogonal cross-section line, and (iii) a dynamic time-series profile of velocity.

All extracted metrics are automatically saved to a CSV file containing frame indices, physical time (s), mean velocity (m/s), spatial standard deviation (m/s), peak velocity (m/s), directional velocity components (Vx, Vy in m/s), and active plume cross-sectional width (m).

Author: Lo Bue Trisciuzzi Giovanni
Affiliation: University of Palermo
Update: September 2026
