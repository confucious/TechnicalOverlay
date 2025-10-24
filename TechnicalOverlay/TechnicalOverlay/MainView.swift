//
//  MainView.swift
//  TechnicalOverlay
//
//  Created by Jerry Hsu on 10/19/25.
//

import SwiftUI
import AVFoundation

//enum State {
//    case waitingForVideo
//    case videoLoaded
//}

struct MainView: View {
    struct ViewModel {
        var player: AVPlayer?
        var scoring: String? //Scoring?
    }

    @State private var state = ViewModel()

    var body: some View {
        VStack {
            HStack {
                Button("Load Video") {
                    
                }
                Button("Save Video") {
                    
                }
            }
            Grid {
                GridRow {
                    Text("Intro: Age: 12/Coaches:/SC of Boston")
                    VStack {
                        Button("Start Now") {
                            
                        }
                        Text("0m 8.5s")
                    }
                }
                GridRow {
                    Text("Intro: Music: ")
                    VStack {
                        Button("Start Now") {
                            
                        }
                        Text("0m 13.5s")
                    }
                }
                GridRow {
                    Text("Blank")
                    VStack {
                        Button("Start Now") {
                            
                        }
                        Text("0m 18.5s")
                    }
                }
                GridRow {
                    Text("Element 1: 1 Axel")
                    VStack {
                        Button("Start Now") {
                            
                        }
                        Text("--")
                    }
                }
                GridRow {
                    Text("Blank")
                    VStack {
                        Button("Start Now") {
                            
                        }
                        Text("--")
                    }
                }
            }
            Button("Edit Slides") {
                
            }
        }
    }
}

#Preview {
    MainView()
}
