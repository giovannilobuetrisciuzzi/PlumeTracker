%% 
% OPTICAL FLOW ALGORITHM TO ESTIMATE MOVEMENT VELOCITY FROM VIDEO (Optical Flow RAFT/Farneback)
% Created by Lo Bue Trisciuzzi Giovanni (University of Palermo)
% Update: 24 September 2026

% MAIN CALCULATIONS AND FILTERING LOGIC:
% 1. OPTICAL FLOW CALCULATION (RAFT):
%    For each pair of consecutive frames, the RAFT Deep Learning model 
%    analyzes the displacement of visual patterns (luminance gradients, puff edges/contours, turbulence)
%    within a region of interest (ROI) drawn by the user.
%    Returns displacement vectors (Vx, Vy) which are converted 
%    to m/s via pixel-to-meter scaling, obtained geometrically from video parameters or known lengths in the video.
%
% 2. BASIC SPATIAL FILTERING (Median Filter):
%    An nxn median filter (medfilt2) smooths extreme peaks and eliminates 
%    high-frequency noise.
%
% 3. TEMPORAL COHERENCE TEST (Directional Persistence):
%    Verifies direction stability over time. If angular deviation 
%    of the same pixel between frame (t-1) and frame (t) is below 
%    cosd(maxAngleDev), the pixel accumulates a coherence point. 
%    Only pixels coherent for consecutive frames (minCoherentFrames) are valid.
%
% 4. MORPHOLOGICAL FILTERING (Adaptive Cluster Removal):
%    Using connected components analysis (bwareaopen), the system 
%    identifies contiguous groups of active pixels. Discards isolated clusters 
%    smaller than a specific fraction/percentage of the total ROI area (minClusterRatio).
%
% 5. MINIMUM COVERAGE VALIDATION (ROI Density):
%    Computes ratio between active validated pixel area and total ROI area. 
%    The frame's mean velocity is calculated only if gas covers at least X% of the ROI (minAreaRatio). 
%    Otherwise, the data point is set to NaN to eliminate noise from lighting changes when no gas is present.
% =========================================================================
%
% SUGGESTED FEATURES:
% Inserire frame di inizio e fine da analizzare.
% Inserire possibilità di ripetere linee e poligoni
%
function PlumeTracker()
    clc; clear; close all; warning off
    %% 1. INTERACTIVE PARAMETER CONFIGURATION GUI
    % Default values for the GUI setup
    def_useRAFT          = 0;     % 1 = RAFT, 0 = Farneback
    def_frameStep        = 1;     % Frame skipping
    def_scaleFactor      = 1.0;   % Image scale factor
    def_maxIter          = 8;     % Algorithm iterations
    def_numPyramidLevels = 6;     % Farneback Pyramid Levels
    def_neighborhoodSize = 9;     % Farneback Neighborhood Size
    def_filterSize       = 15;    % Farneback Filter Size
    def_vel_profile      = 1;     % 0 = Mean direction, 1 = Full vector field
    def_drawEveryN       = 30;    % Graphics refresh rate
    def_maxColorScale    = 5.0;   % Colormap max speed
    def_font             = 10;    % Text font size
    def_n                = 3;     % Median filter window size
    def_maxAngleDev      = 45;    % Angular deviation tolerance
    def_minCoherentFrames= 4;     % Coherence frames
    def_minClusterRatio  = 0.005; % Minimum cluster ROI ratio (0.20 = 20% of ROI)
    def_minAreaRatio     = 0.01;  % Minimum active ROI coverage ratio (0.01 = 1% of ROI)
    def_save_output      = 1;     % Save output CSV
    
    % Create Parameter Setup Window
    figParam = figure('Name', 'Optical Flow Setup - Parameters Configuration', ...
        'NumberTitle', 'off', 'Units', 'normalized', 'Position', [0.20, 0.05, 0.60, 0.88], ...
        'toolbar', 'none', 'MenuBar', 'none', 'Resize', 'on');
    
    % --- PANEL 1: ALGORITHM & PERFORMANCE ---
    pnlAlg = uipanel('Parent', figParam, 'Title', '1. ALGORITHM & PERFORMANCE', ...
        'Units', 'normalized', 'Position', [0.03, 0.65, 0.94, 0.32], ...
        'FontWeight', 'bold', 'FontSize', 10);
    
    % Column 1: General Parameters
    uicontrol('Parent', pnlAlg, 'Style', 'text', 'Units', 'normalized', ...
        'Position', [0.02, 0.75, 0.22, 0.18], 'String', 'Optical Flow Method:', ...
        'HorizontalAlignment', 'right', 'FontWeight', 'bold');
    popRAFT = uicontrol('Parent', pnlAlg, 'Style', 'popupmenu', 'Units', 'normalized', ...
        'Position', [0.25, 0.75, 0.23, 0.18], ...
        'String', {'RAFT (Deep Learning)', 'Farneback (Classical)'}, ...
        'Value', ternary(def_useRAFT == 1, 1, 2), 'Callback', @toggleFarnebackGUI);
    
    uicontrol('Parent', pnlAlg, 'Style', 'text', 'Units', 'normalized', ...
        'Position', [0.02, 0.52, 0.22, 0.18], 'String', 'Frame Step:', ...
        'HorizontalAlignment', 'right');
    editFrameStep = uicontrol('Parent', pnlAlg, 'Style', 'edit', 'Units', 'normalized', ...
        'Position', [0.25, 0.52, 0.23, 0.18], 'String', num2str(def_frameStep), 'BackgroundColor', 'w');
    
    uicontrol('Parent', pnlAlg, 'Style', 'text', 'Units', 'normalized', ...
        'Position', [0.02, 0.29, 0.22, 0.18], 'String', 'Scale Factor (max 1.0):', ...
        'HorizontalAlignment', 'right');
    editScaleFactor = uicontrol('Parent', pnlAlg, 'Style', 'edit', 'Units', 'normalized', ...
        'Position', [0.25, 0.29, 0.23, 0.18], 'String', num2str(def_scaleFactor), 'BackgroundColor', 'w');
    
    uicontrol('Parent', pnlAlg, 'Style', 'text', 'Units', 'normalized', ...
        'Position', [0.02, 0.06, 0.22, 0.18], 'String', 'Max Iterations (suggested: 5-12):', ...
        'HorizontalAlignment', 'right');
    editMaxIter = uicontrol('Parent', pnlAlg, 'Style', 'edit', 'Units', 'normalized', ...
        'Position', [0.25, 0.06, 0.23, 0.18], 'String', num2str(def_maxIter), 'BackgroundColor', 'w');
    
    % Column 2: Farneback-Specific Parameters
    pnlFarnebackGroup = uipanel('Parent', pnlAlg, 'Title', 'Farneback Parameters', ...
        'Units', 'normalized', 'Position', [0.51, 0.02, 0.47, 0.93], 'FontWeight', 'bold');
    
    txtPyr = uicontrol('Parent', pnlFarnebackGroup, 'Style', 'text', 'Units', 'normalized', ...
        'Position', [0.02, 0.68, 0.60, 0.25], 'String', 'Pyramid Levels (suggested: 5-7):', ...
        'HorizontalAlignment', 'right');
    editPyrLevels = uicontrol('Parent', pnlFarnebackGroup, 'Style', 'edit', 'Units', 'normalized', ...
        'Position', [0.64, 0.68, 0.32, 0.25], 'String', num2str(def_numPyramidLevels), 'BackgroundColor', 'w');
    
    txtNeigh = uicontrol('Parent', pnlFarnebackGroup, 'Style', 'text', 'Units', 'normalized', ...
        'Position', [0.02, 0.36, 0.60, 0.25], 'String', 'Neighborhood Size (suggested: 7-11):', ...
        'HorizontalAlignment', 'right');
    editNeighSize = uicontrol('Parent', pnlFarnebackGroup, 'Style', 'edit', 'Units', 'normalized', ...
        'Position', [0.64, 0.36, 0.32, 0.25], 'String', num2str(def_neighborhoodSize), 'BackgroundColor', 'w');
    
    txtFilt = uicontrol('Parent', pnlFarnebackGroup, 'Style', 'text', 'Units', 'normalized', ...
        'Position', [0.02, 0.04, 0.60, 0.25], 'String', 'Filter Size (suggested: 15):', ...
        'HorizontalAlignment', 'right');
    editFiltSize = uicontrol('Parent', pnlFarnebackGroup, 'Style', 'edit', 'Units', 'normalized', ...
        'Position', [0.64, 0.04, 0.32, 0.25], 'String', num2str(def_filterSize), 'BackgroundColor', 'w');
    
    % Initial enable/disable state for Farneback GUI fields
    toggleFarnebackGUI();
    
    % --- PANEL 2: GRAPHICS & DISPLAY ---
    pnlGraph = uipanel('Parent', figParam, 'Title', '2. GRAPHICS & VISUALIZATION', ...
        'Units', 'normalized', 'Position', [0.03, 0.38, 0.94, 0.25], ...
        'FontWeight', 'bold', 'FontSize', 10);
    
    uicontrol('Parent', pnlGraph, 'Style', 'text', 'Units', 'normalized', ...
        'Position', [0.03, 0.73, 0.45, 0.22], 'String', 'Vector Display Profile:', ...
        'HorizontalAlignment', 'right', 'FontWeight', 'bold');
    popVelProfile = uicontrol('Parent', pnlGraph, 'Style', 'popupmenu', 'Units', 'normalized', ...
        'Position', [0.50, 0.73, 0.45, 0.22], ...
        'String', {'Mean Direction Vector', 'Full Vector Field'}, ...
        'Value', ternary(def_vel_profile == 0, 1, 2));
    
    uicontrol('Parent', pnlGraph, 'Style', 'text', 'Units', 'normalized', ...
        'Position', [0.03, 0.49, 0.45, 0.22], 'String', 'Refresh graphics every N frames (high numbers improve velocity):', ...
        'HorizontalAlignment', 'right');
    editDrawEveryN = uicontrol('Parent', pnlGraph, 'Style', 'edit', 'Units', 'normalized', ...
        'Position', [0.50, 0.49, 0.45, 0.22], 'String', num2str(def_drawEveryN), 'BackgroundColor', 'w');
    
    uicontrol('Parent', pnlGraph, 'Style', 'text', 'Units', 'normalized', ...
        'Position', [0.03, 0.25, 0.45, 0.22], 'String', 'Max velocity Colormap (m/s):', ...
        'HorizontalAlignment', 'right');
    editMaxColorScale = uicontrol('Parent', pnlGraph, 'Style', 'edit', 'Units', 'normalized', ...
        'Position', [0.50, 0.25, 0.45, 0.22], 'String', num2str(def_maxColorScale), 'BackgroundColor', 'w');
    
    uicontrol('Parent', pnlGraph, 'Style', 'text', 'Units', 'normalized', ...
        'Position', [0.03, 0.01, 0.45, 0.22], 'String', 'GUI Font Size:', ...
        'HorizontalAlignment', 'right');
    editFont = uicontrol('Parent', pnlGraph, 'Style', 'edit', 'Units', 'normalized', ...
        'Position', [0.50, 0.01, 0.45, 0.22], 'String', num2str(def_font), 'BackgroundColor', 'w');
    
    % --- PANEL 3: FILTERING PARAMETERS ---
    pnlFilt = uipanel('Parent', figParam, 'Title', '3. SIGNAL & NOISE FILTERS', ...
        'Units', 'normalized', 'Position', [0.03, 0.07, 0.94, 0.29], ...
        'FontWeight', 'bold', 'FontSize', 10);
    
    uicontrol('Parent', pnlFilt, 'Style', 'text', 'Units', 'normalized', ...
        'Position', [0.03, 0.82, 0.45, 0.15], 'String', 'Median filter window size (suggested: 3-5):', ...
        'HorizontalAlignment', 'right');
    editN = uicontrol('Parent', pnlFilt, 'Style', 'edit', 'Units', 'normalized', ...
        'Position', [0.50, 0.82, 0.45, 0.15], 'String', num2str(def_n), 'BackgroundColor', 'w');
    
    uicontrol('Parent', pnlFilt, 'Style', 'text', 'Units', 'normalized', ...
        'Position', [0.03, 0.65, 0.45, 0.15], 'String', 'Max direction angular dev (suggested: 30-45):', ...
        'HorizontalAlignment', 'right');
    editMaxAngleDev = uicontrol('Parent', pnlFilt, 'Style', 'edit', 'Units', 'normalized', ...
        'Position', [0.50, 0.65, 0.45, 0.15], 'String', num2str(def_maxAngleDev), 'BackgroundColor', 'w');
    
    uicontrol('Parent', pnlFilt, 'Style', 'text', 'Units', 'normalized', ...
        'Position', [0.03, 0.48, 0.45, 0.15], 'String', 'Min coherent frames (suggested: 3-5, depends on FPS):', ...
        'HorizontalAlignment', 'right');
    editMinCoherentFrames = uicontrol('Parent', pnlFilt, 'Style', 'edit', 'Units', 'normalized', ...
        'Position', [0.50, 0.48, 0.45, 0.15], 'String', num2str(def_minCoherentFrames), 'BackgroundColor', 'w');
    
    uicontrol('Parent', pnlFilt, 'Style', 'text', 'Units', 'normalized', ...
        'Position', [0.03, 0.31, 0.45, 0.15], 'String', 'Min cluster ROI fraction (suggested: 0.005-0.1):', ...
        'HorizontalAlignment', 'right');
    editMinClusterRatio = uicontrol('Parent', pnlFilt, 'Style', 'edit', 'Units', 'normalized', ...
        'Position', [0.50, 0.31, 0.45, 0.15], 'String', num2str(def_minClusterRatio), 'BackgroundColor', 'w');
    
    uicontrol('Parent', pnlFilt, 'Style', 'text', 'Units', 'normalized', ...
        'Position', [0.03, 0.14, 0.45, 0.15], 'String', 'Min active ROI area (0.01 = 1%; suggested: 0.01):', ...
        'HorizontalAlignment', 'right');
    editMinAreaRatio = uicontrol('Parent', pnlFilt, 'Style', 'edit', 'Units', 'normalized', ...
        'Position', [0.50, 0.14, 0.45, 0.15], 'String', num2str(def_minAreaRatio), 'BackgroundColor', 'w');
    
    chkSaveCsv = uicontrol('Parent', pnlFilt, 'Style', 'checkbox', 'Units', 'normalized', ...
        'Position', [0.50, 0.00, 0.45, 0.12], 'String', 'Save output CSV data automatically', ...
        'Value', def_save_output, 'FontWeight', 'bold');
    
    % START BUTTON
    uicontrol('Parent', figParam, 'Style', 'pushbutton', 'Units', 'normalized', ...
        'Position', [0.25, 0.01, 0.50, 0.05], 'String', '🚀 START ANALYSIS', ...
        'FontWeight', 'bold', 'FontSize', 11, 'BackgroundColor', [0.2 0.65 0.3], 'ForegroundColor', 'w', ...
        'Callback', @(src, evt) uiresume(figParam));
    
    % --- CICLO CONTINUO PER COMPILAZIONE ESEGUIBILE (Evita la chiusura del .exe) ---
    while ishandle(figParam)
        set(figParam, 'Visible', 'on');
        figure(figParam); % Riporta la GUI parametri in primo piano
        uiwait(figParam);
        
        if ~ishandle(figParam), break; end % Se l'utente chiude la finestra GUI con la "X", esci dal ciclo
        
        % Read confirmed values from GUI
        useRAFT          = (popRAFT.Value == 1);
        frameStep        = max(1, round(str2double(editFrameStep.String)));
        scaleFactor      = min(1.0, max(0.1, str2double(editScaleFactor.String)));
        maxIter          = max(1, round(str2double(editMaxIter.String)));
        numPyramidLevels = max(1, round(str2double(editPyrLevels.String)));
        neighborhoodSize = max(1, round(str2double(editNeighSize.String)));
        filterSize       = max(1, round(str2double(editFiltSize.String)));
        vel_profile      = (popVelProfile.Value == 2);
        drawEveryN       = max(1, round(str2double(editDrawEveryN.String)));
        maxColorScale    = max(0.1, str2double(editMaxColorScale.String));
        font             = max(6, round(str2double(editFont.String)));
        n                = max(1, round(str2double(editN.String)));
        maxAngleDev      = max(0, str2double(editMaxAngleDev.String));
        minCoherentFrames= max(1, round(str2double(editMinCoherentFrames.String)));
        minClusterRatio  = max(0, str2double(editMinClusterRatio.String));
        minAreaRatio     = max(0, str2double(editMinAreaRatio.String));
        save_output      = chkSaveCsv.Value;
        
        set(figParam, 'Visible', 'off'); % Nascondi temporaneamente la GUI dei parametri durante il calcolo
        
        %% 2. Video Selection & Metadata Reading
        [fileName, pathName] = uigetfile({'*.mp4;*.mov;*.avi', 'Video (*.mp4, *.mov, *.avi)'}, 'Select Video');
        if isequal(fileName, 0), continue; end
        videoPath = fullfile(pathName, fileName);
        vReader   = VideoReader(videoPath);
        try
            fpsRilevato = round(vReader.FrameRate);
        catch
            fpsRilevato = 24;
        end
        disp(['FPS detected: ', num2str(fpsRilevato)]);
        
        %% 3. INTERACTIVE GUI: Scale Calibration & FPS Control (Screen-Independent Layout)
        distanza = 5; % meters
        FOV_h    = 95; % degrees
        frameIniziale = readFrame(vReader);
        frameSmall    = imresize(frameIniziale, scaleFactor);
        
        figCalib = figure('Name', 'Scale Calibration & Video Parameters', ...
            'NumberTitle', 'off', 'Units', 'normalized', 'Position', [0.05, 0.05, 0.90, 0.88], ...
            'toolbar', 'none', 'WindowState', 'maximized');
        
        axCalib = axes('Parent', figCalib, 'Units', 'normalized', 'Position', [0.03, 0.40, 0.94, 0.56]);
        imshow(frameSmall, 'Parent', axCalib);
        title(axCalib, {'PIXEL-TO-METER SCALE CALIBRATION', 'Select a calibration method'}, 'FontSize', 12);
        
        metriPerPixel    = []; % Single factor (used if 1 line or camera parameters)
        calibLinesData   = []; % Structure for 2 lines (perspective correction)
        fps              = fpsRilevato; 
        
        % Main control panel
        pnlControl = uipanel('Parent', figCalib, 'Title', 'CALIBRATION METHODS AND VIDEO PARAMETERS', ...
            'Units', 'normalized', 'Position', [0.03, 0.02, 0.94, 0.35], ...
            'FontSize', font + 1, 'FontWeight', 'bold');
        
        % --- SHARED GENERAL PARAMETERS PANEL (FPS) ---
        pnlFPS = uipanel('Parent', pnlControl, 'Title', 'GENERAL VIDEO PARAMETERS (Required for both Option A & B)', ...
            'Units', 'normalized', 'Position', [0.01, 0.70, 0.98, 0.28], ...
            'FontSize', font, 'FontWeight', 'bold');
        uicontrol('Parent', pnlFPS, 'Style', 'text', 'Units', 'normalized', ...
            'String', 'Video Frame Rate (FPS):', ...
            'Position', [0.02, 0.15, 0.35, 0.70], 'FontWeight', 'bold', 'FontSize', font, ...
            'HorizontalAlignment', 'right');
        editFPS = uicontrol('Parent', pnlFPS, 'Style', 'edit', 'Units', 'normalized', ...
            'String', num2str(fpsRilevato), ...
            'Position', [0.38, 0.15, 0.15, 0.70], 'FontSize', font, ...
            'BackgroundColor', 'w', 'ForegroundColor', 'k', 'HorizontalAlignment', 'center');
        uicontrol('Parent', pnlFPS, 'Style', 'text', 'Units', 'normalized', ...
            'String', '(Used to convert pixel displacements to m/s in both Option A and Option B)', ...
            'Position', [0.55, 0.15, 0.43, 0.70], 'FontAngle', 'italic', 'FontSize', font - 1, ...
            'HorizontalAlignment', 'left');
        
        % --- SUB-PANEL OPTION A ---
        pnlOptA = uipanel('Parent', pnlControl, 'Title', 'OPTION A: Via known field length measurements', ...
            'Units', 'normalized', 'Position', [0.01, 0.03, 0.48, 0.64], ...
            'FontSize', font, 'FontWeight', 'bold');
        
        btnAddPoint = uicontrol('Parent', pnlOptA, 'Style', 'pushbutton', ...
            'Units', 'normalized', 'Position', [0.05, 0.20, 0.90, 0.65], ...
            'String', 'Draw lines of known length (at fumarola distance)', ...
            'FontWeight', 'bold', 'FontSize', font, ...
            'BackgroundColor', [0.2 0.6 0.9], 'ForegroundColor', 'w', ...
            'Callback', @addManualMeasurement);
        
        % --- SUB-PANEL OPTION B ---
        pnlOptB = uipanel('Parent', pnlControl, 'Title', 'OPTION B: Geometrically via Camera Parameters', ...
            'Units', 'normalized', 'Position', [0.51, 0.03, 0.48, 0.64], ...
            'FontSize', font, 'FontWeight', 'bold');
        
        btnCameraParams = uicontrol('Parent', pnlOptB, 'Style', 'pushbutton', ...
            'Units', 'normalized', 'Position', [0.03, 0.65, 0.94, 0.28], ...
            'String', 'Calculate Scale with Camera Parameters', ...
            'FontSize', font, 'FontWeight', 'bold', ...
            'BackgroundColor', [0.2 0.6 0.9], 'ForegroundColor', 'w', ...
            'Callback', @useCameraParams);
        
        uicontrol('Parent', pnlOptB, 'Style', 'text', 'Units', 'normalized', ...
            'String', 'Camera-Fumarola Distance (m):', ...
            'Position', [0.03, 0.43, 0.60, 0.18], 'HorizontalAlignment', 'right', 'FontSize', font - 1);
        editDistanza = uicontrol('Parent', pnlOptB, 'Style', 'edit', 'Units', 'normalized', ...
            'String', distanza, ...
            'Position', [0.65, 0.43, 0.30, 0.18], 'FontSize', font - 1, 'BackgroundColor', 'w');
        
        uicontrol('Parent', pnlOptB, 'Style', 'text', 'Units', 'normalized', ...
            'String', 'Horizontal Lens FOV (°):', ...
            'Position', [0.03, 0.23, 0.60, 0.18], 'HorizontalAlignment', 'right', 'FontSize', font - 1);
        editFOV = uicontrol('Parent', pnlOptB, 'Style', 'edit', 'Units', 'normalized', ...
            'String', FOV_h, ...
            'Position', [0.65, 0.23, 0.30, 0.18], 'FontSize', font - 1, 'BackgroundColor', 'w');
        
        uicontrol('Parent', pnlOptB, 'Style', 'text', 'Units', 'normalized', ...
            'String', 'Horizontal Video Res (px):', ...
            'Position', [0.03, 0.03, 0.60, 0.18], 'HorizontalAlignment', 'right', 'FontSize', font - 1);
        editWidthPx = uicontrol('Parent', pnlOptB, 'Style', 'edit', 'Units', 'normalized', ...
            'String', num2str(vReader.Width), ...
            'Position', [0.65, 0.03, 0.30, 0.18], 'FontSize', font - 1, 'BackgroundColor', 'w');
        
        uiwait(figCalib);
        if isempty(metriPerPixel) && isempty(calibLinesData), continue; end
        disp(['Calculated scale (meters/pixel): ', num2str(metriPerPixel)]);
        
        %% 4. Polygonal ROI Selection
        figRoi = figure('Name', 'Region of Interest (ROI) Selection', 'NumberTitle', 'off', 'toolbar', 'none', 'WindowState', 'maximized');
        axRoi = axes('Parent', figRoi, 'Position', [0.05, 0.12, 0.90, 0.82]);
        
        btnToggleVideo = uicontrol('Parent', figRoi, 'Style', 'pushbutton', 'String', '▶️ Play Video', ...
            'Position', [30, 20, 160, 40], 'FontWeight', 'bold', 'FontSize', 10, 'Callback', @toggleVideoROI);
        
        % BARRA DI SCORRIMENTO PER LA ROI
        sliderVideoRoi = uicontrol('Parent', figRoi, 'Style', 'slider', ...
            'Position', [200, 25, 500, 30], 'Min', 0, 'Max', max(0.1, vReader.Duration), 'Value', vReader.CurrentTime, ...
            'Callback', @sliderScrubRoi);
        
        currFrameRoi = imresize(frameIniziale, scaleFactor);
        hImgRoi = imshow(currFrameRoi, 'Parent', axRoi);
        title(axRoi, {'DRAW A POLYGON AROUND THE REGION OF INTEREST:', ...
               'Click polygon vertices: the last point must match the first point'});
        
        isPlayingRoi = false;
        timerRoi = timer('ExecutionMode', 'fixedRate', 'Period', 1/fps, 'TimerFcn', @updateVideoFrameROI);
        
        roiHandle = drawpolygon('Parent', axRoi);
        if ishandle(timerRoi)
            stop(timerRoi); delete(timerRoi);
        end
        
        if ~isvalid(roiHandle) || isempty(roiHandle.Position)
            if ishandle(figRoi), close(figRoi); end; continue;
        end
        
        roiPosition = roiHandle.Position;
        maskRoiCrop = createMask(roiHandle);
        close(figRoi);
        
        xMin = min(roiPosition(:,1)); xMax = max(roiPosition(:,1));
        yMin = min(roiPosition(:,2)); yMax = max(roiPosition(:,2));
        cropX = floor(xMin); cropY = floor(yMin);
        cropW = ceil(xMax - xMin); cropH = ceil(yMax - yMin);
        
        minDim = 60;
        if cropW < minDim, cropW = minDim; end
        if cropH < minDim, cropH = minDim; end
        imgH = size(currFrameRoi, 1); imgW = size(currFrameRoi, 2);
        cropX = max(1, min(cropX, imgW - cropW));
        cropY = max(1, min(cropY, imgH - cropH));
        cropPos = [cropX, cropY, cropW, cropH];
        
        maskRoiPolygon = imcrop(maskRoiCrop, cropPos);
        totalRoiArea   = sum(maskRoiPolygon(:)); % Total ROI pixel area
        vReader.CurrentTime = 0;
        
        % --- CONSTRUCT PIXEL-TO-METER SCALE MATRIX FOR ROI ---
        if ~isempty(calibLinesData) && length(calibLinesData) == 2
            [~, Y_grid_crop] = meshgrid(1:cropW, 1:cropH);
            Y_global = cropY + Y_grid_crop - 1;
            
            y1 = calibLinesData(1).yAvg; s1 = calibLinesData(1).scale;
            y2 = calibLinesData(2).yAvg; s2 = calibLinesData(2).scale;
            
            slope = (s2 - s1) / (y2 - y1);
            metriPerPixelMap = s1 + slope * (Y_global - y1);
            metriPerPixelMap(metriPerPixelMap <= 0) = min([s1, s2]);
        else
            metriPerPixelMap = metriPerPixel;
        end
        
        %% 5. Optical Flow Initialization (RAFT or Farneback)
        execEnv = 'cpu';
        if canUseGPU()
            execEnv = 'gpu';
            disp('GPU acceleration enabled for RAFT.');
        end
        
        if useRAFT
            flowEstimator = opticalFlowRAFT();
            try
                flowEstimator.NumIterations = maxIter;
            catch
            end
        else
            flowEstimator = opticalFlowFarneback(...
                'NumPyramidLevels', numPyramidLevels, ...
                'PyramidScale', 0.5, ...
                'NumIterations', maxIter, ...
                'NeighborhoodSize', neighborhoodSize, ...
                'FilterSize', filterSize);
        end
        
        % --- MODIFICA LAYOUT VISUALIZZAZIONE: 2x2 PER AVERE LA MAPPA PIÙ GRANDE E ZOOMATA ---
        fig = figure('Name', ternary(useRAFT, 'Flow Analysis (RAFT)', 'Flow Analysis (Farneback)'), 'WindowState', 'maximized');
        hAx1 = subplot(2, 2, 1); % Video principale con area ROI
        hAx2 = subplot(2, 2, 2); % Mappa vettoriale / campo di velocità ingrandita e zoomata sulla ROI
        hAx3 = subplot(2, 1, 2); % Grafico profilogramma di velocità
        
        title(hAx3, 'Gas velocity profile - Average: 0.00 ± 0.00 m/s');
        xlabel(hAx3, 'Time (seconds)'); ylabel(hAx3, 'Mean gas velocity (m/s)');
        grid(hAx3, 'on'); hold(hAx3, 'on');
        hLine = plot(hAx3, NaN, NaN,'Linestyle','-','marker','o', 'LineWidth', 2, 'Color', [0.85 0.325 0.098]);
        
        if hasFrame(vReader)
            framePrev = readFrame(vReader);
            framePrevSmall = imresize(framePrev, scaleFactor);
            cropPrev = imcrop(framePrevSmall, cropPos);
            
            if useRAFT
                if size(cropPrev, 3) == 1
                    cropPrevProc = cat(3, cropPrev, cropPrev, cropPrev);
                else
                    cropPrevProc = cropPrev;
                end
                estimateFlow(flowEstimator, cropPrevProc, 'ExecutionEnvironment', execEnv);
            else
                if size(cropPrev, 3) == 3
                    cropPrevProc = rgb2gray(cropPrev);
                else
                    cropPrevProc = cropPrev;
                end
                cropPrevProc = adapthisteq(cropPrevProc, 'ClipLimit', 0.03);
                estimateFlow(flowEstimator, cropPrevProc);
            end 
        end
        
        %% 6. Processing Loop (with Frame Skipping support)
        frameCount = 1;
        minCos = cosd(maxAngleDev); 
        speedHistory   = [];
        stdHistory     = [];
        maxSpeedHistory = [];
        vxHistory      = [];
        vyHistory      = [];
        sezioneHistory = [];
        timeAxis       = [];
        roiPoints = roiPosition';       
        roiPoints = roiPoints(:)'; 
        
        uX_raw_prev = [];
        uY_raw_prev = [];
        coherentStreak = [];
        dt = frameStep / fps;
        
        while hasFrame(vReader) && ishandle(fig)
            for s = 1:frameStep
                if hasFrame(vReader)
                    frameCurr = readFrame(vReader);
                    frameCount = frameCount + 1;
                end
            end
            
            frameCurrSmall = imresize(frameCurr, scaleFactor);
            cropCurr = imcrop(frameCurrSmall, cropPos);
            
            if useRAFT
                if size(cropCurr, 3) == 1
                    cropCurrProc = cat(3, cropCurr, cropCurr, cropCurr);
                else
                    cropCurrProc = cropCurr;
                end
                flow = estimateFlow(flowEstimator, cropCurrProc, 'ExecutionEnvironment', execEnv);
            else
                if size(cropCurr, 3) == 3
                    cropCurrProc = rgb2gray(cropCurr);
                else
                    cropCurrProc = cropCurr;
                end
                cropCurrProc = adapthisteq(cropCurrProc, 'ClipLimit', 0.03);
                flow = estimateFlow(flowEstimator, cropCurrProc);
            end
            
            if ~isscalar(metriPerPixelMap) && ~isequal(size(metriPerPixelMap), size(flow.Vx))
                metriPerPixelMap = imresize(metriPerPixelMap, size(flow.Vx));
            end
            
            Vx_raw = (flow.Vx / dt) .* metriPerPixelMap;
            Vy_raw = (flow.Vy / dt) .* metriPerPixelMap;
            
            if ~isequal(size(Vx_raw), size(maskRoiPolygon))
                maskRoiPolygon = imresize(maskRoiPolygon, size(Vx_raw));
                totalRoiArea   = sum(maskRoiPolygon(:));
            end
            
            Vx_raw(~maskRoiPolygon) = 0;
            Vy_raw(~maskRoiPolygon) = 0;
            
            Vx_filt = medfilt2(Vx_raw, [n n]);
            Vy_filt = medfilt2(Vy_raw, [n n]);
            
            magRaw = hypot(Vx_filt, Vy_filt);
            epsVal = 1e-6;
            uX_raw_curr = Vx_filt ./ (magRaw + epsVal);
            uY_raw_curr = Vy_filt ./ (magRaw + epsVal);
            
            if isempty(coherentStreak)
                coherentStreak = zeros(size(Vx_filt));
            end
            
            if ~isempty(uX_raw_prev)
                cosTheta = (uX_raw_curr .* uX_raw_prev) + (uY_raw_curr .* uY_raw_prev);
                isCoherentNow = cosTheta >= minCos;
                coherentStreak(isCoherentNow)  = coherentStreak(isCoherentNow) + 1;
                coherentStreak(~isCoherentNow) = 0;
            else
                coherentStreak(maskRoiPolygon) = 1;
            end
            
            uX_raw_prev = uX_raw_curr;
            uY_raw_prev = uY_raw_curr;
            
            rawValidMask = (coherentStreak >= minCoherentFrames) & maskRoiPolygon;
            
            % --- ADAPTIVE MORPHOLOGICAL FILTERING (ROI-Relative Cluster Threshold) ---
            minClusterPixels = max(5, round(totalRoiArea * minClusterRatio));
            cleanValidMask   = bwareaopen(rawValidMask, minClusterPixels);
            
            Vx_out = zeros(size(Vx_filt));
            Vy_out = zeros(size(Vy_filt));
            
            Vx_out(cleanValidMask) = Vx_filt(cleanValidMask);
            Vy_out(cleanValidMask) = Vy_filt(cleanValidMask);
            
            speedMapCrop = hypot(Vx_out, Vy_out);
            
            validGasPixels = sum(cleanValidMask(:));
            activeAreaRatio = validGasPixels / totalRoiArea;
            
            if activeAreaRatio >= minAreaRatio
                validGas = speedMapCrop(cleanValidMask);
                validVx  = Vx_out(cleanValidMask);
                validVy  = Vy_out(cleanValidMask);
                
                currSpeed    = mean(validGas, 'omitnan');
                currStd      = std(validGas, 'omitnan');
                currMaxSpeed = max(validGas, [], 'omitnan');
                currVx       = mean(validVx, 'omitnan');
                currVy       = mean(validVy, 'omitnan');
                
                % --- FLOW-ORTHOGONAL CROSS-SECTION CALCULATION ---
                [Y_act, X_act] = find(cleanValidMask);
                X_act_full = cropX + X_act - 1;
                Y_act_full = cropY + Y_act - 1;
                
                Xc = mean(X_act_full);
                Yc = mean(Y_act_full);
                
                vMag = hypot(currVx, currVy);
                if vMag > 0
                    ux = currVx / vMag;
                    uy = currVy / vMag;
                    
                    nx = -uy;
                    ny =  ux;
                    
                    proj = (X_act_full - Xc) * nx + (Y_act_full - Yc) * ny;
                    pMin = min(proj);
                    pMax = max(proj);
                    
                    xSec = Xc + [pMin, pMax] * nx;
                    ySec = Yc + [pMin, pMax] * ny;
                    lineaSezione = [xSec(:), ySec(:)];
                    
                    if isscalar(metriPerPixelMap)
                        currSezione_m = (pMax - pMin) * metriPerPixelMap;
                    else
                        currSezione_m = (pMax - pMin) * mean(metriPerPixelMap(cleanValidMask), 'omitnan');
                    end
                else
                    currSezione_m = NaN;
                    lineaSezione  = [];
                end
            else
                currSpeed     = NaN;
                currStd       = NaN;
                currMaxSpeed  = NaN;
                currVx        = NaN;
                currVy        = NaN;
                currSezione_m = NaN;
                lineaSezione  = [];
            end
            
            idxData = length(speedHistory) + 1;
            speedHistory(idxData)    = currSpeed;
            stdHistory(idxData)      = currStd;
            maxSpeedHistory(idxData) = currMaxSpeed;
            vxHistory(idxData)       = currVx;
            vyHistory(idxData)       = currVy;
            sezioneHistory(idxData)  = currSezione_m;
            timeAxis(idxData)        = (frameCount - 1) / fps;
            
            % Visualization
            if mod(idxData, drawEveryN) == 0 || ~hasFrame(vReader)
                % --- SUBPLOT 1: VIDEO GENERALE ---
                frameDisplay = insertShape(frameCurrSmall, 'FilledPolygon', roiPoints, ...
                    'Color', 'green', 'Opacity', 0.15);
                imshow(frameDisplay, 'Parent', hAx1);
                title(hAx1, 'Video (ROI: green area)');
                
                % --- SUBPLOT 2: MAPPA VETTORIALE CON SFONDO SCALA DI GRIGI ---
                fullSpeedMap = NaN(size(frameCurrSmall, 1), size(frameCurrSmall, 2));
                hCrop = size(speedMapCrop, 1);
                wCrop = size(speedMapCrop, 2);
                
                cropROI_Speed = speedMapCrop;
                cropROI_Speed(~cleanValidMask) = NaN; 
                fullSpeedMap(cropY:(cropY+hCrop-1), cropX:(cropX+wCrop-1)) = cropROI_Speed;
                
                % Preparazione dello sfondo in scala di grigi (RGB 3 canali) per evitare conflitti con la colormap
                if size(frameCurrSmall, 3) == 1
                    bgFrame = cat(3, frameCurrSmall, frameCurrSmall, frameCurrSmall);
                else
                    grayComp = rgb2gray(frameCurrSmall);
                    bgFrame = cat(3, grayComp, grayComp, grayComp);
                end
                
                cla(hAx2);
                imshow(bgFrame, 'Parent', hAx2);
                hold(hAx2, 'on');
                
                % Sovrapposizione colormap con trasparenza alpha (0.6 per mostrare il frame sottostante)
                imagesc(fullSpeedMap, 'Parent', hAx2, 'AlphaData', ~isnan(fullSpeedMap) * 0.6);
                
                colormap(hAx2, 'jet');
                c = colorbar(hAx2); c.Label.String = 'm/s';
                clim(hAx2, [0, maxColorScale]); 
                axis(hAx2, 'image');
                xlim(hAx2, [cropX, cropX + wCrop - 1]);
                ylim(hAx2, [cropY, cropY + hCrop - 1]);
                
                % DRAW ROI CONTOUR ON VECTOR MAP
                plot(hAx2, [roiPosition(:,1); roiPosition(1,1)], [roiPosition(:,2); roiPosition(1,2)], ...
                    'Color', [0 0.8 0], 'LineWidth', 1.5, 'LineStyle', '--');
                
                % DRAW FLOW-ORTHOGONAL SECTION LINE (BLACK / WHITE DASHED)
                if ~isempty(lineaSezione)
                    plot(hAx2, lineaSezione(:,1), lineaSezione(:,2), 'k-', 'LineWidth', 3.5);
                    plot(hAx2, lineaSezione(:,1), lineaSezione(:,2), 'w--', 'LineWidth', 1.0);
                end
                
                % VECTOR ARROWS
                validMask = cleanValidMask & (speedMapCrop > 0);
                
                if vel_profile == 1
                    stepPx = 20;
                    [X_grid, Y_grid] = meshgrid(1:wCrop, 1:hCrop);
                    X_full = cropX + X_grid - 1;
                    Y_full = cropY + Y_grid - 1;
                    
                    subMask = false(size(validMask));
                    subMask(1:stepPx:end, 1:stepPx:end) = true;
                    plotMask = validMask & subMask;
                    
                    if any(plotMask(:))
                        x_pts = X_full(plotMask);
                        y_pts = Y_full(plotMask);
                        vx_sub = Vx_out(plotMask);
                        vy_sub = Vy_out(plotMask);
                        mag_sub = hypot(vx_sub, vy_sub);
                        
                        base_len = 20; scale_factor_arrow = 5; %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% frecce
                        vis_len = base_len + mag_sub * scale_factor_arrow;
                        
                        dx = (vx_sub ./ mag_sub) .* vis_len;
                        dy = (vy_sub ./ mag_sub) .* vis_len;
                        
                        arrowColor = [1.00 1.00 1.00]; alphaVal = 0.70;           
                        headW = 6; headL = 10; stemW = 1.5; %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% frecce 
                        
                        for k = 1:length(x_pts)
                            x0 = x_pts(k); y0 = y_pts(k);
                            u = dx(k); v = dy(k);
                            len = hypot(u, v);
                            if len == 0, continue; end
                            
                            ux = u / len; uy = v / len;
                            px = -uy; py = ux;
                            
                            pBaseL = [x0 + px*stemW, y0 + py*stemW];
                            pBaseR = [x0 - px*stemW, y0 - py*stemW];
                            pNeck  = [x0 + ux*(len-headL), y0 + uy*(len-headL)];
                            pNeckL = [pNeck(1) + px*stemW, pNeck(2) + py*stemW];
                            pNeckR = [pNeck(1) - px*stemW, pNeck(2) - py*stemW];
                            pHeadL = [pNeck(1) + px*headW, pNeck(2) + py*headW];
                            pHeadR = [pNeck(1) - px*headW, pNeck(2) - py*headW];
                            pTip   = [x0 + u, y0 + v];
                            
                            vx_poly = [pBaseL(1), pNeckL(1), pHeadL(1), pTip(1), pHeadR(1), pNeckR(1), pBaseR(1)];
                            vy_poly = [pBaseL(2), pNeckL(2), pHeadL(2), pTip(2), pHeadR(2), pNeckR(2), pBaseR(2)];
                            
                            patch('XData', vx_poly, 'YData', vy_poly, ...
                                'FaceColor', arrowColor, 'EdgeColor', 'k', ...
                                'FaceAlpha', alphaVal, 'EdgeAlpha', alphaVal, 'Parent', hAx2);
                        end
                    end
                else
                    if any(validMask(:))
                        Vx_mean = mean(Vx_out(validMask), 'omitnan');
                        Vy_mean = mean(Vy_out(validMask), 'omitnan');
                        
                        [X_grid, Y_grid] = meshgrid(1:wCrop, 1:hCrop);
                        X_center = cropX + mean(X_grid(validMask), 'omitnan') - 1;
                        Y_center = cropY + mean(Y_grid(validMask), 'omitnan') - 1;
                        
                        magnitude = sqrt(Vx_mean^2 + Vy_mean^2);
                        if magnitude > 0
                            Vx_plot = (Vx_mean / magnitude) * 100;
                            Vy_plot = (Vy_mean / magnitude) * 100;
                        else
                            Vx_plot = 0; Vy_plot = 0;
                        end
                        
                        quiver(hAx2, X_center, Y_center, Vx_plot, Vy_plot, 0, ...
                            'Color', [0.8500 0.3250 0.0980], 'LineWidth', 2.0, 'MaxHeadSize', 4.5);
                        plot(hAx2, X_center, Y_center, 'o', 'MarkerSize', 6, ...
                            'MarkerFaceColor', [0.8500 0.3250 0.0980], 'MarkerEdgeColor', 'k');
                    end
                end
                
                hold(hAx2, 'off');
                
                if isnan(currSpeed)
                    title(hAx2, sprintf('Frame %d - Insufficient active area (< %.1f%% ROI)', frameCount, minAreaRatio*100));
                else
                    title(hAx2, sprintf('Frame %d - Vel: %.2f ± %.2f m/s (Max: %.2f m/s) | Orthogonal section: %.2f m', ...
                        frameCount, currSpeed, currStd, currMaxSpeed, currSezione_m));
                end
                
                % --- SUBPLOT 3: GRAFICO TEMPORALE ---
                set(hLine, 'XData', timeAxis, 'YData', speedHistory);
                xlim(hAx3, [0, max(timeAxis(end), 1)]);
                
                currentAvg = mean(speedHistory, 'omitnan');
                currentStd = std(speedHistory, 'omitnan');
                if isnan(currentAvg)
                    title(hAx3, 'Gas velocity profile - Average: 0.00 ± 0.00 m/s');
                else
                    title(hAx3, sprintf('Gas velocity profile - Average: %.2f ± %.2f m/s', currentAvg, currentStd));
                end
                
                drawnow limitrate;
            end
        end
        reset(flowEstimator);
        
        %% 7. AUTOMATIC DATA SAVING (CSV WITH V, Std, vel_max, Vx, Vy, Orthogonal_Section_m)
        if save_output == 1 && ~isempty(timeAxis)
            [~, nameOnly, ~] = fileparts(fileName);
            outputCsvName = fullfile(pathName, [nameOnly, ternary(useRAFT, '_RAFT.csv', '_Farneback.csv')]);
            
            Time_s         = timeAxis(:);
            Velocity_ms    = speedHistory(:);   % Scalar velocity magnitude (m/s)
            StdDev_ms      = stdHistory(:);     % Velocity standard deviation (m/s)
            vel_max        = maxSpeedHistory(:);% Maximum velocity magnitude (m/s)
            Vx_ms          = vxHistory(:);      % Horizontal component (m/s)
            Vy_ms          = -vyHistory(:);     % Vertical component (m/s) - FORCED NEGATIVE FOR CONSISTENCY
            Orthogonal_Section_m = sezioneHistory(:); % Flow-orthogonal section width in meters
            Frame          = (1:length(Time_s))';
            
            T_out = table(Frame, Time_s, Velocity_ms, StdDev_ms, vel_max, Vx_ms, Vy_ms, Orthogonal_Section_m);
            writetable(T_out, outputCsvName);
            disp(['Complete data (V, Std, vel_max, Vx, Vy, Orthogonal_Section_m) saved to: ', outputCsvName]);
        end
    end
    if ishandle(figParam), delete(figParam); end
    
    %% CALLBACKS
    function toggleFarnebackGUI(~, ~)
        isFarneback = (popRAFT.Value == 2);
        enableState = ternary(isFarneback, 'on', 'off');
        set([txtPyr, editPyrLevels, txtNeigh, editNeighSize, txtFilt, editFiltSize, pnlFarnebackGroup], ...
            'Enable', enableState);
    end
    function updateVideoFrameROI(~, ~)
        if isPlayingRoi && hasFrame(vReader) && ishandle(hImgRoi)
            currFrameRoi = imresize(readFrame(vReader), scaleFactor);
            set(hImgRoi, 'CData', currFrameRoi);
            if ishandle(sliderVideoRoi), set(sliderVideoRoi, 'Value', vReader.CurrentTime); end
        elseif isPlayingRoi && ~hasFrame(vReader)
            vReader.CurrentTime = 0;
            if ishandle(sliderVideoRoi), set(sliderVideoRoi, 'Value', 0); end
        end
    end
    function toggleVideoROI(~, ~)
        isPlayingRoi = ~isPlayingRoi;
        if isPlayingRoi
            set(btnToggleVideo, 'String', '⏸ Pause Video');
            start(timerRoi);
        else
            set(btnToggleVideo, 'String', '▶️ Play Video');
            stop(timerRoi);
        end
    end
    function sliderScrubRoi(~, ~)
        if ishandle(sliderVideoRoi)
            newTime = get(sliderVideoRoi, 'Value');
            newTime = max(0, min(newTime, vReader.Duration - 0.05));
            vReader.CurrentTime = newTime;
            if hasFrame(vReader) && ishandle(hImgRoi)
                currFrameRoi = imresize(readFrame(vReader), scaleFactor);
                set(hImgRoi, 'CData', currFrameRoi);
            end
        end
    end
    function addManualMeasurement(~, ~)
        fpsUser = str2double(editFPS.String);
        if ~isnan(fpsUser) && fpsUser > 0, fps = fpsUser; end
        
        if ishandle(figCalib), set(figCalib, 'Visible', 'off'); end
        
        figCalibFull = figure('Name', 'Scale Calibration - Frame & Line Selection', ...
            'NumberTitle', 'off', 'toolbar', 'none', 'WindowState', 'maximized');
        axCalibFull = axes('Parent', figCalibFull, 'Position', [0.05, 0.12, 0.90, 0.82]);
        
        btnToggleVideoCalib = uicontrol('Parent', figCalibFull, 'Style', 'pushbutton', 'String', '▶️ Play Video', ...
            'Position', [30, 20, 160, 40], 'FontWeight', 'bold', 'FontSize', 10, 'Callback', @toggleVideoCalib);
        
        % BARRA DI SCORRIMENTO PER LA CALIBRAZIONE
        sliderVideoCalib = uicontrol('Parent', figCalibFull, 'Style', 'slider', ...
            'Position', [200, 25, 500, 30], 'Min', 0, 'Max', max(0.1, vReader.Duration), 'Value', vReader.CurrentTime, ...
            'Callback', @sliderScrubCalib);
        
        currFrameCalib = imresize(frameIniziale, scaleFactor);
        hImgCalib = imshow(currFrameCalib, 'Parent', axCalibFull);
        
        isPlayingCalib = false;
        vReader.CurrentTime = 0;
        timerCalib = timer('ExecutionMode', 'fixedRate', 'Period', 1/fps, 'TimerFcn', @updateVideoFrameCalib);
        
        % --- LINE 1 (MANDATORY: NEAR FUMAROLA) ---
        title(axCalibFull, {'LINE 1 (Mandatory - Near Fumarola):', ...
            'Use Play/Pause video to choose frame, then click FIRST point'});
        p1 = drawpoint('Parent', axCalibFull, 'Color', 'r', 'MarkerSize', 3); pos1 = p1.Position;
        
        title(axCalibFull, {'LINE 1 (Mandatory - Near Fumarola):', 'Click SECOND point'});
        p2 = drawpoint('Parent', axCalibFull, 'Color', 'r', 'MarkerSize', 3); pos2 = p2.Position;
        
        isPlayingCalib = false;
        if ishandle(timerCalib)
            stop(timerCalib); delete(timerCalib);
        end
        
        hold(axCalibFull, 'on'); 
        line(axCalibFull, [pos1(1), pos2(1)], [pos1(2), pos2(2)], 'Color', 'r', 'LineWidth', 2); 
        hold(axCalibFull, 'off');
        
        distPx1 = norm(pos1 - pos2);
        if distPx1 < 3
            delete(p1); delete(p2); 
            if ishandle(figCalibFull), delete(figCalibFull); end
            if ishandle(figCalib), delete(figCalib); end
            return; 
        end
        
        answer1 = inputdlg(sprintf('Enter REAL length in METERS for LINE 1 (Pixels: %.1f):', distPx1), ...
            'Line 1 Real Distance', [1 50], {'1.0'});
        if isempty(answer1) || isnan(str2double(answer1{1}))
            delete(p1); delete(p2); 
            if ishandle(figCalibFull), delete(figCalibFull); end
            if ishandle(figCalib), delete(figCalib); end
            return; 
        end
        
        scale1 = str2double(answer1{1}) / distPx1;
        yAvg1  = mean([pos1(2), pos2(2)]);
        line1Struct = struct('scale', scale1, 'yAvg', yAvg1);
        
        % --- SECOND LINE OPTION ---
        choice = questdlg('Do you want to insert a SECOND line at a different distance to correct perspective?', ...
            'Second Line', 'Yes', 'No, 1 line is enough', 'No, 1 line is enough');
        
        if strcmp(choice, 'Yes')
            title(axCalibFull, {'LINE 2 (Second Distance):', 'Click FIRST point'});
            p3 = drawpoint('Parent', axCalibFull, 'Color', 'cyan', 'MarkerSize', 3); pos3 = p3.Position;
            
            title(axCalibFull, {'LINE 2 (Second Distance):', 'Click SECOND point'});
            p4 = drawpoint('Parent', axCalibFull, 'Color', 'cyan', 'MarkerSize', 3); pos4 = p4.Position;
            
            hold(axCalibFull, 'on'); 
            line(axCalibFull, [pos3(1), pos4(1)], [pos3(2), pos4(2)], 'Color', 'cyan', 'LineWidth', 2); 
            hold(axCalibFull, 'off');
            
            distPx2 = norm(pos3 - pos4);
            if distPx2 >= 3
                answer2 = inputdlg(sprintf('Enter REAL length in METERS for LINE 2 (Pixels: %.1f):', distPx2), ...
                    'Line 2 Real Distance', [1 50], {'1.0'});
                if ~isempty(answer2) && ~isnan(str2double(answer2{1}))
                    scale2 = str2double(answer2{1}) / distPx2;
                    yAvg2  = mean([pos3(2), pos4(2)]);
                    line2Struct = struct('scale', scale2, 'yAvg', yAvg2);
                    calibLinesData = [line1Struct, line2Struct];
                    metriPerPixel = scale1;
                else
                    metriPerPixel = scale1;
                    calibLinesData = [];
                end
            else
                metriPerPixel = scale1;
                calibLinesData = [];
            end
        else
            metriPerPixel = scale1;
            calibLinesData = [];
        end
        
        if ishandle(figCalibFull), delete(figCalibFull); end
        if ishandle(figCalib), delete(figCalib); end
        
        function updateVideoFrameCalib(~, ~)
            if isPlayingCalib && hasFrame(vReader) && ishandle(hImgCalib)
                currFrameCalib = imresize(readFrame(vReader), scaleFactor);
                set(hImgCalib, 'CData', currFrameCalib);
                if ishandle(sliderVideoCalib), set(sliderVideoCalib, 'Value', vReader.CurrentTime); end
            elseif isPlayingCalib && ~hasFrame(vReader)
                vReader.CurrentTime = 0;
                if ishandle(sliderVideoCalib), set(sliderVideoCalib, 'Value', 0); end
            end
        end
        function toggleVideoCalib(~, ~)
            isPlayingCalib = ~isPlayingCalib;
            if isPlayingCalib
                set(btnToggleVideoCalib, 'String', '⏸ Pause Video');
                start(timerCalib);
            else
                set(btnToggleVideoCalib, 'String', '▶️ Play Video');
                stop(timerCalib);
            end
        end
        function sliderScrubCalib(~, ~)
            if ishandle(sliderVideoCalib)
                newTime = get(sliderVideoCalib, 'Value');
                newTime = max(0, min(newTime, vReader.Duration - 0.05));
                vReader.CurrentTime = newTime;
                if hasFrame(vReader) && ishandle(hImgCalib)
                    currFrameCalib = imresize(readFrame(vReader), scaleFactor);
                    set(hImgCalib, 'CData', currFrameCalib);
                end
            end
        end
    end
    function useCameraParams(~, ~)
        fpsUser = str2double(editFPS.String);
        if ~isnan(fpsUser) && fpsUser > 0, fps = fpsUser; end
        
        distanzaInput = str2double(editDistanza.String);
        fovInput      = str2double(editFOV.String);
        widthPxInput  = str2double(editWidthPx.String);
        
        if isnan(distanzaInput) || distanzaInput <= 0 || isnan(fovInput) || fovInput <= 0 || isnan(widthPxInput) || widthPxInput <= 0
            return;
        end
        
        larghezzaScenaMetri = 2 * distanzaInput * tand(fovInput / 2);
        metriPerPixel = larghezzaScenaMetri / (widthPxInput * scaleFactor);
        calibLinesData = [];
        if ishandle(figCalib), delete(figCalib); end
    end
    function val = ternary(cond, trueVal, falseVal)
        if cond, val = trueVal; else, val = falseVal; end
    end
end