import SwiftUI

struct StatsProgressBar: View {
    var value: Double?
    var speed: String
    var label: String
    var color: Color = .blue
    var iconName: String? = "arrow.down"
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary)
                
                Spacer()
                
                if let value = value {
                    Text("\(Int(value))%")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                
                if !speed.isEmpty {
                    HStack(spacing: 3) {
                        if let icon = iconName {
                            Image(systemName: icon)
                                .font(.system(size: 8, weight: .bold))
                        }
                        Text(speed)
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    }
                    .foregroundColor(.primary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.primary.opacity(0.08))
                    .cornerRadius(4)
                }
            }
            
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background track
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.primary.opacity(0.1))
                    
                    // Progress bar
                    if let value = value {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(
                                LinearGradient(
                                    gradient: Gradient(colors: [color, color.opacity(0.7)]),
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: geometry.size.width * CGFloat(min(max(value / 100.0, 0), 1)))
                            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: value)
                    } else {
                        // Indeterminate state
                        IndeterminateBar(color: color)
                            .frame(width: geometry.size.width)
                    }
                }
            }
            .frame(height: 6)
        }
    }
}

struct IndeterminateBar: View {
    var color: Color
    @State private var phase: CGFloat = 0
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                RoundedRectangle(cornerRadius: 3)
                    .fill(color.opacity(0.3))
                
                RoundedRectangle(cornerRadius: 3)
                    .fill(color)
                    .frame(width: geometry.size.width * 0.3)
                    .offset(x: (geometry.size.width * 0.7) * phase)
            }
            .onAppear {
                withAnimation(Animation.linear(duration: 1.5).repeatForever(autoreverses: true)) {
                    phase = 1
                }
            }
        }
    }
}

struct StatsProgressBar_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            StatsProgressBar(value: 45, speed: "85.2 MB/s", label: "Downloading Model")
                .padding()
            StatsProgressBar(value: nil, speed: "", label: "Preparing...")
                .padding()
        }
        .frame(width: 400)
    }
}
