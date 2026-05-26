//
//  MicroblogAPI.swift
//  flitter
//
//  Created by Flawnson Tong on 2026-03-30.
//

import Foundation
import UIKit

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
    private func compressImage(_ image: UIImage) -> Data {
        let maxDimension: CGFloat = 1600
        var target = image

        if image.size.width > maxDimension || image.size.height > maxDimension {
            let scale = image.size.width >= image.size.height
                ? maxDimension / image.size.width
                : maxDimension / image.size.height
            let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            let renderer = UIGraphicsImageRenderer(size: newSize)
            target = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: newSize)) }
        }

        var data = target.jpegData(compressionQuality: 0.8) ?? Data()
        if data.count > 921_600 {
            data = target.jpegData(compressionQuality: 0.6) ?? data
        }
        return data
    }

    private func multipartBody(boundary: String, fields: [(String, String)], imageData: Data) -> Data {
        var data = Data()
        let crlf = "\r\n"
        for (name, value) in fields {
            data.append("--\(boundary)\(crlf)".data(using: .utf8)!)
            data.append("Content-Disposition: form-data; name=\"\(name)\"\(crlf)\(crlf)".data(using: .utf8)!)
            data.append(value.data(using: .utf8)!)
            data.append(crlf.data(using: .utf8)!)
        }
        data.append("--\(boundary)\(crlf)".data(using: .utf8)!)
        data.append("Content-Disposition: form-data; name=\"image\"; filename=\"image.jpg\"\(crlf)".data(using: .utf8)!)
        data.append("Content-Type: image/jpeg\(crlf)\(crlf)".data(using: .utf8)!)
        data.append(imageData)
        data.append("\(crlf)--\(boundary)--\(crlf)".data(using: .utf8)!)
        return data
    }

    func fetchPosts(limit: Int = 20) async throws -> [MicroPost] {
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

    func createPost(body: String, image: UIImage? = nil) async throws -> Int {
        var request = URLRequest(url: AppConfig.baseURL)
        request.httpMethod = "POST"
        request.setValue(AppConfig.adminToken, forHTTPHeaderField: "X-Admin-Token")

        if let image {
            let boundary = UUID().uuidString
            request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            request.httpBody = multipartBody(boundary: boundary, fields: [("body", body)], imageData: compressImage(image))
        } else {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: ["body": body])
        }

        let session = request.value(forHTTPHeaderField: "Content-Type")?.contains("multipart") == true
            ? Self.imageUploadSession : URLSession.shared
        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)
        return try JSONDecoder().decode(CreatePostResponse.self, from: data).id
    }

    func createReply(body: String, replyToId: Int, image: UIImage? = nil) async throws -> Int {
        var request = URLRequest(url: AppConfig.baseURL)
        request.httpMethod = "POST"
        request.setValue(AppConfig.adminToken, forHTTPHeaderField: "X-Admin-Token")

        if let image {
            let boundary = UUID().uuidString
            request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            request.httpBody = multipartBody(
                boundary: boundary,
                fields: [("body", body), ("reply_to_id", String(replyToId))],
                imageData: compressImage(image)
            )
        } else {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: ["body": body, "reply_to_id": replyToId])
        }

        let session = request.value(forHTTPHeaderField: "Content-Type")?.contains("multipart") == true
            ? Self.imageUploadSession : URLSession.shared
        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)
        return try JSONDecoder().decode(CreatePostResponse.self, from: data).id
    }

    private static let imageUploadSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 120
        config.timeoutIntervalForResource = 180
        return URLSession(configuration: config)
    }()

    func updatePost(id: Int, body: String) async throws -> Bool {
        var components = URLComponents(url: AppConfig.baseURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "id", value: String(id))
        ]

        guard let url = components?.url else {
            throw APIError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(AppConfig.adminToken, forHTTPHeaderField: "X-Admin-Token")

        let payload = ["body": body]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)

        return try JSONDecoder().decode(UpdatePostResponse.self, from: data).updated
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
