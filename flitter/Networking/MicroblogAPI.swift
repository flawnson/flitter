//
//  MicroblogAPI.swift
//  flitter
//
//  Created by Flawnson Tong on 2026-03-30.
//

import Foundation

enum APIError: LocalizedError {
    case invalidResponse
    case serverError(String)
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid server response."
        case .serverError(let message):
            return message
        case .encodingFailed:
            return "Could not encode request."
        }
    }
}

final class MicroblogAPI {
    func fetchPosts(limit: Int = 50) async throws -> [MicroPost] {
        var components = URLComponents(url: AppConfig.baseURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "limit", value: String(limit))
        ]

        guard let url = components?.url else {
            throw APIError.invalidResponse
        }

        let (data, response) = try await URLSession.shared.data(from: url)
        try validate(response: response, data: data)

        let decoded = try JSONDecoder().decode(MicroPostsResponse.self, from: data)
        return decoded.posts
    }

    func createPost(body: String) async throws {
        var request = URLRequest(url: AppConfig.baseURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(AppConfig.adminToken, forHTTPHeaderField: "X-Admin-Token")

        let payload = ["body": body]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)

        _ = try JSONDecoder().decode(CreatePostResponse.self, from: data)
    }

    func deletePost(id: Int) async throws {
        var components = URLComponents(url: AppConfig.baseURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "id", value: String(id))
        ]

        guard let url = components?.url else {
            throw APIError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue(AppConfig.adminToken, forHTTPHeaderField: "X-Admin-Token")

        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)

        _ = try JSONDecoder().decode(DeletePostResponse.self, from: data)
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard (200...299).contains(http.statusCode) else {
            if
                let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let error = json["error"] as? String
            {
                throw APIError.serverError(error)
            }

            throw APIError.serverError("Request failed with status \(http.statusCode).")
        }
    }
}
