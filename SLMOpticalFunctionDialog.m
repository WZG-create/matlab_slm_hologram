classdef SLMOpticalFunctionDialog < handle
    %SLMOPTICALFUNCTIONDIALOG Build and combine common SLM optical phases.

    properties (Access = private)
        Figure
        UI struct = struct()
        Config struct
        AcceptCallback function_handle
        Components struct = struct("type", {}, "parameters", {}, "description", {})
    end

    methods
        function dialog = SLMOpticalFunctionDialog(config, acceptCallback, initialComponents)
            if nargin < 3 || isempty(initialComponents)
                initialComponents = struct("type", {}, "parameters", {}, "description", {});
            end
            dialog.Config = config;
            dialog.AcceptCallback = acceptCallback;
            dialog.Components = initialComponents;
            dialog.buildInterface();
            dialog.configureSelectedType();
            if isempty(dialog.Components)
                dialog.previewCurrent();
            else
                dialog.refreshStack();
                dialog.previewStack();
            end
        end

        function exportScreenshot(dialog, filename)
            drawnow;
            exportapp(dialog.Figure, filename);
        end

        function delete(dialog)
            if ~isempty(dialog.Figure) && isvalid(dialog.Figure)
                delete(dialog.Figure);
            end
        end
    end

    methods (Access = private)
        function buildInterface(dialog)
            dialog.Figure = uifigure( ...
                "Name", "SLM 光学功能库与相位叠加", ...
                "Position", [100, 80, 1320, 760], ...
                "WindowStyle", "modal", ...
                "Color", [0.95, 0.96, 0.98]);
            root = uigridlayout(dialog.Figure, [3, 3]);
            root.RowHeight = {70, "1x", 68};
            root.ColumnWidth = {410, 285, "1x"};
            root.Padding = [0, 0, 0, 0];
            root.RowSpacing = 0;
            root.ColumnSpacing = 0;

            header = uipanel(root, "BorderType", "none", "BackgroundColor", [1, 1, 1]);
            header.Layout.Row = 1; header.Layout.Column = [1, 3];
            headerGrid = uigridlayout(header, [2, 2]);
            headerGrid.RowHeight = {36, 22};
            headerGrid.ColumnWidth = {"1x", 340};
            headerGrid.Padding = [22, 7, 22, 5];
            titleLabel = uilabel(headerGrid, "Text", "SLM 光学功能库", ...
                "FontSize", 20, "FontWeight", "bold", "FontColor", [0.08, 0.16, 0.27]);
            titleLabel.Layout.Row = 1; titleLabel.Layout.Column = 1;
            subtitle = uilabel(headerGrid, ...
                "Text", "选择功能 → 设置参数 → 加入叠加列表 → 直接导出或叠加到全息图", ...
                "FontSize", 11, "FontColor", [0.18, 0.43, 0.68]);
            subtitle.Layout.Row = 2; subtitle.Layout.Column = 1;
            sizeLabel = uilabel(headerGrid, ...
                "Text", sprintf("SLM：%d × %d px · λ %.4g nm · pitch %.4g μm", ...
                dialog.Config.slm_size(2), dialog.Config.slm_size(1), ...
                dialog.Config.wavelength_nm, dialog.Config.pixel_pitch_um), ...
                "HorizontalAlignment", "right", "FontWeight", "bold", ...
                "FontColor", [0.30, 0.36, 0.44]);
            sizeLabel.Layout.Row = 1; sizeLabel.Layout.Column = 2;

            dialog.buildFunctionPanel(root);
            dialog.buildStackPanel(root);
            dialog.buildPreviewPanel(root);
            dialog.buildFooter(root);
        end

        function buildFunctionPanel(dialog, parent)
            panel = uipanel(parent, "BorderType", "none", "BackgroundColor", [0.97, 0.98, 0.99]);
            panel.Layout.Row = 2; panel.Layout.Column = 1;
            grid = uigridlayout(panel, [11, 3]);
            grid.RowHeight = {24, 36, 32, 32, 32, 32, 32, 36, 26, "1x", 44};
            grid.ColumnWidth = {145, "1x", 92};
            grid.Padding = [16, 14, 12, 12];
            grid.RowSpacing = 7;
            grid.ColumnSpacing = 8;

            section = uilabel(grid, "Text", "选择一个光学功能", "FontSize", 13, ...
                "FontWeight", "bold", "FontColor", [0.10, 0.18, 0.28]);
            dialog.place(section, 1, [1, 3]);
            dialog.UI.Type = uidropdown(grid, ...
                "Items", [ ...
                "均匀相位", "闪耀光栅", "二值光栅", "正弦光栅", "交叉二值光栅", ...
                "Fresnel 透镜", "二值 Fresnel 透镜", "柱面 Fresnel 透镜", ...
                "轴锥 / 贝塞尔光", "二值轴锥", "涡旋相位", "同心二值环", ...
                "圆形相位孔径", "矩形相位孔径", "单缝相位", "双缝相位", ...
                "水平二分屏", "垂直二分屏", "随机相位", "随机二值相位", ...
                "14 项 Zernike 像差"], ...
                "ItemsData", [ ...
                "blank", "blazed_grating", "binary_grating", "sinusoidal_grating", "crossed_grating", ...
                "fresnel_lens", "binary_fresnel_lens", "cylindrical_lens", ...
                "axicon", "binary_axicon", "vortex", "concentric_rings", ...
                "circular_aperture", "rectangular_aperture", "single_slit", "double_slit", ...
                "split_horizontal", "split_vertical", "random_phase", "random_binary", "zernike14"], ...
                "Value", "blazed_grating", ...
                "ValueChangedFcn", @(~, ~)dialog.onTypeChanged());
            dialog.place(dialog.UI.Type, 2, [1, 3]);

            dialog.UI.ParamLabels = cell(5, 1);
            dialog.UI.ParamFields = cell(5, 1);
            for index = 1:5
                row = index + 2;
                dialog.UI.ParamLabels{index} = uilabel(grid, "Text", "—", ...
                    "FontSize", 11, "FontColor", [0.24, 0.29, 0.36]);
                dialog.place(dialog.UI.ParamLabels{index}, row, 1);
                dialog.UI.ParamFields{index} = uieditfield(grid, "numeric", "Value", 0);
                dialog.place(dialog.UI.ParamFields{index}, row, [2, 3]);
            end

            previewButton = uibutton(grid, "Text", "预览当前功能", ...
                "ButtonPushedFcn", @(~, ~)dialog.previewCurrent());
            dialog.place(previewButton, 8, [1, 2]);
            addButton = uibutton(grid, "Text", "加入叠加列表", "FontWeight", "bold", ...
                "ButtonPushedFcn", @(~, ~)dialog.addCurrent());
            dialog.place(addButton, 8, 3);

            tableTitle = uilabel(grid, "Text", "14 项像差系数（waves，仅 Zernike 模式启用）", ...
                "FontSize", 11, "FontWeight", "bold", "FontColor", [0.23, 0.29, 0.37]);
            dialog.place(tableTitle, 9, [1, 3]);
            catalog = zernike14_catalog();
            tableData = table(catalog.name_zh, catalog.formula, zeros(14, 1), ...
                VariableNames=["Aberration", "Polynomial", "CoefficientWaves"]);
            dialog.UI.ZernikeTable = uitable(grid, "Data", tableData, ...
                "ColumnEditable", [false, false, true], ...
                "ColumnName", ["像差", "多项式", "系数 (waves)"], ...
                "ColumnWidth", {112, 112, 92}, ...
                "RowName", []);
            dialog.place(dialog.UI.ZernikeTable, 10, [1, 3]);
            dialog.UI.FunctionHint = uilabel(grid, "Text", "", "WordWrap", "on", ...
                "FontSize", 10, "FontColor", [0.18, 0.39, 0.58], ...
                "BackgroundColor", [0.91, 0.96, 1.00]);
            dialog.place(dialog.UI.FunctionHint, 11, [1, 3]);
        end

        function buildStackPanel(dialog, parent)
            panel = uipanel(parent, "BorderType", "none", "BackgroundColor", [0.94, 0.95, 0.97]);
            panel.Layout.Row = 2; panel.Layout.Column = 2;
            grid = uigridlayout(panel, [6, 2]);
            grid.RowHeight = {26, "1x", 34, 34, 16, 76};
            grid.ColumnWidth = {"1x", "1x"};
            grid.Padding = [12, 14, 12, 12];
            grid.RowSpacing = 8;

            titleLabel = uilabel(grid, "Text", "相位叠加列表", "FontSize", 13, ...
                "FontWeight", "bold", "FontColor", [0.10, 0.18, 0.28]);
            dialog.place(titleLabel, 1, [1, 2]);
            dialog.UI.Stack = uilistbox(grid, "Items", "尚未添加功能", "ItemsData", 0, "Value", 0);
            dialog.place(dialog.UI.Stack, 2, [1, 2]);
            remove = uibutton(grid, "Text", "移除选中", "ButtonPushedFcn", @(~, ~)dialog.removeSelected());
            dialog.place(remove, 3, 1);
            clear = uibutton(grid, "Text", "清空列表", "ButtonPushedFcn", @(~, ~)dialog.clearStack());
            dialog.place(clear, 3, 2);
            moveUp = uibutton(grid, "Text", "上移", "ButtonPushedFcn", @(~, ~)dialog.moveSelected(-1));
            dialog.place(moveUp, 4, 1);
            moveDown = uibutton(grid, "Text", "下移", "ButtonPushedFcn", @(~, ~)dialog.moveSelected(1));
            dialog.place(moveDown, 4, 2);
            separator = uipanel(grid, "BorderType", "none", "BackgroundColor", [0.82, 0.85, 0.89]);
            dialog.place(separator, 5, [1, 2]);
            note = uilabel(grid, "Text", ...
                "相位按列表逐项相加后统一取模、量化并应用 LUT。添加顺序不改变数学结果，但会保留在元数据中。", ...
                "WordWrap", "on", "FontSize", 10, "FontColor", [0.30, 0.36, 0.44]);
            dialog.place(note, 6, [1, 2]);
        end

        function buildPreviewPanel(dialog, parent)
            panel = uipanel(parent, "BorderType", "none", "BackgroundColor", [1, 1, 1]);
            panel.Layout.Row = 2; panel.Layout.Column = 3;
            grid = uigridlayout(panel, [2, 1]);
            grid.RowHeight = {"1x", 54};
            grid.Padding = [14, 14, 18, 10];
            dialog.UI.Axes = uiaxes(grid);
            axis(dialog.UI.Axes, "image", "off");
            colormap(dialog.UI.Axes, gray(256));
            title(dialog.UI.Axes, "8 位 SLM 灰度预览", "FontWeight", "bold");
            dialog.UI.Caption = uilabel(grid, "Text", "", "HorizontalAlignment", "center", ...
                "WordWrap", "on", "FontSize", 11, "FontColor", [0.30, 0.36, 0.44], ...
                "BackgroundColor", [0.95, 0.97, 0.99]);
        end

        function buildFooter(dialog, parent)
            panel = uipanel(parent, "BorderType", "none", "BackgroundColor", [0.90, 0.92, 0.95]);
            panel.Layout.Row = 3; panel.Layout.Column = [1, 3];
            grid = uigridlayout(panel, [1, 5]);
            grid.ColumnWidth = {"1x", 110, 170, 190, 18};
            grid.Padding = [18, 12, 18, 10];
            cancel = uibutton(grid, "Text", "取消", "ButtonPushedFcn", @(~, ~)delete(dialog));
            cancel.Layout.Column = 2;
            overlay = uibutton(grid, "Text", "叠加到全息图", "FontWeight", "bold", ...
                "ButtonPushedFcn", @(~, ~)dialog.finish("overlay"));
            overlay.Layout.Column = 3;
            direct = uibutton(grid, "Text", "直接生成并导出", "FontWeight", "bold", ...
                "FontColor", [1, 1, 1], "BackgroundColor", [0.05, 0.42, 0.75], ...
                "ButtonPushedFcn", @(~, ~)dialog.finish("direct"));
            direct.Layout.Column = 4;
        end

        function onTypeChanged(dialog)
            dialog.configureSelectedType();
            dialog.previewCurrent();
        end

        function configureSelectedType(dialog)
            type = string(dialog.UI.Type.Value);
            defs = cell(0, 6);
            hint = "";
            switch type
                case "blank"
                    defs = {"phase_offset_rad", "均匀相位 (rad)", 0, -Inf, Inf, false};
                    hint = "生成整屏恒定相位，可用于灰度/相位响应检查。";
                case "blazed_grating"
                    defs = {"period_px", "周期 (px)", 16, eps, Inf, false; ...
                            "angle_deg", "方向角 (°)", 0, -Inf, Inf, false; ...
                            "diffraction_order", "目标衍射阶数 m", 1, -Inf, Inf, true; ...
                            "phase_depth_waves", "相位深度 (waves)", 1, 0, Inf, false};
                    hint = "m 为整数：m=1 是标准一级闪耀；|m| 越大偏转越大，符号决定衍射方向。相位深度通常设为 1 wave。";
                case "binary_grating"
                    defs = {"period_px", "周期 (px)", 16, eps, Inf, false; ...
                            "angle_deg", "方向角 (°)", 0, -Inf, Inf, false; ...
                            "phase_depth_waves", "高电平相位 (waves)", 0.5, 0, Inf, false; ...
                            "duty_cycle", "占空比 (0–1)", 0.5, eps, 1-eps, false};
                    hint = "默认 0.5 wave 为 0/π 二值相位光栅。";
                case "sinusoidal_grating"
                    defs = {"period_px", "周期 (px)", 16, eps, Inf, false; ...
                            "angle_deg", "方向角 (°)", 0, -Inf, Inf, false; ...
                            "phase_span_waves", "峰峰跨度 (waves)", 1, 0, Inf, false};
                    hint = "连续正弦相位调制，可用于多级衍射实验。";
                case "crossed_grating"
                    defs = {"period_px", "X/Y 周期 (px)", 16, eps, Inf, false; ...
                            "phase_depth_waves", "高电平相位 (waves)", 0.5, 0, Inf, false; ...
                            "duty_cycle", "占空比 (0–1)", 0.5, eps, 1-eps, false};
                    hint = "X/Y 二值光栅异或形成棋盘式分束图案。";
                case {"fresnel_lens", "binary_fresnel_lens"}
                    defs = {"focal_length_mm", "焦距 (mm)", 300, -Inf, Inf, false};
                    if type == "binary_fresnel_lens"
                        defs(end + 1, :) = {"phase_depth_waves", "二值高相位 (waves)", 0.5, 0, Inf, false};
                    end
                    hint = "正负焦距对应相反二次相位；计算使用主界面的波长和像元间距。";
                case "cylindrical_lens"
                    defs = {"focal_length_mm", "焦距 (mm)", 300, -Inf, Inf, false; ...
                            "orientation_deg", "柱透镜方向 (°)", 0, -Inf, Inf, false};
                    hint = "仅沿选定方向施加二次相位，用于线聚焦。";
                case "axicon"
                    defs = {"radial_period_px", "径向 2π 周期 (px)", 32, eps, Inf, false; ...
                            "vortex_charge", "拓扑荷", 0, -Inf, Inf, true};
                    hint = "径向锯齿相位产生贝塞尔型光束；非零拓扑荷可生成涡旋贝塞尔光。";
                case "binary_axicon"
                    defs = {"radial_period_px", "径向周期 (px)", 32, eps, Inf, false; ...
                            "phase_depth_waves", "高电平相位 (waves)", 0.5, 0, Inf, false};
                    hint = "二值同心环近似轴锥相位。";
                case "vortex"
                    defs = {"vortex_charge", "拓扑荷", 1, -Inf, Inf, true};
                    hint = "螺旋相位 exp(i·lθ)，拓扑荷必须为整数。";
                case "concentric_rings"
                    defs = {"ring_period_px", "径向周期 (px)", 32, eps, Inf, false; ...
                            "phase_depth_waves", "高电平相位 (waves)", 0.5, 0, Inf, false};
                    hint = "生成等周期同心二值相位环。";
                case "circular_aperture"
                    defs = {"radius_px", "孔径半径 (px)", min(dialog.Config.slm_size)/4, eps, Inf, false; ...
                            "phase_depth_waves", "孔径外相位 (waves)", 0.5, 0, Inf, false};
                    hint = "这是二值相位孔径；相位型 SLM 不等同于真实振幅遮挡。";
                case "rectangular_aperture"
                    defs = {"rect_width_px", "矩形宽度 (px)", dialog.Config.slm_size(2)/2, eps, Inf, false; ...
                            "rect_height_px", "矩形高度 (px)", dialog.Config.slm_size(1)/2, eps, Inf, false; ...
                            "phase_depth_waves", "孔径外相位 (waves)", 0.5, 0, Inf, false};
                    hint = "矩形内外使用两种相位；适用于二值相位实验。";
                case "single_slit"
                    defs = {"slit_width_px", "缝宽 (px)", 20, eps, Inf, false; ...
                            "angle_deg", "缝法线角 (°)", 0, -Inf, Inf, false; ...
                            "phase_depth_waves", "缝外相位 (waves)", 0.5, 0, Inf, false};
                    hint = "单缝区域相位为 0，缝外为指定二值相位。";
                case "double_slit"
                    defs = {"slit_width_px", "单缝宽度 (px)", 20, eps, Inf, false; ...
                            "slit_separation_px", "中心间距 (px)", 100, eps, Inf, false; ...
                            "angle_deg", "缝法线角 (°)", 0, -Inf, Inf, false; ...
                            "phase_depth_waves", "缝外相位 (waves)", 0.5, 0, Inf, false};
                    hint = "双缝中心关于画布中心对称。";
                case {"split_horizontal", "split_vertical"}
                    defs = {"phase_depth_waves", "半屏相位 (waves)", 0.5, 0, Inf, false};
                    hint = "将一半屏幕设为 0，另一半设为指定相位。";
                case "random_phase"
                    defs = {"seed", "随机种子", 42, -Inf, Inf, true; ...
                            "phase_span_waves", "随机跨度 (waves)", 1, 0, Inf, false};
                    hint = "固定种子可复现完全相同的随机相位。";
                case "random_binary"
                    defs = {"seed", "随机种子", 42, -Inf, Inf, true; ...
                            "phase_depth_waves", "高电平相位 (waves)", 0.5, 0, Inf, false};
                    hint = "以 50% 概率生成 0/指定相位。";
                case "zernike14"
                    defs = {"zernike_radius_px", "Zernike 半径 (px)", ...
                        min(dialog.Config.slm_size)/2 - 0.5, eps, Inf, false};
                    hint = "在表格中输入 14 项系数，单位为 waves；圆形 pupil 外相位置零。";
            end
            dialog.setParameterDefinitions(defs);
            dialog.UI.ZernikeTable.Enable = dialog.onOff(type == "zernike14");
            dialog.UI.FunctionHint.Text = hint;
        end

        function setParameterDefinitions(dialog, definitions)
            for index = 1:5
                label = dialog.UI.ParamLabels{index};
                field = dialog.UI.ParamFields{index};
                if index <= size(definitions, 1)
                    label.Text = definitions{index, 2};
                    label.Enable = "on";
                    field.Enable = "on";
                    field.Limits = [-Inf, Inf];
                    field.Value = definitions{index, 3};
                    field.Limits = [definitions{index, 4}, definitions{index, 5}];
                    field.RoundFractionalValues = dialog.onOff(definitions{index, 6});
                    field.UserData = definitions{index, 1};
                else
                    label.Text = "—";
                    label.Enable = "off";
                    field.Enable = "off";
                    field.Limits = [-Inf, Inf];
                    field.Value = 0;
                    field.UserData = "";
                end
            end
        end

        function parameters = parametersFromControls(dialog)
            parameters = struct();
            for index = 1:5
                field = dialog.UI.ParamFields{index};
                key = string(field.UserData);
                if strlength(key) > 0
                    parameters.(key) = field.Value;
                end
            end
            if string(dialog.UI.Type.Value) == "zernike14"
                data = dialog.UI.ZernikeTable.Data;
                parameters.zernike_coefficients_waves = data{:, 3};
            end
        end

        function [entry, gray] = buildCurrent(dialog)
            type = string(dialog.UI.Type.Value);
            parameters = dialog.parametersFromControls();
            [phase, description, completeParameters] = generate_phase_component(type, dialog.Config, parameters);
            [gray, ~] = phase_to_slm_gray(mod(phase, 2*pi), dialog.Config);
            entry = struct("type", char(type), "parameters", completeParameters, ...
                "description", char(string(description)));
        end

        function previewCurrent(dialog)
            try
                [entry, gray] = dialog.buildCurrent();
                dialog.showGray(gray);
                dialog.UI.Caption.Text = "当前功能预览 · " + string(entry.description);
                dialog.UI.Caption.FontColor = [0.05, 0.38, 0.18];
            catch exception
                dialog.UI.Caption.Text = "参数无效：" + string(exception.message);
                dialog.UI.Caption.FontColor = [0.65, 0.04, 0.04];
            end
        end

        function addCurrent(dialog)
            try
                [entry, ~] = dialog.buildCurrent();
                dialog.Components(end + 1) = entry;
                dialog.refreshStack();
                dialog.previewStack();
            catch exception
                uialert(dialog.Figure, exception.message, "无法添加功能", "Icon", "error");
            end
        end

        function refreshStack(dialog)
            if isempty(dialog.Components)
                dialog.UI.Stack.Items = "尚未添加功能";
                dialog.UI.Stack.ItemsData = 0;
                dialog.UI.Stack.Value = 0;
                return;
            end
            items = strings(1, numel(dialog.Components));
            for index = 1:numel(dialog.Components)
                items(index) = sprintf("%02d · %s", index, dialog.Components(index).description);
            end
            dialog.UI.Stack.Items = items;
            dialog.UI.Stack.ItemsData = 1:numel(dialog.Components);
            dialog.UI.Stack.Value = numel(dialog.Components);
        end

        function previewStack(dialog)
            if isempty(dialog.Components)
                dialog.previewCurrent();
                return;
            end
            [phase, descriptions, ~] = compose_slm_phase_components(dialog.Components, dialog.Config);
            [gray, ~] = phase_to_slm_gray(phase, dialog.Config);
            dialog.showGray(gray);
            dialog.UI.Caption.Text = sprintf("叠加预览 · %d 个功能\n%s", ...
                numel(dialog.Components), strjoin(cellstr(descriptions), " + "));
            dialog.UI.Caption.FontColor = [0.05, 0.38, 0.18];
        end

        function removeSelected(dialog)
            index = dialog.UI.Stack.Value;
            if isempty(dialog.Components) || index < 1
                return;
            end
            dialog.Components(index) = [];
            dialog.refreshStack();
            dialog.previewStack();
        end

        function clearStack(dialog)
            dialog.Components = struct("type", {}, "parameters", {}, "description", {});
            dialog.refreshStack();
            dialog.previewCurrent();
        end

        function moveSelected(dialog, offset)
            index = dialog.UI.Stack.Value;
            newIndex = index + offset;
            if isempty(dialog.Components) || index < 1 || newIndex < 1 || newIndex > numel(dialog.Components)
                return;
            end
            temporary = dialog.Components(index);
            dialog.Components(index) = dialog.Components(newIndex);
            dialog.Components(newIndex) = temporary;
            dialog.refreshStack();
            dialog.UI.Stack.Value = newIndex;
            dialog.previewStack();
        end

        function finish(dialog, action)
            if isempty(dialog.Components)
                dialog.addCurrent();
            end
            if isempty(dialog.Components)
                return;
            end
            descriptions = string({dialog.Components.description});
            dialog.AcceptCallback(action, dialog.Components, descriptions);
            delete(dialog);
        end

        function showGray(dialog, grayImage)
            imagesc(dialog.UI.Axes, grayImage);
            axis(dialog.UI.Axes, "image", "off");
            colormap(dialog.UI.Axes, gray(256));
            clim(dialog.UI.Axes, [0, 255]);
            title(dialog.UI.Axes, "8 位 SLM 灰度预览", "FontWeight", "bold");
        end

        function place(~, component, row, column)
            component.Layout.Row = row;
            component.Layout.Column = column;
        end

        function value = onOff(~, enabled)
            if enabled
                value = "on";
            else
                value = "off";
            end
        end
    end
end
