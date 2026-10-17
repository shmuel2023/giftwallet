import SwiftUI
import CoreLocation

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @State private var auth = LocationAlerts.shared.authorization

    var body: some View {
        @Bindable var settings = AppSettings.shared
        let catalog = CatalogStore.shared

        NavigationStack {
            Form {
                Section {
                    ForEach(catalog.cards) { card in
                        Toggle(isOn: cardBinding(card.id)) {
                            VStack(alignment: .leading, spacing: 2) {
                                CardBadge(cardId: card.id)
                                Text("\(card.merchantCount ?? 0) עסקים · \(card.issuer)")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("הכרטיסים שלי")
                }

                Section {
                    Toggle("התראה כשאני ליד חנות", isOn: $settings.locationAlerts)
                        .onChange(of: settings.locationAlerts) { _, on in
                            on ? LocationAlerts.shared.invalidate() : LocationAlerts.shared.stop()
                        }
                    if settings.locationAlerts && auth != .authorizedAlways {
                        VStack(alignment: .leading, spacing: 6) {
                            Label(authText, systemImage: "exclamationmark.triangle")
                                .foregroundStyle(.orange).font(.subheadline)
                            Button("פתח הגדרות מיקום") {
                                if auth == .notDetermined {
                                    LocationAlerts.shared.requestPermission()
                                } else {
                                    UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)
                                }
                            }
                        }
                    }
                    Toggle("תזכורת לפני שתוקף שובר פג", isOn: $settings.expiryReminders)
                        .onChange(of: settings.expiryReminders) { _, _ in
                            let container = context.container
                            Task { await Reminders.reschedule(container: container) }
                        }
                } header: {
                    Text("התראות")
                } footer: {
                    Text("התראת מיקום נשלחת כשאת/ה ליד חנות שיש בה מוצר מהרשימה שלך או שובר שמחכה למימוש. לכל עסק פעם ב-4 שעות לכל היותר.")
                }

                Section {
                    LabeledContent("עסקים שמכבדים את הכרטיסים שלך", value: "\(catalog.brands.count)")
                    LabeledContent("עדכון אחרון", value: catalog.dataDate?.shortHebrew ?? "מובנה באפליקציה")
                    Button {
                        Task { await catalog.refresh(force: true) }
                    } label: {
                        HStack {
                            Text("רענן נתונים עכשיו")
                            if catalog.isRefreshing { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(catalog.isRefreshing)
                    if let err = catalog.lastError {
                        Text(err).font(.caption).foregroundStyle(.red)
                    }
                } header: {
                    Text("נתונים")
                } footer: {
                    Text("רשימת העסקים מתעדכנת כל לילה מאתרי BuyMe ו-DreamCard. הרשימות משתנות מדי פעם - כדאי לוודא באפליקציה של המנפיק לפני מימוש.")
                }
            }
            .navigationTitle("הגדרות")
            .onChange(of: scenePhase) { _, _ in auth = LocationAlerts.shared.authorization }
            .onAppear { auth = LocationAlerts.shared.authorization }
        }
    }

    private var authText: String {
        switch auth {
        case .notDetermined: return "עדיין לא אושרה גישה למיקום"
        case .authorizedWhenInUse: return "כדי לקבל התראות גם כשהאפליקציה סגורה, צריך לבחור מיקום \"תמיד\""
        default: return "הגישה למיקום חסומה"
        }
    }

    private func cardBinding(_ id: String) -> Binding<Bool> {
        Binding(
            get: { AppSettings.shared.selectedCards.contains(id) },
            set: { on in
                if on { AppSettings.shared.selectedCards.insert(id) }
                else { AppSettings.shared.selectedCards.remove(id) }
                LocationAlerts.shared.invalidate()
            })
    }
}

struct OnboardingView: View {
    @State private var selected: Set<String> = []

    var body: some View {
        let catalog = CatalogStore.shared
        VStack(spacing: 24) {
            Spacer(minLength: 20)
            Image(systemName: "wallet.pass.fill")
                .font(.system(size: 64))
                .foregroundStyle(Color.accentColor)
            VStack(spacing: 8) {
                Text("השוברים שלי").font(.largeTitle.bold())
                Text("אילו כרטיסי מתנה יש לך?").font(.title3).foregroundStyle(.secondary)
            }
            VStack(spacing: 12) {
                ForEach(catalog.cards) { card in
                    let on = selected.contains(card.id)
                    Button {
                        if on { selected.remove(card.id) } else { selected.insert(card.id) }
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(card.name).font(.headline)
                                Text("\(card.merchantCount ?? 0) עסקים מכבדים")
                                    .font(.subheadline).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: on ? "checkmark.circle.fill" : "circle")
                                .font(.title2)
                                .foregroundStyle(on ? CardStyle.color(card.id) : .secondary)
                        }
                        .padding()
                        .background(RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(on ? CardStyle.color(card.id) : Color(.separator), lineWidth: on ? 2 : 1))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
            Spacer()
            Text("נבקש גישה למיקום ולהתראות כדי לעדכן אותך כשאת/ה ליד חנות מתאימה.")
                .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                .padding(.horizontal)
            Button {
                AppSettings.shared.selectedCards = selected
                Task {
                    _ = await Reminders.requestPermission()
                    LocationAlerts.shared.requestPermission()
                    AppSettings.shared.onboarded = true
                }
            } label: {
                Text("המשך").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .disabled(selected.isEmpty)
            .padding(.horizontal)
            .padding(.bottom)
        }
    }
}
