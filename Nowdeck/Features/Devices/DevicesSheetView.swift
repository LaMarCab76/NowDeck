import SwiftUI

/// Dispositivos (Dispositivos.dc.html): a 640×398 sheet on the black background with the
/// current device, the list to choose from and "¿No ves tu dispositivo?", which swaps the
/// list for a help view inside the same sheet.
///
/// Like Importar tema, it is shown as a full-screen cover that draws its own sheet: a
/// system sheet in landscape on iPhone takes the whole screen and cannot have the
/// mockup's size and margins.
struct DevicesSheetView: View {
    @ObservedObject var model: DevicesModel
    var dismiss: () -> Void

    @EnvironmentObject private var theme: ThemeStore
    @State private var showsHelp: Bool
    @State private var dragOffset: CGFloat = 0

    private typealias Layout = Metrics.Devices

    /// `showsHelp` opens straight on the help view (previews and screenshot checks).
    init(model: DevicesModel, showsHelp: Bool = false, dismiss: @escaping () -> Void) {
        self.model = model
        self.dismiss = dismiss
        _showsHelp = State(initialValue: showsHelp)
    }

    var body: some View {
        GeometryReader { proxy in
            // 640 wide on 896 (128 pt on each side). On the iPhone 8 Plus (736) it is
            // still 640, with the minimum 48 pt margins.
            let width = min(Layout.sheetWidth, proxy.size.width - 2 * Layout.minSideMargin)

            sheet
                .frame(width: width)
                .frame(maxHeight: .infinity)
                .padding(.top, Layout.sheetTop)
                .offset(y: dragOffset)
                .frame(maxWidth: .infinity)
        }
        // The mockup measures from the screen edges; the status bar and the home indicator
        // are hidden, and the sheet's own padding keeps the content clear of the corners.
        .ignoresSafeArea()
        .background(theme.palette.background.color.ignoresSafeArea())
        .foregroundStyle(theme.palette.text.color)
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .task { await model.reload() }
    }

    private var sheet: some View {
        ZStack(alignment: .topLeading) {
            DevicesListPane(model: model, showHelp: showHelp, dismiss: dismiss,
                            handle: handle)
                .opacity(showsHelp ? 0 : 1)
                .accessibilityHidden(showsHelp)
            if showsHelp {
                DevicesHelpPane(
                    back: { showsHelp = false },
                    refresh: {
                        showsHelp = false
                        Task { await model.reload() }
                    }
                )
            }
        }
        .background(
            UnevenTopRoundedRectangle(radius: Radius.sheet)
                .fill(theme.palette.surface.color)
        )
        .clipShape(UnevenTopRoundedRectangle(radius: Radius.sheet))
    }

    private func showHelp() {
        showsHelp = true
    }

    /// The 40×5 handle. Dragging it down closes the sheet.
    private var handle: some View {
        Capsule()
            .fill(Palette.sheetHandle)
            .frame(width: Layout.handleSize.width, height: Layout.handleSize.height)
            .frame(maxWidth: .infinity, minHeight: Layout.handleSize.height)
            .contentShape(Rectangle().inset(by: -12))
            .gesture(
                DragGesture()
                    .onChanged { dragOffset = max(0, $0.translation.height) }
                    .onEnded { value in
                        if value.translation.height > Layout.dismissDragDistance {
                            dismiss()
                        } else {
                            withAnimation(.easeOut(duration: 0.2)) { dragOffset = 0 }
                        }
                    }
            )
            .accessibilityHidden(true)
    }
}

// MARK: - List

private struct DevicesListPane<Handle: View>: View {
    @ObservedObject var model: DevicesModel
    var showHelp: () -> Void
    var dismiss: () -> Void
    var handle: Handle

    @EnvironmentObject private var theme: ThemeStore
    private typealias Layout = Metrics.Devices

