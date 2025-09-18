import SwiftUI
import CoreLocation
import UIKit


struct ContentView: View {
    @Environment(\.openImmersiveSpace) var openImmersiveSpace
    @Environment(\.dismissWindow) var dismissWindow
    @StateObject private var appModel = 🥽AppModel()
    @State private var serverIP: String = ""
    @State private var streamMode: String = UserDefaults.standard.string(forKey: "stream_mode") ?? "mjpeg"
    @State private var detectedIP: String = ""
    var body: some View {
        VStack(spacing: 32) {
            HStack(spacing: 28) {
                Image(.graph2)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 1200)
                    .clipShape(.rect(cornerRadius: 24))
            }
            Text("You're on IP address [\(getIPAddress())]")
                .font(.largeTitle.weight(.medium))
            
            // Auto-detect Jetson IP (assuming same subnet)
            HStack(alignment: .center, spacing: 12) {
                Text("Detected Jetson Orin IP at RLWRLD: ")
                    .font(.title2)
                    .foregroundColor(.secondary)
                
                TextField("Enter Jetson IP", text: $serverIP)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 140)
                    .onChange(of: serverIP) { _, newValue in
                        if !newValue.isEmpty {
                            UserDefaults.standard.set(newValue, forKey: "server_ip")
                        }
                    }
            }
            .font(.title3)
            .padding(.top, 8)
                
            Button {
                Task {
                    // Save settings
                    if !serverIP.isEmpty {
                        UserDefaults.standard.set(serverIP, forKey: "server_ip")
                    }
                    UserDefaults.standard.set("webrtc", forKey: "stream_mode")

                    // Ensure gRPC server and tracking start
                    appModel.startserver()
                    appModel.run()
                    Task { await appModel.processDeviceAnchorUpdates() }
                    Task(priority: .low) { await appModel.processReconstructionUpdates() }

                    // Open immersive space and hide main window
                    await self.openImmersiveSpace(id: "immersiveSpace")
                    self.dismissWindow()
                }
            } label: {
                Text("Start")
                    .font(.largeTitle)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 60)
            }
            .disabled(serverIP.isEmpty)
            
        }
        .padding(32)
        .onAppear {
            detectJetsonIP()
            // Auto-save settings on app start
            if !serverIP.isEmpty {
                UserDefaults.standard.set(serverIP, forKey: "server_ip")
            }
            UserDefaults.standard.set("webrtc", forKey: "stream_mode")
        }
    }
    
    private func detectJetsonIP() {
        // Set default Jetson IP
        detectedIP = "172.30.1.60"
        
        // Auto-fill if empty
        if serverIP.isEmpty {
            serverIP = detectedIP
        }
    }
}

func getIPAddress() -> String {
    var address: String?
    var ifaddr: UnsafeMutablePointer<ifaddrs>? = nil
    if getifaddrs(&ifaddr) == 0 {
        var ptr = ifaddr
        while ptr != nil {
            defer { ptr = ptr?.pointee.ifa_next }

            guard let interface = ptr?.pointee else { return "" }
            let addrFamily = interface.ifa_addr.pointee.sa_family
            if addrFamily == UInt8(AF_INET) || addrFamily == UInt8(AF_INET6) {

                // wifi = ["en0"]
                // wired = ["en2", "en3", "en4"]
                // cellular = ["pdp_ip0","pdp_ip1","pdp_ip2","pdp_ip3"]

                let name: String = String(cString: (interface.ifa_name))
                if  name == "en0" || name == "en2" || name == "en3" || name == "en4" || name == "pdp_ip0" || name == "pdp_ip1" || name == "pdp_ip2" || name == "pdp_ip3" {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    getnameinfo(interface.ifa_addr, socklen_t((interface.ifa_addr.pointee.sa_len)), &hostname, socklen_t(hostname.count), nil, socklen_t(0), NI_NUMERICHOST)
                    address = String(cString: hostname)
                }
            }
        }
        freeifaddrs(ifaddr)
    }
    return address ?? ""
}


func getWiFiName() -> String? {
  // CNCopyCurrentNetworkInfo is not available in visionOS
  // Return a placeholder or nil
  return nil
}
