classdef SLMHologramWorkbench < handle
    %SLMHOLOGRAMWORKBENCH Guided UI for generating HOLOEYE-ready holograms.

    properties (Access = private)
        Figure
        UI struct = struct()
        TargetPath string = ""
        TargetImage double = []
        TargetDescription string = ""
        TargetParameters struct = struct()
        ReferenceMode logical = false
        PhaseComponents struct = struct("type", {}, "parameters", {}, "description", {})
        GrayHologram uint8 = uint8.empty
        Result struct = struct()
        CancelRequested logical = false
        ProgressDialog = []
        OutputFigure = []
        MonitorPositions double = zeros(0, 4)
    end

    methods
        function app = SLMHologramWorkbench()
            app.buildInterface();
            app.refreshMonitors();
            app.updateZernikeRadius();
            app.setStatus("等待输入", "请选择目标图，然后按步骤核对参数。", "neutral");
        end

        function exportScreenshot(app, filename)
            %EXPORTSCREENSHOT Export the current workbench for visual QA.
            drawnow;
            exportapp(app.Figure, filename);
        end

        function exportWorkflowScreenshots(app, folder)
            %EXPORTWORKFLOWSCREENSHOTS Export each workflow tab for visual QA.
            if ~isfolder(folder)
                mkdir(folder);
            end
            tabs = [app.UI.InputTab, app.UI.AlgorithmTab, app.UI.CalibrationTab, app.UI.OutputTab];
            names = ["01_input", "02_algorithm", "03_calibration", "04_output"];
            for index = 1:numel(tabs)
                app.UI.WorkflowTabs.SelectedTab = tabs(index);
                app.UI.HeaderHint.Text = sprintf("步骤 %d/4", index);
                drawnow;
                exportapp(app.Figure, fullfile(folder, names(index) + ".png"));
            end
        end

        function delete(app)
            app.closeOutputFigure();
            app.closeProgressDialog();
            if ~isempty(app.Figure) && isvalid(app.Figure)
                delete(app.Figure);
            end
        end
    end

    methods (Access = private)
        function buildInterface(app)
            app.Figure = uifigure( ...
                "Name", "SLM 灰度全息图工作台", ...
                "Position", [40, 40, 1440, 860], ...
                "Color", [0.95, 0.96, 0.98]);

            root = uigridlayout(app.Figure, [3, 2]);
            root.RowHeight = {78, "1x", 70};
            root.ColumnWidth = {455, "1x"};
            root.Padding = [0, 0, 0, 0];
            root.RowSpacing = 0;
            root.ColumnSpacing = 0;

            app.buildHeader(root);
            app.buildWorkflow(root);
            app.buildPreview(root);
            app.buildActionBar(root);
        end

        function buildHeader(app, parent)
            header = uipanel(parent, "BorderType", "none", "BackgroundColor", [1, 1, 1]);
            header.Layout.Row = 1;
            header.Layout.Column = [1, 2];
            grid = uigridlayout(header, [2, 3]);
            grid.RowHeight = {38, 26};
            grid.ColumnWidth = {"1x", 360, 130};
            grid.Padding = [24, 8, 22, 6];
            grid.RowSpacing = 0;

            titleLabel = uilabel(grid, "Text", "SLM 灰度全息图工作台", ...
                "FontSize", 22, "FontWeight", "bold", "FontColor", [0.08, 0.16, 0.27]);
            titleLabel.Layout.Row = 1;
            titleLabel.Layout.Column = 1;
            subtitle = uilabel(grid, "Text", "目标图 → GS/WGS/MRAF → 相位校准与补偿 → 8 位 SLM 输出", ...
                "FontSize", 11, "FontColor", [0.16, 0.42, 0.68]);
            subtitle.Layout.Row = 2;
            subtitle.Layout.Column = [1, 2];

            app.UI.HeaderHint = uilabel(grid, "Text", "步骤 1/4 · 输入与设备", ...
                "HorizontalAlignment", "right", "FontSize", 12, "FontColor", [0.28, 0.38, 0.50]);
            app.UI.HeaderHint.Layout.Row = 1;
            app.UI.HeaderHint.Layout.Column = 2;
            app.UI.StateBadge = uilabel(grid, "Text", "等待输入", ...
                "HorizontalAlignment", "center", "FontWeight", "bold", ...
                "FontColor", [0.10, 0.18, 0.28], "BackgroundColor", [0.86, 0.91, 0.97]);
            app.UI.StateBadge.Layout.Row = 1;
            app.UI.StateBadge.Layout.Column = 3;
        end

        function buildWorkflow(app, parent)
            panel = uipanel(parent, "BorderType", "none", "BackgroundColor", [0.95, 0.96, 0.98]);
            panel.Layout.Row = 2;
            panel.Layout.Column = 1;
            grid = uigridlayout(panel, [1, 1]);
            grid.Padding = [14, 14, 10, 12];

            app.UI.WorkflowTabs = uitabgroup(grid, "SelectionChangedFcn", @(~, event)app.onWorkflowTabChanged(event));
            app.UI.InputTab = uitab(app.UI.WorkflowTabs, "Title", "① 输入与设备");
            app.UI.AlgorithmTab = uitab(app.UI.WorkflowTabs, "Title", "② 算法与相位");
            app.UI.CalibrationTab = uitab(app.UI.WorkflowTabs, "Title", "③ 校准与补偿");
            app.UI.OutputTab = uitab(app.UI.WorkflowTabs, "Title", "④ 输出");

            app.buildInputTab();
            app.buildAlgorithmTab();
            app.buildCalibrationTab();
            app.buildOutputTab();
        end

        function buildInputTab(app)
            grid = uigridlayout(app.UI.InputTab, [16, 3]);
            grid.RowHeight = {24, 36, 28, 32, 16, 24, 32, 32, 32, 32, ...
                32, 32, 32, 34, "1x", 54};
            grid.ColumnWidth = {145, "1x", 94};
            grid.Padding = [14, 14, 14, 12];
            grid.ColumnSpacing = 8;
            grid.RowSpacing = 7;

            app.sectionLabel(grid, "目标图像", 1);
            app.UI.TargetField = uieditfield(grid, "text", "Editable", "off", "Value", "尚未选择目标图");
            app.place(app.UI.TargetField, 2, [1, 2]);
            chooseButton = uibutton(grid, "Text", "从文件…", ...
                "ButtonPushedFcn", @(~, ~)app.chooseTarget());
            app.place(chooseButton, 2, 3);
            app.UI.TargetInfo = uilabel(grid, "Text", "支持 PNG、BMP、JPG、TIFF", ...
                "FontColor", [0.38, 0.43, 0.50], "FontSize", 11);
            app.place(app.UI.TargetInfo, 3, [1, 2]);
            generateTarget = uibutton(grid, "Text", "自动生成…", ...
                "FontWeight", "bold", "ButtonPushedFcn", @(~, ~)app.openTargetGenerator());
            app.place(generateTarget, 3, 3);
            app.fieldLabel(grid, "基准对照", 4);
            referenceButton = uibutton(grid, "Text", "基础相位参考 · 不运行迭代算法", ...
                "FontWeight", "bold", "BackgroundColor", [0.91, 0.95, 1.00], ...
                "ButtonPushedFcn", @(~, ~)app.selectReferencePhase());
            referenceButton.Tooltip = "生成不含目标迭代、载波、透镜和像差叠加的均匀相位参考图";
            app.place(referenceButton, 4, [2, 3]);

            separator = uipanel(grid, "BorderType", "none", "BackgroundColor", [0.87, 0.89, 0.92]);
            app.place(separator, 5, [1, 3]);
            app.sectionLabel(grid, "SLM 与光学参数", 6);

            app.fieldLabel(grid, "原生分辨率 (px)", 7);
            resolutionGrid = uigridlayout(grid, [1, 3]);
            resolutionGrid.ColumnWidth = {"1x", 18, "1x"};
            resolutionGrid.Padding = [0, 0, 0, 0];
            resolutionGrid.ColumnSpacing = 3;
            app.place(resolutionGrid, 7, [2, 3]);
            app.UI.Width = uieditfield(resolutionGrid, "numeric", "Value", 1920, ...
                "Limits", [1, Inf], "RoundFractionalValues", "on", ...
                "ValueChangedFcn", @(~, ~)app.onResolutionChanged());
            timesLabel = uilabel(resolutionGrid, "Text", "×", "HorizontalAlignment", "center");
            app.UI.Height = uieditfield(resolutionGrid, "numeric", "Value", 1080, ...
                "Limits", [1, Inf], "RoundFractionalValues", "on", ...
                "ValueChangedFcn", @(~, ~)app.onResolutionChanged());
            app.UI.Width.Tooltip = "宽度";
            app.UI.Height.Tooltip = "高度";
            timesLabel.Tooltip = "宽 × 高";

            app.fieldLabel(grid, "有效加载区域", 8);
            regionModeGrid = uigridlayout(grid, [1, 2]);
            regionModeGrid.ColumnWidth = {112, "1x"};
            regionModeGrid.Padding = [0, 0, 0, 0];
            regionModeGrid.ColumnSpacing = 6;
            app.place(regionModeGrid, 8, [2, 3]);
            app.UI.ActiveRegionEnabled = uicheckbox(regionModeGrid, ...
                "Text", "限制范围", "Value", false, ...
                "ValueChangedFcn", @(~, ~)app.onActiveRegionChanged());
            app.UI.ActiveRegionShape = uidropdown(regionModeGrid, ...
                "Items", ["矩形", "椭圆"], ...
                "ItemsData", ["rectangle", "ellipse"], "Value", "rectangle");
            app.UI.ActiveRegionShape.Tooltip = "选择加载孔径的形状";

            app.fieldLabel(grid, "区域宽 × 高 (px)", 9);
            regionSizeGrid = uigridlayout(grid, [1, 3]);
            regionSizeGrid.ColumnWidth = {"1x", 18, "1x"};
            regionSizeGrid.Padding = [0, 0, 0, 0];
            regionSizeGrid.ColumnSpacing = 3;
            app.place(regionSizeGrid, 9, [2, 3]);
            app.UI.ActiveRegionWidth = uieditfield(regionSizeGrid, "numeric", ...
                "Value", 1920, "Limits", [1, Inf], "RoundFractionalValues", "on");
            uilabel(regionSizeGrid, "Text", "×", "HorizontalAlignment", "center");
            app.UI.ActiveRegionHeight = uieditfield(regionSizeGrid, "numeric", ...
                "Value", 1080, "Limits", [1, Inf], "RoundFractionalValues", "on");
            app.UI.ActiveRegionWidth.Tooltip = "有效区域宽度";
            app.UI.ActiveRegionHeight.Tooltip = "有效区域高度";

            app.fieldLabel(grid, "中心偏移 X / Y", 10);
            regionOffsetGrid = uigridlayout(grid, [1, 3]);
            regionOffsetGrid.ColumnWidth = {"1x", 18, "1x"};
            regionOffsetGrid.Padding = [0, 0, 0, 0];
            regionOffsetGrid.ColumnSpacing = 3;
            app.place(regionOffsetGrid, 10, [2, 3]);
            app.UI.ActiveRegionOffsetX = uieditfield(regionOffsetGrid, "numeric", ...
                "Value", 0, "RoundFractionalValues", "on");
            uilabel(regionOffsetGrid, "Text", "/", "HorizontalAlignment", "center");
            app.UI.ActiveRegionOffsetY = uieditfield(regionOffsetGrid, "numeric", ...
                "Value", 0, "RoundFractionalValues", "on");
            app.UI.ActiveRegionOffsetX.Tooltip = "相对 SLM 中心的水平偏移；向右为正";
            app.UI.ActiveRegionOffsetY.Tooltip = "相对 SLM 中心的垂直偏移；向下为正";
            app.onActiveRegionChanged();

            app.fieldLabel(grid, "入射波长 (nm)", 11);
            app.UI.Wavelength = uieditfield(grid, "numeric", "Value", 532, "Limits", [1, Inf]);
            app.place(app.UI.Wavelength, 11, [2, 3]);
            app.fieldLabel(grid, "像元间距 (μm)", 12);
            app.UI.PixelPitch = uieditfield(grid, "numeric", "Value", 8.0, "Limits", [eps, Inf]);
            app.place(app.UI.PixelPitch, 12, [2, 3]);

            app.fieldLabel(grid, "Zernike 半径 (px)", 13);
            app.UI.ZernikeRadius = uieditfield(grid, "numeric", "Value", 539.5, "Limits", [eps, Inf]);
            app.place(app.UI.ZernikeRadius, 13, 2);
            app.UI.AutoZernike = uicheckbox(grid, "Text", "自动", "Value", true, ...
                "ValueChangedFcn", @(~, ~)app.onAutoZernikeChanged());
            app.place(app.UI.AutoZernike, 13, 3);

            app.UI.PreserveAspect = uicheckbox(grid, "Text", "保持目标图比例并居中到黑色 SLM 画布", "Value", true);
            app.place(app.UI.PreserveAspect, 14, [1, 3]);

            note = app.infoCard(grid, ...
                "输出始终保持 SLM 原生分辨率；加载区域只限制最终有效孔径，不改变功能库的独立参数。", ...
                [0.90, 0.95, 1.00], [0.10, 0.31, 0.53]);
            app.place(note, 16, [1, 3]);
        end

        function buildAlgorithmTab(app)
            grid = uigridlayout(app.UI.AlgorithmTab, [18, 3]);
            grid.RowHeight = {24, 34, 32, 32, 32, 32, 16, 24, 32, 32, 32, 16, 24, 50, 16, 24, 32, "1x"};
            grid.ColumnWidth = {155, "1x", "1x"};
            grid.Padding = [14, 14, 14, 12];
            grid.ColumnSpacing = 8;
            grid.RowSpacing = 5;

            app.sectionLabel(grid, "GS / WGS / MRAF 计算", 1);
            app.fieldLabel(grid, "算法", 2);
            app.UI.Algorithm = uidropdown(grid, ...
                "Items", ["自动 · 多焦点 WGS / 连续目标 MRAF", "WGS · 多焦点均匀化", ...
                "MRAF · 连续图案", "GS · 标准相位恢复"], ...
                "ItemsData", ["auto", "wgs", "mraf", "gs"], "Value", "auto", ...
                "ValueChangedFcn", @(~, ~)app.onAlgorithmChanged());
            app.UI.Algorithm.Tooltip = "自动模式：离散多焦点 WGS；参数化连续环/平顶 MRAF；其余 GS";
            app.place(app.UI.Algorithm, 2, [2, 3]);
            app.fieldLabel(grid, "质量预设", 3);
            app.UI.Quality = uidropdown(grid, ...
                "Items", ["快速预览 · 30 次", "标准 · 100 次", "高质量 · 200 次", "自定义"], ...
                "ItemsData", [30, 100, 200, -1], "Value", 100, ...
                "ValueChangedFcn", @(~, ~)app.onQualityChanged());
            app.place(app.UI.Quality, 3, [2, 3]);
            app.fieldLabel(grid, "迭代次数 / 随机种子", 4);
            app.UI.Iterations = uieditfield(grid, "numeric", "Value", 100, ...
                "Limits", [1, Inf], "RoundFractionalValues", "on", ...
                "ValueChangedFcn", @(~, ~)app.onIterationChanged());
            app.place(app.UI.Iterations, 4, 2);
            app.UI.Seed = uieditfield(grid, "numeric", "Value", 42, "RoundFractionalValues", "on");
            app.UI.Seed.Tooltip = "随机种子：固定值可复现相同结果";
            app.place(app.UI.Seed, 4, 3);
            app.fieldLabel(grid, "WGS 反馈 / 积分半径", 5);
            app.UI.WGSFeedback = uieditfield(grid, "numeric", "Value", 0.8, "Limits", [eps, 1]);
            app.UI.WGSFeedback.Tooltip = "0–1；越大均匀化越强，0.6–0.9 通常更稳定";
            app.place(app.UI.WGSFeedback, 5, 2);
            app.UI.WGSRadius = uieditfield(grid, "numeric", "Value", 0, ...
                "Limits", [0, Inf]);
            app.UI.WGSRadius.Tooltip = "焦点功率积分半径（目标面像素）；0 根据焦点 σ 自动设置";
            app.place(app.UI.WGSRadius, 5, 3);
            app.fieldLabel(grid, "目标亮度 Gamma", 6);
            app.UI.TargetGamma = uieditfield(grid, "numeric", "Value", 1.0, "Limits", [eps, Inf]);
            app.place(app.UI.TargetGamma, 6, [2, 3]);

            separator1 = uipanel(grid, "BorderType", "none", "BackgroundColor", [0.87, 0.89, 0.92]);
            app.place(separator1, 7, [1, 3]);
            app.sectionLabel(grid, "常用相位项", 8);
            app.fieldLabel(grid, "载波周期 X / Y (px)", 9);
            app.UI.GratingX = uieditfield(grid, "numeric", "Value", 8, "Limits", [0, Inf]);
            app.UI.GratingX.Tooltip = "0 表示关闭 X 方向载波";
            app.place(app.UI.GratingX, 9, 2);
            app.UI.GratingY = uieditfield(grid, "numeric", "Value", 0, "Limits", [0, Inf]);
            app.UI.GratingY.Tooltip = "0 表示关闭 Y 方向载波";
            app.place(app.UI.GratingY, 9, 3);
            app.fieldLabel(grid, "Fresnel 焦距 (mm)", 10);
            app.UI.FresnelFocal = uieditfield(grid, "numeric", "Value", 0);
            app.UI.FresnelFocal.Tooltip = "0 表示关闭；正负号对应相反二次相位";
            app.place(app.UI.FresnelFocal, 10, [2, 3]);
            app.fieldLabel(grid, "相位级数 / 常相位 (rad)", 11);
            app.UI.PhaseLevels = uieditfield(grid, "numeric", "Value", 256, ...
                "Limits", [2, 256], "RoundFractionalValues", "on");
            app.place(app.UI.PhaseLevels, 11, 2);
            app.UI.PhaseOffset = uieditfield(grid, "numeric", "Value", 0);
            app.place(app.UI.PhaseOffset, 11, 3);

            separator2 = uipanel(grid, "BorderType", "none", "BackgroundColor", [0.87, 0.89, 0.92]);
            app.place(separator2, 12, [1, 3]);
            app.sectionLabel(grid, "通用光学功能库", 13);
            libraryButton = uibutton(grid, "Text", "打开功能库…", "FontWeight", "bold", ...
                "ButtonPushedFcn", @(~, ~)app.openOpticalLibrary());
            app.place(libraryButton, 14, 1);
            app.UI.OpticalSummary = uilabel(grid, "Text", "未添加额外相位元件", ...
                "WordWrap", "on", "FontSize", 10, "FontColor", [0.31, 0.37, 0.44], ...
                "BackgroundColor", [0.92, 0.96, 1.00]);
            app.place(app.UI.OpticalSummary, 14, 2);
            clearLibraryButton = uibutton(grid, "Text", "清除叠加", ...
                "ButtonPushedFcn", @(~, ~)app.clearOpticalFunctions());
            app.place(clearLibraryButton, 14, 3);

            separator3 = uipanel(grid, "BorderType", "none", "BackgroundColor", [0.87, 0.89, 0.92]);
            app.place(separator3, 15, [1, 3]);
            app.sectionLabel(grid, "快捷低阶波前修正（单位：waves）", 16);
            app.fieldLabel(grid, "倾斜 X / Y", 17);
            app.UI.TiltX = uieditfield(grid, "numeric", "Value", 0);
            app.place(app.UI.TiltX, 17, 2);
            app.UI.TiltY = uieditfield(grid, "numeric", "Value", 0);
            app.place(app.UI.TiltY, 17, 3);

            advancedGrid = uigridlayout(grid, [2, 3]);
            advancedGrid.RowHeight = {30, 30};
            advancedGrid.ColumnWidth = {155, "1x", "1x"};
            advancedGrid.Padding = [0, 0, 0, 0];
            advancedGrid.ColumnSpacing = 8;
            app.place(advancedGrid, 18, [1, 3]);
            app.fieldLabel(advancedGrid, "离焦 / 像散 0°", 1);
            app.UI.Defocus = uieditfield(advancedGrid, "numeric", "Value", 0);
            app.place(app.UI.Defocus, 1, 2);
            app.UI.Astig0 = uieditfield(advancedGrid, "numeric", "Value", 0);
            app.place(app.UI.Astig0, 1, 3);
            app.fieldLabel(advancedGrid, "像散 45°", 2);
            app.UI.Astig45 = uieditfield(advancedGrid, "numeric", "Value", 0);
            app.place(app.UI.Astig45, 2, 2);
        end

        function buildCalibrationTab(app)
            grid = uigridlayout(app.UI.CalibrationTab, [14, 3]);
            grid.RowHeight = {24, 36, 30, 72, 16, 24, 36, 30, 72, 16, 24, 36, 30, "1x"};
            grid.ColumnWidth = {"1x", 100, 108};
            grid.Padding = [14, 14, 14, 12];
            grid.ColumnSpacing = 8;
            grid.RowSpacing = 8;

            app.sectionLabel(grid, "相位—灰度标定 LUT", 1);
            app.UI.LutPath = uieditfield(grid, "text", "Editable", "off", "Value", "未加载（当前为线性映射）");
            app.place(app.UI.LutPath, 2, [1, 2]);
            lutButton = uibutton(grid, "Text", "选择 LUT…", "ButtonPushedFcn", @(~, ~)app.chooseLut());
            app.place(lutButton, 2, 3);
            clearLutButton = uibutton(grid, "Text", "恢复线性映射", "ButtonPushedFcn", @(~, ~)app.clearLut());
            app.place(clearLutButton, 3, [2, 3]);
            lutNote = app.infoCard(grid, ...
                "真实实验建议加载与当前波长、偏振和入射角一致的 phase_rad,gray CSV。线性映射主要用于软件验证。", ...
                [1.00, 0.96, 0.88], [0.48, 0.28, 0.04]);
            app.place(lutNote, 4, [1, 3]);

            separator = uipanel(grid, "BorderType", "none", "BackgroundColor", [0.87, 0.89, 0.92]);
            app.place(separator, 5, [1, 3]);
            app.sectionLabel(grid, "背景补偿相位图", 6);
            app.UI.BackgroundPath = uieditfield(grid, "text", "Editable", "off", "Value", "未加载");
            app.place(app.UI.BackgroundPath, 7, [1, 2]);
            bgButton = uibutton(grid, "Text", "选择相位图…", "ButtonPushedFcn", @(~, ~)app.chooseBackground());
            app.place(bgButton, 7, 3);
            clearBgButton = uibutton(grid, "Text", "移除补偿图", "ButtonPushedFcn", @(~, ~)app.clearBackground());
            app.place(clearBgButton, 8, 2);
            app.UI.Invert = uicheckbox(grid, "Text", "反转最终灰度", "Value", false);
            app.place(app.UI.Invert, 8, 3);
            bgNote = app.infoCard(grid, ...
                "补偿图必须与 SLM 原生分辨率完全一致，且 0–255 对应 0–2π。程序不会缩放，以保护像差标定。", ...
                [0.92, 0.97, 1.00], [0.08, 0.33, 0.53]);
            app.place(bgNote, 9, [1, 3]);
            separator2 = uipanel(grid, "BorderType", "none", "BackgroundColor", [0.87, 0.89, 0.92]);
            app.place(separator2, 10, [1, 3]);
            app.sectionLabel(grid, "实测入射光振幅（可选）", 11);
            app.UI.IlluminationPath = uieditfield(grid, "text", "Editable", "off", "Value", "未加载（均匀入射）");
            app.place(app.UI.IlluminationPath, 12, [1, 2]);
            illuminationButton = uibutton(grid, "Text", "选择振幅图…", ...
                "ButtonPushedFcn", @(~, ~)app.chooseIllumination());
            app.place(illuminationButton, 12, 3);
            clearIlluminationButton = uibutton(grid, "Text", "恢复均匀入射", ...
                "ButtonPushedFcn", @(~, ~)app.clearIllumination());
            app.place(clearIlluminationButton, 13, [2, 3]);
        end

        function buildOutputTab(app)
            grid = uigridlayout(app.UI.OutputTab, [10, 3]);
            grid.RowHeight = {24, 36, 30, 16, 24, 36, 32, 72, 70, "1x"};
            grid.ColumnWidth = {125, "1x", 90};
            grid.Padding = [14, 14, 14, 12];
            grid.ColumnSpacing = 8;
            grid.RowSpacing = 8;

            app.sectionLabel(grid, "文件输出", 1);
            app.UI.OutputDir = uieditfield(grid, "text", "Value", fullfile(pwd, "output"));
            app.place(app.UI.OutputDir, 2, [1, 2]);
            outputButton = uibutton(grid, "Text", "选择目录…", "ButtonPushedFcn", @(~, ~)app.chooseOutputDir());
            app.place(outputButton, 2, 3);
            formatLabel = uilabel(grid, "Text", "固定输出：8 位 PNG + BMP + 重建预览 + metadata.json", ...
                "FontSize", 11, "FontColor", [0.34, 0.39, 0.46]);
            app.place(formatLabel, 3, [1, 3]);

            separator = uipanel(grid, "BorderType", "none", "BackgroundColor", [0.87, 0.89, 0.92]);
            app.place(separator, 4, [1, 3]);
            app.sectionLabel(grid, "扩展桌面中的 SLM", 5);
            app.UI.Monitor = uidropdown(grid, "Items", "请选择显示器", "ItemsData", 0, "Value", 0, ...
                "ValueChangedFcn", @(~, ~)app.onMonitorChanged());
            app.place(app.UI.Monitor, 6, [1, 2]);
            refreshButton = uibutton(grid, "Text", "刷新", "ButtonPushedFcn", @(~, ~)app.refreshMonitors());
            app.place(refreshButton, 6, 3);
            app.UI.MonitorInfo = uilabel(grid, "Text", "请明确选择 SLM 对应的扩展显示器。", ...
                "FontSize", 11, "FontColor", [0.38, 0.43, 0.50]);
            app.place(app.UI.MonitorInfo, 7, [1, 3]);
            displayNote = app.infoCard(grid, ...
                "全屏显示只负责把最终灰度图放到所选屏幕。请在 Windows 中关闭缩放、色彩增强、Gamma 和屏幕保护，并确认 SLM 使用原生分辨率。", ...
                [1.00, 0.95, 0.90], [0.51, 0.22, 0.03]);
            app.place(displayNote, 8, [1, 3]);
            app.UI.OutputSummary = uilabel(grid, "Text", "尚未生成输出。", ...
                "WordWrap", "on", "FontSize", 11, "FontColor", [0.30, 0.35, 0.42]);
            app.place(app.UI.OutputSummary, 9, [1, 3]);
        end

        function buildPreview(app, parent)
            panel = uipanel(parent, "BorderType", "none", "BackgroundColor", [1, 1, 1]);
            panel.Layout.Row = 2;
            panel.Layout.Column = 2;
            grid = uigridlayout(panel, [2, 1]);
            grid.RowHeight = {"1x", 42};
            grid.Padding = [12, 14, 16, 12];
            grid.RowSpacing = 8;

            app.UI.PreviewTabs = uitabgroup(grid);
            app.UI.TargetPreviewTab = uitab(app.UI.PreviewTabs, "Title", "目标图");
            app.UI.HologramPreviewTab = uitab(app.UI.PreviewTabs, "Title", "SLM 灰度图");
            app.UI.ReconstructionPreviewTab = uitab(app.UI.PreviewTabs, "Title", "数值重建");
            app.UI.ErrorPreviewTab = uitab(app.UI.PreviewTabs, "Title", "收敛曲线");

            app.UI.TargetAxes = app.makePreviewAxes(app.UI.TargetPreviewTab, "请选择一张目标图");
            app.UI.HologramAxes = app.makePreviewAxes(app.UI.HologramPreviewTab, "生成后显示 8 位灰度全息图");
            app.UI.ReconstructionAxes = app.makePreviewAxes(app.UI.ReconstructionPreviewTab, "生成后显示傅里叶面数值重建");
            app.UI.ErrorAxes = app.makePreviewAxes(app.UI.ErrorPreviewTab, "生成后显示算法收敛曲线");

            app.UI.PreviewCaption = uilabel(grid, "Text", "预览区 · 图像始终以等比例显示", ...
                "HorizontalAlignment", "center", "FontSize", 11, ...
                "FontColor", [0.36, 0.41, 0.48], "BackgroundColor", [0.95, 0.97, 0.99]);
        end

        function buildActionBar(app, parent)
            panel = uipanel(parent, "BorderType", "none", "BackgroundColor", [0.91, 0.93, 0.96]);
            panel.Layout.Row = 3;
            panel.Layout.Column = [1, 2];
            grid = uigridlayout(panel, [2, 7]);
            grid.RowHeight = {34, 22};
            grid.ColumnWidth = {120, 150, 90, "1x", 160, 135, 135};
            grid.Padding = [16, 8, 16, 6];
            grid.ColumnSpacing = 8;
            grid.RowSpacing = 2;

            app.UI.Validate = uibutton(grid, "Text", "检查参数", ...
                "ButtonPushedFcn", @(~, ~)app.validateInputs(true));
            app.place(app.UI.Validate, 1, 1);
            app.UI.Generate = uibutton(grid, "Text", "生成全息图", "FontWeight", "bold", ...
                "FontColor", [1, 1, 1], "BackgroundColor", [0.05, 0.42, 0.75], ...
                "ButtonPushedFcn", @(~, ~)app.generate());
            app.place(app.UI.Generate, 1, 2);
            app.UI.Cancel = uibutton(grid, "Text", "取消", "Enable", "off", ...
                "ButtonPushedFcn", @(~, ~)app.requestCancel());
            app.place(app.UI.Cancel, 1, 3);
            app.UI.Display = uibutton(grid, "Text", "全屏显示到 SLM", "Enable", "off", ...
                "FontWeight", "bold", "ButtonPushedFcn", @(~, ~)app.displayOnSelectedMonitor());
            app.place(app.UI.Display, 1, 5);
            app.UI.CloseDisplay = uibutton(grid, "Text", "关闭 SLM 窗口", "Enable", "off", ...
                "ButtonPushedFcn", @(~, ~)app.closeOutputFigure());
            app.place(app.UI.CloseDisplay, 1, 6);
            openOutput = uibutton(grid, "Text", "打开输出目录", ...
                "ButtonPushedFcn", @(~, ~)app.openOutputDirectory());
            app.place(openOutput, 1, 7);

            app.UI.StatusLine = uilabel(grid, "Text", "请选择目标图，然后按步骤配置。", ...
                "FontSize", 11, "FontColor", [0.28, 0.33, 0.40]);
            app.place(app.UI.StatusLine, 2, [1, 7]);
        end

        function chooseTarget(app)
            [name, folder] = uigetfile( ...
                {'*.png;*.bmp;*.jpg;*.jpeg;*.tif;*.tiff', '图像文件'; '*.*', '所有文件'}, ...
                "选择目标图");
            if isequal(name, 0)
                return;
            end
            app.TargetPath = string(fullfile(folder, name));
            app.TargetImage = [];
            app.TargetDescription = "文件目标：" + string(name);
            app.TargetParameters = struct();
            app.setReferenceMode(false);
            app.UI.TargetField.Value = app.TargetPath;
            raw = imread(app.TargetPath);
            preview = app.previewGray(raw);
            app.showImage(app.UI.TargetAxes, preview, [0, 1]);
            app.UI.TargetInfo.Text = sprintf("%s · %d × %d px · 将适配至 %d × %d px", ...
                name, size(raw, 2), size(raw, 1), app.UI.Width.Value, app.UI.Height.Value);
            app.UI.PreviewTabs.SelectedTab = app.UI.TargetPreviewTab;
            app.setStatus("目标图已加载", "下一步：在“算法与相位”中选择质量和载波参数。", "success");
        end

        function openTargetGenerator(app)
            SLMTargetGeneratorDialog( ...
                [app.UI.Height.Value, app.UI.Width.Value], ...
                @(target, description, parameters)app.acceptGeneratedTarget(target, description, parameters));
        end

        function acceptGeneratedTarget(app, target, description, parameters)
            app.TargetImage = target;
            app.TargetPath = "";
            app.TargetDescription = string(description);
            app.TargetParameters = parameters;
            app.setReferenceMode(false);
            app.UI.TargetField.Value = "自动生成 · " + app.TargetDescription;
            algorithmHint = "";
            if isfield(parameters, "focus_centers_px") && size(parameters.focus_centers_px, 1) >= 2
                algorithmHint = " · 自动模式将使用 WGS";
            elseif isfield(parameters, "pattern_type") && ...
                    ismember(string(parameters.pattern_type), ["annulus", "disk"])
                algorithmHint = " · 自动模式将使用 MRAF";
            end
            app.UI.TargetInfo.Text = sprintf("%d × %d px · 已与当前 SLM 画布匹配%s", ...
                size(target, 2), size(target, 1), algorithmHint);
            app.showImage(app.UI.TargetAxes, target, [0, 1]);
            app.UI.PreviewTabs.SelectedTab = app.UI.TargetPreviewTab;
            app.setStatus("目标已自动生成", "可继续调整算法、相位校准和输出参数。", "success");
        end

        function selectReferencePhase(app)
            app.TargetPath = "";
            app.TargetImage = [];
            app.TargetDescription = "基础相位参考 · 无目标迭代与额外光学相位";
            app.TargetParameters = struct("pattern_type", "reference_phase");
            app.setReferenceMode(true);
            app.UI.TargetField.Value = "基础相位参考 · 跳过迭代算法";
            app.UI.TargetInfo.Text = sprintf( ...
                "%d × %d px · 保留当前相位偏置、LUT、反相和背景补偿", ...
                app.UI.Width.Value, app.UI.Height.Value);
            app.showImage(app.UI.TargetAxes, ...
                zeros(app.UI.Height.Value, app.UI.Width.Value), [0, 1]);
            title(app.UI.TargetAxes, "零相位参考（不运行迭代算法）", ...
                "FontWeight", "normal", "Color", [0.20, 0.38, 0.58]);
            app.UI.PreviewTabs.SelectedTab = app.UI.TargetPreviewTab;
            app.setStatus("已选择基础相位参考", ...
                "生成时忽略迭代算法、载波、透镜、像差和功能库叠加，仅保留设备校准链路。", ...
                "success");
        end

        function setReferenceMode(app, enabled)
            app.ReferenceMode = logical(enabled);
            algorithmControls = {app.UI.Algorithm, app.UI.Quality, app.UI.Iterations, ...
                app.UI.Seed, app.UI.WGSFeedback, app.UI.WGSRadius, app.UI.TargetGamma, ...
                app.UI.PreserveAspect, app.UI.GratingX, app.UI.GratingY, ...
                app.UI.FresnelFocal, app.UI.TiltX, app.UI.TiltY, ...
                app.UI.Defocus, app.UI.Astig0, app.UI.Astig45};
            state = app.onOff(~app.ReferenceMode);
            for index = 1:numel(algorithmControls)
                algorithmControls{index}.Enable = state;
            end
            if ~app.ReferenceMode
                app.onQualityChanged();
                app.onAlgorithmChanged();
            end
        end

        function openOpticalLibrary(app)
            config = app.configFromControls();
            SLMOpticalFunctionDialog(config, ...
                @(action, components, descriptions)app.acceptOpticalFunctions(action, components, descriptions), ...
                app.PhaseComponents);
        end

        function clearOpticalFunctions(app)
            app.PhaseComponents = struct("type", {}, "parameters", {}, "description", {});
            app.UI.OpticalSummary.Text = "未添加额外相位元件";
            app.setStatus("已清除额外相位", "后续 GS 计算将不再叠加功能库中的相位元件。", "success");
        end

        function acceptOpticalFunctions(app, action, components, descriptions)
            if action == "overlay"
                app.PhaseComponents = components;
                app.UI.OpticalSummary.Text = sprintf("将叠加 %d 个功能：%s", ...
                    numel(components), strjoin(cellstr(descriptions), " + "));
                app.setStatus("相位功能已加入", "生成全息图时会在量化与 LUT 映射前统一叠加。", "success");
                return;
            end

            try
                config = app.configFromControls();
                config.phase_components = struct("type", {}, "parameters", {}, "description", {});
                [app.GrayHologram, app.Result] = generate_slm_phase_hologram(components, config);
                app.showImage(app.UI.HologramAxes, app.GrayHologram, [0, 255]);
                app.UI.PreviewTabs.SelectedTab = app.UI.HologramPreviewTab;
                app.UI.PreviewCaption.Text = sprintf("直接相位全息图 · %d × %d px · %d 个叠加功能", ...
                    size(app.GrayHologram, 2), size(app.GrayHologram, 1), numel(components));
                app.UI.OutputSummary.Text = sprintf( ...
                    "已生成直接相位图：hologram.png/.bmp、active_region_mask.png、phase_preview.png、phase_data.mat 和 metadata.json\n输出：%s", ...
                    char(app.UI.OutputDir.Value));
                app.UI.WorkflowTabs.SelectedTab = app.UI.OutputTab;
                app.setStatus("直接相位图已生成", "已应用相位量化和当前 LUT；可预览或全屏显示到 SLM。", "success");
                app.onMonitorChanged();
            catch exception
                app.setStatus("直接相位图生成失败", exception.message, "error");
                uialert(app.Figure, exception.message, "光学功能生成失败", "Icon", "error");
            end
        end

        function chooseLut(app)
            [name, folder] = uigetfile({'*.csv', 'phase_rad,gray 标定 LUT'}, "选择相位 LUT");
            if isequal(name, 0)
                return;
            end
            path = string(fullfile(folder, name));
            try
                app.quickValidateLut(path);
                app.UI.LutPath.Value = path;
                app.UI.LutPath.UserData = path;
                app.setStatus("LUT 已加载", "生成时将按实测 phase_rad → gray 映射输出。", "success");
            catch exception
                uialert(app.Figure, exception.message, "LUT 无效");
            end
        end

        function clearLut(app)
            app.UI.LutPath.Value = "未加载（当前为线性映射）";
            app.UI.LutPath.UserData = "";
            app.setStatus("已恢复线性映射", "线性 0–2π → 0–255 仅建议用于软件验证。", "warning");
        end

        function chooseBackground(app)
            [name, folder] = uigetfile( ...
                {'*.png;*.bmp;*.tif;*.tiff', '8 位背景补偿相位图'}, ...
                "选择背景补偿相位图");
            if isequal(name, 0)
                return;
            end
            path = string(fullfile(folder, name));
            info = imfinfo(path);
            expected = [app.UI.Width.Value, app.UI.Height.Value];
            if info.Width ~= expected(1) || info.Height ~= expected(2)
                uialert(app.Figure, sprintf( ...
                    "补偿图为 %d × %d px，但当前 SLM 为 %d × %d px。请使用原生尺寸补偿图。", ...
                    info.Width, info.Height, expected(1), expected(2)), "尺寸不匹配");
                return;
            end
            app.UI.BackgroundPath.Value = path;
            app.UI.BackgroundPath.UserData = path;
            app.setStatus("补偿图已加载", "尺寸检查通过；生成时将在相位量化前叠加。", "success");
        end

        function clearBackground(app)
            app.UI.BackgroundPath.Value = "未加载";
            app.UI.BackgroundPath.UserData = "";
            app.setStatus("已移除背景补偿", "后续生成不会叠加背景相位图。", "neutral");
        end

        function chooseIllumination(app)
            [name, folder] = uigetfile( ...
                {'*.png;*.bmp;*.tif;*.tiff', '入射光振幅图'}, "选择入射光振幅图");
            if isequal(name, 0)
                return;
            end
            path = string(fullfile(folder, name));
            info = imfinfo(path);
            if info.Width ~= app.UI.Width.Value || info.Height ~= app.UI.Height.Value
                uialert(app.Figure, "入射光振幅图必须为 SLM 原生分辨率。", "尺寸不匹配");
                return;
            end
            app.UI.IlluminationPath.Value = path;
            app.UI.IlluminationPath.UserData = path;
            app.setStatus("入射光振幅图已加载", "后续优化和数值重建将使用这张原生尺寸振幅图。", "success");
        end

        function clearIllumination(app)
            app.UI.IlluminationPath.Value = "未加载（均匀入射）";
            app.UI.IlluminationPath.UserData = "";
            app.setStatus("已恢复均匀入射模型", "后续优化将假定入射光振幅均匀。", "neutral");
        end

        function chooseOutputDir(app)
            startFolder = char(app.UI.OutputDir.Value);
            if ~isfolder(startFolder)
                startFolder = pwd;
            end
            folder = uigetdir(startFolder, "选择输出目录");
            if ~isequal(folder, 0)
                app.UI.OutputDir.Value = folder;
            end
        end

        function openOutputDirectory(app)
            folder = char(app.UI.OutputDir.Value);
            if ~isfolder(folder)
                uialert(app.Figure, "输出目录尚不存在，请先生成全息图。", "目录不存在");
                return;
            end
            if ispc
                winopen(folder);
            else
                open(folder);
            end
        end

        function onResolutionChanged(app)
            app.updateZernikeRadius();
            if isfield(app.UI, "ActiveRegionEnabled") && ~app.UI.ActiveRegionEnabled.Value
                app.UI.ActiveRegionWidth.Value = app.UI.Width.Value;
                app.UI.ActiveRegionHeight.Value = app.UI.Height.Value;
                app.UI.ActiveRegionOffsetX.Value = 0;
                app.UI.ActiveRegionOffsetY.Value = 0;
            end
            if app.ReferenceMode
                app.selectReferencePhase();
            elseif ~isempty(app.TargetImage) && isfield(app.TargetParameters, "pattern_type")
                try
                    removable = intersect(fieldnames(app.TargetParameters), ...
                        {'pattern_type', 'slm_size', 'focus_centers_px'});
                    parameters = rmfield(app.TargetParameters, removable);
                    [target, description, completeParameters] = generate_slm_target( ...
                        app.TargetParameters.pattern_type, ...
                        [app.UI.Height.Value, app.UI.Width.Value], parameters);
                    app.acceptGeneratedTarget(target, description, completeParameters);
                    app.setStatus("目标已随分辨率更新", "自动生成目标已重建到新的 SLM 画布。", "success");
                catch exception
                    app.setStatus("目标参数超出新画布", exception.message, "warning");
                end
            elseif strlength(app.TargetPath) > 0 && isfile(app.TargetPath)
                rawInfo = imfinfo(app.TargetPath);
                [~, name, extension] = fileparts(app.TargetPath);
                app.UI.TargetInfo.Text = sprintf("%s%s · %d × %d px · 将适配至 %d × %d px", ...
                    name, extension, rawInfo.Width, rawInfo.Height, app.UI.Width.Value, app.UI.Height.Value);
            end
            if ~isempty(app.UI.BackgroundPath.UserData)
                app.setStatus("SLM 尺寸已改变", "请重新检查或重新加载背景补偿图。", "warning");
            end
            app.onMonitorChanged();
        end

        function onActiveRegionChanged(app)
            enabled = isfield(app.UI, "ActiveRegionEnabled") && ...
                app.UI.ActiveRegionEnabled.Value;
            state = app.onOff(enabled);
            controls = {app.UI.ActiveRegionShape, app.UI.ActiveRegionWidth, ...
                app.UI.ActiveRegionHeight, app.UI.ActiveRegionOffsetX, ...
                app.UI.ActiveRegionOffsetY};
            for index = 1:numel(controls)
                controls{index}.Enable = state;
            end
        end

        function onAutoZernikeChanged(app)
            app.UI.ZernikeRadius.Enable = app.onOff(~app.UI.AutoZernike.Value);
            app.updateZernikeRadius();
        end

        function updateZernikeRadius(app)
            if isfield(app.UI, "AutoZernike") && app.UI.AutoZernike.Value
                app.UI.ZernikeRadius.Value = max(eps, ...
                    min(app.UI.Width.Value, app.UI.Height.Value) / 2 - 0.5);
                app.UI.ZernikeRadius.Enable = "off";
            end
        end

        function onQualityChanged(app)
            if app.UI.Quality.Value > 0
                app.UI.Iterations.Value = app.UI.Quality.Value;
                app.UI.Iterations.Enable = "off";
            else
                app.UI.Iterations.Enable = "on";
            end
        end

        function onAlgorithmChanged(app)
            selected = string(app.UI.Algorithm.Value);
            enableWgs = ismember(selected, ["auto", "wgs"]);
            app.UI.WGSFeedback.Enable = app.onOff(enableWgs);
            app.UI.WGSRadius.Enable = app.onOff(enableWgs);
            if selected == "auto"
                app.setStatus("自动选择算法", ...
                    "多焦点用 WGS；连续环和平顶用 MRAF；其他图像用 GS。", "neutral");
            elseif selected == "wgs"
                app.setStatus("WGS 已启用", ...
                    "多焦点目标将反馈修正每个焦点的功率；积分半径为 0 时按焦点尺寸自动选择。", ...
                    "neutral");
            elseif selected == "mraf"
                app.setStatus("MRAF 已启用", ...
                    "只在目标信号区强制约束振幅，连续环和平顶光束可降低局部误差。", "neutral");
            else
                app.setStatus("使用标准 GS", "WGS 焦点权重反馈已关闭。", "neutral");
            end
        end

        function onIterationChanged(app)
            presets = [30, 100, 200];
            if any(app.UI.Iterations.Value == presets)
                app.UI.Quality.Value = app.UI.Iterations.Value;
                app.UI.Iterations.Enable = "off";
            else
                app.UI.Quality.Value = -1;
                app.UI.Iterations.Enable = "on";
            end
        end

        function onWorkflowTabChanged(app, event)
            tabs = [app.UI.InputTab, app.UI.AlgorithmTab, app.UI.CalibrationTab, app.UI.OutputTab];
            index = find(tabs == event.NewValue, 1);
            names = ["输入与设备", "算法与相位", "校准与补偿", "输出"];
            if ~isempty(index)
                app.UI.HeaderHint.Text = sprintf("步骤 %d/4 · %s", index, names(index));
            end
        end

        function refreshMonitors(app)
            app.MonitorPositions = get(groot, "MonitorPositions");
            count = size(app.MonitorPositions, 1);
            items = strings(1, count + 1);
            items(1) = "请选择显示器";
            for index = 1:count
                position = app.MonitorPositions(index, :);
                items(index + 1) = sprintf("显示器 %d · %d × %d", index, position(3), position(4));
            end
            app.UI.Monitor.Items = items;
            app.UI.Monitor.ItemsData = 0:count;
            app.UI.Monitor.Value = 0;
            app.onMonitorChanged();
        end

        function onMonitorChanged(app)
            monitorIndex = app.UI.Monitor.Value;
            if monitorIndex == 0
                app.UI.MonitorInfo.Text = "请明确选择 SLM 对应的扩展显示器。";
                app.UI.MonitorInfo.FontColor = [0.38, 0.43, 0.50];
                app.UI.Display.Enable = "off";
                return;
            end
            position = app.MonitorPositions(monitorIndex, :);
            matches = position(3) == app.UI.Width.Value && position(4) == app.UI.Height.Value;
            if matches
                app.UI.MonitorInfo.Text = "显示器尺寸与当前 SLM 原生分辨率一致。";
                app.UI.MonitorInfo.FontColor = [0.02, 0.43, 0.18];
            else
                app.UI.MonitorInfo.Text = sprintf( ...
                    "注意：显示器为 %d × %d，SLM 输出为 %d × %d。", ...
                    position(3), position(4), app.UI.Width.Value, app.UI.Height.Value);
                app.UI.MonitorInfo.FontColor = [0.72, 0.30, 0.02];
            end
            app.UI.Display.Enable = app.onOff(~isempty(app.GrayHologram));
        end

        function [isValid, errors, warnings] = validateInputs(app, showResult)
            errors = strings(0, 1);
            warnings = strings(0, 1);
            hasFileTarget = strlength(app.TargetPath) > 0 && isfile(app.TargetPath);
            hasGeneratedTarget = ~isempty(app.TargetImage) && ...
                isequal(size(app.TargetImage), [app.UI.Height.Value, app.UI.Width.Value]);
            if ~(hasFileTarget || hasGeneratedTarget || app.ReferenceMode)
                errors(end + 1) = "尚未选择或生成有效目标图。";
            end
            if ~app.ReferenceMode && string(app.UI.Algorithm.Value) == "wgs" && hasGeneratedTarget && ...
                    (~isfield(app.TargetParameters, "focus_centers_px") || ...
                    size(app.TargetParameters.focus_centers_px, 1) < 2)
                errors(end + 1) = "WGS 需要至少两个独立焦点；当前参数化目标应使用 GS。";
            end
            if app.UI.Width.Value < 1 || app.UI.Height.Value < 1
                errors(end + 1) = "SLM 分辨率必须为正整数。";
            end
            regionConfig = default_slm_config();
            regionConfig.slm_size = [app.UI.Height.Value, app.UI.Width.Value];
            regionConfig.active_region_enabled = app.UI.ActiveRegionEnabled.Value;
            regionConfig.active_region_shape = app.UI.ActiveRegionShape.Value;
            regionConfig.active_region_size_px = [app.UI.ActiveRegionHeight.Value, ...
                app.UI.ActiveRegionWidth.Value];
            regionConfig.active_region_offset_px = [app.UI.ActiveRegionOffsetX.Value, ...
                app.UI.ActiveRegionOffsetY.Value];
            try
                slm_active_region_mask(regionConfig);
            catch exception
                errors(end + 1) = "有效加载区域无效：" + string(exception.message);
            end
            if app.UI.ActiveRegionEnabled.Value
                warnings(end + 1) = ...
                    "相位型 SLM 的区域外仍会反射光；加工时应让入射光束或物理光阑与有效区域匹配。";
            end
            if strlength(string(app.UI.OutputDir.Value)) == 0
                errors(end + 1) = "输出目录不能为空。";
            end
            if isempty(app.UI.LutPath.UserData)
                warnings(end + 1) = "未加载实测 LUT，当前使用线性相位映射。";
            end
            if ~isempty(app.UI.IlluminationPath.UserData)
                illuminationPath = string(app.UI.IlluminationPath.UserData);
                if ~isfile(illuminationPath)
                    errors(end + 1) = "入射光振幅图已不存在。";
                else
                    info = imfinfo(illuminationPath);
                    if info.Width ~= app.UI.Width.Value || info.Height ~= app.UI.Height.Value
                        errors(end + 1) = "入射光振幅图尺寸与 SLM 分辨率不一致。";
                    end
                end
            end
            if app.ReferenceMode
                warnings(end + 1) = ...
                    "基础相位参考会跳过迭代算法、载波、透镜、像差和功能库相位。";
            end
            if ~isempty(app.UI.BackgroundPath.UserData)
                backgroundPath = string(app.UI.BackgroundPath.UserData);
                if ~isfile(backgroundPath)
                    errors(end + 1) = "背景补偿相位图已不存在。";
                else
                    info = imfinfo(backgroundPath);
                    if info.Width ~= app.UI.Width.Value || info.Height ~= app.UI.Height.Value
                        errors(end + 1) = "背景补偿图尺寸与当前 SLM 原生分辨率不一致。";
                    end
                end
            end
            if app.UI.Monitor.Value == 0
                warnings(end + 1) = "尚未选择 SLM 显示器；仍可生成并导出文件。";
            else
                position = app.MonitorPositions(app.UI.Monitor.Value, :);
                if position(3) ~= app.UI.Width.Value || position(4) ~= app.UI.Height.Value
                    warnings(end + 1) = "所选显示器尺寸与 SLM 输出尺寸不一致。";
                end
            end
            isValid = isempty(errors);

            if showResult
                if isValid
                    message = "参数检查通过。";
                    if ~isempty(warnings)
                        message = message + newline + newline + "提示：" + newline + "• " + join(warnings, newline + "• ");
                    end
                    uialert(app.Figure, message, "参数检查", "Icon", "success");
                    app.setStatus("参数可用", "可以生成全息图。", "success");
                else
                    message = "请先修正：" + newline + "• " + join(errors, newline + "• ");
                    if ~isempty(warnings)
                        message = message + newline + newline + "提示：" + newline + "• " + join(warnings, newline + "• ");
                    end
                    uialert(app.Figure, message, "参数检查未通过", "Icon", "error");
                    app.setStatus("参数有误", "请根据检查结果修正后再生成。", "error");
                end
            end
        end

        function generate(app)
            [isValid, ~, ~] = app.validateInputs(false);
            if ~isValid
                app.validateInputs(true);
                return;
            end
            if app.ReferenceMode
                app.generateReferencePhase();
                return;
            end

            app.CancelRequested = false;
            app.UI.Generate.Enable = "off";
            app.UI.Validate.Enable = "off";
            app.UI.Cancel.Enable = "on";
            app.UI.Display.Enable = "off";
            app.ProgressDialog = uiprogressdlg(app.Figure, ...
                "Title", "正在生成全息图", ...
                "Message", "初始化传播与目标约束…", ...
                "Value", 0, "Cancelable", "on", ...
                "CancelText", "取消计算");
            app.setStatus("正在计算", "可在进度窗口或底部按钮取消。", "working");
            drawnow;

            try
                config = app.configFromControls();
                if ~isempty(app.TargetImage)
                    targetInput = app.TargetImage;
                else
                    targetInput = app.TargetPath;
                end
                [app.GrayHologram, app.Result] = generate_slm_hologram(targetInput, config);
                app.showImage(app.UI.HologramAxes, app.GrayHologram, [0, 255]);
                app.showImage(app.UI.ReconstructionAxes, app.Result.reconstruction, [0, 1]);
                app.showErrorCurve(app.Result.error_history, ...
                    app.Result.spot_uniformity_history, app.Result.algorithm);
                app.UI.PreviewTabs.SelectedTab = app.UI.HologramPreviewTab;
                if app.Result.algorithm == "wgs"
                    app.UI.PreviewCaption.Text = sprintf( ...
                        "WGS 完成 · %d × %d px · 信号区 nRMSE %.3g · 焦点均匀度 %.2f%%", ...
                        size(app.GrayHologram, 2), size(app.GrayHologram, 1), ...
                        app.Result.signal_metrics.signal_nrmse, 100 * app.Result.final_spot_uniformity);
                else
                    app.UI.PreviewCaption.Text = sprintf( ...
                        "%s 完成 · %d × %d px · 信号区 nRMSE %.3g · 信号功率占比 %.1f%%", ...
                        upper(char(app.Result.algorithm)), ...
                        size(app.GrayHologram, 2), size(app.GrayHologram, 1), ...
                        app.Result.signal_metrics.signal_nrmse, ...
                        100 * app.Result.signal_metrics.signal_power_fraction);
                end
                app.UI.OutputSummary.Text = sprintf( ...
                    "已生成：hologram.png/.bmp、active_region_mask.png、target_used.png、重建预览、convergence.csv 和 metadata.json\n输出：%s", ...
                    char(app.UI.OutputDir.Value));
                app.setStatus(upper(app.Result.algorithm) + " 生成完成", ...
                    "请检查最终灰度图的数值重建、信号区误差与功率占比，再进行全屏显示。", "success");
                app.UI.WorkflowTabs.SelectedTab = app.UI.OutputTab;
            catch exception
                if strcmp(exception.identifier, "slm_hologram:Cancelled")
                    app.setStatus("计算已取消", "上一次成功导出的结果未受影响。", "warning");
                else
                    app.setStatus("生成失败", "请检查参数或输入文件。", "error");
                    uialert(app.Figure, exception.message, "生成失败", "Icon", "error");
                end
            end
            app.finishGenerationControls();
        end

        function generateReferencePhase(app)
            app.UI.Generate.Enable = "off";
            app.UI.Validate.Enable = "off";
            app.UI.Display.Enable = "off";
            app.setStatus("正在生成基础相位参考", "正在应用相位偏置、背景补偿、量化和 LUT。", "working");
            drawnow;
            try
                config = app.configFromControls();
                config.phase_components = struct("type", {}, "parameters", {}, "description", {});
                [app.GrayHologram, app.Result] = generate_slm_phase_hologram( ...
                    struct("type", {}, "parameters", {}, "description", {}), config);
                app.Result.algorithm = "reference";
                app.showImage(app.UI.HologramAxes, app.GrayHologram, [0, 255]);
                cla(app.UI.ReconstructionAxes);
                axis(app.UI.ReconstructionAxes, "image", "off");
                title(app.UI.ReconstructionAxes, "基础相位参考不包含目标重建", ...
                    "FontWeight", "normal", "Color", [0.42, 0.47, 0.54]);
                yyaxis(app.UI.ErrorAxes, "left");
                cla(app.UI.ErrorAxes);
                yyaxis(app.UI.ErrorAxes, "right");
                cla(app.UI.ErrorAxes);
                yyaxis(app.UI.ErrorAxes, "left");
                axis(app.UI.ErrorAxes, "off");
                title(app.UI.ErrorAxes, "基础相位参考不运行迭代", ...
                    "FontWeight", "normal", "Color", [0.42, 0.47, 0.54]);
                app.UI.PreviewTabs.SelectedTab = app.UI.HologramPreviewTab;
                app.UI.PreviewCaption.Text = sprintf( ...
                    "基础相位参考 · %d × %d px · 相位偏置 %.4g rad · uint8", ...
                    size(app.GrayHologram, 2), size(app.GrayHologram, 1), config.phase_offset_rad);
                app.UI.OutputSummary.Text = sprintf( ...
                    "已生成：reference_phase.png、hologram.png/.bmp、active_region_mask.png、phase_preview.png、phase_data.mat 和 metadata.json\n输出：%s", ...
                    char(app.UI.OutputDir.Value));
                app.UI.WorkflowTabs.SelectedTab = app.UI.OutputTab;
                app.setStatus("基础相位参考已生成", ...
                    "该图未经过迭代算法，也未加入载波、透镜、像差或功能库相位。", "success");
            catch exception
                app.setStatus("基础相位参考生成失败", exception.message, "error");
                uialert(app.Figure, exception.message, "参考相位生成失败", "Icon", "error");
            end
            app.finishGenerationControls();
        end

        function config = configFromControls(app)
            config = default_slm_config();
            config.slm_size = [app.UI.Height.Value, app.UI.Width.Value];
            config.active_region_enabled = app.UI.ActiveRegionEnabled.Value;
            config.active_region_shape = app.UI.ActiveRegionShape.Value;
            config.active_region_size_px = [app.UI.ActiveRegionHeight.Value, ...
                app.UI.ActiveRegionWidth.Value];
            config.active_region_offset_px = [app.UI.ActiveRegionOffsetX.Value, ...
                app.UI.ActiveRegionOffsetY.Value];
            config.wavelength_nm = app.UI.Wavelength.Value;
            config.pixel_pitch_um = app.UI.PixelPitch.Value;
            config.iterations = app.UI.Iterations.Value;
            config.random_seed = app.UI.Seed.Value;
            config.algorithm = app.UI.Algorithm.Value;
            config.wgs_feedback_strength = app.UI.WGSFeedback.Value;
            config.wgs_spot_radius_px = app.UI.WGSRadius.Value;
            config.target_gamma = app.UI.TargetGamma.Value;
            config.preserve_aspect = app.UI.PreserveAspect.Value;
            config.grating_period_x_px = app.UI.GratingX.Value;
            config.grating_period_y_px = app.UI.GratingY.Value;
            config.phase_levels = app.UI.PhaseLevels.Value;
            config.phase_offset_rad = app.UI.PhaseOffset.Value;
            config.zernike_radius_px = app.UI.ZernikeRadius.Value;
            config.tilt_x_cycles = app.UI.TiltX.Value;
            config.tilt_y_cycles = app.UI.TiltY.Value;
            config.fresnel_focal_length_mm = app.UI.FresnelFocal.Value;
            config.defocus_waves = app.UI.Defocus.Value;
            config.astigmatism_0_waves = app.UI.Astig0.Value;
            config.astigmatism_45_waves = app.UI.Astig45.Value;
            config.invert_grayscale = app.UI.Invert.Value;
            config.phase_lut_file = app.userDataOrEmpty(app.UI.LutPath);
            config.illumination_amplitude_file = app.userDataOrEmpty(app.UI.IlluminationPath);
            config.background_phase_map_file = app.userDataOrEmpty(app.UI.BackgroundPath);
            config.phase_components = app.PhaseComponents;
            config.output_dir = app.UI.OutputDir.Value;
            config.target_description = app.TargetDescription;
            config.target_parameters = app.TargetParameters;
            config.progress_callback = @(completed, total, mse, uniformity, algorithm) ...
                app.reportProgress(completed, total, mse, uniformity, algorithm);
        end

        function reportProgress(app, completed, total, mse, uniformity, algorithm)
            isWgs = string(algorithm) == "wgs";
            if isWgs && isfinite(uniformity)
                message = sprintf("WGS 迭代 %d / %d\nMSE：%.5g · 均匀度：%.2f%%", ...
                    completed, total, mse, 100 * uniformity);
                status = sprintf("WGS：%d/%d，MSE %.5g，均匀度 %.2f%%", ...
                    completed, total, mse, 100 * uniformity);
            else
                label = upper(char(string(algorithm)));
                message = sprintf("%s 迭代 %d / %d\n当前全图 MSE：%.5g", label, completed, total, mse);
                status = sprintf("%s：%d/%d，全图 MSE %.5g", label, completed, total, mse);
            end
            if ~isempty(app.ProgressDialog) && isvalid(app.ProgressDialog)
                app.ProgressDialog.Value = completed / total;
                if completed == 1 || completed == total || mod(completed, 3) == 0
                    app.ProgressDialog.Message = message;
                end
                if app.ProgressDialog.CancelRequested
                    app.CancelRequested = true;
                end
            end
            if completed == 1 || completed == total || mod(completed, 5) == 0
                app.UI.StatusLine.Text = status;
                drawnow limitrate;
            end
            if app.CancelRequested
                error("slm_hologram:Cancelled", "Generation was cancelled by the user.");
            end
        end

        function requestCancel(app)
            app.CancelRequested = true;
            app.UI.StatusLine.Text = "正在安全停止：将在当前迭代结束后取消…";
            if ~isempty(app.ProgressDialog) && isvalid(app.ProgressDialog)
                app.ProgressDialog.Message = "正在取消…";
            end
        end

        function finishGenerationControls(app)
            app.closeProgressDialog();
            app.UI.Generate.Enable = "on";
            app.UI.Validate.Enable = "on";
            app.UI.Cancel.Enable = "off";
            app.onMonitorChanged();
        end

        function closeProgressDialog(app)
            if ~isempty(app.ProgressDialog) && isvalid(app.ProgressDialog)
                close(app.ProgressDialog);
            end
            app.ProgressDialog = [];
        end

        function displayOnSelectedMonitor(app)
            if isempty(app.GrayHologram)
                uialert(app.Figure, "请先生成全息图。", "没有可显示的图像");
                return;
            end
            monitorIndex = app.UI.Monitor.Value;
            if monitorIndex == 0 || monitorIndex > size(app.MonitorPositions, 1)
                uialert(app.Figure, "请在“输出”步骤选择 SLM 对应的显示器。", "未选择显示器");
                app.UI.WorkflowTabs.SelectedTab = app.UI.OutputTab;
                return;
            end
            position = app.MonitorPositions(monitorIndex, :);
            sizeMatches = position(3) == size(app.GrayHologram, 2) && position(4) == size(app.GrayHologram, 1);
            if ~sizeMatches
                choice = uiconfirm(app.Figure, sprintf( ...
                    "所选显示器为 %d × %d，但全息图为 %d × %d。缩放会破坏像素映射。仍要继续吗？", ...
                    position(3), position(4), size(app.GrayHologram, 2), size(app.GrayHologram, 1)), ...
                    "分辨率不匹配", "Options", ["取消", "仍然显示"], ...
                    "DefaultOption", 1, "CancelOption", 1, "Icon", "warning");
                if strcmp(choice, "取消")
                    return;
                end
            end

            app.closeOutputFigure();
            app.OutputFigure = figure( ...
                "Name", "SLM 输出 · 按 ESC 关闭", "NumberTitle", "off", ...
                "MenuBar", "none", "ToolBar", "none", "Color", "black", ...
                "Units", "pixels", "Position", position, ...
                "KeyPressFcn", @(source, event)app.closeOnEscape(source, event), ...
                "CloseRequestFcn", @(source, ~)app.onOutputFigureClosed(source));
            axesHandle = axes(app.OutputFigure, "Units", "normalized", "Position", [0, 0, 1, 1]);
            image(axesHandle, app.GrayHologram);
            colormap(axesHandle, gray(256));
            clim(axesHandle, [0, 255]);
            axis(axesHandle, "image", "off");
            try
                app.OutputFigure.WindowState = "fullscreen";
            catch
            end
            app.UI.CloseDisplay.Enable = "on";
            app.setStatus("正在输出到 SLM", sprintf("显示器 %d · 按 ESC 或“关闭 SLM 窗口”停止显示。", monitorIndex), "working");
        end

        function closeOutputFigure(app)
            if ~isempty(app.OutputFigure) && isvalid(app.OutputFigure)
                output = app.OutputFigure;
                app.OutputFigure = [];
                delete(output);
            end
            if isfield(app.UI, "CloseDisplay") && isvalid(app.UI.CloseDisplay)
                app.UI.CloseDisplay.Enable = "off";
            end
        end

        function onOutputFigureClosed(app, source)
            if isvalid(source)
                delete(source);
            end
            app.OutputFigure = [];
            app.UI.CloseDisplay.Enable = "off";
            app.setStatus("SLM 输出已关闭", "全息图文件仍保留在输出目录中。", "neutral");
        end

        function closeOnEscape(app, source, event)
            if strcmp(event.Key, "escape")
                app.onOutputFigureClosed(source);
            end
        end

        function quickValidateLut(~, filename)
            tableData = readtable(filename, "VariableNamingRule", "preserve");
            required = {'phase_rad', 'gray'};
            if ~all(ismember(required, tableData.Properties.VariableNames))
                error("LUT 必须包含 phase_rad 和 gray 两列。");
            end
            phase = double(tableData.phase_rad);
            grayValues = double(tableData.gray);
            if numel(phase) < 2 || any(diff(phase) <= 0) || phase(1) > 1e-6 || ...
                    phase(end) < 2 * pi - 1e-3 || any(grayValues < 0) || ...
                    any(grayValues > 255) || any(~isfinite(grayValues)) || ...
                    ~(all(diff(grayValues) > 0) || all(diff(grayValues) < 0))
                error("LUT 相位必须从 0 严格递增覆盖到 2π，gray 必须在 0–255 严格单调。");
            end
        end

        function showImage(~, axesHandle, imageData, limits)
            cla(axesHandle);
            imagesc(axesHandle, imageData);
            axis(axesHandle, "image", "off");
            colormap(axesHandle, gray(256));
            clim(axesHandle, limits);
        end

        function showErrorCurve(app, history, uniformityHistory, algorithm)
            axis(app.UI.ErrorAxes, "on");
            yyaxis(app.UI.ErrorAxes, "left");
            cla(app.UI.ErrorAxes);
            yyaxis(app.UI.ErrorAxes, "right");
            cla(app.UI.ErrorAxes);
            yyaxis(app.UI.ErrorAxes, "left");
            legend(app.UI.ErrorAxes, "off");
            semilogy(app.UI.ErrorAxes, max(history, eps), "LineWidth", 1.6, ...
                "Color", [0.05, 0.42, 0.75], "DisplayName", "归一化 MSE");
            grid(app.UI.ErrorAxes, "on");
            xlabel(app.UI.ErrorAxes, "迭代次数");
            ylabel(app.UI.ErrorAxes, "归一化 MSE（对数）");
            if string(algorithm) == "wgs" && any(isfinite(uniformityHistory))
                yyaxis(app.UI.ErrorAxes, "right");
                plot(app.UI.ErrorAxes, 100 * uniformityHistory, "LineWidth", 1.5, ...
                    "Color", [0.05, 0.55, 0.25], "DisplayName", "焦点均匀度");
                ylim(app.UI.ErrorAxes, [0, 100]);
                ylabel(app.UI.ErrorAxes, "焦点均匀度 (%)");
                legend(app.UI.ErrorAxes, "Location", "best");
                title(app.UI.ErrorAxes, "WGS 误差与焦点均匀度");
            else
                title(app.UI.ErrorAxes, upper(string(algorithm)) + " 收敛曲线");
            end
        end

        function preview = previewGray(~, imageData)
            if isinteger(imageData)
                preview = double(imageData) ./ double(intmax(class(imageData)));
            else
                preview = double(imageData);
            end
            if ndims(preview) == 3
                preview = 0.2126 .* preview(:, :, 1) + 0.7152 .* preview(:, :, 2) + 0.0722 .* preview(:, :, 3);
            end
            preview = min(max(preview, 0), 1);
        end

        function axesHandle = makePreviewAxes(~, parent, emptyText)
            grid = uigridlayout(parent, [1, 1]);
            grid.Padding = [8, 8, 8, 8];
            axesHandle = uiaxes(grid);
            axesHandle.XTick = [];
            axesHandle.YTick = [];
            axesHandle.Color = [0.985, 0.99, 0.995];
            axis(axesHandle, "image", "off");
            colormap(axesHandle, gray(256));
            title(axesHandle, emptyText, "FontWeight", "normal", "Color", [0.42, 0.47, 0.54]);
        end

        function setStatus(app, badge, detail, kind)
            switch kind
                case "success"
                    background = [0.82, 0.95, 0.87]; foreground = [0.02, 0.37, 0.16];
                case "warning"
                    background = [1.00, 0.91, 0.72]; foreground = [0.48, 0.25, 0.02];
                case "error"
                    background = [1.00, 0.83, 0.83]; foreground = [0.61, 0.03, 0.03];
                case "working"
                    background = [0.80, 0.90, 1.00]; foreground = [0.02, 0.27, 0.56];
                otherwise
                    background = [0.86, 0.91, 0.97]; foreground = [0.10, 0.18, 0.28];
            end
            app.UI.StateBadge.Text = badge;
            app.UI.StateBadge.BackgroundColor = background;
            app.UI.StateBadge.FontColor = foreground;
            app.UI.StatusLine.Text = detail;
            app.UI.StatusLine.FontColor = foreground;
        end

        function sectionLabel(~, parent, text, row)
            label = uilabel(parent, "Text", text, "FontWeight", "bold", ...
                "FontSize", 13, "FontColor", [0.10, 0.18, 0.28]);
            label.Layout.Row = row;
            label.Layout.Column = [1, 3];
        end

        function fieldLabel(~, parent, text, row)
            label = uilabel(parent, "Text", text, "FontSize", 11, ...
                "FontColor", [0.24, 0.29, 0.36], "HorizontalAlignment", "left");
            label.Layout.Row = row;
            label.Layout.Column = 1;
        end

        function panel = infoCard(~, parent, text, background, foreground)
            panel = uipanel(parent, "BorderType", "none", "BackgroundColor", background);
            layout = uigridlayout(panel, [1, 1]);
            layout.Padding = [12, 7, 12, 7];
            uilabel(layout, "Text", text, "WordWrap", "on", ...
                "FontSize", 10, "FontColor", foreground);
        end

        function place(~, component, row, column)
            component.Layout.Row = row;
            component.Layout.Column = column;
        end

        function result = userDataOrEmpty(~, field)
            if isempty(field.UserData)
                result = "";
            else
                result = field.UserData;
            end
        end

        function result = onOff(~, value)
            if value
                result = "on";
            else
                result = "off";
            end
        end
    end
end
