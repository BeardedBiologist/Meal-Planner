import SwiftData
import SwiftUI

struct ChatView: View {
    let language: AppLanguage
    let service: GeminiService

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Recipe.title) private var recipes: [Recipe]
    @Query(sort: \MealPlanEntry.date) private var mealPlans: [MealPlanEntry]
    @Query private var shoppingItems: [ShoppingListItem]
    @Query(sort: \StorePrice.updatedAt, order: .reverse) private var storePrices: [StorePrice]
    @Query(sort: \ChatConversation.updatedAt, order: .reverse) private var conversations: [ChatConversation]
    @Query private var settingsRecords: [UserSettings]

    @State private var inputText = ""
    @State private var showHistory = false
    @FocusState private var inputFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                messageList
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if !service.messages.isEmpty {
                    promptSuggestions
                }
                inputBar
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Assistant")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showHistory = true
                    } label: {
                        Label("History", systemImage: "clock.arrow.circlepath")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        service.startNewConversation()
                    } label: {
                        Label("New Chat", systemImage: "square.and.pencil")
                    }
                }
            }
        }
        .sheet(isPresented: $showHistory) {
            ChatHistoryView(conversations: conversations, activeConversationID: service.activeConversationID) { conversation in
                service.loadConversation(conversation)
                showHistory = false
            } deletedActiveConversation: {
                service.startNewConversation()
            }
        }
        .onAppear { syncContext() }
        .onChange(of: recipes.count) { syncContext() }
        .onChange(of: mealPlans.count) { syncContext() }
        .onChange(of: shoppingItems.count) { syncContext() }
        .onChange(of: storePrices.count) { syncContext() }
        .onChange(of: settingsRecords.count) { syncContext() }
    }

    // MARK: - Message list

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if service.messages.isEmpty {
                        welcomeView
                    }
                    ForEach(service.messages) { msg in
                        MessageBubble(message: msg)
                    }
                    if service.isLoading {
                        TypingIndicator()
                            .padding(.leading, 4)
                    }
                    if let err = service.lastError {
                        ErrorBubble(text: err)
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.horizontal)
                .padding(.top, 14)
                .padding(.bottom, 12)
            }
            .onChange(of: service.messages.count) {
                withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("bottom") }
            }
            .onChange(of: service.isLoading) {
                withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("bottom") }
            }
        }
    }

    // MARK: - Welcome screen

    private var welcomeView: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Color.accentColor, in: Circle())

                VStack(alignment: .leading, spacing: 5) {
                    Text("Meal Planner Assistant")
                        .font(.title2.bold())
                    Text("Ask for recipes, weekly plans, shopping list changes, or saved meal details.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            suggestionGrid
        }
        .padding(18)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Input bar

    private var promptSuggestions: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                SuggestionChip("Compare milk prices", icon: "tag") {
                    send("Compare saved prices for milk")
                }
                SuggestionChip("Add price", icon: "plus.circle") {
                    send("Save Tine milk at Kiwi for 24.90 NOK")
                }
                SuggestionChip("Plan this week", icon: "calendar") {
                    send("Plan dinners for every day this week")
                }
                SuggestionChip("Shopping list", icon: "cart") {
                    send("Show me my current shopping list")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    private var suggestionGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], alignment: .leading, spacing: 10) {
            SuggestionChip("Add a pasta recipe", icon: "book.closed") {
                send("Add a pasta carbonara recipe with full ingredients and steps")
            }
            SuggestionChip("Plan this week", icon: "calendar") {
                send("Plan dinners for every day this week")
            }
            SuggestionChip("Show shopping list", icon: "cart") {
                send("Show me my current shopping list")
            }
            SuggestionChip("Track a price", icon: "tag") {
                send("Save Tine milk at Kiwi for 24.90 NOK")
            }
        }
    }

    private var inputBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(alignment: .bottom, spacing: 10) {
                TextField("Message…", text: $inputText, axis: .vertical)
                    .lineLimit(1...5)
                    .focused($inputFocused)
                    .submitLabel(.send)
                    .onSubmit(sendCurrentInput)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        Color(.secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 8)
                    )

                Button(action: sendCurrentInput) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(canSend ? Color.accentColor : Color.secondary.opacity(0.45), in: Circle())
                }
                .disabled(!canSend)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .padding(.bottom, 2)
        }
        .background(.bar)
    }

    // MARK: - Helpers

    private var canSend: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !service.isLoading
    }

    private func sendCurrentInput() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        inputText = ""
        send(text)
    }

    private func send(_ text: String) {
        Task { await service.send(text) }
    }

    private func syncContext() {
        service.configure(context: modelContext, recipes: recipes, mealPlans: mealPlans, shoppingItems: shoppingItems, storePrices: storePrices, settings: settingsRecords.first)
    }
}

