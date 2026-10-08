import SwiftUI
import CoreHaptics
import UIKit

private enum Design {
    static let text = Color(red: 0.2, green: 0.2, blue: 0.2)
    static let secondary = Color(red: 146/255, green: 153/255, blue: 162/255)
    static let blue = Color(red: 66/255, green: 139/255, blue: 249/255)
    static let neutral = Color(red: 0, green: 16/255, blue: 36/255).opacity(0.03)
    static let search = Color(red: 0, green: 16/255, blue: 36/255).opacity(0.06)
    static let hold = 0.45
    static let ringFillDuration = 1.5
    static let morph = Animation.spring(response: 0.308, dampingFraction: 0.64)
}

private struct RowBounds: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next.width > 0 { value = next }
    }
}

private struct Asset: View {
    let name: String
    let width: CGFloat
    let height: CGFloat
    init(_ name: String, _ width: CGFloat, _ height: CGFloat? = nil) {
        self.name = name; self.width = width; self.height = height ?? width
    }
    var body: some View {
        Image(name).resizable().frame(width: width, height: height).accessibilityHidden(true)
    }
}

struct PaymentsView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var rowBounds: CGRect = .zero
    @GestureState private var touchActive = false
    @State private var pressing = false
    @State private var expanded = false
    @State private var ready = false
    @State private var departing = false
    @State private var flight: CGFloat = 0
    @State private var fillingScale: CGFloat = 1
    @State private var toastVisible = false
    @State private var motherRemoved = false
    @State private var upcomingCollapsed = false
    @State private var openingImpact = UIImpactFeedbackGenerator(style: .medium)
    @State private var departureFeedback = UINotificationFeedbackGenerator()

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                screen
                    .allowsHitTesting(!expanded)
                    .accessibilityHidden(expanded)
                Color.black.opacity(expanded && !departing ? 0.11 : 0)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .allowsHitTesting(expanded)
                    .onTapGesture { close() }
                    .accessibilityLabel("Закрыть карточку")
                    .accessibilityIdentifier("dismissCard")
                    .accessibilityAddTraits(.isButton)
                    .accessibilityHidden(!expanded)
                if rowBounds.width > 0 && !motherRemoved {
                    MorphingPayment(progress: expanded ? 1 : 0, backgroundScale: reduceMotion ? 1 : fillingScale, rowSize: rowBounds.size,
                                    holding: expanded && touchActive && !departing, openingDuration: reduceMotion ? 0.15 : 0.308,
                                    ready: ready, reduceMotion: reduceMotion, onFillStarted: {
                                        guard expanded && touchActive && !departing else { return }
                                        fillingScale = 0.90
                                    }, onFilled: {
                                        guard expanded && touchActive && !departing else { return }
                                        departureFeedback.prepare()
                                        withAnimation(.easeOut(duration: 0.12)) { ready = true }
                                        withAnimation(.spring(response: 0.30, dampingFraction: 0.68)) {
                                            fillingScale = 1
                                        }
                                    })
                        .frame(width: expanded ? 132 : rowBounds.width,
                               height: expanded ? 166 : rowBounds.height)
                        .scaleEffect(pressing && !expanded && !reduceMotion ? 0.95 : 1)
                        .contentShape(Rectangle())
                        .gesture(holdGesture)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Мама, 10 000 рублей")
                        .accessibilityValue(departing ? "Карточка отправляется" : ready ? "Готово к отправке" : expanded ? "Карточка открыта" : "Строка платежа")
                        .accessibilityHint(expanded ? "Карточка перевода" : "Удерживайте, чтобы открыть карточку")
                        .accessibilityAddTraits(.isButton)
                        .accessibilityAction { guard !departing else { return }; withAnimation(animation) { expanded.toggle(); pressing = false; ready = false; fillingScale = 1 } }
                        .accessibilityAction(.escape) { close() }
                        .accessibilityIdentifier("motherPayment")
                        .scaleEffect(x: reduceMotion ? 1 : 1 - 0.72 * flight,
                                     y: reduceMotion ? 1 : 1 + 0.18 * flight)
                        .rotationEffect(.degrees(reduceMotion ? 0 : -8 * flight))
                        .offset(y: reduceMotion ? 0 : -(geometry.size.height + 200) * flight)
                        .opacity(reduceMotion ? 1 - flight : 1)
                        .allowsHitTesting(!departing)
                        .position(x: rowBounds.midX + (expanded ? 0.5 : 0),
                                  y: expanded ? min(max(rowBounds.midY - 56, 83), geometry.size.height - 83) : rowBounds.midY)
                    // Secondary labels fade at their row positions, independently of the moving card.
                    ZStack(alignment: .topLeading) {
                        Text("Часто переводите")
                            .frame(width: 186, alignment: .leading)
                            .position(x: 169, y: 40)
                        Text("Сегодня")
                            .position(x: rowBounds.width - 46.5, y: 40)
                    }
                        .font(.system(size: 13))
                        .foregroundStyle(Design.secondary)
                        .frame(width: rowBounds.width, height: rowBounds.height)
                        .scaleEffect(pressing && !expanded && !reduceMotion ? 0.95 : 1)
                        .position(x: rowBounds.midX, y: rowBounds.midY)
                        .opacity(expanded ? 0 : 1)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .overlay(alignment: .top) {
                if toastVisible {
                    paymentToast
                        .padding(.top, 2)
                        .transition(reduceMotion ? .opacity : .offset(y: -160).combined(with: .opacity))
                        .zIndex(10)
                }
            }
            .animation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.32, dampingFraction: 0.85), value: toastVisible)
            .task(id: toastVisible) {
                guard toastVisible else { return }
                // Keep it readable for two seconds after its entrance.
                do { try await Task.sleep(for: .seconds(reduceMotion ? 2.15 : 2.32)) }
                catch { return }
                toastVisible = false
            }
            .coordinateSpace(name: "screen")
            .onPreferenceChange(RowBounds.self) { rowBounds = $0 }
            .onChange(of: touchActive) { _, active in
                if active {
                    openingImpact.prepare()
                    withAnimation(.easeInOut(duration: Design.hold)) { pressing = true }
                } else {
                    endTouch()
                }
            }
            .onChange(of: scenePhase) { _, phase in if phase != .active { toastVisible = false; reset() } }
            .task(id: departing) {
                guard departing else { return }
                departureFeedback.notificationOccurred(.success)
                withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .timingCurve(0.45, 0, 0.85, 0.55, duration: 0.280)) {
                    flight = 1
                }
                do { try await Task.sleep(for: .seconds(reduceMotion ? 0.2 : 0.280)) }
                catch { return }
                // Hide the offscreen card before collapsing its vacant row.
                var transaction = Transaction(animation: nil)
                transaction.disablesAnimations = true
                withTransaction(transaction) { motherRemoved = true }
                reset()
                withAnimation(.easeInOut(duration: reduceMotion ? 0.15 : 0.28)) {
                    upcomingCollapsed = true
                }
                toastVisible = true
            }
        }
        .background(Color.white)
        .foregroundStyle(Design.text)
    }

    private var paymentToast: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(LinearGradient(colors: [Color(red: 0, green: 0.73, blue: 0.20),
                                                      Color(red: 0.38, green: 0.83, blue: 0.47)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                Image(systemName: "checkmark").font(.system(size: 17, weight: .heavy)).foregroundStyle(.white)
            }.frame(width: 30, height: 30).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Мама").font(.system(size: 15, weight: .semibold))
                Text("-10 000 ₽").font(.system(size: 15)).foregroundStyle(Design.secondary).fixedSize()
            }.frame(width: 67, alignment: .leading)
            Button(action: undoPayment) {
                Text("Отменить").font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Design.blue)
                    .frame(width: 87, height: 30)
                    .background(Design.neutral, in: Capsule())
            }.buttonStyle(.plain).accessibilityIdentifier("undoPayment")
        }
        .padding(.leading, 20).padding(.trailing, 16)
        .frame(height: 68)
        .background { Capsule().fill(.white).shadow(color: .black.opacity(0.12), radius: 20, y: 8) }
        .accessibilityElement(children: .contain)
    }

    private func undoPayment() {
        toastVisible = false
        withAnimation(.easeInOut(duration: reduceMotion ? 0.15 : 0.28)) {
            upcomingCollapsed = false
            motherRemoved = false
        }
    }

    // The second gesture keeps tracking the same finger after long-press recognition.
    // GestureState also resets on cancellation, when onEnded isn't called.
    private var holdGesture: some Gesture {
        LongPressGesture(minimumDuration: Design.hold, maximumDistance: 14)
            .sequenced(before: DragGesture(minimumDistance: 0))
            .updating($touchActive) { _, active, _ in active = true }
            .onChanged { value in
                if case .second(true, _) = value, !expanded, !departing {
                    openingImpact.impactOccurred()
                    withAnimation(animation) { expanded = true; pressing = false }
                }
            }
            .onEnded { _ in endTouch() }
    }

    private func endTouch() {
        guard !departing, pressing || expanded else { return }
        if ready && expanded {
            withAnimation(.easeOut(duration: 0.35)) { departing = true; pressing = false }
            return
        }
        let transition = expanded ? animation : .easeOut(duration: 0.20)
        withAnimation(transition) { expanded = false; pressing = false; fillingScale = 1 }
    }

    private var animation: Animation {
        reduceMotion ? .easeOut(duration: 0.15) : Design.morph
    }
    private func close() {
        guard !departing else { return }
        withAnimation(animation) { expanded = false; pressing = false; ready = false; fillingScale = 1 }
    }

    private func reset() {
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            expanded = false; pressing = false; ready = false; departing = false; flight = 0; fillingScale = 1
        }
    }

    private var screen: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                header
                shortcuts.padding(.top, 28)
                upcoming.padding(.top, 20)
                HStack(spacing: 16) {
                    action("На оплату", asset: "Bill")
                    action("Автоплатежи", asset: "Autopay")
                }.padding(.top, 20)
                phoneTransfer.padding(.top, 20)
            }
            .padding(.horizontal, 16)
            .padding(.top, 52)
            .padding(.bottom, 70)
        }
        .scrollDisabled(pressing || expanded)
        .overlay(alignment: .bottom) { tabBar }
    }

    private var header: some View {
        VStack(spacing: 8) {
            HStack(spacing: 0) {
                Text("Платежи").font(.system(size: 30, weight: .bold)).tracking(0.36)
                Spacer()
                Asset("Scan", 36)
            }.frame(height: 36)
            HStack(spacing: 3) {
                Image("Search").renderingMode(.template).foregroundStyle(Design.secondary)
                    .frame(width: 24, height: 24)
                Text("Поиск").font(.system(size: 17)).foregroundStyle(Design.secondary)
                Spacer(minLength: 0)
            }
            .padding(.leading, 4).frame(height: 36)
            .background(Design.search, in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private var shortcuts: some View {
        HStack(spacing: 8) {
            shortcut("Тройка", subtitle: "700 ₽", asset: "Troika", isTroika: true)
            shortcut("Мой\nтелефон", asset: "PhoneShortcut")
            shortcut("Добавить", asset: "Add", isAdd: true)
        }
    }

    private func shortcut(_ title: String, subtitle: String? = nil, asset: String, isTroika: Bool = false, isAdd: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Asset(asset, 30).padding(.bottom, 7)
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 12, weight: .semibold)).lineSpacing(2)
                    .foregroundStyle(isAdd ? Design.blue : Design.text)
                if let subtitle { Text(subtitle).font(.system(size: 12)) }
            }
        }
        .padding(12).frame(width: 92, height: 92, alignment: .leading)
        .background(isTroika ? Color(red: 232/255, green: 249/255, blue: 252/255) : Design.neutral,
                    in: RoundedRectangle(cornerRadius: 12))
        .overlay(alignment: .topTrailing) {
            if isTroika {
                Image("Close")
                    .frame(width: 24, height: 24).padding(.top, 4).padding(.trailing, 4)
            }
        }
    }

    private var upcoming: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Предстоящие").font(.system(size: 20, weight: .bold)).tracking(0.38)
                Spacer()
                Text("Все").font(.system(size: 17)).foregroundStyle(Design.blue)
            }.padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 12).frame(height: 52)
            payment("Анастасия К.", detail: "Напоминание", amount: "10 000 ₽", date: "Сегодня", asset: "TBank")
            Color.clear.frame(height: upcomingCollapsed ? 0 : 4)
            Color.clear.frame(height: upcomingCollapsed ? 0 : 56)
                .overlay(Design.neutral.opacity(pressing ? 1 : 0))
                .background(GeometryReader { proxy in
                    Color.clear.preference(key: RowBounds.self, value: proxy.frame(in: .named("screen")))
                })
            Color.clear.frame(height: upcomingCollapsed ? 0 : 4)
            payment("Мой телефон", detail: "Автоплатеж", amount: "599 ₽", date: "17 марта", asset: "Phone")
                .accessibilityIdentifier("upcomingPhone")
            Color.clear.frame(height: 12)
        }
        .background { RoundedRectangle(cornerRadius: 24).fill(.white)
            .shadow(color: .black.opacity(0.12), radius: 17, y: 6) }
    }

    private func payment(_ title: String, detail: String, amount: String, date: String, asset: String) -> some View {
        HStack(spacing: 16) {
            Asset(asset, 40).clipShape(Circle())
            VStack(spacing: 4) {
                HStack(alignment: .top, spacing: 8) {
                    Text(title).lineLimit(1)
                    Spacer(minLength: 0)
                    Text(amount).fixedSize()
                }.font(.system(size: 17)).frame(height: 20)
                HStack(spacing: 8) {
                    Text(detail).lineLimit(1)
                    Spacer(minLength: 0)
                    Text(date).fixedSize()
                }.font(.system(size: 13)).foregroundStyle(Design.secondary).frame(height: 16)
            }
        }.padding(.horizontal, 20).frame(height: 56)
    }

    private func action(_ title: String, asset: String) -> some View {
        HStack(spacing: 8) {
            Asset(asset, 24)
            Text(title).font(.system(size: 15, weight: .semibold)).fixedSize()
            Spacer(minLength: 0)
        }.padding(.horizontal, 12).frame(maxWidth: .infinity).frame(height: 48)
            .background { RoundedRectangle(cornerRadius: 16).fill(.white)
                .shadow(color: .black.opacity(0.10), radius: 10, y: 5) }
    }

    private var phoneTransfer: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                Text("Перевод по телефону").font(.system(size: 20, weight: .bold)).tracking(0.38)
                Asset("SBP", 14.5407, 17.9355).frame(width: 24, height: 24)
                Spacer(minLength: 0)
            }.frame(height: 24).padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 16)
            Text("Введите номер телефона").font(.system(size: 17)).tracking(-0.41).foregroundStyle(Design.secondary)
                .padding(.horizontal, 12).frame(maxWidth: .infinity, alignment: .leading).frame(height: 56)
                .background(Design.neutral, in: RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal, 20)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 4) {
                    phoneContact("Влад", "Бонькин", index: 1)
                    phoneContact("Виталик", "Аметистов", index: 2)
                    phoneContact("Викедсик", "Монстров", index: 3)
                    phoneContact("Алена", "Avatar label", index: 4)
                    phoneContact("Михаил", "Обжоркин", index: 5)
                    phoneContact("Контакты", "Avatar label", index: 6)
                }.padding(.horizontal, 12)
            }
            .frame(height: 90).padding(.top, 20).padding(.bottom, 20)
            .accessibilityIdentifier("phoneContacts")
        }
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .background { RoundedRectangle(cornerRadius: 24).fill(.white)
            .shadow(color: .black.opacity(0.12), radius: 17, y: 6) }
    }

    private func phoneContact(_ first: String, _ second: String, index: Int) -> some View {
        VStack(spacing: 6) {
            ZStack {
                if index == 6 {
                    Circle().fill(Design.blue)
                    Asset("PhoneContactsIcon", 34)
                } else {
                    Image("PhoneContact\(index)").resizable().scaledToFill()
                        .frame(width: 56, height: 56).clipShape(Circle())
                    if index == 5 { Asset("PhoneContactSymbol", 56) }
                }
            }
            .frame(width: 56, height: 56)
            .clipShape(Circle())
            .overlay(alignment: .bottomTrailing) {
                if index == 1 {
                    Circle().fill(Color(red: 1, green: 221/255, blue: 45/255))
                        .frame(width: 8, height: 8)
                        .overlay(Circle().stroke(.white, lineWidth: 2))
                        .padding(.trailing, 5).padding(.bottom, 4)
                }
            }
            VStack(spacing: 0) {
                Text(first).frame(height: 14)
                Text(second).frame(height: 14)
            }.font(.system(size: 12)).multilineTextAlignment(.center)
        }.frame(width: 72, height: 90)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("phoneContact\(index)")
    }

    // The reference uses a branded, pre-iOS-26 bar; preserve its artwork and geometry.
    private var tabBar: some View {
        HStack(spacing: 0) {
            tab("Главная", "Home")
            tab("Платежи", "Payments", selected: true)
            tab("Город", "City")
            tab("Чат", "Chat")
            tab("Еще", "More")
        }.frame(height: 50)
            .background {
                Rectangle().fill(.ultraThinMaterial)
                    .overlay(Color(red: 249/255, green: 249/255, blue: 249/255).opacity(0.94))
                    .ignoresSafeArea(edges: .bottom)
            }
            .overlay(alignment: .top) { Color.black.opacity(0.21).frame(height: 0.5) }
    }

    private func tab(_ title: String, _ asset: String, selected: Bool = false) -> some View {
        VStack(spacing: 0) {
            if asset == "City" {
                Asset(asset, 28).frame(width: 32, height: 32)
            } else {
                Asset(asset, 28).frame(width: 32, height: 32)
            }
            Text(title).font(.system(size: 10, weight: .medium)).tracking(-0.24)
                .foregroundStyle(selected ? Design.blue : Design.secondary)
        }.padding(.top, 2).frame(maxWidth: .infinity).frame(height: 50, alignment: .top)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// All moving pieces remain in one surface throughout the row-to-card morph.
private struct MorphingPayment: View, Animatable {
    var progress: CGFloat
    var backgroundScale: CGFloat
    let rowSize: CGSize
    let holding: Bool
    let openingDuration: Double
    let ready: Bool
    let reduceMotion: Bool
    let onFillStarted: () -> Void
    let onFilled: () -> Void
    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(progress, backgroundScale) }
        set { progress = newValue.first; backgroundScale = newValue.second }
    }
    private func blend(_ start: CGFloat, _ end: CGFloat) -> CGFloat { start + (end - start) * progress }

    var body: some View {
        let width = blend(rowSize.width, 132)
        let height = blend(rowSize.height, 166)
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: blend(0, 35)).fill(.white).opacity(progress)
                .scaleEffect(backgroundScale)
            ZStack {
                Asset("Sber", 40)
                Asset("Flash", 10).frame(width: 16, height: 16)
                    .background { Circle().fill(.white).overlay(Circle().fill(Color(red: 1, green: 221/255, blue: 45/255).opacity(0.3))) }
                    .overlay(Circle().stroke(.white, lineWidth: 1))
                    .offset(x: 15, y: 15)
            }.frame(width: 40, height: 40)
                .position(x: blend(40, 66), y: blend(28, 57)).opacity(1 - progress)
            TransferStatus(ready: ready, reduceMotion: reduceMotion)
                .position(x: blend(40, 66), y: blend(28, 57)).opacity(progress)
            HoldProgressRing(active: holding, openingDuration: openingDuration, onFillStarted: onFillStarted, onFilled: onFilled)
                .frame(width: 60, height: 60)
                .position(x: blend(40, 66), y: blend(28, 57))
            Text("Мама").font(.system(size: 17, weight: .regular))
                .opacity(1 - progress)
                .position(x: blend(99, 66.5), y: blend(18, 104))
            Text("Мама").font(.system(size: 17, weight: .bold))
                .opacity(progress)
                .position(x: blend(99, 66.5), y: blend(18, 104))
            Text("10 000 ₽").font(.system(size: blend(17, 15)))
                .foregroundStyle(Color(red: blend(0.2, 146/255), green: blend(0.2, 153/255), blue: blend(0.2, 162/255)))
                .position(x: blend(rowSize.width - 54.5, 66.5), y: blend(18, 125))
        }.frame(width: width, height: height).foregroundStyle(Design.text)
    }
}

