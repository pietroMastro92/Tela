import SwiftUI

struct SettingsView: View {
    @Environment(TelaSessionStore.self) private var store

    var body: some View {
        TabView {
            timerSettings
                .tabItem { Label("Timer", systemImage: "timer") }
            artworkSettings
                .tabItem { Label("Opera", systemImage: "photo.artframe") }
            notificationSettings
                .tabItem { Label("Avvisi", systemImage: "bell") }
        }
        .scenePadding()
        .frame(width: 520, height: 390)
    }

    private var timerSettings: some View {
        Form {
            Section("Durate") {
                durationStepper(title: "Concentrazione", symbol: "brain.head.profile", value: focusBinding, range: 4 ... 60)
                durationStepper(title: "Pausa breve", symbol: "cup.and.saucer", value: shortBreakBinding, range: 1 ... 30)
                durationStepper(title: "Pausa lunga", symbol: "leaf", value: longBreakBinding, range: 5 ... 60)
            }
            Section {
                Text("Le nuove durate si applicano alla prossima fase e non modificano una sessione già avviata.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var artworkSettings: some View {
        Form {
            Section("Rivelazione") {
                Stepper(value: sessionsBinding, in: 4 ... 60) {
                    LabeledContent {
                        Text("\(store.sessionsPerArtwork) sessioni").monospacedDigit()
                    } label: {
                        Label("Obiettivo per opera", systemImage: "paintbrush.pointed")
                    }
                }
            }
            Section {
                Text("L’obiettivo viene congelato quando scegli una nuova opera. Ogni focus completato rende il quadro più nitido.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var notificationSettings: some View {
        Form {
            Section("Al termine di una fase") {
                Toggle(isOn: soundBinding) {
                    Label("Riproduci un suono", systemImage: "speaker.wave.2")
                }
                Toggle(isOn: notificationsBinding) {
                    Label("Mostra una notifica", systemImage: "bell.badge")
                }
            }
            Section {
                Text("Le notifiche vengono richieste solo quando avvii il timer e possono essere gestite nelle Impostazioni di Sistema.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func durationStepper(title: String, symbol: String, value: Binding<Int>, range: ClosedRange<Int>) -> some View {
        Stepper(value: value, in: range) {
            LabeledContent {
                Text("\(value.wrappedValue) min").monospacedDigit()
            } label: {
                Label(title, systemImage: symbol)
            }
        }
    }

    private var focusBinding: Binding<Int> {
        Binding(get: { store.durationMinutes }, set: { value in store.setFocusDuration(minutes: value) })
    }

    private var shortBreakBinding: Binding<Int> {
        Binding(get: { store.shortBreakMinutes }, set: { value in store.setShortBreakDuration(minutes: value) })
    }

    private var longBreakBinding: Binding<Int> {
        Binding(get: { store.longBreakMinutes }, set: { value in store.setLongBreakDuration(minutes: value) })
    }

    private var sessionsBinding: Binding<Int> {
        Binding(get: { store.sessionsPerArtwork }, set: { value in store.setSessionsPerArtwork(value) })
    }

    private var soundBinding: Binding<Bool> {
        Binding(get: { store.soundEnabled }, set: { value in store.setSoundEnabled(value) })
    }

    private var notificationsBinding: Binding<Bool> {
        Binding(get: { store.notificationsEnabled }, set: { value in store.setNotificationsEnabled(value) })
    }
}
