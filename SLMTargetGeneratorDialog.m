classdef SLMTargetGeneratorDialog < handle
    %SLMTARGETGENERATORDIALOG Parameter editor and preview for target patterns.

    properties (Access = private)
        Figure
        UI struct = struct()
        SLMSize double
        AcceptCallback function_handle
        CurrentTarget double = []
        CurrentDescription string = ""
        CurrentParameters struct = struct()
    end

    methods
        function dialog = SLMTargetGeneratorDialog(slmSize, acceptCallback)
            dialog.SLMSize = slmSize;
            dialog.AcceptCallback = acceptCallback;
            dialog.buildInterface();
            dialog.updateEnabledFields();
            dialog.refreshPreview();
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
                "Name", "自动生成目标图", ...
                "Position", [220, 130, 980, 650], ...
                "WindowStyle", "modal", ...
                "Color", [0.95, 0.96, 0.98]);
            root = uigridlayout(dialog.Figure, [3, 2]);
            root.RowHeight = {68, "1x", 62};
            root.ColumnWidth = {390, "1x"};
            root.Padding = [0, 0, 0, 0];
            root.RowSpacing = 0;
            root.ColumnSpacing = 0;

            header = uipanel(root, "BorderType", "none", "BackgroundColor", [1, 1, 1]);
            header.Layout.Row = 1;
            header.Layout.Column = [1, 2];
            headerGrid = uigridlayout(header, [2, 2]);
            headerGrid.RowHeight = {34, 22};
            headerGrid.ColumnWidth = {"1x", 220};
            headerGrid.Padding = [20, 7, 20, 5];
            titleLabel = uilabel(headerGrid, "Text", "参数化目标图生成器", ...
                "FontSize", 19, "FontWeight", "bold", "FontColor", [0.08, 0.16, 0.27]);
            titleLabel.Layout.Row = 1; titleLabel.Layout.Column = 1;
            subtitle = uilabel(headerGrid, "Text", "生成结果直接作为 GS/IFTA 的目标强度", ...
                "FontSize", 11, "FontColor", [0.18, 0.43, 0.68]);
            subtitle.Layout.Row = 2; subtitle.Layout.Column = 1;
            sizeLabel = uilabel(headerGrid, ...
                "Text", sprintf("画布：%d × %d px", dialog.SLMSize(2), dialog.SLMSize(1)), ...
                "HorizontalAlignment", "right", "FontWeight", "bold", ...
                "FontColor", [0.30, 0.36, 0.44]);
            sizeLabel.Layout.Row = 1; sizeLabel.Layout.Column = 2;

            settingsPanel = uipanel(root, "BorderType", "none", "BackgroundColor", [0.97, 0.98, 0.99]);
            settingsPanel.Layout.Row = 2; settingsPanel.Layout.Column = 1;
            grid = uigridlayout(settingsPanel, [11, 3]);
            grid.RowHeight = {26, 34, 34, 34, 34, 34, 34, 34, 34, 44, "1x"};
            grid.ColumnWidth = {145, "1x", "1x"};
            grid.Padding = [18, 14, 14, 12];
            grid.RowSpacing = 8;
            grid.ColumnSpacing = 8;

            section = uilabel(grid, "Text", "目标类型与几何参数", "FontSize", 13, ...
                "FontWeight", "bold", "FontColor", [0.10, 0.18, 0.28]);
            section.Layout.Row = 1; section.Layout.Column = [1, 3];

            dialog.UI.TypeLabel = dialog.fieldLabel(grid, "目标类型", 2);
            dialog.UI.Type = uidropdown(grid, ...
                "Items", ["二维多焦点阵列", "环形多焦点阵列", "单高斯光斑", "连续环形光束", "圆形平顶光斑"], ...
                "ItemsData", ["grid", "ring_spots", "gaussian", "annulus", "disk"], ...
                "Value", "grid", "ValueChangedFcn", @(~, ~)dialog.onTypeChanged());
            dialog.place(dialog.UI.Type, 2, [2, 3]);

            dialog.UI.GridSizeLabel = dialog.fieldLabel(grid, "阵列行数 / 列数", 3);
            dialog.UI.Rows = uieditfield(grid, "numeric", "Value", 5, ...
                "Limits", [1, Inf], "RoundFractionalValues", "on");
            dialog.place(dialog.UI.Rows, 3, 2);
            dialog.UI.Columns = uieditfield(grid, "numeric", "Value", 5, ...
                "Limits", [1, Inf], "RoundFractionalValues", "on");
            dialog.place(dialog.UI.Columns, 3, 3);

            dialog.UI.SpacingLabel = dialog.fieldLabel(grid, "间距 X / Y (px)", 4);
            dialog.UI.SpacingX = uieditfield(grid, "numeric", "Value", 80, "Limits", [eps, Inf]);
            dialog.place(dialog.UI.SpacingX, 4, 2);
            dialog.UI.SpacingY = uieditfield(grid, "numeric", "Value", 80, "Limits", [eps, Inf]);
            dialog.place(dialog.UI.SpacingY, 4, 3);

            dialog.UI.CountLabel = dialog.fieldLabel(grid, "环上焦点数量", 5);
            dialog.UI.Count = uieditfield(grid, "numeric", "Value", 12, ...
                "Limits", [1, Inf], "RoundFractionalValues", "on");
            dialog.place(dialog.UI.Count, 5, [2, 3]);

            dialog.UI.SigmaLabel = dialog.fieldLabel(grid, "焦点 σ (px)", 6);
            dialog.UI.Sigma = uieditfield(grid, "numeric", "Value", 5, "Limits", [eps, Inf]);
            dialog.place(dialog.UI.Sigma, 6, [2, 3]);

            dialog.UI.RadiusLabel = dialog.fieldLabel(grid, "环半径 (px)", 7);
            dialog.UI.Radius = uieditfield(grid, "numeric", "Value", 220, "Limits", [eps, Inf]);
            dialog.place(dialog.UI.Radius, 7, [2, 3]);

            dialog.UI.WidthLabel = dialog.fieldLabel(grid, "环宽 σ (px)", 8);
            dialog.UI.RingWidth = uieditfield(grid, "numeric", "Value", 12, "Limits", [eps, Inf]);
            dialog.place(dialog.UI.RingWidth, 8, [2, 3]);

            dialog.UI.DiskLabel = dialog.fieldLabel(grid, "平顶半径 / 边缘 (px)", 9);
            dialog.UI.DiskRadius = uieditfield(grid, "numeric", "Value", 180, "Limits", [eps, Inf]);
            dialog.place(dialog.UI.DiskRadius, 9, 2);
            dialog.UI.EdgeWidth = uieditfield(grid, "numeric", "Value", 2, "Limits", [0, Inf]);
            dialog.place(dialog.UI.EdgeWidth, 9, 3);

            dialog.UI.RotationLabel = dialog.fieldLabel(grid, "旋转角 (°)", 10);
            dialog.UI.Rotation = uieditfield(grid, "numeric", "Value", 0);
            dialog.place(dialog.UI.Rotation, 10, 2);
            refresh = uibutton(grid, "Text", "更新预览", "ButtonPushedFcn", @(~, ~)dialog.refreshPreview());
            dialog.place(refresh, 10, 3);

            dialog.UI.Help = uilabel(grid, "Text", "多焦点阵列中的每个点具有相同峰值和 σ；间距与半径均使用目标平面的像素单位。", ...
                "WordWrap", "on", "FontSize", 10, "FontColor", [0.20, 0.37, 0.55]);
            dialog.place(dialog.UI.Help, 11, [1, 3]);

            previewPanel = uipanel(root, "BorderType", "none", "BackgroundColor", [1, 1, 1]);
            previewPanel.Layout.Row = 2; previewPanel.Layout.Column = 2;
            previewGrid = uigridlayout(previewPanel, [2, 1]);
            previewGrid.RowHeight = {"1x", 48};
            previewGrid.Padding = [14, 14, 18, 10];
            dialog.UI.Axes = uiaxes(previewGrid);
            axis(dialog.UI.Axes, "image", "off");
            colormap(dialog.UI.Axes, gray(256));
            title(dialog.UI.Axes, "目标强度预览", "FontWeight", "bold");
            dialog.UI.Caption = uilabel(previewGrid, "Text", "", ...
                "HorizontalAlignment", "center", "WordWrap", "on", ...
                "FontSize", 11, "FontColor", [0.30, 0.36, 0.44], ...
                "BackgroundColor", [0.95, 0.97, 0.99]);

            footer = uipanel(root, "BorderType", "none", "BackgroundColor", [0.91, 0.93, 0.96]);
            footer.Layout.Row = 3; footer.Layout.Column = [1, 2];
            footerGrid = uigridlayout(footer, [1, 4]);
            footerGrid.ColumnWidth = {"1x", 120, 150, 18};
            footerGrid.Padding = [18, 11, 18, 10];
            cancel = uibutton(footerGrid, "Text", "取消", "ButtonPushedFcn", @(~, ~)delete(dialog));
            cancel.Layout.Column = 2;
            accept = uibutton(footerGrid, "Text", "使用此目标", ...
                "FontWeight", "bold", "FontColor", [1, 1, 1], ...
                "BackgroundColor", [0.05, 0.42, 0.75], ...
                "ButtonPushedFcn", @(~, ~)dialog.accept());
            accept.Layout.Column = 3;
        end

        function onTypeChanged(dialog)
            dialog.updateEnabledFields();
            dialog.refreshPreview();
        end

        function updateEnabledFields(dialog)
            type = string(dialog.UI.Type.Value);
            dialog.setEnabled([dialog.UI.Rows, dialog.UI.Columns], type == "grid");
            dialog.UI.GridSizeLabel.Enable = dialog.onOff(type == "grid");
            dialog.setEnabled([dialog.UI.SpacingX, dialog.UI.SpacingY], type == "grid");
            dialog.UI.SpacingLabel.Enable = dialog.onOff(type == "grid");
            dialog.UI.Count.Enable = dialog.onOff(type == "ring_spots");
            dialog.UI.CountLabel.Enable = dialog.onOff(type == "ring_spots");

            usesSpot = ismember(type, ["grid", "ring_spots", "gaussian"]);
            dialog.UI.Sigma.Enable = dialog.onOff(usesSpot);
            dialog.UI.SigmaLabel.Enable = dialog.onOff(usesSpot);
            usesRadius = ismember(type, ["ring_spots", "annulus"]);
            dialog.UI.Radius.Enable = dialog.onOff(usesRadius);
            dialog.UI.RadiusLabel.Enable = dialog.onOff(usesRadius);
            dialog.UI.RingWidth.Enable = dialog.onOff(type == "annulus");
            dialog.UI.WidthLabel.Enable = dialog.onOff(type == "annulus");
            usesDisk = type == "disk";
            dialog.setEnabled([dialog.UI.DiskRadius, dialog.UI.EdgeWidth], usesDisk);
            dialog.UI.DiskLabel.Enable = dialog.onOff(usesDisk);
            usesRotation = ismember(type, ["grid", "ring_spots"]);
            dialog.UI.Rotation.Enable = dialog.onOff(usesRotation);
            dialog.UI.RotationLabel.Enable = dialog.onOff(usesRotation);

            switch type
                case "grid"
                    dialog.UI.Help.Text = "二维阵列以画布中心为原点；行列可分别设定，旋转不会改变焦点间距。";
                case "ring_spots"
                    dialog.UI.Help.Text = "焦点均匀分布在圆周上；旋转角控制第一个焦点的起始方位。";
                case "gaussian"
                    dialog.UI.Help.Text = "生成位于画布中心的单个高斯目标，σ 控制焦点宽度。";
                case "annulus"
                    dialog.UI.Help.Text = "生成连续高斯环；环半径决定位置，环宽 σ 决定径向厚度。";
                case "disk"
                    dialog.UI.Help.Text = "生成圆形平顶目标；边缘宽度为 0 时是硬边缘，大于 0 时为平滑边缘。";
            end
        end

        function refreshPreview(dialog)
            try
                parameters = dialog.parametersFromControls();
                [target, description, completeParameters] = generate_slm_target( ...
                    dialog.UI.Type.Value, dialog.SLMSize, parameters);
                dialog.CurrentTarget = target;
                dialog.CurrentDescription = description;
                dialog.CurrentParameters = completeParameters;
                imagesc(dialog.UI.Axes, target);
                axis(dialog.UI.Axes, "image", "off");
                colormap(dialog.UI.Axes, gray(256));
                clim(dialog.UI.Axes, [0, 1]);
                title(dialog.UI.Axes, "目标强度预览", "FontWeight", "bold");
                dialog.UI.Caption.Text = description;
                dialog.UI.Caption.FontColor = [0.05, 0.38, 0.18];
            catch exception
                dialog.CurrentTarget = [];
                dialog.UI.Caption.Text = "参数无效：" + string(exception.message);
                dialog.UI.Caption.FontColor = [0.65, 0.04, 0.04];
            end
        end

        function accept(dialog)
            dialog.refreshPreview();
            if isempty(dialog.CurrentTarget)
                uialert(dialog.Figure, "当前参数不能生成有效目标图，请先修正。", "目标无效", "Icon", "error");
                return;
            end
            dialog.AcceptCallback(dialog.CurrentTarget, dialog.CurrentDescription, dialog.CurrentParameters);
            delete(dialog);
        end

        function parameters = parametersFromControls(dialog)
            parameters = struct();
            parameters.rows = dialog.UI.Rows.Value;
            parameters.columns = dialog.UI.Columns.Value;
            parameters.spacing_x_px = dialog.UI.SpacingX.Value;
            parameters.spacing_y_px = dialog.UI.SpacingY.Value;
            parameters.spot_count = dialog.UI.Count.Value;
            parameters.spot_sigma_px = dialog.UI.Sigma.Value;
            parameters.ring_radius_px = dialog.UI.Radius.Value;
            parameters.ring_width_px = dialog.UI.RingWidth.Value;
            parameters.disk_radius_px = dialog.UI.DiskRadius.Value;
            parameters.edge_width_px = dialog.UI.EdgeWidth.Value;
            parameters.rotation_deg = dialog.UI.Rotation.Value;
        end

        function label = fieldLabel(~, parent, text, row)
            label = uilabel(parent, "Text", text, "FontSize", 11, ...
                "FontColor", [0.24, 0.29, 0.36]);
            label.Layout.Row = row;
            label.Layout.Column = 1;
        end

        function place(~, component, row, column)
            component.Layout.Row = row;
            component.Layout.Column = column;
        end

        function setEnabled(dialog, controls, enabled)
            value = dialog.onOff(enabled);
            for index = 1:numel(controls)
                controls(index).Enable = value;
            end
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
