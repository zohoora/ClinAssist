import SwiftUI

struct HelperPanelView: View {
    let suggestions: HelperSuggestions
    
    @State private var expandedSections: Set<String> = []
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            Text("ASSISTANT")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
            
            VStack(spacing: 0) {
                // Issues
                ExpandableSection(
                    title: "Issues",
                    count: suggestions.issues.count,
                    isExpanded: expandedSections.contains("issues")
                ) {
                    toggleSection("issues")
                } content: {
                    ForEach(suggestions.issues) { issue in
                        IssueRowViewFromLLM(issue: issue)
                    }
                }
                
                Divider().padding(.horizontal, 8)
                
                // DDx
                ExpandableSection(
                    title: "DDx",
                    count: suggestions.ddx.count,
                    isExpanded: expandedSections.contains("ddx")
                ) {
                    toggleSection("ddx")
                } content: {
                    ForEach(suggestions.ddx, id: \.self) { diagnosis in
                        SimpleRowView(text: diagnosis)
                    }
                }
                
                Divider().padding(.horizontal, 8)
                
                // Drug Cards
                ExpandableSection(
                    title: "Drug Cards",
                    count: suggestions.drugCards.count,
                    isExpanded: expandedSections.contains("drugCards")
                ) {
                    toggleSection("drugCards")
                } content: {
                    ForEach(suggestions.drugCards) { card in
                        DrugCardView(card: card)
                    }
                }
            }
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
        }
    }
    
    private func toggleSection(_ section: String) {
        withAnimation(.easeInOut(duration: 0.2)) {
            if expandedSections.contains(section) {
                expandedSections.remove(section)
            } else {
                expandedSections.insert(section)
            }
        }
    }
}

// MARK: - Expandable Section

struct ExpandableSection<Content: View>: View {
    let title: String
    let count: Int
    let isExpanded: Bool
    var badgeColor: Color = .blue
    let onTap: () -> Void
    @ViewBuilder let content: () -> Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(width: 12)
                
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                
                Spacer()
                
                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(badgeColor)
                        .cornerRadius(10)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
            .onTapGesture(perform: onTap)
            
            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    content()
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
            }
        }
    }
}

// MARK: - Issue Row

struct IssueRowView: View {
    let issue: Issue
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: issue.addressedInPlan ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 12))
                .foregroundColor(issue.addressedInPlan ? .green : .secondary)
            
            Text(issue.label)
                .font(.system(size: 12))
                .foregroundColor(issue.addressedInPlan ? .secondary : .primary)
                .strikethrough(issue.addressedInPlan)
            
            Spacer()
        }
        .padding(.leading, 12)
    }
}

struct IssueRowViewFromLLM: View {
    let issue: IssueFromLLM
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: issue.addressedInPlan ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 12))
                .foregroundColor(issue.addressedInPlan ? .green : .secondary)
            
            Text(issue.label)
                .font(.system(size: 12))
                .foregroundColor(issue.addressedInPlan ? .secondary : .primary)
                .strikethrough(issue.addressedInPlan)
            
            Spacer()
        }
        .padding(.leading, 12)
    }
}

// MARK: - Simple Row

struct SimpleRowView: View {
    let text: String
    var icon: String = "circle.fill"
    var iconColor: Color = .secondary
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 8))
                .foregroundColor(iconColor)
                .frame(width: 12, height: 16)
            
            Text(text)
                .font(.system(size: 12))
                .foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true)
            
            Spacer()
        }
        .padding(.leading, 12)
    }
}

// MARK: - Drug Card

struct DrugCardView: View {
    let card: DrugCard
    @State private var isExpanded: Bool = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundColor(.secondary)
                
                Text(card.name)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.primary)
                
                Spacer()
            }
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            }
            
            if isExpanded {
                VStack(alignment: .leading, spacing: 4) {
                    LabeledContent("Class", value: card.drugClass)
                    LabeledContent("Dose", value: card.typicalAdultDose)
                    
                    if !card.keyCautions.isEmpty {
                        Text("Cautions:")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                        
                        ForEach(card.keyCautions, id: \.self) { caution in
                            HStack(alignment: .top, spacing: 4) {
                                Text("•")
                                    .font(.system(size: 10))
                                    .foregroundColor(.orange)
                                Text(caution)
                                    .font(.system(size: 10))
                                    .foregroundColor(.primary)
                            }
                        }
                    }
                }
                .padding(.leading, 16)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .cornerRadius(6)
        .padding(.leading, 12)
    }
    
    @ViewBuilder
    func LabeledContent(_ label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 4) {
            Text("\(label):")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(size: 10))
                .foregroundColor(.primary)
        }
    }
}

#Preview {
    HelperPanelView(
        suggestions: HelperSuggestions()
    )
    .padding()
    .frame(width: 380)
}

