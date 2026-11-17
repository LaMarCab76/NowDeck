import XCTest
@testable import Nowdeck

/// Detail of a playlist or an album: the two track-list requests, their models, the rows
/// and `CollectionDetailModel` (first page, more pages, restricted playlists, errors).
@MainActor
final class CollectionDetailTests: XCTestCase {
    private let album = LibraryEntry(kind: .album, uri: "spotify:album:a1", name: "Costanera",
                                    subtitle: "Álbum · Marea Baja", artworkURL: nil,
                                    pageURL: URL(string: "https://open.spotify.com/album/a1"))
    private let playlist = LibraryEntry(kind: .playlist, uri: "spotify:playlist:p1",
                                       name: "Para laburar", subtitle: "Playlist · 3 temas",
                                       artworkURL: nil, pageURL: nil)

    // MARK: Requests

    func testAlbumTracksRequest() async throws {
        let (api, recorder) = makeLibraryTestAPI { _ in (.stub(200), LibraryJSON.page([])) }

        _ = try await api.albumTracks(albumID: "a1")
        _ = try await api.albumTracks(albumID: "a1", offset: 50)

        XCTAssertEqual(recorder.requests.map { $0.url?.absoluteString }, [
            "https://api.spotify.com/v1/albums/a1/tracks?limit=50&offset=0",
            "https://api.spotify.com/v1/albums/a1/tracks?limit=50&offset=50",
        ])
        XCTAssertTrue(recorder.requests.allSatisfy { $0.httpMethod == "GET" })
    }

    func testPlaylistItemsRequestUsesTheNewPathAndAsksForEpisodes() async throws {
        let (api, recorder) = makeLibraryTestAPI { _ in (.stub(200), LibraryJSON.page([])) }

        _ = try await api.playlistItems(playlistID: "p1")

        let request = try XCTUnwrap(recorder.requests.first)
        XCTAssertEqual(request.url?.path, "/v1/playlists/p1/items",
                       "`/tracks` was removed in February 2026")
        XCTAssertEqual(request.queryValues, [
            "limit": "50",
            "offset": "0",
            "additional_types": "track,episode",
        ])
    }

    func testIDsCannotChangeThePath() async throws {
        let (api, recorder) = makeLibraryTestAPI { _ in (.stub(200), LibraryJSON.page([])) }

        _ = try await api.albumTracks(albumID: "../me")

        XCTAssertEqual(recorder.requests.first?.url?.absoluteString,
                       "https://api.spotify.com/v1/albums/%2E%2E%2Fme/tracks?limit=50&offset=0")
    }

    func testPlaylistItemsReadItemAndTheDeprecatedTrackKey() async throws {
        let body = LibraryJSON.page([
            LibraryJSON.playlistItem(LibraryJSON.track("Nuevo", id: "t1")),
            LibraryJSON.playlistItem(LibraryJSON.track("Viejo", id: "t2"), legacyKey: true),
            LibraryJSON.playlistItem(nil),
        ], total: 3)
        let (api, _) = makeLibraryTestAPI { _ in (.stub(200), body) }

        let page = try await api.playlistItems(playlistID: "p1")

        XCTAssertEqual(page.items.map { $0.content?.name }, ["Nuevo", "Viejo", nil])
        XCTAssertEqual(page.total, 3)
    }

    // MARK: Rows

