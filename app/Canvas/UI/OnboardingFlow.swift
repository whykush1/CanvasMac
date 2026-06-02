import SwiftUI

struct OnboardingSlide: Identifiable {
    let id = UUID()
    let title: String
    let description: String
    let imageName: String
    let systemSymbol: String
    let color: Color
}

/// A premium, interactive onboarding walkthrough that introduces the user to Canvas.
/// Explains features using interactive layouts, visuals, and dynamic controls.
struct OnboardingFlow: View {
    @Binding var isPresented: Bool
    @State private var currentSlideIndex = 0
    
    let slides = [
        OnboardingSlide(
            title: "Welcome to Canvas",
            description: "Transform your desktop with stunning, high-performance 4K video, animated GIFs, and static photo wallpapers tailored perfectly for macOS.",
            imageName: "welcome_slide",
            systemSymbol: "paintpalette.fill",
            color: .accentColor
        ),
        OnboardingSlide(
            title: "Seamless Library & Drag Drop",
            description: "Browse curated public submissions copyright-free presets, or drop your own MP4, MOV, or GIF files directly into the menu bar panel to apply them instantly.",
            imageName: "drop_slide",
            systemSymbol: "plus.square.dashed",
            color: .blue
        ),
        OnboardingSlide(
            title: "Stretched Layout Canvas",
            description: "Running multiple monitors? Canvas stretches a single 4K wallpaper seamlessly across all of them using advanced coordinate layout matching.",
            imageName: "screens_slide",
            systemSymbol: "desktopcomputer",
            color: .purple
        ),
        OnboardingSlide(
            title: "Smart Performance Tuning",
            description: "Zero battery drain. Playback automatically pauses when you launch games, enter full-screen apps, start the screensaver, or toggle Low Power Mode.",
            imageName: "perf_slide",
            systemSymbol: "bolt.batteryblock.fill",
            color: .green
        ),
        OnboardingSlide(
            title: "Monitored Folders & Automation",
            description: "Choose any local folder for Canvas to monitor. Drag new assets into that folder, and they will automatically sync to your wallpaper library instantly.",
            imageName: "folder_slide",
            systemSymbol: "folder.badge.plus",
            color: .orange
        )
    ]
    
    var body: some View {
        VStack(spacing: 0) {
            // Slide content switcher
            ZStack {
                ForEach(0..<slides.count) { index in
                    if index == currentSlideIndex {
                        SlideContentView(slide: slides[index])
                            .transition(.asymmetric(
                                insertion: .move(edge: .trailing).combined(with: .opacity),
                                removal: .move(edge: .leading).combined(with: .opacity)
                            ))
                    }
                }
            }
            .frame(height: 380)
            .padding(.top, 20)
            
            Divider()
            
            // Onboarding Footer Controls
            HStack {
                // Page Indicator Dots
                HStack(spacing: 8) {
                    ForEach(0..<slides.count) { index in
                        Circle()
                            .fill(index == currentSlideIndex ? Color.accentColor : Color.secondary.opacity(0.3))
                            .frame(width: 8, height: 8)
                            .animation(.spring(), value: currentSlideIndex)
                    }
                }
                
                Spacer()
                
                // Back Button
                if currentSlideIndex > 0 {
                    Button("Back") {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            currentSlideIndex -= 1
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                    .padding(.trailing, 10)
                }
                
                // Primary Action Button (Next / Finish)
                Button {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        if currentSlideIndex < slides.count - 1 {
                            currentSlideIndex += 1
                        } else {
                            // Finish Onboarding
                            UserDefaults.standard.set(true, forKey: "com.canvas.onboarding.completed")
                            isPresented = false
                        }
                    }
                } label: {
                    Text(currentSlideIndex == slides.count - 1 ? "Get Started" : "Continue")
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.accentColor)
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
            .padding(20)
            .background(Color(NSColor.windowBackgroundColor).opacity(0.4))
        }
        .frame(width: 550, height: 480)
        .background(VisualEffectView(material: .hudWindow, blendingMode: .behindWindow))
    }
}

// MARK: - Slide Content View

struct SlideContentView: View {
    let slide: OnboardingSlide
    
    var body: some View {
        VStack(spacing: 24) {
            // Dynamic Mockup UI representation (placeholder until user adds real app screenshots)
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(LinearGradient(
                        colors: [slide.color.opacity(0.15), slide.color.opacity(0.02)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .frame(width: 320, height: 160)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(slide.color.opacity(0.3), lineWidth: 1)
                    )
                
                // High fidelity layout representations (resembles real macOS screens)
                VStack(spacing: 12) {
                    Image(systemName: slide.systemSymbol)
                        .font(.system(size: 40, weight: .semibold))
                        .foregroundColor(slide.color)
                        .shadow(color: slide.color.opacity(0.4), radius: 8)
                    
                    // Tiny schematic drawing representing layouts
                    HStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(slide.color.opacity(0.4))
                            .frame(width: 40, height: 24)
                        
                        RoundedRectangle(cornerRadius: 4)
                            .fill(slide.color.opacity(0.2))
                            .frame(width: 40, height: 24)
                        
                        RoundedRectangle(cornerRadius: 4)
                            .fill(slide.color.opacity(0.2))
                            .frame(width: 40, height: 24)
                    }
                    .opacity(slide.imageName == "screens_slide" ? 1.0 : 0.0)
                    .frame(height: slide.imageName == "screens_slide" ? nil : 0)
                }
            }
            .frame(height: 180)
            
            // Text Details
            VStack(spacing: 8) {
                Text(slide.title)
                    .font(.system(.title2, design: .rounded))
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                
                Text(slide.description)
                    .font(.system(.body, design: .rounded))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                    .lineSpacing(4)
            }
        }
    }
}
