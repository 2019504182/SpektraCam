import XCTest

/// Native gestures catch integration faults that pixel/reference checks cannot observe.
final class EditorInteractionTests: XCTestCase {
    @MainActor func testLUTManagerPresentation() throws {
        let app = importPhoto()
        let manager = app.buttons["library.luts"]
        XCTAssertTrue(manager.waitForExistence(timeout: 5))
        XCTAssertLessThan(app.staticTexts["library.count"].frame.maxY, manager.frame.minY)
        manager.tap()
        XCTAssertTrue(app.buttons["lut.import"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["lut.delete"].isEnabled)
        XCTAssertFalse(app.buttons["lut.none"].exists, "Manager must not edit a photo's LUT assignment")
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Shared LUT Manager"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.buttons["lut.library.close"].tap()
        XCTAssertTrue(manager.waitForExistence(timeout: 5))
    }
    @MainActor func testCameraPresentationKeepsEditor() throws {
        let app = importPhoto()
        app.buttons["camera.open"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["camera.unavailable"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["camera.shutter"].isEnabled)
        XCTAssertEqual(app.buttons["camera.shutter"].frame.midX, app.frame.midX, accuracy: 1,
            "The camera shutter is not centered")
        app.buttons["camera.library"].tap()
        XCTAssertTrue(app.buttons["library.import"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["camera.close"].exists)
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'library.photo.'")).firstMatch.tap()
        XCTAssertTrue(app.buttons["photo.develop"].waitForExistence(timeout: 10))
        app.buttons["camera.open"].tap()
        XCTAssertTrue(app.buttons["camera.close"].waitForExistence(timeout: 5))
        app.buttons["camera.close"].tap()
        app.buttons["photo.develop"].tap()
        XCTAssertTrue(app.buttons["editor.back"].waitForExistence(timeout: 30))
        app.buttons["camera.open"].tap()
        XCTAssertTrue(app.buttons["camera.close"].waitForExistence(timeout: 5))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Simulator camera unavailable"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.buttons["camera.close"].tap()
        XCTAssertTrue(app.buttons["editor.back"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.buttons["editor.expand"].value as? String, "Expanded")
    }
    @MainActor func testCameraLibraryReturnsToRoot() {
        let app = openPhoto()
        app.buttons["camera.open"].tap()
        XCTAssertTrue(app.buttons["camera.library"].waitForExistence(timeout: 10))
        app.buttons["camera.library"].tap()
        XCTAssertTrue(app.buttons["library.import"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["editor.back"].exists)
        XCTAssertFalse(app.buttons["photo.develop"].exists)
        XCTAssertFalse(app.buttons["camera.close"].exists)
    }
    @MainActor func testRevertSelectedPhoto() throws {
        let app = openPhoto()
        app.buttons["editor.back"].tap()
        XCTAssertTrue(app.buttons["photo.develop"].waitForExistence(timeout: 30))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["library.select"].waitForExistence(timeout: 5))
        app.buttons["library.select"].tap()
        XCTAssertTrue(app.buttons["library.revert"].waitForExistence(timeout: 5))
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: app.buttons["library.import"])
        waitForExpectations(timeout: 5)
        XCTAssertFalse(app.buttons["library.revert"].isEnabled)
        libraryPhotos(app).firstMatch.tap()
        XCTAssertTrue(app.buttons["library.revert"].isEnabled)
        app.buttons["library.revert"].tap()
        XCTAssertTrue(app.buttons["Revert to Original"].waitForExistence(timeout: 5))
        if app.buttons["Cancel"].exists {
            app.buttons["Cancel"].tap()
        } else {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)).tap()
        }
        XCTAssertTrue(app.descendants(matching: .any)["photo.badge.edited"].exists)
        app.buttons["library.revert"].tap()
        app.buttons["Revert to Original"].tap()
        let original = NSPredicate(format: "value == %@", "Original")
        expectation(for: original, evaluatedWith: libraryPhotos(app).firstMatch)
        waitForExpectations(timeout: 10)
        XCTAssertFalse(app.descendants(matching: .any)["photo.badge.edited"].exists)
        app.buttons["library.select"].tap()
        XCTAssertTrue(app.buttons["library.import"].exists)
    }
    @MainActor func testNativeZoomAndGuardedExit() throws {
        let app = openPhoto()
        app.buttons["editor.tool.develop"].tap()
        let photo = app.images["Edited photo"]
        XCTAssertTrue(photo.waitForExistence(timeout: 30))
        let fit = NSPredicate(format: "value == %@", "100 percent zoom")
        expectation(for: fit, evaluatedWith: photo)
        waitForExpectations(timeout: 15)
        photo.doubleTap()
        let zoomed = NSPredicate(format: "value != %@", "100 percent zoom")
        expectation(for: zoomed, evaluatedWith: photo)
        waitForExpectations(timeout: 10)
        let compareZoom = photo.value as? String
        app.buttons["editor.compare"].tap()
        XCTAssertEqual(photo.value as? String, compareZoom, "Compare reset the zoom")
        app.buttons["editor.compare"].tap()
        XCTAssertEqual(photo.value as? String, compareZoom, "Returning to edits reset the zoom")
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
        app.buttons["editor.back"].tap()
        XCTAssertTrue(app.buttons["photo.develop"].waitForExistence(timeout: 30))
        XCTAssertFalse(app.sheets["Return to Photo?"].exists)
        XCTAssertFalse(app.buttons["editor.back"].exists)
    }
    @MainActor func testCompareKeepsCroppedZoom() {
        let app = openPhoto()
        app.buttons["editor.tool.crop"].tap()
        app.buttons["crop.ratio.square"].tap()
        app.buttons["editor.tool.adjust"].tap()
        app.buttons["editor.tool.adjust"].tap()
        let photo = app.images["Edited photo"]
        let square = NSPredicate { _, _ in abs(photo.frame.width - photo.frame.height) < 2 }
        expectation(for: square, evaluatedWith: photo)
        waitForExpectations(timeout: 15)
        photo.doubleTap()
        let zoomed = NSPredicate(format: "value != %@", "100 percent zoom")
        expectation(for: zoomed, evaluatedWith: photo)
        waitForExpectations(timeout: 10)
        let value = photo.value as? String
        XCTAssertLessThan(photo.frame.minY, app.buttons["editor.info"].frame.maxY,
            "Zoomed photo cannot extend behind the information panel")
        app.buttons["editor.compare"].tap()
        XCTAssertEqual(photo.value as? String, value, "Comparing an uncropped original reset zoom")
        app.buttons["editor.compare"].tap()
        XCTAssertEqual(photo.value as? String, value, "Returning to a crop reset zoom")
        let capture = XCTAttachment(screenshot: app.screenshot())
        capture.name = "Cropped comparison preserves zoom behind glass"
        capture.lifetime = .keepAlways
        add(capture)
    }
    @MainActor private func importPhoto(count: Int = 1) -> XCUIApplication {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication(bundleIdentifier: "io.github.runzeni.andreavolpato-spektrafilm")
        app.launchArguments = ["--ui-test-library", "--reset-test-library"]
        app.launch()
        XCTAssertTrue(app.buttons["library.import"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["library.delete"].isEnabled)
        app.buttons["library.import"].tap()
        app.buttons["From Photos"].tap()
        // Prefer native picker elements. Some Simulator runs expose only its remote surface.
        let cells = app.images.matching(identifier: "PXGGridLayout-Info")
        if cells.firstMatch.waitForExistence(timeout: 5) {
            cells.element(boundBy: 0).tap()
            if count > 1 { cells.element(boundBy: 1).tap() }
        } else {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.167, dy: 0.24)).press(forDuration: 0.15)
            if count > 1 {
                app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.24)).press(forDuration: 0.15)
            }
        }
        let picked = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        picked.name = "System picker selection"
        picked.lifetime = .keepAlways
        self.add(picked)
        let done = app.navigationBars["Photos"].buttons["Done"]
        if done.exists {
            XCTAssertTrue(done.isEnabled)
            done.tap()
        } else {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.91, dy: 0.115)).press(forDuration: 0.15)
        }
        let photo = libraryPhotos(app).firstMatch
        XCTAssertTrue(photo.waitForExistence(timeout: 30), app.debugDescription)
        return app
    }
    /// A physical thumb drag also checks the new native glass track, independent of AX value formatting.
    @MainActor private func drag(_ slider: XCUIElement, to position: CGFloat) {
        let current: CGFloat
        if let number = slider.value as? NSNumber {
            current = CGFloat(number.doubleValue)
        } else {
            let text = slider.value as? String ?? "50%"
            let number =
                Double(text.replacingOccurrences(of: "%", with: "")) ?? (text.contains("%") ? 50 : 0.5)
            current = CGFloat(text.contains("%") ? number / 100 : number)
        }
        slider.coordinate(withNormalizedOffset: CGVector(dx: current, dy: 0.5)).press(
            forDuration: 0.1,
            thenDragTo: slider.coordinate(withNormalizedOffset: CGVector(dx: position, dy: 0.5)),
            withVelocity: .slow, thenHoldForDuration: 0.1)
    }
    @MainActor private func libraryPhotos(_ app: XCUIApplication) -> XCUIElementQuery {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'library.photo.'"))
    }
    @MainActor private func openPhoto() -> XCUIApplication {
        let app = importPhoto()
        libraryPhotos(app).firstMatch.tap()
        XCTAssertTrue(app.buttons["photo.develop"].waitForExistence(timeout: 10))
        app.buttons["photo.develop"].tap()
        XCTAssertTrue(app.buttons["editor.histogram"].waitForExistence(timeout: 30))
        return app
    }

    @MainActor func testLibraryRestartEditAndDelete() {
        let app = openPhoto()
        app.buttons["editor.tool.adjust"].tap()
        let slider = app.sliders["tone.exposure"]
        XCTAssertTrue(slider.waitForExistence(timeout: 5))
        drag(slider, to: 0.75)
        let savedValue = app.buttons["tone.exposure.value"].value as? String
        XCTAssertNotEqual(savedValue, "0 EV")
        // A recipe also survives termination without using the editor's Save action.
        Thread.sleep(forTimeInterval: 0.5)
        app.terminate()
        app.launchArguments = ["--ui-test-library"]
        app.launch()
        XCTAssertTrue(libraryPhotos(app).firstMatch.waitForExistence(timeout: 15))
        libraryPhotos(app).firstMatch.tap()
        app.buttons["photo.develop"].tap()
        XCTAssertTrue(app.buttons["editor.tool.adjust"].waitForExistence(timeout: 30))
        app.buttons["editor.tool.adjust"].tap()
        XCTAssertEqual(app.buttons["tone.exposure.value"].value as? String, savedValue)
        app.buttons["editor.back"].tap()
        XCTAssertTrue(app.buttons["photo.delete"].waitForExistence(timeout: 30))
        app.buttons["photo.delete"].tap()
        app.buttons["Delete App Copy"].tap()
        XCTAssertTrue(app.buttons["library.import"].waitForExistence(timeout: 10))
        XCTAssertEqual(libraryPhotos(app).count, 0)
        app.terminate()
        app.launch()
        XCTAssertTrue(app.staticTexts["Your Library"].waitForExistence(timeout: 10))
        XCTAssertEqual(libraryPhotos(app).count, 0)
    }

    @MainActor func testLibraryFiltersSelectionAndOriginalExport() {
        let app = importPhoto()
        app.buttons["library.filter"].tap()
        app.buttons["RAW"].tap()
        // The seeded first asset is a rendered photo.
        XCTAssertTrue(app.staticTexts["No RAW Photos"].waitForExistence(timeout: 5))
        app.buttons["library.filter"].tap()
        app.buttons["All"].tap()
        XCTAssertTrue(libraryPhotos(app).firstMatch.waitForExistence(timeout: 5))
        app.buttons["library.select"].tap()
        XCTAssertFalse(app.buttons["library.delete"].isEnabled)
        libraryPhotos(app).firstMatch.tap()
        XCTAssertTrue(app.buttons["library.delete"].isEnabled)
        XCTAssertTrue(app.buttons["Cancel Selection"].exists)
        app.buttons["library.select"].tap()
        XCTAssertFalse(app.buttons["library.delete"].isEnabled)
        libraryPhotos(app).firstMatch.tap()
        app.buttons["photo.export"].tap()
        XCTAssertTrue(app.buttons["S"].waitForExistence(timeout: 10))
        app.buttons["S"].tap()
        XCTAssertTrue(app.buttons["export.save"].waitForExistence(timeout: 30))
        XCTAssertTrue(app.buttons["export.save"].isHittable)
        XCTAssertTrue(app.buttons["export.share"].isHittable)
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["photo.develop"].waitForExistence(timeout: 5))
        let image = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        image.name = "Photo view before development"
        image.lifetime = .keepAlways
        add(image)
    }

    @MainActor func testFilmstripAndEditedBadge() {
        let app = importPhoto(count: 2)
        XCTAssertEqual(libraryPhotos(app).count, 2)
        let firstID = libraryPhotos(app).element(boundBy: 0).identifier.replacingOccurrences(
            of: "library.photo.", with: "")
        let secondID = libraryPhotos(app).element(boundBy: 1).identifier.replacingOccurrences(
            of: "library.photo.", with: "")
        libraryPhotos(app).element(boundBy: 0).tap()
        let first = app.buttons["photo.filmstrip." + firstID]
        let second = app.buttons["photo.filmstrip." + secondID]
        XCTAssertTrue(first.waitForExistence(timeout: 10))
        XCTAssertTrue(first.isSelected)
        second.tap()
        XCTAssertTrue(second.isSelected)
        XCTAssertFalse(first.isSelected)
        app.buttons["photo.develop"].tap()
        XCTAssertTrue(app.buttons["editor.back"].waitForExistence(timeout: 30))
        app.buttons["editor.back"].tap()
        XCTAssertTrue(app.buttons["photo.develop"].waitForExistence(timeout: 30))
        XCTAssertEqual(second.value as? String, "Edited")
        app.navigationBars.buttons["BackButton"].tap()
        XCTAssertTrue(libraryPhotos(app).firstMatch.waitForExistence(timeout: 10))
        let edited = app.buttons["library.photo." + secondID]
        XCTAssertEqual(edited.value as? String, "Edited")
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "Edited badge in gallery"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor func testPhotoInformationAndCanvasBounds() {
        let app = openPhoto()
        let info = app.buttons["editor.info"]
        XCTAssertTrue(info.waitForExistence(timeout: 10))
        let image = app.images["Edited photo"]
        XCTAssertTrue(image.waitForExistence(timeout: 20))
        XCTAssertEqual(info.value as? String, "Collapsed")
        let toolbar =
            ["crop", "develop", "adjust", "effects"].map { app.buttons["editor.tool." + $0] }
            + [app.buttons["editor.export"]]
        for button in toolbar {
            XCTAssertGreaterThanOrEqual(button.frame.width, 44, "Tool touch area is too narrow")
            XCTAssertEqual(button.frame.minY, toolbar[0].frame.minY, accuracy: 1)
        }
        // Native toolbar segments expose their 36 pt visual frame inside a 48 pt glass surface.
        // Check the required 44 pt touch height with physical taps outside that visual frame.
        for name in ["crop", "develop", "adjust", "effects"] {
            let button = app.buttons["editor.tool." + name]
            let center = button.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            center.withOffset(CGVector(dx: 0, dy: -21)).tap()
            XCTAssertTrue(button.isSelected, "The native tool did not accept its upper touch edge")
            center.withOffset(CGVector(dx: 0, dy: 21)).tap()
            XCTAssertFalse(button.isSelected, "The native tool did not accept its lower touch edge")
        }
        app.buttons["editor.tool.develop"].tap()
        let before = image.frame
        XCTAssertGreaterThanOrEqual(before.minY, info.frame.maxY + 6)
        XCTAssertLessThanOrEqual(before.maxY, app.buttons["editor.tool.develop"].frame.minY + 1)
        app.buttons["editor.histogram"].tap()
        XCTAssertEqual(info.value as? String, "Collapsed", "Histogram opened photo details")
        info.tap()
        XCTAssertEqual(info.value as? String, "Expanded")
        XCTAssertEqual(image.frame.minY, before.minY, accuracy: 1)
        XCTAssertEqual(image.frame.height, before.height, accuracy: 1)
        app.buttons["editor.histogram"].tap()
        XCTAssertEqual(info.value as? String, "Expanded", "Histogram closed photo details")
        info.tap()
        XCTAssertEqual(info.value as? String, "Collapsed")
        app.buttons["editor.tool.crop"].tap()
        XCTAssertFalse(app.buttons["editor.info"].exists)
        app.buttons["editor.back"].tap()
        XCTAssertTrue(app.buttons["photo.info"].waitForExistence(timeout: 30))
        XCTAssertTrue(
            app.descendants(matching: .any).matching(identifier: "photo.banner.date").firstMatch.exists)
        let badge = app.images["photo.badge.edited"]
        XCTAssertTrue(badge.exists)
        XCTAssertLessThan(badge.frame.maxY, app.buttons["photo.info"].frame.minY)
        let viewerInfo = app.buttons["photo.info"]
        app.buttons["photo.histogram"].tap()
        XCTAssertEqual(viewerInfo.value as? String, "Collapsed")
        viewerInfo.tap()
        XCTAssertEqual(viewerInfo.value as? String, "Expanded")
    }

    @MainActor func testGroupedPanelsAndSliderReset() {
        let app = openPhoto()
        XCTAssertEqual(app.buttons["editor.expand"].value as? String, "Expanded")
        let compare = app.buttons["editor.compare"]
        XCTAssertGreaterThanOrEqual(compare.frame.minY, app.buttons["editor.info"].frame.maxY)
        XCTAssertTrue(app.buttons["Camera"].exists)
        app.buttons["editor.tool.adjust"].tap()
        drag(app.sliders["tone.exposure"], to: 0.7)
        XCTAssertNotEqual(app.buttons["tone.exposure.value"].value as? String, "0 EV")
        app.buttons["editor.history"].tap()
        app.buttons["Undo"].tap()
        XCTAssertEqual(
            app.buttons["tone.exposure.value"].value as? String, "0 EV", "A drag must undo in one step")
        let contrast = app.sliders["tone.contrast"]
        XCTAssertTrue(contrast.waitForExistence(timeout: 5))
        drag(contrast, to: 0.8)
        XCTAssertNotEqual(
            (app.buttons["tone.contrast.value"].value as? String)?.trimmingCharacters(in: .whitespaces), "1")
        contrast.doubleTap()
        XCTAssertEqual(
            (app.buttons["tone.contrast.value"].value as? String)?.trimmingCharacters(in: .whitespaces), "1")
        app.buttons["editor.expand"].tap()
        XCTAssertEqual(app.buttons["editor.expand"].value as? String, "Expanded")
        app.images["Edited photo"].coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.02)).tap()
        XCTAssertTrue(
            XCTWaiter.wait(
                for: [
                    XCTNSPredicateExpectation(
                        predicate: NSPredicate(format: "value == %@", "Collapsed"),
                        object: app.buttons["editor.expand"])
                ], timeout: 3) == .completed)
        app.buttons["adjust.section.liftGain"].tap()
        XCTAssertTrue(app.sliders["tone.shadows"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.sliders["tone.highlights"].waitForExistence(timeout: 5))
        XCTAssertLessThan(app.sliders["tone.highlights"].frame.minY, app.sliders["tone.shadows"].frame.minY)
        app.buttons["adjust.section.color"].tap()
        let bw = app.descendants(matching: .any).matching(identifier: "tone.monochrome").firstMatch
        XCTAssertTrue(bw.waitForExistence(timeout: 5))
        bw.tap()
        XCTAssertEqual(bw.value as? String, "1")
        app.buttons["editor.tool.effects"].tap()
        let grain = app.descendants(matching: .any).matching(identifier: "grain.monochrome").firstMatch
        XCTAssertTrue(grain.waitForExistence(timeout: 5))
        grain.tap()
        XCTAssertEqual(grain.value as? String, "1")
        app.buttons["effects.section.halation"].tap()
        XCTAssertTrue(
            app.descendants(matching: .any).matching(identifier: "film_render.halation.active").firstMatch
                .waitForExistence(timeout: 5))
        app.buttons["effects.section.diffusion"].tap()
        XCTAssertTrue(
            app.descendants(matching: .any).matching(identifier: "camera.diffusion_filter.active").firstMatch
                .waitForExistence(timeout: 5))
        app.buttons["editor.back"].tap()
        XCTAssertTrue(app.buttons["photo.develop"].waitForExistence(timeout: 30))
    }

    @MainActor func testSourceResetAndDiffusionControls() {
        let app = openPhoto()
        app.buttons["editor.tool.adjust"].tap()
        let exposure = app.sliders["tone.exposure"]
        XCTAssertTrue(exposure.waitForExistence(timeout: 5))
        drag(exposure, to: 0.6)
        let entered = app.buttons["tone.exposure.value"]
        XCTAssertNotEqual(entered.value as? String, "0 EV")
        app.buttons["editor.history"].tap()
        app.buttons["Reset All Edits"].tap()
        let reset = app.alerts["Reset all edits?"]
        XCTAssertTrue(reset.waitForExistence(timeout: 5))
        reset.buttons["Reset All Edits"].tap()
        expectation(for: NSPredicate(format: "value == %@", "0 EV"), evaluatedWith: entered)
        waitForExpectations(timeout: 10)
        app.buttons["editor.tool.effects"].tap()
        let area = app.sliders["film_render.grain.particle_area_um2"]
        let areaValue = app.buttons["film_render.grain.particle_area_um2.value"]
        let stockArea = areaValue.value as? String
        drag(area, to: 0.5)
        XCTAssertNotEqual(areaValue.value as? String, stockArea)
        app.buttons["grain.stockDefaults"].tap()
        XCTAssertEqual(areaValue.value as? String, stockArea)
        XCTAssertLessThan(
            app.buttons["grain.stockDefaults"].frame.maxY,
            app.buttons["film_render.grain.details"].frame.minY)
        app.buttons["effects.section.halation"].tap()
        let scatter = app.buttons["film_render.halation.scatter_amount.value"]
        XCTAssertEqual(scatter.value as? String, "100 %")
        let halation = app.sliders["film_render.halation.halation_amount"]
        drag(halation, to: 0.8)
        let amount = app.buttons["film_render.halation.halation_amount.value"].value as? String ?? ""
        XCTAssertGreaterThan(Double(amount.split(separator: " ").first ?? "0") ?? 0, 5)
        app.buttons["effects.section.diffusion"].tap()
        for key in ["camera.diffusion_filter.active", "enlarger.diffusion_filter.active"] {
            let toggle = app.descendants(matching: .any).matching(identifier: key).firstMatch
            XCTAssertTrue(toggle.waitForExistence(timeout: 5))
            for _ in 0..<8 {
                let controls = app.scrollViews["editor.controls"].frame
                let top = controls.minY + 12
                let bottom = controls.maxY - 12
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
        expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: save)
        waitForExpectations(timeout: 45)
        XCTAssertTrue(save.isHittable, "Default export layout hid Save to Photos")
        XCTAssertTrue(app.buttons["export.share"].isHittable)
        XCTAssertGreaterThan(
            app.buttons["Done"].frame.minY, app.frame.height * 0.4, "Export opened at full height")
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
