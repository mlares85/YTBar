import XCTest
@testable import YTBar

final class StubHTTPClient: HTTPClient {
    var responses: [(Data, URLResponse)] = []
    var capturedRequests: [URLRequest] = []
    private var callIndex = 0

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        capturedRequests.append(request)
        guard callIndex < responses.count else {
            throw URLError(.badServerResponse)
        }
        let response = responses[callIndex]
        callIndex += 1
        return response
    }
}

// MARK: - Helpers

private func okResponse() -> URLResponse {
    HTTPURLResponse(
        url: URL(string: "https://music.youtube.com")!,
        statusCode: 200, httpVersion: nil, headerFields: nil
    )!
}

private func errorResponse(code: Int) -> URLResponse {
    HTTPURLResponse(
        url: URL(string: "https://music.youtube.com")!,
        statusCode: code, httpVersion: nil, headerFields: nil
    )!
}

private func jsonData(_ string: String) -> Data {
    string.data(using: .utf8)!
}

// MARK: - Search Track Tests

final class YTMusicClientSearchTests: XCTestCase {
    private var http: StubHTTPClient!
    private var sut: YTMusicClient!

    override func setUp() {
        http = StubHTTPClient()
        sut = YTMusicClient(httpClient: http) { "test-token" }
    }

    func testSearchReturnsParsedTracks() async throws {
        http.responses = [(jsonData(Fixtures.searchTrackJSON), okResponse())]

        let result = try await sut.search(query: "test")

        XCTAssertEqual(result.tracks.count, 1)
        XCTAssertEqual(result.tracks[0].id, "dQw4w9WgXcQ")
        XCTAssertEqual(result.tracks[0].title, "Never Gonna Give You Up")
        XCTAssertEqual(result.tracks[0].artist, "Rick Astley")
        XCTAssertEqual(result.tracks[0].album, "Whenever You Need Somebody")
        XCTAssertEqual(result.tracks[0].durationSeconds, 213)
    }

    func testSearchReturnsParsedPlaylists() async throws {
        http.responses = [(jsonData(Fixtures.searchPlaylistJSON), okResponse())]

        let result = try await sut.search(query: "chill")

        XCTAssertEqual(result.playlists.count, 1)
        XCTAssertEqual(result.playlists[0].id, "RDCLAK5uy_abc")
        XCTAssertEqual(result.playlists[0].title, "Chill Vibes")
        XCTAssertEqual(result.playlists[0].trackCount, 50)
    }

    func testSearchParsesItemSectionRenderer() async throws {
        http.responses = [(jsonData(Fixtures.searchItemSectionJSON), okResponse())]

        let result = try await sut.search(query: "test")

        XCTAssertEqual(result.tracks.count, 1)
        XCTAssertEqual(result.tracks[0].id, "abc123")
        XCTAssertEqual(result.tracks[0].title, "Creep")
        XCTAssertEqual(result.tracks[0].artist, "Radiohead")
        XCTAssertNil(result.tracks[0].album)
    }

    func testSearchParsesCardShelfWithDuration() async throws {
        http.responses = [(jsonData(Fixtures.searchCardShelfJSON), okResponse())]

        let result = try await sut.search(query: "test")

        XCTAssertEqual(result.tracks.count, 1)
        XCTAssertEqual(result.tracks[0].id, "card456")
        XCTAssertEqual(result.tracks[0].title, "Anti-Hero")
        XCTAssertEqual(result.tracks[0].artist, "Taylor Swift")
        XCTAssertEqual(result.tracks[0].durationSeconds, 227)
    }

    func testSearchHandlesEmptyResults() async throws {
        http.responses = [(jsonData(Fixtures.emptySearchJSON), okResponse())]

        let result = try await sut.search(query: "zzzznothing")

        XCTAssertTrue(result.tracks.isEmpty)
        XCTAssertTrue(result.playlists.isEmpty)
    }

