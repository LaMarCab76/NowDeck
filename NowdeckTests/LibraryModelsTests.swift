import XCTest
@testable import Nowdeck

/// Decoding of the library and search answers, and their mapping to cards.
final class LibraryModelsTests: XCTestCase {
    private func decode<T: Decodable>(_ type: T.Type, fixture: String) throws -> T {
        try SpotifyAPI.makeDecoder().decode(type, from: Fixture.data(fixture))
    }

    // MARK: Reference examples (developer.spotify.com, 2026-11-17)

    func testDecodesPlaylistsReference() throws {
        let page = try decode(Paging<SimplifiedPlaylist>.self, fixture: "playlists-reference")

        XCTAssertEqual(page.total, 4)
        XCTAssertEqual(page.limit, 20)
        XCTAssertEqual(page.items.count, 1)
        XCTAssertNotNil(page.next)
        XCTAssertEqual(page.nextOffset, 20)
        let playlist = try XCTUnwrap(page.items.first)
        XCTAssertEqual(playlist.name, "string")
        XCTAssertEqual(playlist.images?.first?.width, 300)
        XCTAssertEqual(playlist.items?.total, 0)
        XCTAssertEqual(playlist.tracks?.total, 0)
        XCTAssertEqual(playlist.owner?.displayName, "string")
    }

    func testDecodesSavedAlbumsReference() throws {
        let page = try decode(Paging<SavedAlbum>.self, fixture: "saved-albums-reference")

        XCTAssertEqual(page.total, 4)
        let album = try XCTUnwrap(page.items.first?.album)
        XCTAssertEqual(album.uri, "spotify:album:2up3OPMp9Tb4dAKM2erWXQ")
        XCTAssertEqual(album.albumType, "compilation")
        XCTAssertEqual(album.totalTracks, 9)
        XCTAssertEqual(album.artists?.first?.name, "string")

        let item = try XCTUnwrap(LibraryEntry(album: album))
        XCTAssertEqual(item.kind, .album)
        XCTAssertEqual(item.subtitle, "Álbum · string")
        XCTAssertEqual(item.artworkURL?.absoluteString,
                       "https://i.scdn.co/image/ab67616d00001e02ff9ca10b55ce82ae553c8228")
        XCTAssertEqual(item.pageURL?.absoluteString,
                       "https://open.spotify.com/album/2up3OPMp9Tb4dAKM2erWXQ",
                       "The example's external URL is not a URL: fall back to the URI")
    }

    func testDecodesSavedShowsReference() throws {
        let page = try decode(Paging<SavedShow>.self, fixture: "saved-shows-reference")

        let show = try XCTUnwrap(page.items.first?.show)
        XCTAssertEqual(show.name, "string")
        XCTAssertEqual(show.totalEpisodes, 0)
        XCTAssertEqual(show.images?.count, 1)
        XCTAssertNil(LibraryEntry(show: show), "\"string\" is not a Spotify URI: no card")
    }

    func testDecodesSavedAudiobooksReferenceWithoutWrapper() throws {
        let page = try decode(Paging<SimplifiedAudiobook>.self, fixture: "saved-audiobooks-reference")

        let book = try XCTUnwrap(page.items.first)
        XCTAssertEqual(book.authors?.first?.name, "string")
        XCTAssertEqual(book.narrators?.first?.name, "string")
        XCTAssertEqual(book.totalChapters, 0)
    }

    func testDecodesSearchReference() throws {
        let results = try decode(SearchResults.self, fixture: "search-reference")

        XCTAssertEqual(results.tracks?.items.count, 1)
        XCTAssertEqual(results.albums?.items.count, 1)
        XCTAssertEqual(results.playlists?.items.count, 1)
        XCTAssertEqual(results.shows?.items.count, 1)
        XCTAssertEqual(results.audiobooks?.items.count, 1)
        XCTAssertEqual(results.tracks?.total, 4)
        XCTAssertNotNil(results.tracks?.items.first?.album)
    }

    // MARK: Lenient pages

    func testNullAndMalformedItemsAreDropped() throws {
        let data = LibraryJSON.page([
            LibraryJSON.playlist("Para laburar", id: "p1"),
            NSNull(),
            ["id": "p2", "name": 42] as [String: Any],
            LibraryJSON.playlist("Ruta 2", id: "p3"),
        ], limit: 4, hasNext: true)

        let page = try SpotifyAPI.makeDecoder().decode(Paging<SimplifiedPlaylist>.self, from: data)

        XCTAssertEqual(page.items.map(\.name), ["Para laburar", "Ruta 2"])
        XCTAssertEqual(page.nextOffset, 4, "Dropped items still count for the next offset")
    }