    func testRowsShowArtistsShowNamesAndAvailability() throws {
        let decoder = SpotifyAPI.makeDecoder()
        func item(_ object: [String: Any]) throws -> CollectionItem {
            try decoder.decode(CollectionItem.self,
                               from: JSONSerialization.data(withJSONObject: object))
        }

        let rows = CollectionDetailModel.rows([
            (try item(LibraryJSON.track("Loop", id: "t1", artists: ["Los Tilos", "Marea Baja"],
                                        explicit: true)), false),
            (try item(LibraryJSON.episode("Capítulo 4", id: "e1", show: "Charlas")), false),
            (try item(LibraryJSON.track("", id: "t2")), false),
            (try item(LibraryJSON.track("Galpón", id: "t3", isPlayable: false)), false),
            (try item(LibraryJSON.track("Afuera", id: "t4", restriction: "market")), false),
            (try item(LibraryJSON.track("Demo", id: "t5")), true),
        ], from: 10)

        XCTAssertEqual(rows.map(\.title), ["Loop", "Capítulo 4", "Galpón", "Afuera", "Demo"],
                       "Items without a name are dropped")
        XCTAssertEqual(rows.map(\.number), [11, 12, 13, 14, 15])
        XCTAssertEqual(rows.map(\.subtitle),
                       ["Los Tilos, Marea Baja", "Charlas", "Artista", "Artista", "Artista"])
        XCTAssertEqual(rows.map(\.isExplicit), [true, false, false, false, false])
        XCTAssertEqual(rows.map(\.isAvailable), [true, true, false, false, false])
        XCTAssertEqual(rows.first?.pageURL?.absoluteString, "https://open.spotify.com/track/t1")
        XCTAssertNil(rows.last?.pageURL, "Local files have no Spotify page")
    }

    // MARK: Model

    private func makeModel(_ entry: LibraryEntry,
                           handler: @escaping StubURLProtocol.Handler)
        -> (CollectionDetailModel, StubRecorder) {
        let (api, recorder) = makeLibraryTestAPI(handler: handler)
        return (CollectionDetailModel(entry: entry, api: api), recorder)
    }

    func testAlbumLoadsItsTracksAndTotalDuration() async {
        let body = LibraryJSON.page([
            LibraryJSON.track("Intro", id: "t1", durationMs: 72_000),
            LibraryJSON.track("Vereda Mojada", id: "t2", durationMs: 222_000),
        ], limit: 50)
        let (model, recorder) = makeModel(album) { _ in (.stub(200), body) }

        await model.loadIfNeeded()
        await model.loadIfNeeded()

        XCTAssertEqual(model.state, .loaded)
        XCTAssertEqual(model.tracks.map(\.title), ["Intro", "Vereda Mojada"])
        XCTAssertFalse(model.hasMore)
        XCTAssertEqual(model.totalDurationMs, 294_000)
        XCTAssertEqual(model.listLabel, "2 TEMAS · 5 MIN")
        XCTAssertEqual(recorder.requests.count, 1, "Loaded once")
    }

    func testMorePagesContinueTheNumberingAndHideThePartialDuration() async {
        let (model, recorder) = makeModel(playlist) { request in
            let offset = request.queryValues["offset"]
            if offset == "0" {
                return (.stub(200), LibraryJSON.page(
                    [LibraryJSON.playlistItem(LibraryJSON.track("Uno", id: "t1"))],
                    limit: 50, total: 51, hasNext: true))
            }
            return (.stub(200), LibraryJSON.page(
                [LibraryJSON.playlistItem(LibraryJSON.track("Dos", id: "t2"))],
                offset: 50, limit: 50, total: 51))
        }

        await model.load()
        XCTAssertTrue(model.hasMore)
        XCTAssertNil(model.totalDurationMs, "A partial sum would be wrong")
        XCTAssertEqual(model.listLabel, "51 TEMAS")

        await model.loadMore()
        XCTAssertEqual(model.tracks.map(\.number), [1, 2])
        XCTAssertFalse(model.hasMore)
        XCTAssertEqual(recorder.requests.map { $0.queryValues["offset"] }, ["0", "50"])

        await model.loadMore()
        XCTAssertEqual(recorder.requests.count, 2, "Nothing left to load")
    }

    func testFailedPageCanBeRetried() async {
        let calls = OffsetRecorder()
        let (model, _) = makeModel(album) { request in
            calls.record(0)
            if request.queryValues["offset"] == "0" {
                return (.stub(200), LibraryJSON.page([LibraryJSON.track("Uno", id: "t1")],
                                                     limit: 50, hasNext: true))
            }
            if calls.values.count == 2 { return (.stub(404), Data()) }
            return (.stub(200), LibraryJSON.page([LibraryJSON.track("Dos", id: "t2")],
                                                 offset: 50, limit: 50))
        }

        await model.load()
        await model.loadMore()
        XCTAssertTrue(model.loadMoreFailed)
        XCTAssertEqual(model.tracks.count, 1)

        await model.loadMore()
        XCTAssertFalse(model.loadMoreFailed)
        XCTAssertEqual(model.tracks.map(\.title), ["Uno", "Dos"])
    }

