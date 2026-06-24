//
//  ChunkSegmentTests.swift
//  TechnicalOverlayTests
//

import Testing
@testable import Technical_Overlay

struct ChunkSegmentTests {

    @Test func renderingHashIdenticalForSameData() {
        let data1 = OverlayData(
            skaterFullName: "Alice",
            skaterAbbreviatedName: "ALI",
            introductionTexts: [],
            elementScores: []
        )
        let data2 = OverlayData(
            skaterFullName: "Alice",
            skaterAbbreviatedName: "ALI",
            introductionTexts: [],
            elementScores: []
        )
        #expect(data1.renderingHash == data2.renderingHash)
    }

    @Test func renderingHashChangesWhenNameChanges() {
        let data1 = OverlayData(skaterFullName: "Alice")
        let data2 = OverlayData(skaterFullName: "Bob")
        #expect(data1.renderingHash != data2.renderingHash)
    }

    @Test func renderingHashChangesWhenTimeChanges() {
        let data = OverlayData(
            skaterFullName: "Alice",
            introductionTexts: [IntroductionData(left: "1P", center: "", right: "", displayTime: 10.0)]
        )
        let hash1 = data.renderingHash
        data.setIntroTime(index: 0, time: 20.0)
        let hash2 = data.renderingHash
        #expect(hash1 != hash2)
    }

    @Test func renderingHashChangesWhenScoreChanges() {
        let data = OverlayData(
            skaterFullName: "Alice",
            elementScores: [ElementData(name: "2A", baseValue: 1500, goeValue: 0, bonusValue: 0)]
        )
        let hash1 = data.renderingHash
        data.elementScores[0].goeValue = 200
        let hash2 = data.renderingHash
        #expect(hash1 != hash2)
    }

    @Test func renderingHashSameForDifferentOrder() {
        // Hash depends on order of elements in arrays.
        let data1 = OverlayData(
            elementScores: [
                ElementData(name: "2A", baseValue: 1500, goeValue: 0, bonusValue: 0),
                ElementData(name: "3T", baseValue: 4300, goeValue: 0, bonusValue: 0),
            ]
        )
        let data2 = OverlayData(
            elementScores: [
                ElementData(name: "2A", baseValue: 1500, goeValue: 0, bonusValue: 0),
                ElementData(name: "3T", baseValue: 4300, goeValue: 0, bonusValue: 0),
            ]
        )
        #expect(data1.renderingHash == data2.renderingHash)
    }

    @Test func renderingHashDiffersForElementOrder() {
        let data1 = OverlayData(
            elementScores: [
                ElementData(name: "2A", baseValue: 1500, goeValue: 0, bonusValue: 0),
                ElementData(name: "3T", baseValue: 4300, goeValue: 0, bonusValue: 0),
            ]
        )
        let data2 = OverlayData(
            elementScores: [
                ElementData(name: "3T", baseValue: 4300, goeValue: 0, bonusValue: 0),
                ElementData(name: "2A", baseValue: 1500, goeValue: 0, bonusValue: 0),
            ]
        )
        #expect(data1.renderingHash != data2.renderingHash)
    }

    @Test func emptyDataHasHash() {
        let data = OverlayData()
        #expect(!data.renderingHash.isEmpty)
    }
}
