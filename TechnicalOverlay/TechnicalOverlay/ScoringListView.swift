//
//  ScoringListView.swift
//  TechnicalOverlay
//
//  Created by Jerry Hsu on 10/19/25.
//

import SwiftUI

struct ScoringListView: View {
    @State private var firstName: String = ""
    @State private var lastName: String = ""
    @State private var elementName: String = "1 Axel"
    
    var body: some View {
        ScrollView {
            Grid {
                GridRow {
                    Text("Full Name")
                    TextField("Used for Introduction Slides", text: $firstName)
                }
                GridRow {
                    Text("Abbreviated Name")
                    TextField("Used for Technical Scores", text: $lastName)
                }
            }
            Divider()
            Grid {
                Text("Introduction Slides")
                GridRow {
                    Text("Left")
                    Text("Center")
                    Text("Right")
                }
                GridRow {
                    Text("Age: 12")
                    Text("Coaches: Philip Deyesso, Renée Lauren-Roos")
                    Text("SC of Boston")
                }
                GridRow {
                    Text("")
                    Text("Music: The Mask of Zorro by James Horner")
                    Text("")
                }
            }
            Button("Add Slide") {
                
            }
            Divider()
            Button("Import Scores") {
                
            }
            Grid {
                GridRow {
                    Text("#")
                    Text("Element")
                    Text("Base Value")
                    Text("GOE")
                    Text("Bonus")
                }
                GridRow {
                    Text("1")
                    TextField("Element", text: $elementName)
                    Text("1.10")
                    Text("0.11")
                    Text("")
                }
                GridRow {
                    Text("2")
                }
            }
            Button("Add Element") {
                
            }
        }
    }
}

#Preview {
    ScoringListView()
}