    func testPlaylistOfSomeoneElseIsRestricted() async {
        let (model, _) = makeModel(playlist) { _ in
            (.stub(403), spotifyErrorJSON(status: 403, message: "Forbidden"))
        }

        await model.load()

        XCTAssertEqual(model.state, .restricted)
        XCTAssertTrue(model.tracks.isEmpty)
    }

    func testAlbumErrorsBecomeFailures() async {
        let (forbidden, _) = makeModel(album) { _ in
            (.stub(403), spotifyErrorJSON(status: 403, message: "Forbidden"))
        }
        let (limited, _) = makeModel(album) { _ in
            (.stub(429), spotifyErrorJSON(status: 429, message: "Slow down"))
        }
        let (broken, _) = makeModel(album) { _ in (.stub(200), Data("not json".utf8)) }

        await forbidden.load()
        await limited.load()
        await broken.load()

        XCTAssertEqual(forbidden.state, .failed(.forbidden),
                       "Only playlists get the \"not yours\" message")
        XCTAssertEqual(limited.state, .failed(.rateLimited))
        XCTAssertEqual(broken.state, .failed(.failed))
    }

    func testDurationLabel() {
        XCTAssertEqual(CollectionDetailModel.durationLabel(ms: 10_000), "1 MIN")
        XCTAssertEqual(CollectionDetailModel.durationLabel(ms: 41 * 60_000 + 20_000), "41 MIN")
        XCTAssertEqual(CollectionDetailModel.durationLabel(ms: 171 * 60_000), "2 H 51 MIN")
        XCTAssertEqual(CollectionDetailModel.durationLabel(ms: 180 * 60_000), "3 H")
    }

    // MARK: Library

    func testLibraryOpensDetailOnlyForPlaylistsAndAlbums() {
        let (api, _) = makeLibraryTestAPI { _ in (.stub(204), Data()) }
        let library = LibraryModel(api: api)
        let show = LibraryEntry(kind: .show, uri: "spotify:show:s1", name: "Charlas",
                                subtitle: "Podcast", artworkURL: nil, pageURL: nil)

        library.showDetail(of: show)
        XCTAssertNil(library.detail)

        library.showDetail(of: album)
        XCTAssertEqual(library.detail?.entry, album)

        library.closeDetail()
        XCTAssertNil(library.detail)
    }

    func testDetailSubtitles() throws {
        let decoder = SpotifyAPI.makeDecoder()
        var playlistJSON = LibraryJSON.playlist("Para laburar", id: "p1", count: 48)
        playlistJSON["owner"] = ["id": "u1", "display_name": "Lucía"]
        let playlistEntry = try XCTUnwrap(LibraryEntry(playlist: decoder.decode(
            SimplifiedPlaylist.self, from: JSONSerialization.data(withJSONObject: playlistJSON))))
        XCTAssertEqual(playlistEntry.detailSubtitle, "De Lucía · 48 temas")

        var albumJSON = try XCTUnwrap(LibraryJSON.savedAlbum("Costanera", id: "a1",
                                                             artist: "Marea Baja")["album"]
                                      as? [String: Any])
        albumJSON["release_date"] = "2024-03-01"
        let albumEntry = try XCTUnwrap(LibraryEntry(album: decoder.decode(
            SimplifiedAlbum.self, from: JSONSerialization.data(withJSONObject: albumJSON))))
        XCTAssertEqual(albumEntry.detailSubtitle, "Marea Baja · 2024")

        albumJSON["release_date"] = "unknown"
        let noYear = try XCTUnwrap(LibraryEntry(album: decoder.decode(
            SimplifiedAlbum.self, from: JSONSerialization.data(withJSONObject: albumJSON))))
        XCTAssertEqual(noYear.detailSubtitle, "Marea Baja")
    }
}