    var body: some View {
        VStack(alignment: .leading, spacing: Layout.sheetGap) {
            handle
            CurrentDeviceHeader(device: model.currentDevice, listState: listState,
                                dismiss: dismiss)
            content
            helpButton
        }
        .padding(.top, Layout.sheetTopPadding)
        .padding(.horizontal, Layout.sheetHorizontalPadding)
        .padding(.bottom, Layout.sheetBottomPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var listState: CurrentDeviceHeader.ListState {
        if model.choices != nil { return .loaded }
        return model.problem == nil ? .loading : .failed
    }

    @ViewBuilder
    private var content: some View {
        if let choices = model.choices {
            if let problem = model.problem {
                ProblemLine(problem: problem)
            }
            if choices.others.isEmpty {
                Text(choices.current == nil
                     ? "No encontramos dispositivos. Abrí Spotify en la compu, el celu o el parlante donde quieras escuchar."
                     : "No hay otros dispositivos disponibles.")
                    .textStyle(.devicesMessage)
                    .foregroundStyle(theme.palette.bodyText.color)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, Layout.listLabelTopMargin)
            } else {
                Text("ELEGÍ UN DISPOSITIVO")
                    .textStyle(.devicesLabel)
                    .foregroundStyle(theme.palette.label.color)
                    .padding(.top, Layout.listLabelTopMargin)
                    .accessibilityAddTraits(.isHeader)
                // Three rows fit in the mockup's sheet; more scroll.
                ViewThatFits(in: .vertical) {
                    rows(choices.others)
                    ScrollView(.vertical, showsIndicators: true) {
                        rows(choices.others)
                    }
                }
            }
        } else if let problem = model.problem {
            // The first load failed: explain and offer to try again.
            ProblemLine(problem: problem)
                .padding(.top, Layout.listLabelTopMargin)
            Button("Reintentar") {
                Task { await model.reload() }
            }
            .buttonStyle(DevicesRefreshButtonStyle())
        } else {
            ProgressView()
                .tint(theme.palette.tertiaryText.color)
                .frame(maxWidth: .infinity, minHeight: Layout.rowHeight)
                .accessibilityLabel(Text("Buscando dispositivos"))
        }
    }

    private func rows(_ devices: [SpotifyDevice]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(devices.enumerated()), id: \.offset) { index, device in
                DeviceChoiceRow(
                    device: device,
                    isTransferring: model.transferringID != nil
                        && model.transferringID == device.id,
                    isBlocked: model.transferringID != nil,
                    isLast: index == devices.count - 1,
                    choose: {
                        Task {
                            if await model.transfer(to: device) { dismiss() }
                        }
                    }
                )
            }
        }
    }

    private var helpButton: some View {
        Button(action: showHelp) {
            HStack(spacing: Layout.helpButtonGap) {
                Image(systemName: "questionmark.circle")
                    .font(.system(size: Layout.helpButtonIconSize - 1, weight: .medium))
                    .frame(width: Layout.helpButtonIconSize, height: Layout.helpButtonIconSize)
                    .accessibilityHidden(true)
                Text("¿No ves tu dispositivo?")
                    .textStyle(.devicesTextButton)
            }
            .foregroundStyle(theme.palette.text.color)
            .padding(.horizontal, Layout.helpButtonPadding)
            .frame(height: Metrics.minTouchTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Accent circle with the device icon, "DISPOSITIVO ACTUAL", the name and Cerrar.
private struct CurrentDeviceHeader: View {
    enum ListState {
        case loading
        case loaded
        case failed
    }

    var device: SpotifyDevice?
    var listState: ListState
    var dismiss: () -> Void

    @EnvironmentObject private var theme: ThemeStore
    private typealias Layout = Metrics.Devices

    var body: some View {
        HStack(spacing: Layout.headerGap) {
            HStack(spacing: Layout.headerGap) {
                DeviceSymbol.image(named: device.map { DeviceSymbol.name(for: $0.type) }
                                            ?? "speaker.slash")
                    .font(.system(size: Layout.currentIconSize - 4, weight: .semibold))
                    .foregroundStyle(device == nil
                        ? theme.palette.tertiaryText.color : theme.palette.textOnAccent.color)
                    .frame(width: Layout.currentCircleSize, height: Layout.currentCircleSize)
                    .background(Circle().fill(device == nil
                        ? Palette.closeButtonFill : theme.palette.accent.color))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: Layout.headerTextGap) {
                    label
                        .textStyle(.devicesLabel)
                        .foregroundStyle(theme.palette.accent.color)
                        .lineLimit(1)
                    name
                        .textStyle(.currentDeviceName)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityElement(children: .combine)

            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: Layout.closeIconSize, weight: .bold))
                    .foregroundStyle(theme.palette.text.color)
                    .frame(width: Metrics.minTouchTarget, height: Metrics.minTouchTarget)
                    .background(Circle().fill(Palette.closeButtonFill))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Cerrar"))
        }
        .frame(height: Layout.currentCircleSize)
    }

    private var label: Text {
        if device?.isInPrivateSession == true {
            return Text("DISPOSITIVO ACTUAL · SESIÓN PRIVADA")
        }
        return Text("DISPOSITIVO ACTUAL")
    }

    private var name: Text {
        if let device, !device.name.isEmpty {
            // Device names come from the user's account: shown verbatim.
            return Text(verbatim: device.name)
        }
        switch listState {
        case .loading: return Text(verbatim: " ")
        case .loaded: return Text("Ninguno")
        case .failed: return Text("Sin datos")
        }
    }
}

/// One device: icon, name and type, between 10 % white lines.
private struct DeviceChoiceRow: View {
    var device: SpotifyDevice
    var isTransferring: Bool
    /// Another transfer is running.
    var isBlocked: Bool
    var isLast: Bool
    var choose: () -> Void

    @EnvironmentObject private var theme: ThemeStore
    private typealias Layout = Metrics.Devices

    var body: some View {
        Button(action: choose) {
            HStack(spacing: Layout.rowGap) {
                DeviceSymbol.image(for: device.type)
                    .font(.system(size: Layout.rowIconSize - 4, weight: .regular))
                    .frame(width: Layout.rowIconSize, height: Layout.rowIconSize)
                    .accessibilityHidden(true)
                Text(verbatim: device.name)
                    .textStyle(.deviceRowName)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                trailing
            }
            .foregroundStyle(theme.palette.text.color)
            .frame(height: Layout.rowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!device.acceptsTransfer || isBlocked)
        .opacity(device.acceptsTransfer ? 1 : Layout.disabledRowOpacity)
        .overlay(alignment: .top) { separator }
        .overlay(alignment: .bottom) { if isLast { separator } }
        .accessibilityElement(children: .combine)
        .accessibilityHint(device.acceptsTransfer
            ? Text("Pasa la música a este dispositivo")
            : Text("Este dispositivo no acepta control remoto"))
    }

    @ViewBuilder
    private var trailing: some View {
        if isTransferring {
            ProgressView()
                .tint(theme.palette.bodyText.color)
                .accessibilityLabel(Text("Pasando la música"))
        } else {
            typeText
                .textStyle(.deviceRowType)
                .foregroundStyle(theme.palette.bodyText.color)
                .lineLimit(1)
                .fixedSize()
        }
    }

    private var typeText: Text {
        if !device.acceptsTransfer {
            return Text("No admite control remoto")
        }
        let type = Text(DeviceTypeName.key(for: device.type))
        guard device.isInPrivateSession else { return type }
        return type + Text(verbatim: " · ") + Text("Sesión privada")
    }

    private var separator: some View {
        Rectangle()
            .fill(Palette.deviceSeparator)
            .frame(height: Layout.separatorWidth)
            .accessibilityHidden(true)
    }
}

/// The last problem, with the warning icon.
private struct ProblemLine: View {
    var problem: DevicesProblem

    @EnvironmentObject private var theme: ThemeStore

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
            Image(systemName: "exclamationmark.circle")
                .foregroundStyle(theme.palette.warning.color)
                .accessibilityHidden(true)
            Text(problem.message)
                .foregroundStyle(theme.palette.bodyText.color)
                .fixedSize(horizontal: false, vertical: true)
        }
        .textStyle(.devicesMessage)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
    }
}

// MARK: - Help

/// "¿No ves tu dispositivo?": three steps, "Actualizar lista" and "Volver a la lista".
private struct DevicesHelpPane: View {
    var back: () -> Void
    var refresh: () -> Void

    @EnvironmentObject private var theme: ThemeStore
    private typealias Layout = Metrics.Devices

    var body: some View {
        VStack(alignment: .leading, spacing: Layout.helpGap) {
            Button(action: back) {
                HStack(spacing: Layout.backGap) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: Layout.backIconSize - 3, weight: .bold))
                        .frame(width: Layout.backIconSize, height: Layout.backIconSize)
                        .accessibilityHidden(true)
                    Text("Volver a la lista")
                        .textStyle(.devicesTextButton)
                }
                .foregroundStyle(theme.palette.text.color)
                .frame(height: Metrics.minTouchTarget)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Text("¿No ves tu dispositivo?")
                .textStyle(.devicesHelpTitle)
                .accessibilityAddTraits(.isHeader)

            VStack(alignment: .leading, spacing: Layout.stepsGap) {
                step(1, "Abrí Spotify en ese dispositivo. La lista solo muestra los que tienen Spotify activo en este momento.")
                step(2, "Fijate que use la misma cuenta de Spotify que esta app.")
                step(3, "Si es un parlante o una tele, despertalo primero: en reposo no aparece.")
            }

            Spacer(minLength: 0)

            Button("Actualizar lista", action: refresh)
                .buttonStyle(DevicesRefreshButtonStyle())
        }
        .padding(.vertical, Layout.helpVerticalPadding)
        .padding(.horizontal, Layout.sheetHorizontalPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func step(_ number: Int, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: Layout.stepsGap) {
            Text(verbatim: "\(number)")
                .textStyle(.devicesStepNumber)
                .frame(width: Layout.stepNumberSize, height: Layout.stepNumberSize)
                .overlay(Circle().strokeBorder(Palette.outline.color,
                                               lineWidth: Layout.stepNumberBorder))
                .accessibilityHidden(true)
            Text(text)
                .textStyle(.devicesHelpStep)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(theme.palette.text.color)
    }
}

/// "Actualizar lista" / "Reintentar": accent capsule of 48, hugging its text.
private struct DevicesRefreshButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Label(configuration: configuration)
    }

    private struct Label: View {
        let configuration: ButtonStyleConfiguration
        @EnvironmentObject private var theme: ThemeStore

        var body: some View {
            configuration.label
                .textStyle(.devicesRefreshButton)
                .foregroundStyle(theme.palette.textOnAccent.color)
                .lineLimit(1)
                .padding(.horizontal, Metrics.Devices.refreshButtonPadding)
                .frame(height: Metrics.Devices.refreshButtonHeight)
                .background(Capsule().fill(theme.palette.accent.color))
                .contentShape(Capsule())
                .opacity(configuration.isPressed ? 0.8 : 1)
        }
    }
}