private struct ChatHistoryView: View {
    let conversations: [ChatConversation]
    let activeConversationID: UUID?
    let select: (ChatConversation) -> Void
    let deletedActiveConversation: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var entries: [ChatEntry]

    var body: some View {
        NavigationStack {
            List {
                if conversations.isEmpty {
                    ContentUnavailableView("No chats yet", systemImage: "message", description: Text("Start a chat and it will appear here."))
                } else {
                    ForEach(conversations) { conversation in
                        Button {
                            select(conversation)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: conversation.id == activeConversationID ? "checkmark.circle.fill" : "message")
                                    .foregroundStyle(conversation.id == activeConversationID ? Color.accentColor : Color.secondary)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(conversation.title)
                                        .font(.headline)
                                        .lineLimit(1)
                                    Text(conversation.updatedAt.formatted(date: .abbreviated, time: .shortened))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete(perform: deleteConversations)
                }
            }
            .navigationTitle("Chats")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func deleteConversations(offsets: IndexSet) {
        var deletedActive = false
        for index in offsets {
            let conversation = conversations[index]
            deletedActive = deletedActive || conversation.id == activeConversationID
            for entry in entries where entry.conversationID == conversation.id {
                modelContext.delete(entry)
            }
            modelContext.delete(conversation)
        }
        if deletedActive {
            deletedActiveConversation()
        }
    }
}

// MARK: - Message bubble

private struct MessageBubble: View {
    let message: ChatMessage

    private var isUser: Bool { message.role == .user }

    var body: some View {
        VStack(alignment: isUser ? .trailing : .leading, spacing: 6) {
            HStack(alignment: .bottom, spacing: 8) {
                if isUser { Spacer(minLength: 60) }

                if !isUser {
                    assistantIcon
                }

                Text(message.text)
                    .font(.body)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        isUser ? Color.accentColor : Color(.secondarySystemGroupedBackground)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(isUser ? Color.clear : Color(.separator).opacity(0.35), lineWidth: 0.5)
                    )
                    .foregroundStyle(isUser ? .white : .primary)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                if !isUser { Spacer(minLength: 60) }
            }

            if !message.toolActions.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(message.toolActions, id: \.self) { action in
                        Label(action, systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                .padding(.leading, isUser ? 0 : 42)
                .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
    }

    private var assistantIcon: some View {
        Image(systemName: "sparkles")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Color.accentColor)
            .frame(width: 30, height: 30)
            .background(Color.accentColor.opacity(0.12), in: Circle())
    }
}

// MARK: - Typing indicator

private struct TypingIndicator: View {
    @State private var phase = false

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(Color.secondary.opacity(0.5))
                    .frame(width: 8, height: 8)
                    .scaleEffect(phase ? 1.2 : 0.7)
                    .animation(
                        .easeInOut(duration: 0.45).repeatForever().delay(Double(i) * 0.13),
                        value: phase
                    )
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
        .onAppear { phase = true }
    }
}

// MARK: - Error bubble

private struct ErrorBubble: View {
    let text: String

    var body: some View {
        Label(text, systemImage: "exclamationmark.triangle.fill")
            .font(.caption)
            .foregroundStyle(.red)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Suggestion chip

private struct SuggestionChip: View {
    let label: String
    let icon: String
    let action: () -> Void

    init(_ label: String, icon: String, action: @escaping () -> Void) {
        self.label = label
        self.icon = icon
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Label(label, systemImage: icon)
                .font(.subheadline)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    Color(.tertiarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 8)
                )
                .foregroundStyle(.primary)
        }
        .buttonStyle(.plain)
    }
}
