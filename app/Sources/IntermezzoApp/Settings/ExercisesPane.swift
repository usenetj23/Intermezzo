import SwiftUI
import SwiftData
import AppKit
import Carbon.HIToolbox
import ServiceManagement
import CoreLocation
import UserNotifications
import IOKit.hidsystem
import IntermezzoKit

struct ExercisesPane: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Exercise.createdAt) private var exercises: [Exercise]
    @State private var newName = ""
    @State private var newTitle = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            List {
                ForEach(exercises) { exercise in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(localizedExerciseName(exercise.name)).font(.headline)
                            Spacer()
                            Button(role: .destructive) {
                                context.delete(exercise)
                                try? context.save()
                            } label: {
                                Image(systemName: "trash").font(.caption)
                            }
                            .buttonStyle(.borderless)
                        }
                        Text(localized: exercise.title).foregroundStyle(.secondary)
                        HStack(spacing: 16) {
                            Toggle("Short Break", isOn: Binding(
                                get: { exercise.assignToShort },
                                set: { exercise.assignToShort = $0; try? context.save() }))
                            Toggle("Long Break", isOn: Binding(
                                get: { exercise.assignToLong },
                                set: { exercise.assignToLong = $0; try? context.save() }))
                        }
                        .toggleStyle(.checkbox)
                        .font(.callout)
                    }
                    .padding(.vertical, 2)
                }
            }

            HStack {
                TextField("Name (e.g. Neck roll)", text: $newName)
                TextField("Title shown on break screen", text: $newTitle)
                Button("Add Exercise") {
                    guard !newName.isEmpty else { return }
                    context.insert(Exercise(
                        name: newName,
                        title: newTitle.isEmpty ? newName : newTitle,
                        detail: String(localized: "Take a moment. Breathe. Reset."),
                        assignToShort: true, assignToLong: false))
                    try? context.save()
                    newName = ""; newTitle = ""
                }.settingsAnchor("exercises-add-exercise")
            }
            .padding(10)

            HStack {
                Text("Biblioteka: \(ExerciseLibrary.all.count) ćwiczeń (oczy, kark i barki, nadgarstki, plecy, nogi, stanowisko).")
                    .settingsNote()
                Spacer()
                Button("Przywróć bibliotekę") {
                    ExerciseSeed.syncLibrary(context, force: true)
                }.settingsAnchor("exercises-przywroc-biblioteke")
                .controlSize(.small)
            }
            .padding(.horizontal, 10).padding(.bottom, 10)
        }
    }
}

// MARK: - Statistics