private struct TransferStatus: View {
    let ready: Bool
    let reduceMotion: Bool
    @State private var scale: CGFloat = 1

    var body: some View {
        ZStack {
            Asset("TransferArrow", 50).opacity(ready ? 0 : 1)
            ZStack {
                Circle().fill(Color(red: 78/255, green: 246/255, blue: 83/255))
                Image(systemName: "arrow.right")
                    .font(.system(size: 19, weight: .semibold))
                    .rotationEffect(.degrees(-90))
                    .foregroundStyle(.white)
            }.opacity(ready ? 1 : 0)
        }
        .frame(width: 50, height: 50)
        .scaleEffect(scale)
        .accessibilityHidden(true)
        .task(id: ready) {
            guard ready && !reduceMotion else { scale = 1; return }
            withAnimation(.easeOut(duration: 0.10)) { scale = 0.9 }
            do { try await Task.sleep(for: .seconds(0.10)) }
            catch { return }
            withAnimation(.spring(response: 0.28, dampingFraction: 0.6)) { scale = 1 }
        }
    }
}

/// A separate animation keeps the fill linear while the card itself uses a spring.
private struct HoldProgressRing: View {
    let active: Bool
    let openingDuration: Double
    let onFillStarted: () -> Void
    let onFilled: () -> Void
    @State private var fill: CGFloat = 0
    @State private var visible = false
    @StateObject private var haptics = HoldHaptics()