    func testSearchThrowsOnAPIError() async throws {
        http.responses = [(jsonData("{}"), errorResponse(code: 500))]

        do {
            _ = try await sut.search(query: "test")
            XCTFail("Expected error")
        } catch let error as YTMusicError {
            XCTAssertEqual(error, .httpError(500))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}

// MARK: - Radio Mix Tests

final class YTMusicClientRadioTests: XCTestCase {
    private var http: StubHTTPClient!
    private var sut: YTMusicClient!

    override func setUp() {
        http = StubHTTPClient()
        sut = YTMusicClient(httpClient: http) { "test-token" }
    }

    func testRadioMixParsesShortBylineArtist() async throws {
        http.responses = [(jsonData(Fixtures.radioMixJSON), okResponse())]

        let tracks = try await sut.getRadioMix(videoId: "abc123")

        XCTAssertEqual(tracks.count, 1)
        XCTAssertEqual(tracks[0].id, "vid999")
        XCTAssertEqual(tracks[0].title, "Take On Me")
        XCTAssertEqual(tracks[0].artist, "a-ha")
        XCTAssertEqual(tracks[0].durationSeconds, 227)
    }
}

// MARK: - Library & Playlist Tests

final class YTMusicClientLibraryTests: XCTestCase {
    private var http: StubHTTPClient!
    private var sut: YTMusicClient!

    override func setUp() {
        http = StubHTTPClient()
        sut = YTMusicClient(httpClient: http) { "test-token" }
    }

    func testFetchLibraryPlaylists() async throws {
        http.responses = [(jsonData(Fixtures.libraryJSON), okResponse())]

        let playlists = try await sut.getLibraryPlaylists()

        XCTAssertEqual(playlists.count, 1)
        XCTAssertEqual(playlists[0].id, "PLmyplaylist123")
        XCTAssertEqual(playlists[0].title, "My Favorites")
        XCTAssertEqual(playlists[0].trackCount, 25)
    }

    func testFetchPlaylistTracks() async throws {
        http.responses = [(jsonData(Fixtures.playlistTracksJSON), okResponse())]

        let tracks = try await sut.getPlaylistTracks(playlistId: "PLmyplaylist123")

        XCTAssertEqual(tracks.count, 1)
        XCTAssertEqual(tracks[0].id, "xyz789")
        XCTAssertEqual(tracks[0].title, "Bohemian Rhapsody")
        XCTAssertEqual(tracks[0].artist, "Queen")
    }
}

// MARK: - Request Building Tests

final class YTMusicClientRequestTests: XCTestCase {
    private var http: StubHTTPClient!

    func testRequestIncludesAuthHeader() async throws {
        http = StubHTTPClient()
        http.responses = [(jsonData(Fixtures.libraryJSON), okResponse())]
        let sut = YTMusicClient(httpClient: http) { "my-token-123" }

        _ = try await sut.getLibraryPlaylists()

        let request = http.capturedRequests[0]
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer my-token-123")
    }

    func testRequestIncludesYTMContext() async throws {
        http = StubHTTPClient()
        http.responses = [(jsonData(Fixtures.emptySearchJSON), okResponse())]
        let sut = YTMusicClient(httpClient: http) { "tok" }

        _ = try await sut.search(query: "hello")

        let request = http.capturedRequests[0]
        let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
        let context = body["context"] as! [String: Any]
        let client = context["client"] as! [String: Any]
        XCTAssertEqual(client["clientName"] as? String, "WEB_REMIX")
    }

    func testRequestOmitsAuthWhenNoToken() async throws {
        http = StubHTTPClient()
        http.responses = [(jsonData(Fixtures.emptySearchJSON), okResponse())]
        let sut = YTMusicClient(httpClient: http) { nil }

        _ = try await sut.search(query: "test")

        let request = http.capturedRequests[0]
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
    }
}

// MARK: - PlaybackState Tests

final class PlaybackStateTests: XCTestCase {
    func testRoundTripEncodeDecode() throws {
        let track = Track(
            id: "vid1", title: "Song", artist: "Artist",
            album: nil, durationSeconds: 200, thumbnailURL: nil
        )
        let original = PlaybackState(
            queue: [track],
            currentIndex: 0,
            progressSeconds: 42.5,
            repeatMode: .all,
            isShuffled: false,
            queueSourcePlaylistId: "PL123",
            queueSourcePlaylistTitle: "My List",
            autoExtendStartIndex: nil
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(PlaybackState.self, from: data)
        XCTAssertEqual(decoded.queue.count, 1)
        XCTAssertEqual(decoded.queue[0].id, "vid1")
        XCTAssertEqual(decoded.currentIndex, 0)
        XCTAssertEqual(decoded.progressSeconds, 42.5)
        XCTAssertEqual(decoded.repeatMode, .all)
        XCTAssertEqual(decoded.queueSourcePlaylistId, "PL123")
    }

    func testDecodesWithMissingFields() throws {
        let json = #"{"queue":[],"currentIndex":0}"#
        let data = json.data(using: .utf8)!
        let state = try JSONDecoder().decode(PlaybackState.self, from: data)
        XCTAssertEqual(state.progressSeconds, 0)
        XCTAssertEqual(state.repeatMode, .off)
        XCTAssertFalse(state.isShuffled)
        XCTAssertNil(state.queueSourcePlaylistId)
    }
}

// MARK: - Fixtures

private enum Fixtures {
    static let searchTrackJSON = """
    {
      "contents": {
        "tabbedSearchResultsRenderer": {
          "tabs": [{
            "tabRenderer": {
              "content": {
                "sectionListRenderer": {
                  "contents": [{
                    "musicShelfRenderer": {
                      "contents": [{
                        "musicResponsiveListItemRenderer": {
                          "playlistItemData": {"videoId": "dQw4w9WgXcQ"},
                          "flexColumns": [
                            {"musicResponsiveListItemFlexColumnRenderer": {"text": {"runs": [{"text": "Never Gonna Give You Up"}]}}},
                            {"musicResponsiveListItemFlexColumnRenderer": {"text": {"runs": [{"text": "Rick Astley"}]}}},
                            {"musicResponsiveListItemFlexColumnRenderer": {"text": {"runs": [{"text": "Whenever You Need Somebody"}]}}}
                          ],
                          "fixedColumns": [{"musicResponsiveListItemFixedColumnRenderer": {"text": {"runs": [{"text": "3:33"}]}}}],
                          "thumbnail": {"musicThumbnailRenderer": {"thumbnail": {"thumbnails": [{"url": "https://lh3.googleusercontent.com/thumb1"}]}}}
                        }
                      }]
                    }
                  }]
                }
              }
            }
          }]
        }
      }
    }
    """

    static let searchPlaylistJSON = """
    {
      "contents": {
        "tabbedSearchResultsRenderer": {
          "tabs": [{
            "tabRenderer": {
              "content": {
                "sectionListRenderer": {
                  "contents": [{
                    "musicShelfRenderer": {
                      "contents": [{
                        "musicResponsiveListItemRenderer": {
                          "navigationEndpoint": {"browseEndpoint": {"browseId": "RDCLAK5uy_abc"}},
                          "flexColumns": [
                            {"musicResponsiveListItemFlexColumnRenderer": {"text": {"runs": [{"text": "Chill Vibes"}]}}},
                            {"musicResponsiveListItemFlexColumnRenderer": {"text": {"runs": [{"text": "50 tracks"}]}}}
                          ],
                          "thumbnail": {"musicThumbnailRenderer": {"thumbnail": {"thumbnails": [{"url": "https://lh3.googleusercontent.com/pl_thumb"}]}}}
                        }
                      }]
                    }
                  }]
                }
              }
            }
          }]
        }
      }
    }
    """

    static let searchItemSectionJSON = """
    {
      "contents": {
        "tabbedSearchResultsRenderer": {
          "tabs": [{
            "tabRenderer": {
              "content": {
                "sectionListRenderer": {
                  "contents": [{
                    "itemSectionRenderer": {
                      "contents": [{
                        "musicResponsiveListItemRenderer": {
                          "playlistItemData": {"videoId": "abc123"},
                          "flexColumns": [
                            {"musicResponsiveListItemFlexColumnRenderer": {"text": {"runs": [{"text": "Creep"}]}}},
                            {"musicResponsiveListItemFlexColumnRenderer": {"text": {"runs": [{"text": "Song"}, {"text": " • "}, {"text": "Radiohead"}]}}},
                            {"musicResponsiveListItemFlexColumnRenderer": {"text": {"runs": [{"text": "2.1B plays"}]}}}
                          ],
                          "thumbnail": {"musicThumbnailRenderer": {"thumbnail": {"thumbnails": [{"url": "https://lh3.googleusercontent.com/thumb2"}]}}}
                        }
                      }]
                    }
                  }]
                }
              }
            }
          }]
        }
      }
    }
    """

    static let searchCardShelfJSON = """
    {
      "contents": {
        "tabbedSearchResultsRenderer": {
          "tabs": [{
            "tabRenderer": {
              "content": {
                "sectionListRenderer": {
                  "contents": [{
                    "musicCardShelfRenderer": {
                      "contents": [{
                        "musicResponsiveListItemRenderer": {
                          "playlistItemData": {"videoId": "card456"},
                          "flexColumns": [
                            {"musicResponsiveListItemFlexColumnRenderer": {"text": {"runs": [{"text": "Anti-Hero"}]}}},
                            {"musicResponsiveListItemFlexColumnRenderer": {"text": {"runs": [{"text": "Song"}, {"text": " • "}, {"text": "Taylor Swift"}, {"text": " • "}, {"text": "3:47"}]}}},
                            {"musicResponsiveListItemFlexColumnRenderer": {"text": {"runs": [{"text": "650M plays"}]}}}
                          ],
                          "thumbnail": {"musicThumbnailRenderer": {"thumbnail": {"thumbnails": [{"url": "https://lh3.googleusercontent.com/thumb3"}]}}}
                        }
                      }]
                    }
                  }]
                }
              }
            }
          }]
        }
      }
    }
    """

    static let emptySearchJSON = """
    {
      "contents": {
        "tabbedSearchResultsRenderer": {
          "tabs": [{
            "tabRenderer": {
              "content": {
                "sectionListRenderer": {
                  "contents": []
                }
              }
            }
          }]
        }
      }
    }
    """

    static let radioMixJSON = """
    {
      "contents": {
        "singleColumnMusicWatchNextResultsRenderer": {
          "tabbedRenderer": {
            "watchNextTabbedResultsRenderer": {
              "tabs": [{
                "tabRenderer": {
                  "content": {
                    "musicQueueRenderer": {
                      "content": {
                        "playlistPanelRenderer": {
                          "contents": [{
                            "playlistPanelVideoRenderer": {
                              "videoId": "vid999",
                              "title": {"runs": [{"text": "Take On Me"}]},
                              "longBylineText": {"runs": [{"text": "a-ha"}, {"text": " \\u2022 "}, {"text": "2.4B views"}, {"text": " \\u2022 "}, {"text": "12M likes"}]},
                              "shortBylineText": {"runs": [{"text": "a-ha"}]},
                              "lengthText": {"runs": [{"text": "3:47"}]},
                              "thumbnail": {"thumbnails": [{"url": "https://example.com/thumb"}]}
                            }
                          }]
                        }
                      }
                    }
                  }
                }
              }]
            }
          }
        }
      }
    }
    """

    static let libraryJSON = """
    {
      "items": [{
        "id": "PLmyplaylist123",
        "snippet": {
          "title": "My Favorites",
          "thumbnails": {"medium": {"url": "https://i.ytimg.com/vi/thumb/mqdefault.jpg"}}
        },
        "contentDetails": {"itemCount": 25}
      }]
    }
    """

    static let playlistTracksJSON = """
    {
      "items": [{
        "snippet": {
          "title": "Bohemian Rhapsody",
          "videoOwnerChannelTitle": "Queen",
          "resourceId": {"videoId": "xyz789"},
          "thumbnails": {"medium": {"url": "https://i.ytimg.com/vi/thumb2/mqdefault.jpg"}}
        },
        "contentDetails": {"videoId": "xyz789"}
      }]
    }
    """
}
