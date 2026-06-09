import SwiftUI

struct LogsView: View {
    @State private var allLogs: [SyncLog] = []
    @State private var selectedStatus: SyncStatus? = nil
    @State private var selectedDate: Date? = nil
    @State private var showDatePicker = false
    @State private var page = 1
    @State private var expandedId: UUID? = nil

    private let pageSize = 25

    private var filteredLogs: [SyncLog] {
        allLogs.filter { log in
            if let status = selectedStatus, log.status != status { return false }
            if let date = selectedDate {
                let cal = Calendar.current
                if !cal.isDate(log.date, inSameDayAs: date) { return false }
            }
            return true
        }
    }

    private var pagedLogs: [SyncLog] {
        Array(filteredLogs.prefix(page * pageSize))
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    filterBar
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                }

                if pagedLogs.isEmpty {
                    ContentUnavailableView(
                        "No Logs",
                        systemImage: "doc.text.magnifyingglass",
                        description: Text(allLogs.isEmpty ? "No sync history yet." : "No logs match the current filter.")
                    )
                    .listRowBackground(Color.clear)
                } else {
                    Section {
                        ForEach(pagedLogs) { log in
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    expandedId = expandedId == log.id ? nil : log.id
                                }
                            } label: {
                                LogRow(log: log, isExpanded: expandedId == log.id)
                            }
                            .buttonStyle(.plain)
                        }
                    } footer: {
                        if filteredLogs.count > pagedLogs.count {
                            Button("Load More") {
                                page += 1
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Sync Logs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if selectedStatus != nil || selectedDate != nil {
                        Button("Clear") {
                            selectedStatus = nil
                            selectedDate = nil
                            page = 1
                        }
                        .font(.subheadline)
                    }
                }
            }
        }
        .onAppear { reload() }
    }

    private var filterBar: some View {
        VStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    FilterChip(label: "All", isSelected: selectedStatus == nil) {
                        selectedStatus = nil
                        page = 1
                    }
                    FilterChip(
                        label: "Success",
                        icon: "checkmark.circle.fill",
                        color: .green,
                        isSelected: selectedStatus == .success
                    ) {
                        selectedStatus = selectedStatus == .success ? nil : .success
                        page = 1
                    }
                    FilterChip(
                        label: "Failed",
                        icon: "xmark.circle.fill",
                        color: .red,
                        isSelected: selectedStatus == .failed
                    ) {
                        selectedStatus = selectedStatus == .failed ? nil : .failed
                        page = 1
                    }
                    FilterChip(
                        label: "Partial",
                        icon: "exclamationmark.circle.fill",
                        color: .orange,
                        isSelected: selectedStatus == .partial
                    ) {
                        selectedStatus = selectedStatus == .partial ? nil : .partial
                        page = 1
                    }
                }
                .padding(.horizontal, 2)
            }

            HStack {
                Button {
                    showDatePicker.toggle()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "calendar")
                            .font(.caption)
                        if let date = selectedDate {
                            Text(date, style: .date)
                                .font(.caption)
                        } else {
                            Text("Filter by Date")
                                .font(.caption)
                        }
                    }
                    .foregroundStyle(selectedDate != nil ? .blue : .secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background((selectedDate != nil ? Color.blue : Color.secondary).opacity(0.1), in: Capsule())
                }

                if selectedDate != nil {
                    Button {
                        selectedDate = nil
                        page = 1
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                }

                Spacer()

                Text("\(filteredLogs.count) entries")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .sheet(isPresented: $showDatePicker) {
            NavigationStack {
                DatePicker("Select Date", selection: Binding(
                    get: { selectedDate ?? Date() },
                    set: { selectedDate = $0; page = 1 }
                ), displayedComponents: .date)
                .datePickerStyle(.graphical)
                .navigationTitle("Filter by Date")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { showDatePicker = false }
                    }
                }
            }
            .presentationDetents([.medium])
        }
    }

    private func reload() {
        allLogs = SyncService.shared.loadAllLogs()
    }
}

// MARK: - Log Row

private struct LogRow: View {
    let log: SyncLog
    let isExpanded: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: log.statusIcon)
                    .foregroundStyle(log.statusColor)
                    .font(.system(size: 16))
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(log.type.rawValue)
                        .font(.system(size: 15, weight: .semibold))
                    Text(log.formattedDate)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(log.recordsSynced) records")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                    Text(log.formattedDuration)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
            }
            .padding(.vertical, 4)

            if isExpanded {
                Divider()
                    .padding(.vertical, 8)

                VStack(alignment: .leading, spacing: 6) {
                    ForEach(log.details) { detail in
                        HStack {
                            Text(detail.type.rawValue)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.secondary)
                            Spacer()
                            if let error = detail.error {
                                Text(error)
                                    .font(.caption)
                                    .foregroundStyle(.red)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.trailing)
                            } else {
                                Text("\(detail.recordsSynced) records")
                                    .font(.system(size: 13, design: .rounded))
                                    .foregroundStyle(.primary)
                            }
                        }
                    }

                    if let error = log.errorMessage {
                        Divider()
                            .padding(.top, 2)
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .padding(.top, 2)
                    }
                }
                .padding(.bottom, 4)
            }
        }
    }
}

// MARK: - Filter Chip

private struct FilterChip: View {
    let label: String
    var icon: String? = nil
    var color: Color = .blue
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let icon {
                    Image(systemName: icon)
                        .font(.caption2)
                        .foregroundStyle(isSelected ? .white : color)
                }
                Text(label)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(isSelected ? .white : .primary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .frame(minWidth: 68)
            .background(isSelected ? color : Color.secondary.opacity(0.1), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    LogsView()
}
