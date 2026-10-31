import XCTest

/// Native gestures catch integration faults that pixel/reference checks cannot observe.
final class EditorInteractionTests: XCTestCase {
    @MainActor func testNativeZoomAndGuardedExit() throws {
        let app = openPhoto()
        let photo = app.images["Edited photo"]
        XCTAssertTrue(photo.waitForExistence(timeout: 30))
        let fit = NSPredicate(format: "value == %@", "100 percent zoom")
        expectation(for: fit, evaluatedWith: photo)
        waitForExpectations(timeout: 15)
        photo.doubleTap()
        let zoomed = NSPredicate(format: "value != %@", "100 percent zoom")
        expectation(for: zoomed, evaluatedWith: photo)
        waitForExpectations(timeout: 10)
        let zoomImage = XCTAttachment(screenshot: app.screenshot())
        zoomImage.name = "Native double tap zoom"
        zoomImage.lifetime = .keepAlways
        add(zoomImage)
        let doubleTapValue = photo.value as? String
        photo.pinch(withScale: 1.2, velocity: 1)
        XCTAssertNotEqual(photo.value as? String, doubleTapValue, "Native pinch did not change zoom")
        photo.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(
                forDuration: 0.05,
                thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.4)))
        photo.doubleTap()
        expectation(for: fit, evaluatedWith: photo)
        waitForExpectations(timeout: 10)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.001, dy: 0.4))
            .press(
                forDuration: 0.05,
                thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.4)))
        XCTAssertTrue(app.buttons["editor.back"].exists, "Editing allowed an accidental navigation pop")
        app.buttons["editor.back"].tap()
        XCTAssertTrue(app.sheets["Return to Photos?"].waitForExistence(timeout: 5))
        // Native popovers dismiss by tapping outside; they omit a separate Cancel row.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.4)).tap()
        XCTAssertTrue(app.buttons["editor.histogram"].exists)
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = "Native zoom and guarded exit"
        image.lifetime = .keepAlways
        add(image)
        let portraitPhoto = photo.frame
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        XCTAssertGreaterThan(
            app.frame.height, app.frame.width, "The iPhone interface rotated out of portrait")
        XCTAssertEqual(photo.frame.height, portraitPhoto.height, accuracy: 1)
        XCTAssertEqual(photo.frame.width, portraitPhoto.width, accuracy: 1)
        let locked = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        locked.name = "iPhone portrait orientation lock"
        locked.lifetime = .keepAlways
        add(locked)
    }
    @MainActor private func openPhoto() -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "io.github.runzeni.andreavolpato-spektrafilm")
        app.launch()
        let open = app.buttons["checkmark"]
        XCTAssertTrue(open.waitForExistence(timeout: 15))
        // The picker can finish loading after the toolbar appears on a cold launch.
        let ready = NSPredicate(format: "enabled == true")
        for _ in 0..<3 {
            if open.isEnabled { break }
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.167, dy: 0.29)).tap()
            let selection = XCTNSPredicateExpectation(predicate: ready, object: open)
            if XCTWaiter.wait(for: [selection], timeout: 3) == .completed { break }
        }
        XCTAssertTrue(open.isEnabled, "The seeded Simulator photo was not selected")
        open.tap()
        XCTAssertTrue(app.buttons["editor.histogram"].waitForExistence(timeout: 30))
        return app
    }

    @MainActor func testSourceResetAndDiffusionControls() {
        let app = openPhoto()
        app.buttons["editor.tool.adjust"].tap()
        let exposure = app.sliders["source.exposure"]
        XCTAssertTrue(exposure.waitForExistence(timeout: 5))
        exposure.adjust(toNormalizedSliderPosition: 0.6)
        let entered = app.buttons["source.exposure.value"]
        XCTAssertNotEqual(entered.value as? String, "0 EV")
        app.buttons["editor.history"].tap()
        app.buttons["Reset All Edits"].tap()
        let reset = app.alerts["Reset all edits?"]
        XCTAssertTrue(reset.waitForExistence(timeout: 5))
        reset.buttons["Reset All Edits"].tap()
        XCTAssertEqual(entered.value as? String, "0 EV")
        app.buttons["editor.tool.effects"].tap()
        let area = app.sliders["film_render.grain.particle_area_um2"]
        let areaValue = app.buttons["film_render.grain.particle_area_um2.value"]
        let stockArea = areaValue.value as? String
        area.adjust(toNormalizedSliderPosition: 0.5)
        XCTAssertNotEqual(areaValue.value as? String, stockArea)
        app.buttons["grain.stockDefaults"].tap()
        XCTAssertEqual(areaValue.value as? String, stockArea)
        let controls = app.scrollViews["editor.controls"]
        for key in ["camera.diffusion_filter.active", "enlarger.diffusion_filter.active"] {
            let toggle = app.descendants(matching: .any).matching(identifier: key).firstMatch
            for _ in 0..<8 {
                let top = controls.frame.minY + 24
                let bottom = app.buttons["editor.tool.effects"].frame.minY - 24
                if toggle.isHittable && toggle.frame.minY >= top && toggle.frame.maxY <= bottom { break }
                let upwards = toggle.frame.midY > (top + bottom) / 2
                let origin = app.coordinate(withNormalizedOffset: .zero)
                let start = origin.withOffset(CGVector(dx: app.frame.midX, dy: upwards ? bottom : top))
                let end = origin.withOffset(CGVector(dx: app.frame.midX, dy: (top + bottom) / 2))
                start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.2)
            }
            XCTAssertTrue(toggle.isHittable, app.debugDescription)
            toggle.tap()
            XCTAssertEqual(toggle.value as? String, "1")
            XCTAssertLessThanOrEqual(toggle.frame.maxX, app.frame.maxX)
        }
        let busy = app.progressIndicators["Rendering preview"]
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: busy)
        waitForExpectations(timeout: 30)
        XCTAssertFalse(app.staticTexts["Couldn’t update preview"].exists)
        XCTAssertTrue(app.buttons["editor.back"].exists)
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = "Both diffusion stages enabled"
        image.lifetime = .keepAlways
        add(image)
    }

    @MainActor func testExportOptionsAndCancellation() {
        let app = openPhoto()
        app.buttons["editor.export"].tap()
        XCTAssertTrue(app.buttons["S"].waitForExistence(timeout: 5))
        app.buttons["S"].tap()
        app.buttons["PNG"].tap()
        app.buttons["JPEG"].tap()
        app.buttons["Standard"].tap()
        let save = app.buttons["export.save"]
        XCTAssertTrue(save.waitForExistence(timeout: 45))
        XCTAssertTrue(save.isHittable, "Default export layout hid Save to Photos")
        XCTAssertTrue(app.buttons["export.share"].isHittable)
        let dimensions = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "1080")).firstMatch
        XCTAssertTrue(dimensions.exists)
        XCTAssertFalse(
            app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "needs more rendering memory"))
                .firstMatch.exists)
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = "Native export options"
        image.lifetime = .keepAlways
        add(image)
    }

}