    func testLastPageHasNoNextOffset() throws {
        let data = LibraryJSON.page([LibraryJSON.playlist("A", id: "a")], offset: 40)
        let page = try SpotifyAPI.makeDecoder().decode(Paging<SimplifiedPlaylist>.self, from: data)
        XCTAssertNil(page.nextOffset)
    }

    // MARK: Cards

    func testPlaylistCountPrefersItemsOverDeprecatedTracks() throws {
        let both = #"{"uri": "spotify:playlist:p1", "items": {"total": 48}, "tracks": {"total": 3}}"#
        let old = #"{"uri": "spotify:playlist:p1", "tracks": {"total": 3}}"#
        let decoder = SpotifyAPI.makeDecoder()

        XCTAssertEqual(try decoder.decode(SimplifiedPlaylist.self, from: Data(both.utf8)).itemCount, 48)
        XCTAssertEqual(try decoder.decode(SimplifiedPlaylist.self, from: Data(old.utf8)).itemCount, 3)
    }

    func testCardSubtitles() {
        func playlist(_ count: Int?) -> String? {
            LibraryEntry(playlist: SimplifiedPlaylist(name: "P", uri: "spotify:playlist:p",
                                                     items: count.map { ItemCount(total: $0) }))?
                .subtitle
        }
        XCTAssertEqual(playlist(48), "Playlist · 48 temas")
        XCTAssertEqual(playlist(1), "Playlist · 1 tema")
        XCTAssertEqual(playlist(nil), "Playlist")

        let album = SimplifiedAlbum(name: "Costanera", uri: "spotify:album:a",
                                    artists: [ArtistSummary(name: "Marea Baja"),
                                              ArtistSummary(name: "Inés Varela")])
        XCTAssertEqual(LibraryEntry(album: album)?.subtitle, "Álbum · Marea Baja, Inés Varela")

        let show = SimplifiedShow(name: "Charla", uri: "spotify:show:s", totalEpisodes: 7)
        XCTAssertEqual(LibraryEntry(show: show)?.subtitle, "Podcast · 7 episodios")

        let book = SimplifiedAudiobook(name: "El faro", uri: "spotify:audiobook:b",
                                       authors: [.init(name: "R. Ferreyra")])
        XCTAssertEqual(LibraryEntry(audiobook: book)?.subtitle, "Audiolibro · R. Ferreyra")
    }

    func testNamesAreKeptVerbatim() {
        let name = "**Lo mejor** de [2026](https://example.com) %@"
        let item = LibraryEntry(playlist: SimplifiedPlaylist(name: name, uri: "spotify:playlist:p"))
        XCTAssertEqual(item?.name, name)
    }

    func testItemsWithoutValidURIAreDropped() {
        XCTAssertNil(LibraryEntry(playlist: SimplifiedPlaylist(name: "Sin URI")))
        XCTAssertNil(LibraryEntry(playlist: SimplifiedPlaylist(name: "Local",
                                                              uri: "spotify:local:a:b:c:1")))
    }

    func testOnlyAlbumsAndPlaylistsPlayInPlace() {
        XCTAssertEqual(LibraryEntry(playlist: SimplifiedPlaylist(uri: "spotify:playlist:p"))?
            .playsInPlace, true)
        XCTAssertEqual(LibraryEntry(album: SimplifiedAlbum(uri: "spotify:album:a"))?
            .playsInPlace, true)
        XCTAssertEqual(LibraryEntry(show: SimplifiedShow(uri: "spotify:show:s"))?
            .playsInPlace, false)
        XCTAssertEqual(LibraryEntry(audiobook: SimplifiedAudiobook(uri: "spotify:audiobook:b"))?
            .playsInPlace, false)
    }

    func testArtworkPicksSmallestImageOfAtLeast300Pixels() {
        let images = [
            SpotifyImage(url: "https://i.scdn.co/640", width: 640, height: 640),
            SpotifyImage(url: "https://i.scdn.co/300", width: 300, height: 300),
            SpotifyImage(url: "https://i.scdn.co/64", width: 64, height: 64),
        ]
        XCTAssertEqual(LibraryEntry.artworkURL(images)?.absoluteString, "https://i.scdn.co/300")

        let small = [SpotifyImage(url: "https://i.scdn.co/64", width: 64),
                     SpotifyImage(url: "https://i.scdn.co/120", width: 120)]
        XCTAssertEqual(LibraryEntry.artworkURL(small)?.absoluteString, "https://i.scdn.co/120")

        let unknownSize = [SpotifyImage(url: "https://mosaic.scdn.co/640/x")]
        XCTAssertEqual(LibraryEntry.artworkURL(unknownSize)?.absoluteString,
                       "https://mosaic.scdn.co/640/x")

        XCTAssertNil(LibraryEntry.artworkURL([SpotifyImage(url: "http://i.scdn.co/300", width: 300)]),
                     "Only https artwork is loaded")
        XCTAssertNil(LibraryEntry.artworkURL([]))
    }
}