    var body: some View {
        Circle()
            .trim(from: 0, to: fill)
            .stroke(Color(red: 65/255, green: 244/255, blue: 69/255),
                    style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
            .rotationEffect(.degrees(-90))
            .opacity(active && visible ? 1 : 0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .onChange(of: active) { _, active in if !active { haptics.stop() } }
            .onDisappear { haptics.stop() }
            .task(id: active) {
                haptics.stop()
                var reset = Transaction(animation: nil)
                reset.disablesAnimations = true
                withTransaction(reset) { fill = 0; visible = false }
                guard active else { return }
                do {
                    try await Task.sleep(for: .seconds(openingDuration))
                    try Task.checkCancellation()
                } catch { return }
                let hapticSession = haptics.start(duration: Design.ringFillDuration)
                defer { haptics.stop(session: hapticSession) }
                withTransaction(reset) { visible = true }
                withAnimation(.linear(duration: Design.ringFillDuration)) {
                    fill = 1
                    onFillStarted()
                }
                do {
                    try await Task.sleep(for: .seconds(Design.ringFillDuration))
                    try Task.checkCancellation()
                } catch { return }
                withAnimation(.easeOut(duration: 0.12)) { visible = false }
                onFilled()
            }
    }
}

/// Each hold owns a finite continuous event; an old cancelled task cannot stop a new hold.
@MainActor
private final class HoldHaptics: ObservableObject {
    private var engine: CHHapticEngine?
    private var player: (any CHHapticPatternPlayer)?
    private var session: UUID?

    func start(duration: TimeInterval) -> UUID? {
        stop()
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return nil }
        do {
            let engine = try CHHapticEngine()
            self.engine = engine
            engine.playsHapticsOnly = true
            engine.isAutoShutdownEnabled = true
            let event = CHHapticEvent(eventType: .hapticContinuous, parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.55),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.3)
            ], relativeTime: 0, duration: duration)
            let pattern = try CHHapticPattern(events: [event], parameters: [])
            try engine.start()
            let player = try engine.makePlayer(with: pattern)
            self.player = player
            try player.start(atTime: CHHapticTimeImmediate)
            let session = UUID()
            self.session = session
            return session
        } catch {
            stop()
            return nil
        }
    }

    func stop(session expected: UUID?) {
        guard let expected, session == expected else { return }
        stop()
    }

    func stop() {
        try? player?.stop(atTime: CHHapticTimeImmediate)
        engine?.stop(completionHandler: nil)
        player = nil
        engine = nil
        session = nil
    }
}

#Preview("Платежи") { PaymentsView().preferredColorScheme(.light) }
