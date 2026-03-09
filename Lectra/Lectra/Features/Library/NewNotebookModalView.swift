import SwiftUI

enum NotebookPaperPattern: String, CaseIterable {
    case blank = "Blank"
    case dotted = "Dotted"
    case squared = "Squared"
    case ruledNarrow = "Ruled Narrow"
    case ruledWide = "Ruled Wide"
}

struct PaperTemplateOptions: Equatable {
    var pattern: NotebookPaperPattern = .dotted
    var background: Color = .white
}

struct NewNotebookModalView: View {
    @Environment(\.dismiss) private var dismiss
    
    @Binding var documentName: String
    @Binding var selectedLanguage: String
    @Binding var isCoverEnabled: Bool
    @Binding var selectedSize: String
    @Binding var paperOptions: PaperTemplateOptions
    
    var onCreate: () -> Void
    
    @State private var selectedTab: Int = 1 // 0 for Cover, 1 for Paper
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Main Content
                HStack(alignment: .top, spacing: 20) {
                    // Left Side Previews
                    HStack(spacing: 16) {
                        // Cover Preview
                        ZStack(alignment: .bottom) {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.black)
                                .frame(width: 140, height: 190)
                                .overlay {
                                    // Lectra Cover Mock
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color.white)
                                        .frame(width: 80, height: 40)
                                        .overlay {
                                            Image("LectraLogo") // Assume there's a LectraLogo in assets, otherwise fallback to book
                                                .resizable()
                                                .scaledToFit()
                                                .frame(width: 24, height: 24)
                                                .foregroundColor(.black)
                                                // Fallback if image asset doesn't exist
                                                .onAppear { } // just a placeholder
                                        }
                                }
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                )
                        }
                        .opacity(isCoverEnabled ? 1.0 : 0.4)
                        
                        // Paper Preview
                        ZStack(alignment: .bottom) {
                            PaperPreviewThumbnail(pattern: paperOptions.pattern, background: paperOptions.background)
                                .frame(width: 140, height: 190)
                        }
                    }
                    
                    // Right Side Settings Form
                    VStack(spacing: 16) {
                        // Top inputs
                        VStack(spacing: 0) {
                            HStack {
                                Text("Name")
                                    .font(.system(size: 15))
                                    .foregroundColor(LectraColor.textSecondary)
                                    .frame(width: 80, alignment: .leading)
                                TextField("Untitled Notebook", text: $documentName)
                                    .font(.system(size: 15))
                                    .foregroundColor(.white)
                            }
                            .padding(.horizontal, 16)
                            .frame(height: 44)
                        }
                        .background(LectraColor.surfaceBG)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        
                        // Paper Templates Settings
                        VStack(alignment: .leading, spacing: 8) {
                            Text("PAPER TEMPLATES")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(LectraColor.textTertiary)
                                .padding(.horizontal, 12)
                            
                            VStack(spacing: 0) {
                                HStack {
                                    Text("Size")
                                        .font(.system(size: 15))
                                        .foregroundColor(.white)
                                    
                                    Spacer()
                                    
                                    Menu {
                                        Button("Standard, Portrait") { selectedSize = "Standard, Portrait" }
                                        Button("A4, Portrait") { selectedSize = "A4, Portrait" }
                                        Button("Letter, Portrait") { selectedSize = "Letter, Portrait" }
                                    } label: {
                                        HStack {
                                            Text(selectedSize)
                                                .font(.system(size: 15))
                                                .foregroundColor(LectraColor.textSecondary)
                                            Image(systemName: "chevron.down")
                                                .font(.system(size: 13))
                                                .foregroundColor(LectraColor.textSecondary)
                                        }
                                    }
                                }
                                .padding(.horizontal, 16)
                                .frame(height: 44)
                                
                                Divider().background(LectraGlass.hairlineStroke)
                                
                                HStack {
                                    Text("Color")
                                        .font(.system(size: 15))
                                        .foregroundColor(.white)
                                    Spacer()
                                    
                                    ColorPicker("", selection: $paperOptions.background)
                                        .labelsHidden()
                                }
                                .padding(.horizontal, 16)
                                .frame(height: 44)
                            }
                            .background(LectraColor.surfaceBG)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }
                }
                .padding(.top, 24)
                .padding(.horizontal, 24)
                
                Divider()
                    .background(LectraGlass.hairlineStroke)
                    .padding(.top, 32)
                
                // Bottom Paper Templates Grid
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        HStack {
                            Text("Paper Templates")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(.white)
                            Spacer()
                            Button("Edit") {
                                // Action for Edit
                            }
                            .font(.system(size: 15))
                            .foregroundColor(LectraColor.accent)
                        }
                        
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 16)], spacing: 24) {
                            ForEach([NotebookPaperPattern.blank, .dotted, .squared, .ruledNarrow, .ruledWide], id: \.self) { pattern in
                                PaperTemplateSelectionCard(
                                    pattern: pattern,
                                    currentOptions: $paperOptions
                                )
                            }
                        }
                        
                        // Writing Papers Section
                        Text("Writing Papers")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.top, 16)
                        
                        // (Would add more templates here)
                    }
                    .padding(24)
                }
            }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("New Notebook")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(LectraColor.textSecondary)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Create") {
                        onCreate()
                        dismiss()
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .buttonStyle(.borderedProminent)
                    .tint(LectraColor.accent)
                    .clipShape(Capsule())
                    .disabled(documentName.isEmpty)
                }
            }
            .toolbarBackground(Color.black, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
    }
}

// MARK: - Subcomponents

struct PaperPreviewThumbnail: View {
    let pattern: NotebookPaperPattern
    let background: Color
    var isSelected: Bool = false
    
    private var strokeColor: Color {
        let uiColor = UIColor(background)
        var w: CGFloat = 0
        _ = uiColor.getWhite(&w, alpha: nil)
        return w < 0.5 ? Color.white.opacity(0.1) : Color.black.opacity(0.1)
    }
    
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(background)
            
            // Draw pattern lines based on pattern
            GeometryReader { geo in
                let width = geo.size.width
                let height = geo.size.height
                
                Path { path in
                    switch pattern {
                    case .blank:
                        break
                    case .dotted:
                        let step: CGFloat = 8
                        for x in stride(from: step, to: width, by: step) {
                            for y in stride(from: step, to: height, by: step) {
                                path.addEllipse(in: CGRect(x: x, y: y, width: 1.5, height: 1.5))
                            }
                        }
                    case .squared:
                        let step: CGFloat = 10
                        for x in stride(from: step, to: width, by: step) {
                            path.move(to: CGPoint(x: x, y: 0))
                            path.addLine(to: CGPoint(x: x, y: height))
                        }
                        for y in stride(from: step, to: height, by: step) {
                            path.move(to: CGPoint(x: 0, y: y))
                            path.addLine(to: CGPoint(x: width, y: y))
                        }
                    case .ruledNarrow:
                        let step: CGFloat = 8
                        for y in stride(from: step*2, to: height, by: step) {
                            path.move(to: CGPoint(x: 0, y: y))
                            path.addLine(to: CGPoint(x: width, y: y))
                        }
                    case .ruledWide:
                        let step: CGFloat = 14
                        for y in stride(from: step*2, to: height, by: step) {
                            path.move(to: CGPoint(x: 0, y: y))
                            path.addLine(to: CGPoint(x: width, y: y))
                        }
                    }
                }
                .stroke(strokeColor, lineWidth: 0.5)
                .fill(strokeColor)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isSelected ? LectraColor.accent : Color.white.opacity(0.1), lineWidth: isSelected ? 3 : 1)
        }
    }
}

struct PaperTemplateSelectionCard: View {
    let pattern: NotebookPaperPattern
    @Binding var currentOptions: PaperTemplateOptions
    
    var body: some View {
        VStack(spacing: 12) {
            ZStack(alignment: .bottom) {
                PaperPreviewThumbnail(
                    pattern: pattern,
                    background: currentOptions.background,
                    isSelected: false
                )
                .frame(width: 100, height: 135)
                .onTapGesture {
                    currentOptions.pattern = pattern
                }
                
                if currentOptions.pattern == pattern {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(LectraColor.accent)
                        .background(Circle().fill(Color.white).padding(2))
                        .offset(y: 10)
                }
            }
            
            Text(pattern.rawValue)
                .font(.system(size: 13))
                .foregroundColor(.white)
        }
    }
}
